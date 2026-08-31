module AutoMail.App.Context where

import Control.Concurrent.STM (STM, atomically, check, newTVarIO, readTVar, writeTVar)
import Control.Monad.Reader (ReaderT, ask, runReaderT)

import AutoMail.Action.Driver (RegistryAct)
import AutoMail.Analysis.Driver (RegistryAn)
import AutoMail.App.Account.Runtime (RegistryAccountPrv)
import AutoMail.App.Config (ConfigApp)
import AutoMail.Credential.Store (StoreCred)
import AutoMail.DB.Core (PoolsDB)
import AutoMail.Job.Capability (QueueJob, RegistryJob)
import AutoMail.Model.Time (Clock)
import AutoMail.Provider.Driver (RegistryPrv)
import AutoMail.Workflow.Driver (DriverWf)


data ShutdownApp = ShutdownApp {
    requestedSA :: STM Bool
    , requestSA :: IO ()
    , awaitSA :: IO ()
  }


newShutdownApp :: IO ShutdownApp
newShutdownApp = do
  requestedVar <- newTVarIO False
  let
    requested = readTVar requestedVar
    request = atomically $ writeTVar requestedVar True
    await = atomically $ do
      shutdownRequested <- readTVar requestedVar
      check shutdownRequested
  pure ShutdownApp {
      requestedSA = requested
      , requestSA = request
      , awaitSA = await
    }


data AppContext = AppContext {
    configEA :: ConfigApp
    , poolsEA :: PoolsDB
    , clockEA :: Clock IO
    , credentialsEA :: StoreCred IO
    , accountResolversEA :: RegistryAccountPrv IO
    , providersEA :: RegistryPrv IO
    , analysesEA :: RegistryAn IO
    , jobsEA :: QueueJob IO
    , jobHandlersEA :: RegistryJob IO
    , workflowEA :: DriverWf IO
    , actionsEA :: RegistryAct IO
    , shutdownEA :: ShutdownApp
  }


data DepsAppContext = DepsAppContext {
    configDAC :: ConfigApp
    , poolsDAC :: PoolsDB
    , clockDAC :: Clock IO
    , credentialsDAC :: StoreCred IO
    , accountResolversDAC :: RegistryAccountPrv IO
    , providersDAC :: RegistryPrv IO
    , analysesDAC :: RegistryAn IO
    , jobsDAC :: QueueJob IO
    , jobHandlersDAC :: RegistryJob IO
    , workflowDAC :: DriverWf IO
    , actionsDAC :: RegistryAct IO
    , shutdownDAC :: ShutdownApp
  }


mkAppContext :: DepsAppContext -> AppContext
mkAppContext deps =
  AppContext {
      configEA = deps.configDAC
      , poolsEA = deps.poolsDAC
      , clockEA = deps.clockDAC
      , credentialsEA = deps.credentialsDAC
      , accountResolversEA = deps.accountResolversDAC
      , providersEA = deps.providersDAC
      , analysesEA = deps.analysesDAC
      , jobsEA = deps.jobsDAC
      , jobHandlersEA = deps.jobHandlersDAC
      , workflowEA = deps.workflowDAC
      , actionsEA = deps.actionsDAC
      , shutdownEA = deps.shutdownDAC
    }


type AppM = ReaderT AppContext IO


runAppM :: AppContext -> AppM a -> IO a
runAppM context action = runReaderT action context


envApp :: AppM AppContext
envApp = ask