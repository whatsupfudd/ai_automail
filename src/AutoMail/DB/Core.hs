{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE QuasiQuotes #-}

module AutoMail.DB.Core (
    TenantPoolDB(..), ControlPoolDB(..), PoolsDB(..), PoolDB
    , openPoolsDB, closePoolsDB
    , openTenantPoolDB, openControlPoolDB
    , closeTenantPoolDB, closeControlPoolDB
    , runSessionDB, runControlSessionDB
    , runTransactionDB
    , runTenantDB, runTenantReadDB, runTenantWriteDB
    , runControlDB, runControlReadDB, runControlWriteDB
    , healthDB, healthTenantDB, healthControlDB
    , SettingsContextDB(..)
    , setContextTenantDB
    , contextStatementDB
    , healthStatementDB
    , renderTenantUidDB
    , renderPrincipalUidDB
    , renderCorrelationKeyDB
    , exceptionErrorDB, handleExceptionDB
  ) where

import Control.Exception (
    SomeException
    , displayException
    , try
  )

import Data.ByteString (ByteString)
import Data.Int (Int64)
import Data.Profunctor (dimap)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (NominalDiffTime)

import GHC.Generics (Generic)

import qualified Hasql.Pool as Pool
import qualified Hasql.Pool.Config as Hpc
import qualified Hasql.Session as HS
import Hasql.Session (Session)
import Hasql.Statement (Statement)
import qualified Hasql.TH as HTH
import Hasql.Transaction (Transaction)
import qualified Hasql.Transaction as HT
import Hasql.Transaction.Sessions (
    IsolationLevel(..)
    , Mode(..)
  )
import qualified Hasql.Transaction.Sessions as HTS

import AutoMail.App.Config (ConfigDb(..))
import AutoMail.Model.Common (ContextTenant(..))
import AutoMail.Model.Id (
    CorrelationKey(..)
    , PrincipalUid(..)
    , TenantUid(..)
  )

import DB.Connect (PgDbConfig, configPg)
import AutoMail.App.Error (ErrorDb, mkErrorDb)


newtype TenantPoolDB = TenantPoolDB Pool.Pool


newtype ControlPoolDB =
  ControlPoolDB Pool.Pool


type PoolDB =
  TenantPoolDB


data PoolsDB = PoolsDB {
    tenantPD :: TenantPoolDB
    , controlPD :: ControlPoolDB
  }


data SettingsContextDB = SettingsContextDB {
    tenantSCDB :: Text
    , principalSCDB :: Text
    , correlationSCDB :: Text
  }
  deriving stock (Eq, Show, Generic)


type ContextParamsSqlDB =
  (Text, Text, Text)


openPoolsDB :: ConfigDb -> IO (Either ErrorDb PoolsDB)
openPoolsDB config = do
  tenantResult <- openTenantPoolDB config.tenantConf

  case tenantResult of
    Left err ->
      pure $ Left err

    Right tenantPool -> do
      controlResult <- openControlPoolDB config.controlConf

      case controlResult of
        Left err -> do
          closeTenantPoolDB tenantPool
          pure $ Left err

        Right controlPool ->
          pure $
            Right
              PoolsDB {
                  tenantPD = tenantPool
                  , controlPD = controlPool
                }


closePoolsDB :: PoolsDB -> IO ()
closePoolsDB pools = do
  closeControlPoolDB pools.controlPD
  closeTenantPoolDB pools.tenantPD


openTenantPoolDB :: PgDbConfig -> IO (Either ErrorDb TenantPoolDB)
openTenantPoolDB config =
  fmap TenantPoolDB <$> openRawPoolDB "tenant" config


openControlPoolDB :: PgDbConfig -> IO (Either ErrorDb ControlPoolDB)
openControlPoolDB config =
  fmap ControlPoolDB <$> openRawPoolDB "control" config


closeTenantPoolDB :: TenantPoolDB -> IO ()
closeTenantPoolDB (TenantPoolDB pool) = Pool.release pool


closeControlPoolDB :: ControlPoolDB -> IO ()
closeControlPoolDB (ControlPoolDB pool) = Pool.release pool

{-
Deprecated:
openPoolsDB :: ConfigDb -> IO (Either ErrorDb PoolsDB)
openPoolsDB config = do
  tenantPool <- openTenantPoolDB config
  controlPool <- openControlPoolDB config
  case (tenantPool, controlPool) of
    (Right tenantPool, Right controlPool) ->
      pure $ Right $ PoolsDB {
        tenantPD = tenantPool, controlPD = controlPool
      }
    (_, _) -> pure $ Left err


closePoolDB :: PoolsDB -> IO ()
closePoolDB pools = do
  closeTenantPoolDB pools.tenantPD
  closeControlPoolDB pools.controlPD

-}


runSessionDB :: TenantPoolDB -> Session a -> IO (Either ErrorDb a)
runSessionDB (TenantPoolDB pool) =
  runRawSessionDB "tenant session" pool


runControlSessionDB ::
  ControlPoolDB
  -> Session a
  -> IO (Either ErrorDb a)
runControlSessionDB (ControlPoolDB pool) =
  runRawSessionDB "control session" pool


runTransactionDB ::
  TenantPoolDB
  -> IsolationLevel
  -> Mode
  -> Transaction a
  -> IO (Either ErrorDb a)
runTransactionDB pool isolation mode transaction =
  runSessionDB pool $
    HTS.transaction isolation mode transaction


runTenantDB ::
  TenantPoolDB
  -> ContextTenant
  -> IsolationLevel
  -> Mode
  -> Transaction a
  -> IO (Either ErrorDb a)
runTenantDB pool context isolation mode transaction =
  runTransactionDB pool isolation mode $ do
    setContextTenantDB context
    transaction


runTenantReadDB ::
  TenantPoolDB
  -> ContextTenant
  -> Transaction a
  -> IO (Either ErrorDb a)
runTenantReadDB pool context =
  runTenantDB
    pool
    context
    ReadCommitted
    Read


runTenantWriteDB ::
  TenantPoolDB
  -> ContextTenant
  -> Transaction a
  -> IO (Either ErrorDb a)
runTenantWriteDB pool context =
  runTenantDB
    pool
    context
    ReadCommitted
    Write


runControlDB ::
  ControlPoolDB
  -> IsolationLevel
  -> Mode
  -> Transaction a
  -> IO (Either ErrorDb a)
runControlDB pool isolation mode transaction =
  runControlSessionDB pool $
    HTS.transaction isolation mode transaction


runControlReadDB ::
  ControlPoolDB
  -> Transaction a
  -> IO (Either ErrorDb a)
runControlReadDB pool =
  runControlDB pool ReadCommitted Read


runControlWriteDB ::
  ControlPoolDB
  -> Transaction a
  -> IO (Either ErrorDb a)
runControlWriteDB pool =
  runControlDB pool ReadCommitted Write


healthDB :: PoolsDB -> IO (Either ErrorDb ())
healthDB pools = do
  healthTenantDB pools.tenantPD
  healthControlDB pools.controlPD


healthTenantDB :: TenantPoolDB -> IO (Either ErrorDb ())
healthTenantDB pool =
  runSessionDB pool $ HS.statement () healthStatementDB


healthControlDB :: ControlPoolDB -> IO (Either ErrorDb ())
healthControlDB pool =
  runControlSessionDB pool $ HS.statement () healthStatementDB


setContextTenantDB ::
  ContextTenant -> Transaction ()
setContextTenantDB context =
  HT.statement
    (settingsContextDB context)
    contextStatementDB


contextStatementDB ::
  Statement SettingsContextDB ()
contextStatementDB =
  dimap settingsContextToParamsDB (const ())
    [HTH.singletonStatement|
      SELECT
        set_config(
          'automail.tenant_uid',
          $1 :: text,
          true
        ) :: text,
        set_config(
          'automail.principal_uid',
          $2 :: text,
          true
        ) :: text,
        set_config(
          'automail.correlation_key',
          $3 :: text,
          true
        ) :: text
    |]


healthStatementDB ::
  Statement () ()
healthStatementDB =
  dimap id (const ())
    [HTH.singletonStatement|
      SELECT true :: bool
    |]


settingsContextToParamsDB ::
  SettingsContextDB -> ContextParamsSqlDB
settingsContextToParamsDB settings =
  ( settings.tenantSCDB
  , settings.principalSCDB
  , settings.correlationSCDB
  )


renderTenantUidDB :: TenantUid -> Text
renderTenantUidDB (TenantUid uid) = T.pack $ show uid


renderPrincipalUidDB :: PrincipalUid -> Text
renderPrincipalUidDB (PrincipalUid uid) = T.pack $ show uid


renderCorrelationKeyDB ::
  CorrelationKey -> Text
renderCorrelationKeyDB (CorrelationKey key) =
  key


exceptionErrorDB :: Text -> SomeException -> ErrorDb
exceptionErrorDB context exception = mkErrorDb $ context <> ": " <> T.pack (displayException exception)


handleExceptionDB :: SomeException -> IO (Either SomeException a)
handleExceptionDB exception = pure $ Left exception


openRawPoolDB :: Text -> PgDbConfig -> IO (Either ErrorDb Pool.Pool)
openRawPoolDB label dbConf = do
  acquired <- try $ Pool.acquire $ configPg dbConf
  case acquired of
    Left exception -> pure $ Left $ exceptionErrorDB ("open " <> label <> " database pool") exception
    Right pool -> do
      healthResult <- runRawSessionDB ("open " <> label <> " database health") pool (HS.statement () healthStatementDB)
      case healthResult of
        Left err -> do
          Pool.release pool
          pure $ Left err
        Right () -> pure $ Right pool


runRawSessionDB :: Text -> Pool.Pool -> Session a -> IO (Either ErrorDb a)
runRawSessionDB context pool session = do
  result <- try $ Pool.use pool session
  case result of
    Left exception -> pure . Left $ exceptionErrorDB context exception
    Right (Left usageError) -> pure . Left . mkErrorDb $ context <> ": " <> T.pack (show usageError)
    Right (Right value) -> pure $ Right value


settingsContextDB :: ContextTenant -> SettingsContextDB
settingsContextDB context =
  SettingsContextDB {
      tenantSCDB = renderTenantUidDB context.tenantUidCT
      , principalSCDB = maybe "" renderPrincipalUidDB context.principalUidCT
      , correlationSCDB = renderCorrelationKeyDB context.correlationKeyCT
    }
