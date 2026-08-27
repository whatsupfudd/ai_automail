module AutoMail.DB.Core (
    PoolDB
    , openPoolDB
    , closePoolDB
    , runSessionDB
    , runTransactionDB
    , runTenantDB
    , healthDB
  ) where

import Control.Exception (SomeAsyncException, SomeException, catch, displayException, fromException, throwIO)
import qualified Control.Monad.Cont as Mc

import Data.Bifunctor (first)
import Data.Functor.Contravariant (contramap)
import Data.Text (Text)
import qualified Data.Text as Tx

import qualified Hasql.Decoders as HD
import qualified Hasql.Encoders as HE
import qualified Hasql.Pool as Pool
import qualified Hasql.Session as HS
import Hasql.Session (Session)
import Hasql.Statement (Statement(..))
import qualified Hasql.Transaction as HT
import Hasql.Transaction (Transaction)
import qualified Hasql.Transaction.Sessions as HTS
import Hasql.Transaction.Sessions (IsolationLevel, Mode)

import DB.Connect (startPg, PgDbConfig(..))
import AutoMail.App.Config (ConfigDb(..))
import AutoMail.App.Error (ErrorDb(..))
import AutoMail.Model.Common (ContextTenant(..))
import AutoMail.Model.Id (CorrelationKey(..), PrincipalUid(..), TenantUid(..))


type PoolDB = Pool.Pool


data SettingsContextDB = SettingsContextDB {
    tenantSCDB :: Text
    , principalSCDB :: Text
    , correlationSCDB :: Text
  }


openPoolDB :: PgDbConfig -> IO (Either ErrorDb PoolDB)
openPoolDB config =
  let
    pgPool = startPg config
  in do
  result <- trySyncDB $ Mc.runContT pgPool testDb
  pure $ first (exceptionErrorDB "database pool acquisition failed") result
  where
  testDb pgPool = do
    pure $ pgPool


closePoolDB :: PoolDB -> IO ()
closePoolDB = Pool.release


runSessionDB :: PoolDB -> Session a -> IO (Either ErrorDb a)
runSessionDB pool session = do
  result <- trySyncDB $ Pool.use pool session
  pure $
    case result of
      Left exception -> Left $ exceptionErrorDB "database session raised an exception" exception
      Right usageResult -> first (ErrorDb . ("database session failed: " <>) . Tx.pack . show) usageResult


runTransactionDB :: PoolDB -> IsolationLevel -> Mode -> Transaction a -> IO (Either ErrorDb a)
runTransactionDB pool isolation mode transactionDB =
  runSessionDB pool $ HTS.transaction isolation mode transactionDB


runTenantDB :: PoolDB -> ContextTenant -> IsolationLevel -> Mode -> Transaction a -> IO (Either ErrorDb a)
runTenantDB pool context isolation mode transactionDB =
  runTransactionDB pool isolation mode $ do
    setContextTenantDB context
    transactionDB


healthDB :: PoolDB -> IO (Either ErrorDb ())
healthDB pool = runSessionDB pool $ HS.statement () healthStatementDB


setContextTenantDB :: ContextTenant -> Transaction ()
setContextTenantDB context =
  let
    settings = SettingsContextDB {
        tenantSCDB = renderTenantUidDB context.tenantUidCT
        , principalSCDB = maybe "" renderPrincipalUidDB context.principalUidCT
        , correlationSCDB = renderCorrelationKeyDB context.correlationKeyCT
      }
  in
  HT.statement settings contextStatementDB


contextStatementDB :: Statement SettingsContextDB ()
contextStatementDB =
  Statement
    "SELECT set_config('automail.tenant_uid', $1, true), set_config('automail.principal_uid', $2, true), set_config('automail.correlation_key', $3, true)"
    contextParametersDB
    contextResultDB
    True


contextParametersDB :: HE.Params SettingsContextDB
contextParametersDB =
  contramap (\settings -> settings.tenantSCDB) textParameterDB
    <> contramap (\settings -> settings.principalSCDB) textParameterDB
    <> contramap (\settings -> settings.correlationSCDB) textParameterDB


contextResultDB :: HD.Result ()
contextResultDB =
  () <$ HD.singleRow ((,,) <$> textColumnDB <*> textColumnDB <*> textColumnDB)


healthStatementDB :: Statement () ()
healthStatementDB =
  Statement "SELECT 1::int4" HE.noParams healthResultDB True


healthResultDB :: HD.Result ()
healthResultDB =
  () <$ HD.singleRow (HD.column $ HD.nonNullable HD.int4)


textParameterDB :: HE.Params Text
textParameterDB =
  HE.param $ HE.nonNullable HE.text


textColumnDB :: HD.Row Text
textColumnDB =
  HD.column $ HD.nonNullable HD.text


renderTenantUidDB :: TenantUid -> Text
renderTenantUidDB tenantUid =
  case tenantUid of
    TenantUid value -> Tx.pack $ show value


renderPrincipalUidDB :: PrincipalUid -> Text
renderPrincipalUidDB principalUid =
  case principalUid of
    PrincipalUid value -> Tx.pack $ show value


renderCorrelationKeyDB :: CorrelationKey -> Text
renderCorrelationKeyDB correlationKey =
  case correlationKey of
    CorrelationKey value -> value


exceptionErrorDB :: Text -> SomeException -> ErrorDb
exceptionErrorDB context exception =
  ErrorDb $ context <> ": " <> Tx.pack (displayException exception)


trySyncDB :: IO a -> IO (Either SomeException a)
trySyncDB action =
  catch (Right <$> action) handleExceptionDB


handleExceptionDB :: SomeException -> IO (Either SomeException a)
handleExceptionDB exception =
  case fromException exception :: Maybe SomeAsyncException of
    Just _ -> throwIO exception
    Nothing -> pure $ Left exception