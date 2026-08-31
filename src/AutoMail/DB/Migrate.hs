{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE QuasiQuotes #-}

module AutoMail.DB.Migrate (
    MigrationDB(..), StateMigrationDB(..)
    , loadMigrationsDB
    , fetchMigrationsDB
    , validateMigrationsDB
    , pendingMigrationsDB
    , applyMigrationDB
    , applyMigrationsDB
  ) where

import Control.Monad (filterM)
import qualified Control.Exception as Ex

import Crypto.Hash (Digest, SHA256)
import qualified Crypto.Hash as Crypto

import qualified Data.ByteArray as BA
import qualified Data.ByteString as Bs
import Data.ByteString (ByteString)
import Data.Char (isDigit, isSpace, toLower)
import Data.Int (Int32)
import Data.List (groupBy, sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Profunctor (dimap)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Tx
import Data.Time (UTCTime)
import qualified Data.Vector as V
import Data.Vector (Vector)
import Data.Word (Word8)

import GHC.Generics (Generic)

import System.Directory (doesFileExist, listDirectory)
import System.FilePath ((</>), takeBaseName, takeExtension)
import Text.Read (readMaybe)

import qualified Hasql.Connection as Hc
import Hasql.Connection (Connection)
import qualified Hasql.Session as Hs
import Hasql.Session (Session)
import Hasql.Statement (Statement)
import qualified Hasql.TH as HTH

import AutoMail.App.Error (ErrorDb(..))
import AutoMail.DB.Schema (VersionSchemaDB(..))
import AutoMail.Model.Common (
    HashSha256
    , bytesHashSha256
    , mkHashSha256
    , renderHashSha256
  )


data MigrationDB = MigrationDB {
    versionMDB :: VersionSchemaDB
    , nameMDB :: Text
    , checksumMDB :: HashSha256
    , sqlMDB :: ByteString
  }
  deriving stock (Eq, Show, Generic)


data StateMigrationDB =
    PendingSMD MigrationDB
  | AppliedSMD MigrationDB UTCTime
  deriving stock (Eq, Show, Generic)


type AppliedMigrationRowSqlDB =
  ( Int32
  , ByteString
  , UTCTime
  )


type InsertMigrationParamsSqlDB =
  ( Int32
  , Text
  , ByteString
  )


loadMigrationsDB ::
  FilePath -> IO (Either ErrorDb (Vector MigrationDB))
loadMigrationsDB root = do
  loaded <-
    Ex.try load
      :: IO (
           Either
             Ex.SomeException
             (Either ErrorDb (Vector MigrationDB))
         )
  pure $
    either
      (Left . exceptionErrorMigrateDB "loading migration files")
      id
      loaded
  where
  load = do
    entries <- listDirectory root
    files <-
      filterM
        (\entry -> doesFileExist $ root </> entry)
        entries
    let
      sqlFiles = filter sqlFileNameDB files
    parsed <- traverse (loadMigrationFileDB root) sqlFiles
    pure $ do
      migrations <- sequence parsed
      let
        sorted =
          V.fromList $
            sortOn versionMDB migrations
      validateMigrationsDB sorted V.empty
      pure sorted


fetchMigrationsDB ::
  Session (Vector (VersionSchemaDB, HashSha256, UTCTime))
fetchMigrationsDB = do
  ensureMigrationTableDB
  Hs.statement () fetchMigrationsStatementDB


validateMigrationsDB ::
  Vector MigrationDB
  -> Vector (VersionSchemaDB, HashSha256, UTCTime)
  -> Either ErrorDb ()
validateMigrationsDB migrations applied =
  case errorsValidateMigrationsDB migrations applied of
    [] ->
      Right ()

    errors ->
      Left $
        ErrorDb $
          renderErrorsMigrateDB
            "Invalid migration set"
            errors


pendingMigrationsDB ::
  Vector MigrationDB
  -> Vector (VersionSchemaDB, HashSha256, UTCTime)
  -> Either ErrorDb (Vector MigrationDB)
pendingMigrationsDB migrations applied = do
  validateMigrationsDB migrations applied
  let
    appliedVersions =
      Set.fromList $
        V.toList $
          V.map versionAppliedMigrationDB applied
  pure $
    V.filter
      (\migration ->
        Set.notMember migration.versionMDB appliedVersions
      )
      migrations


applyMigrationDB ::
  MigrationDB -> Session ()
applyMigrationDB migration = do
  ensureMigrationTableDB

  -- Migration SQL is runtime data. Hasql.Session.sql is intentionally
  -- non-prepared and supports multi-statement SQL, so no statement
  -- splitting or manual Statement construction is required.
  Hs.sql migration.sqlMDB

  Hs.statement migration insertMigrationStatementDB


applyMigrationsDB ::
  ByteString
  -> Vector MigrationDB
  -> IO (Either ErrorDb ())
applyMigrationsDB connection migrations = do
  pure . Left $ ErrorDb "@[applyMigrationsDB] Note: implemented"
  {-
  acquired <-
    Ex.try (Hc.acquire []) connection
      :: IO (
           Either
             Ex.SomeException
             (Either Hc.ConnectionError Connection)
         )

  case acquired of
    Left exception ->
      pure $
        Left $
          exceptionErrorMigrateDB
            "connecting to PostgreSQL"
            exception

    Right (Left errorConnection) ->
      pure $
        Left $
          ErrorDb $
            "PostgreSQL connection failed: "
              <> Tx.pack (show errorConnection)

    Right (Right dbConnection) ->
      Ex.finally
        (applyMigrationsConnectionDB dbConnection migrations)
        (Hc.release dbConnection)
  -}

applyMigrationsConnectionDB ::
  Connection
  -> Vector MigrationDB
  -> IO (Either ErrorDb ())
applyMigrationsConnectionDB connection migrations = do
  fetched <-
    runMigrationSessionDB
      connection
      fetchMigrationsDB

  case fetched >>= pendingMigrationsDB migrations of
    Left err ->
      pure $ Left err

    Right pending ->
      applyPendingMigrationsDB
        connection
        (V.toList pending)


applyPendingMigrationsDB ::
  Connection
  -> [MigrationDB]
  -> IO (Either ErrorDb ())
applyPendingMigrationsDB connection migrations =
  case migrations of
    [] ->
      pure $ Right ()

    migration:rest -> do
      result <-
        runMigrationSessionDB
          connection
          (applyMigrationTransactionDB migration)

      case result of
        Left err ->
          pure $ Left err

        Right () ->
          applyPendingMigrationsDB connection rest


applyMigrationTransactionDB ::
  MigrationDB -> Session ()
applyMigrationTransactionDB migration = do
  Hs.sql beginSqlMigrationDB
  applyMigrationDB migration
  Hs.sql commitSqlMigrationDB


runMigrationSessionDB ::
  Connection
  -> Session a
  -> IO (Either ErrorDb a)
runMigrationSessionDB connection session = do
  result <- Hs.run session connection
  pure $
    either
      (Left . queryErrorMigrateDB)
      Right
      result


ensureMigrationTableDB :: Session ()
ensureMigrationTableDB = do
  Hs.sql createSchemaSqlMigrationDB
  Hs.sql createTableSqlMigrationDB


fetchMigrationsStatementDB ::
  Statement
    ()
    (Vector (VersionSchemaDB, HashSha256, UTCTime))
fetchMigrationsStatementDB =
  dimap id (fmap appliedMigrationFromRowDB)
    [HTH.vectorStatement|
      SELECT
        version :: int4,
        checksum :: bytea,
        applied_at :: timestamptz
      FROM am.schema_migration
      ORDER BY version ASC
    |]


insertMigrationStatementDB ::
  Statement MigrationDB ()
insertMigrationStatementDB =
  dimap migrationToInsertParamsDB id
    [HTH.resultlessStatement|
      INSERT INTO am.schema_migration (
        version,
        name,
        checksum
      )
      VALUES (
        $1 :: int4,
        $2 :: text,
        $3 :: bytea
      )
    |]


createSchemaSqlMigrationDB :: ByteString
createSchemaSqlMigrationDB =
  [HTH.uncheckedSql|
    CREATE SCHEMA IF NOT EXISTS am
  |]


createTableSqlMigrationDB :: ByteString
createTableSqlMigrationDB =
  [HTH.uncheckedSql|
    CREATE TABLE IF NOT EXISTS am.schema_migration (
      version integer PRIMARY KEY,
      name text NOT NULL,
      checksum bytea NOT NULL
        CHECK (length(checksum) = 32),
      applied_at timestamptz NOT NULL
        DEFAULT now()
    )
  |]


beginSqlMigrationDB :: ByteString
beginSqlMigrationDB =
  [HTH.uncheckedSql|
    BEGIN
  |]


commitSqlMigrationDB :: ByteString
commitSqlMigrationDB =
  [HTH.uncheckedSql|
    COMMIT
  |]


appliedMigrationFromRowDB ::
  AppliedMigrationRowSqlDB
  -> (VersionSchemaDB, HashSha256, UTCTime)
appliedMigrationFromRowDB
  (version, checksum, appliedAt) =
  ( versionSchemaDB version
  , unsafeHashSha256DB checksum
  , appliedAt
  )


migrationToInsertParamsDB ::
  MigrationDB -> InsertMigrationParamsSqlDB
migrationToInsertParamsDB migration =
  ( versionInt32DB migration.versionMDB
  , migration.nameMDB
  , bytesHashSha256 migration.checksumMDB
  )


loadMigrationFileDB ::
  FilePath
  -> FilePath
  -> IO (Either ErrorDb MigrationDB)
loadMigrationFileDB root file = do
  content <- Bs.readFile $ root </> file
  pure $ makeMigrationFileDB file content


makeMigrationFileDB ::
  FilePath
  -> ByteString
  -> Either ErrorDb MigrationDB
makeMigrationFileDB file content = do
  (version, name) <-
    parseMigrationFileNameDB file

  if blankByteStringDB content
    then
      Left $
        ErrorDb $
          "Migration file is empty: "
            <> Tx.pack file

    else
      Right
        MigrationDB {
            versionMDB = version
            , nameMDB = name
            , checksumMDB = hashSha256DB content
            , sqlMDB = content
          }


parseMigrationFileNameDB ::
  FilePath
  -> Either ErrorDb (VersionSchemaDB, Text)
parseMigrationFileNameDB file =
  let
    base =
      takeBaseName file

    (digits, rest) =
      span isDigit base
  in
  case readMaybe digits of
    Nothing ->
      Left $
        ErrorDb $
          "Migration file name must start with a positive "
            <> "integer version: "
            <> Tx.pack file

    Just version
      | version <= 0 ->
          Left $
            ErrorDb $
              "Migration version must be positive in file: "
                <> Tx.pack file

      | otherwise -> do
          name <-
            parseMigrationNameDB file base rest

          pure
            (VersionSchemaDB version, name)


parseMigrationNameDB ::
  FilePath
  -> String
  -> String
  -> Either ErrorDb Text
parseMigrationNameDB file base rest =
  case rest of
    [] ->
      Right $ Tx.pack base

    first:_
      | separatorMigrationNameDB first ->
          let
            name =
              dropWhile separatorMigrationNameDB rest
          in
          if null name || all isSpace name
            then
              Left $
                ErrorDb $
                  "Migration file name must contain a non-empty "
                    <> "name after the version: "
                    <> Tx.pack file

            else
              Right $ Tx.pack name

      | otherwise ->
          Left $
            ErrorDb $
              "Migration version and name must be separated "
                <> "by '_', '-' or '.': "
                <> Tx.pack file


sqlFileNameDB :: FilePath -> Bool
sqlFileNameDB file =
  map toLower (takeExtension file) == ".sql"


separatorMigrationNameDB :: Char -> Bool
separatorMigrationNameDB c =
  c == '_'
    || c == '-'
    || c == '.'
    || isSpace c


blankByteStringDB :: ByteString -> Bool
blankByteStringDB =
  Bs.all asciiSpaceWord8DB


asciiSpaceWord8DB :: Word8 -> Bool
asciiSpaceWord8DB word =
  word == 9
    || word == 10
    || word == 11
    || word == 12
    || word == 13
    || word == 32


hashSha256DB :: ByteString -> HashSha256
hashSha256DB content =
  fromMaybe impossible $
    mkHashSha256 digestBytes
  where
  digest =
    Crypto.hash content :: Digest SHA256

  digestBytes =
    BA.convert digest

  impossible =
    error $
      "internal error: SHA-256 digest did not contain 32 bytes"


unsafeHashSha256DB ::
  ByteString -> HashSha256
unsafeHashSha256DB bytes =
  fromMaybe invalid $
    mkHashSha256 bytes
  where
  invalid =
    error $
      "database invariant violated: "
        <> "am.schema_migration.checksum is not 32 bytes"


versionSchemaDB ::
  Int32 -> VersionSchemaDB
versionSchemaDB =
  VersionSchemaDB . fromIntegral


versionInt32DB ::
  VersionSchemaDB -> Int32
versionInt32DB (VersionSchemaDB version) =
  fromIntegral version


versionAppliedMigrationDB ::
  (VersionSchemaDB, HashSha256, UTCTime)
  -> VersionSchemaDB
versionAppliedMigrationDB (version, _, _) =
  version


checksumAppliedMigrationDB ::
  (VersionSchemaDB, HashSha256, UTCTime)
  -> HashSha256
checksumAppliedMigrationDB (_, checksum, _) =
  checksum


errorsValidateMigrationsDB ::
  Vector MigrationDB
  -> Vector (VersionSchemaDB, HashSha256, UTCTime)
  -> [Text]
errorsValidateMigrationsDB migrations applied =
  errorsLoaded
    <> errorsApplied
    <> errorsMissing
    <> errorsChecksum
    <> errorsSkipped
  where
  migrationVersions =
    V.map versionMDB migrations

  appliedVersions =
    V.map versionAppliedMigrationDB applied

  errorsLoaded =
    errorsVersionVectorDB
      "migration files"
      migrationVersions

  errorsApplied =
    errorsVersionVectorDB
      "applied migrations"
      appliedVersions

  migrationMap =
    Map.fromList
      [ (migration.versionMDB, migration)
      | migration <- V.toList migrations
      ]

  errorsMissing =
    missingMigrationErrorsDB
      migrationMap
      applied

  errorsChecksum =
    checksumMigrationErrorsDB
      migrationMap
      applied

  errorsSkipped =
    skippedMigrationErrorsDB
      migrations
      appliedVersions


errorsVersionVectorDB ::
  Text
  -> Vector VersionSchemaDB
  -> [Text]
errorsVersionVectorDB label versions =
  duplicateErrors <> orderedErrors
  where
  duplicates =
    duplicateVersionsDB versions

  duplicateErrors =
    if V.null duplicates
      then
        []

      else
        [ label
            <> " contain duplicate versions: "
            <> renderVersionsDB duplicates
        ]

  orderedErrors =
    if strictlyIncreasingDB versions
      then
        []

      else
        [ label
            <> " must be strictly ordered by increasing version"
        ]


missingMigrationErrorsDB ::
  Map.Map VersionSchemaDB MigrationDB
  -> Vector (VersionSchemaDB, HashSha256, UTCTime)
  -> [Text]
missingMigrationErrorsDB migrationMap applied =
  map render $
    filter (`Map.notMember` migrationMap) $
      V.toList $
        V.map versionAppliedMigrationDB applied
  where
  render version =
    "Applied migration "
      <> renderVersionSchemaDB version
      <> " is not present on disk"


checksumMigrationErrorsDB ::
  Map.Map VersionSchemaDB MigrationDB
  -> Vector (VersionSchemaDB, HashSha256, UTCTime)
  -> [Text]
checksumMigrationErrorsDB migrationMap applied =
  mapMaybe render $
    V.toList applied
  where
  render row =
    let
      version =
        versionAppliedMigrationDB row

      appliedChecksum =
        checksumAppliedMigrationDB row
    in
    case Map.lookup version migrationMap of
      Nothing ->
        Nothing

      Just migration
        | migration.checksumMDB == appliedChecksum ->
            Nothing

        | otherwise ->
            Just $
              "Applied migration "
                <> renderVersionSchemaDB version
                <> " has changed on disk; database checksum "
                <> renderHashSha256 appliedChecksum
                <> ", file checksum "
                <> renderHashSha256 migration.checksumMDB


skippedMigrationErrorsDB ::
  Vector MigrationDB
  -> Vector VersionSchemaDB
  -> [Text]
skippedMigrationErrorsDB migrations appliedVersions =
  case V.toList appliedVersions of
    [] ->
      []

    versions ->
      let
        highestApplied =
          maximum versions

        appliedSet =
          Set.fromList versions

        skipped =
          V.map versionMDB $
            V.filter
              (\migration ->
                migration.versionMDB <= highestApplied
                  && Set.notMember
                    migration.versionMDB
                    appliedSet
              )
              migrations
      in
      if V.null skipped
        then
          []

        else
          [ "Earlier migration versions are present on disk "
              <> "but not applied while a later version is "
              <> "already applied: "
              <> renderVersionsDB skipped
          ]


duplicateVersionsDB ::
  Vector VersionSchemaDB
  -> Vector VersionSchemaDB
duplicateVersionsDB versions =
  V.fromList $
    mapMaybe duplicate $
      groupBy (==) $
        sortOn id $
          V.toList versions
  where
  duplicate values =
    case values of
      value:_:_ ->
        Just value

      _ ->
        Nothing


strictlyIncreasingDB ::
  Vector VersionSchemaDB -> Bool
strictlyIncreasingDB versions =
  and $
    zipWith
      (<)
      values
      (drop 1 values)
  where
  values =
    V.toList versions


renderVersionsDB ::
  Vector VersionSchemaDB -> Text
renderVersionsDB versions =
  Tx.intercalate ", " $
    V.toList $
      V.map renderVersionSchemaDB versions


renderVersionSchemaDB ::
  VersionSchemaDB -> Text
renderVersionSchemaDB (VersionSchemaDB version) =
  Tx.pack $ show version


renderErrorsMigrateDB ::
  Text
  -> [Text]
  -> Text
renderErrorsMigrateDB heading errors =
  heading
    <> ":\n"
    <> Tx.intercalate
      "\n"
      (map ("- " <>) errors)


queryErrorMigrateDB ::
  Show err => err -> ErrorDb
queryErrorMigrateDB err =
  ErrorDb $
    "PostgreSQL migration query failed: "
      <> Tx.pack (show err)


exceptionErrorMigrateDB ::
  Text
  -> Ex.SomeException
  -> ErrorDb
exceptionErrorMigrateDB context exception =
  ErrorDb $
    "Exception while "
      <> context
      <> ": "
      <> Tx.pack (show exception)