{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module Commands.Server (OptsServer(..), runServer) where

import Control.Exception (finally)
import Control.Monad (void, when)
import Control.Monad.Except (ExceptT(..), runExceptT)
import Control.Monad.IO.Class (liftIO)

import Data.Bifunctor (first)
import Data.Text (Text)
import qualified Data.Text as Tx
import qualified Data.Text.IO as Tio
import qualified Data.Vector as V

import GHC.Generics (Generic)
import Data.Aeson (Value(Null))

import System.Exit (exitFailure)
import System.IO (stderr)
import qualified System.Posix.Signals as Sig

import AutoMail.Credential.Store (emptyStoreCred)
import AutoMail.App.Account.Runtime (emptyRegistryAccountPrv)
import AutoMail.Action.Driver (emptyRegistryAct)
import AutoMail.Action.Types
import AutoMail.Analysis.Driver
import AutoMail.App.Config  
import AutoMail.App.Context
import AutoMail.App.Error
import AutoMail.DB.Core
import AutoMail.Job.Capability
import AutoMail.Job.Types
import AutoMail.Model.Time
import AutoMail.Provider.Driver
import AutoMail.Workflow.Driver
import AutoMail.Workflow.Types


data OptsServer = OptsServer {
    configPathOS :: Maybe FilePath
  }
  deriving stock (Eq, Show, Generic)


runServer :: OptsServer -> IO ()
runServer opts = do
  result <- runExceptT $ do
    config <- ExceptT $ pure . first ConfigEA =<< loadConfigServer opts
    pools <- ExceptT $ first DatabaseEA <$> openPoolsDB config.databaseCA
    liftIO $ finally (runOpenedServer config pools) (closePoolsDB pools)
  case result of
    Right () -> pure ()
    Left err -> do
      Tio.hPutStrLn stderr $ "automail server failed: " <> renderErrorApp err
      exitFailure


runOpenedServer :: ConfigApp -> PoolsDB -> IO ()
runOpenedServer config pool = do
  result <- runExceptT $ do
    ExceptT $ first DatabaseEA <$> verifySchemaServer pool
    shutdown <- liftIO newShutdownApp
    liftIO $ installSignalHandlersServer shutdown
    let
      context = mkContextServer config pool shutdown
    liftIO $ announceStartedServer context
    liftIO context.shutdownEA.awaitSA
    liftIO $ announceStoppingServer context
  case result of
    Right () -> pure ()
    Left err -> do
      Tio.hPutStrLn stderr $ "automail server failed after database startup: " <> renderErrorApp err
      exitFailure


loadConfigServer :: OptsServer -> IO (Either ErrorConfig ConfigApp)
loadConfigServer opts = do
  when (opts.configPathOS /= Nothing) $ pure ()
  case opts.configPathOS of
    Nothing -> loadConfigApp (Just "config.yaml") >>= pure . (>>= validateConfigApp)
    Just path -> pure $ Left $ ErrorConfig $
      "configuration file loading is not wired into AutoMail.App.Config yet; refusing to ignore requested file " <> Tx.pack path


verifySchemaServer :: PoolsDB -> IO (Either ErrorDb ())
verifySchemaServer pools =
  healthDB pools


mkContextServer :: ConfigApp -> PoolsDB -> ShutdownApp -> AppContext
mkContextServer config pool shutdown =
  AppContext {
      configEA = config
      , poolsEA = pool
      , clockEA = systemClock
      , credentialsEA = emptyStoreCred
      , accountResolversEA = emptyRegistryAccountPrv
      , providersEA = emptyRegistryPrv
      , analysesEA = emptyRegistryAn
      , jobsEA = unavailableQueueJob
      , jobHandlersEA = emptyRegistryJob
      , workflowEA = noopDriverWf
      , actionsEA = emptyRegistryAct
      , shutdownEA = shutdown
    }


installSignalHandlersServer :: ShutdownApp -> IO ()
installSignalHandlersServer shutdown = do
  void $ Sig.installHandler Sig.keyboardSignal (Sig.Catch shutdown.requestSA) Nothing
  void $ Sig.installHandler Sig.softwareTermination (Sig.Catch shutdown.requestSA) Nothing


announceStartedServer :: AppContext -> IO ()
announceStartedServer context =
  Tio.putStrLn $ "automail server started: instance=" <> context.configEA.runtimeCA.instanceIdCR
    <> ", workers=" <> Tx.pack (show context.configEA.workersCA.countCW)
    <> ", http=" <> context.configEA.httpCA.hostCH <> ":" <> Tx.pack (show context.configEA.httpCA.portCH)


announceStoppingServer :: AppContext -> IO ()
announceStoppingServer context =
  Tio.putStrLn $ "automail server stopping: instance=" <> context.configEA.runtimeCA.instanceIdCR


unavailableQueueJob :: QueueJob IO
unavailableQueueJob =
  QueueJob {
      enqueueQJ = \_ -> pure $ Left unavailable
      , claimQJ = \_ -> pure $ Left unavailable
      , heartbeatQJ = \_ _ _ -> pure $ Left unavailable
      , completeQJ = \_ _ -> pure $ Left unavailable
      , retryQJ = \_ _ _ _ -> pure $ Left unavailable
      , failQJ = \_ _ _ -> pure $ Left unavailable
      , cancelQJ = \_ _ -> pure $ Left unavailable
      , recoverQJ = \_ -> pure $ Right 0
    }
  where
  unavailable = ErrorJob "job queue has not been registered in Commands.Server yet"


noopDriverWf :: DriverWf IO
noopDriverWf =
  DriverWf {
      processDW = \_ _ -> pure $ Right V.empty
    }


renderErrorApp :: ErrorApp -> Text
renderErrorApp err =
  case err of
    ConfigEA detail -> "configuration error: " <> renderErrorConfig detail
    DatabaseEA detail -> "database error: " <> renderErrorDb detail
    ProviderEA detail -> "provider error: " <> renderErrorPrv detail
    MailEA detail -> "mail error: " <> renderErrorMail detail
    BlobEA detail -> "blob error: " <> renderErrorBlob detail
    JobEA detail -> "job error: " <> renderErrorJob detail
    AnalysisEA detail -> "analysis error: " <> renderErrorAn detail
    KnowledgeEA detail -> "knowledge error: " <> renderErrorKn detail
    WorkflowEA detail -> "workflow error: " <> renderErrorWf detail
    PolicyEA detail -> "policy error: " <> renderErrorPol detail
    ActionEA detail -> "action error: " <> renderErrorAct detail
    InternalEA detail -> "internal error: " <> detail


renderErrorConfig :: ErrorConfig -> Text
renderErrorConfig (ErrorConfig message) =
  message


renderErrorDb :: ErrorDb -> Text
renderErrorDb (ErrorDb message) =
  message


renderErrorPrv :: ErrorPrv -> Text
renderErrorPrv err =
  err.messageEP <> " [" <> Tx.pack (show err.kindEP) <> ", retry=" <> Tx.pack (show err.retryEP) <> renderDetails err.detailsEP <> "]"


renderErrorMail :: ErrorMail -> Text
renderErrorMail (ErrorMail message) =
  message


renderErrorBlob :: ErrorBlob -> Text
renderErrorBlob (ErrorBlob message) =
  message


renderErrorJob :: ErrorJob -> Text
renderErrorJob (ErrorJob message) =
  message


renderErrorAn :: ErrorAn -> Text
renderErrorAn (ErrorAn message) =
  message


renderErrorKn :: ErrorKn -> Text
renderErrorKn (ErrorKn message) =
  message


renderErrorWf :: ErrorWf -> Text
renderErrorWf (ErrorWf message) =
  message


renderErrorPol :: ErrorPol -> Text
renderErrorPol (ErrorPol message) =
  message


renderErrorAct :: ErrorAct -> Text
renderErrorAct (ErrorAct message) =
  message


renderDetails :: Maybe Value -> Text
renderDetails details =
  case details of
    Nothing -> ""
    Just Null -> ""
    Just _ -> ", details=<redacted>"