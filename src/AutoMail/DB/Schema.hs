{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE QuasiQuotes #-}

module AutoMail.DB.Schema (
    VersionSchemaDB(..)
    , StateSchemaDB(..)
    , expectedVersionSchemaDB
    , fetchVersionSchemaDB
    , verifySchemaDB
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Int (Int32)
import Data.Profunctor (dimap)
import Data.Text (Text)
import qualified Data.Text as Tx

import GHC.Generics (Generic)

import Hasql.Session (Session)
import qualified Hasql.Session as HS
import Hasql.Statement (Statement)
import qualified Hasql.TH as HTH

import AutoMail.App.Error (ErrorDb, mkErrorDb)
import AutoMail.DB.Core


newtype VersionSchemaDB = VersionSchemaDB Int
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


data StateSchemaDB = StateSchemaDB {
    currentSSD :: VersionSchemaDB
    , expectedSSD :: VersionSchemaDB
  }
  deriving stock (Eq, Show, Generic)


-- | Expected schema version for this AutoMail binary.
--
-- This value must be bumped whenever a new immutable migration is added and
-- becomes required by the server runtime.
expectedVersionSchemaDB :: VersionSchemaDB
expectedVersionSchemaDB =
  VersionSchemaDB 1


fetchVersionSchemaDB :: Session (Maybe VersionSchemaDB)
fetchVersionSchemaDB =
  HS.statement () versionStatementDB


verifySchemaDB :: PoolDB -> IO (Either ErrorDb StateSchemaDB)
verifySchemaDB pool = do
  fetched <- runSessionDB pool fetchVersionSchemaDB
  pure $ case fetched of
    Left errorDB ->
      Left errorDB

    Right Nothing ->
      Left $ missingSchemaDB expectedVersionSchemaDB

    Right (Just current) ->
      verifyVersionSchemaDB
        current
        expectedVersionSchemaDB


verifyVersionSchemaDB ::
  VersionSchemaDB
  -> VersionSchemaDB
  -> Either ErrorDb StateSchemaDB
verifyVersionSchemaDB current expected =
  case compare current expected of
    EQ ->
      Right
        StateSchemaDB {
            currentSSD = current
            , expectedSSD = expected
          }

    LT ->
      Left $ oldSchemaDB current expected

    GT ->
      Left $ newSchemaDB current expected


versionStatementDB ::
  Statement () (Maybe VersionSchemaDB)
versionStatementDB =
  dimap id (fmap versionFromInt32DB)
    [HTH.maybeStatement|
      SELECT version :: int4
      FROM am.schema_migration
      ORDER BY version DESC
      LIMIT 1
    |]


versionFromInt32DB :: Int32 -> VersionSchemaDB
versionFromInt32DB value =
  VersionSchemaDB $ fromIntegral value


missingSchemaDB :: VersionSchemaDB -> ErrorDb
missingSchemaDB expected =
  mkErrorDb $
    "AutoMail database schema is not initialized; expected schema version "
      <> renderVersionSchemaDB expected
      <> ". Run `automail migrate` before starting `automail server`."


oldSchemaDB ::
  VersionSchemaDB
  -> VersionSchemaDB
  -> ErrorDb
oldSchemaDB current expected =
  mkErrorDb $
    "AutoMail database schema is too old; current version is "
      <> renderVersionSchemaDB current
      <> ", expected version is "
      <> renderVersionSchemaDB expected
      <> ". Run `automail migrate` before starting `automail server`."


newSchemaDB ::
  VersionSchemaDB
  -> VersionSchemaDB
  -> ErrorDb
newSchemaDB current expected =
  mkErrorDb $
    "AutoMail database schema is newer than this binary; current version is "
      <> renderVersionSchemaDB current
      <> ", expected version is "
      <> renderVersionSchemaDB expected
      <> ". Deploy a compatible AutoMail binary or restore a compatible database."


renderVersionSchemaDB :: VersionSchemaDB -> Text
renderVersionSchemaDB (VersionSchemaDB version) =
  Tx.pack $ show version
