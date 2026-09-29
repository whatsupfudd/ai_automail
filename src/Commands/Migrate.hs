{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module Commands.Migrate (migrateCmd) where

import Control.Exception (finally)
import Control.Monad.Except (ExceptT(..), runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Data.Text (Text)
import qualified Data.Text as Tx
import qualified Data.Text.IO as Tio
import qualified Data.Vector as V
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import System.Exit (exitFailure)
import System.IO (stderr)

import AutoMail.App.Config
import AutoMail.App.Error (ErrorConfig, ErrorDb, mkErrorDb)
import AutoMail.DB.Core
import AutoMail.DB.Migrate
import AutoMail.DB.Schema
import AutoMail.Model.Common

import Options.Cli (MigrateOpts (..))
import qualified Options.Runtime as Rt
import Commands.Config (convertConfig)

data ErrorMigrate =
    ConfigEM ErrorConfig
  | DatabaseEM ErrorDb
  deriving stock (Eq, Show, Generic)


migrateCmd :: MigrateOpts -> Rt.RunOptions -> IO ()
migrateCmd opts rtOptions = do
  result <- runExceptT $ executeMigrate opts rtOptions
  case result of
    Right () -> pure ()
    Left err -> do
      putTextErr $ "automail migrate: " <> renderErrorMigrate err
      exitFailure


executeMigrate :: MigrateOpts -> Rt.RunOptions -> ExceptT ErrorMigrate IO ()
executeMigrate opts rtOpts =
  let
    config = convertConfig rtOpts
  in do
  migrations <- liftEitherIO DatabaseEM $ loadMigrationsDB opts.migrationsPathOM
  applied <- fetchAppliedMigrate config
  liftEitherPure DatabaseEM $ validateMigrationsDB migrations applied
  pending <- liftEitherPure DatabaseEM $ pendingMigrationsDB migrations applied

  liftIO $ printPlanMigrate opts migrations applied pending

  case (opts.dryRunOM, V.null pending) of
    (_, True) -> liftIO $ putTextLn "No pending migrations."
    (True, False) -> liftIO $ putTextLn "Dry run complete; no migrations were applied."
    (False, False) -> do
      liftIO $ putTextLn $ "Applying " <> renderCountMigrate (V.length pending) "migration" <> "."
      liftEitherIO DatabaseEM $ applyMigrationsDB config.databaseCA.tenantConf pending
      liftIO $ putTextLn $ "Applied " <> renderCountMigrate (V.length pending) "migration" <> "."

{-
loadConfigMigrate :: MigrateOpts -> ExceptT ErrorMigrate IO ConfigApp
loadConfigMigrate opts = do
  case opts.configPathOM of
    Nothing -> pure ()
    Just path -> liftIO $ putTextErr $
      "warning: configPathOM is currently informational for Commands.Migrate; loadConfigApp selects the effective configuration source: "
      <> Tx.pack path
  liftEitherIO ConfigEM $ loadConfigApp opts.configPathOM
-}

fetchAppliedMigrate :: ConfigApp -> ExceptT ErrorMigrate IO (V.Vector (VersionSchemaDB, HashSha256, UTCTime))
fetchAppliedMigrate config =
  withPoolMigrate config $ \pools -> liftEitherIO DatabaseEM $ runSessionDB pools.tenantPD fetchMigrationsDB


withPoolMigrate :: ConfigApp -> (PoolsDB -> ExceptT ErrorMigrate IO a) -> ExceptT ErrorMigrate IO a
withPoolMigrate config action = do
  pools <- liftEitherIO DatabaseEM $ openPoolsDB config.databaseCA
  ExceptT $ runExceptT (action pools) `finally` closePoolsDB pools


printPlanMigrate :: MigrateOpts -> V.Vector MigrationDB -> V.Vector (VersionSchemaDB, HashSha256, UTCTime) -> V.Vector MigrationDB -> IO ()
printPlanMigrate opts migrations applied pending = do
  putTextLn "AutoMail migration plan"
  putTextLn $ "  migrations path: " <> Tx.pack opts.migrationsPathOM
  putTextLn $ "  loaded: " <> renderCountMigrate (V.length migrations) "migration"
  putTextLn $ "  already applied: " <> renderCountMigrate (V.length applied) "migration"
  putTextLn $ "  pending: " <> renderCountMigrate (V.length pending) "migration"
  if V.null pending
    then pure ()
    else do
      putTextLn "Pending migrations:"
      V.mapM_ (putTextLn . renderMigrationMigrate) pending


renderMigrationMigrate :: MigrationDB -> Text
renderMigrationMigrate migration =
  "  " <> renderVersionSchemaMigrate migration.versionMDB <> "  " <> migration.nameMDB


renderVersionSchemaMigrate :: VersionSchemaDB -> Text
renderVersionSchemaMigrate (VersionSchemaDB version) =
  Tx.pack $ show version


renderCountMigrate :: Int -> Text -> Text
renderCountMigrate count noun =
  Tx.pack (show count) <> " " <> noun <> if count == 1 then "" else "s"


renderErrorMigrate :: ErrorMigrate -> Text
renderErrorMigrate err =
  case err of
    ConfigEM errMsg -> "configuration error: " <> errMsg
    DatabaseEM errMsg -> "database error: " <> errMsg


liftEitherIO :: (err -> ErrorMigrate) -> IO (Either err a) -> ExceptT ErrorMigrate IO a
liftEitherIO wrap action = do
  result <- liftIO action
  liftEitherPure wrap result


liftEitherPure :: (err -> ErrorMigrate) -> Either err a -> ExceptT ErrorMigrate IO a
liftEitherPure wrap result =
  case result of
    Right value -> pure value
    Left err -> throwError $ wrap err


putTextLn :: Text -> IO ()
putTextLn =
  Tio.putStrLn


putTextErr :: Text -> IO ()
putTextErr =
  Tio.hPutStrLn stderr