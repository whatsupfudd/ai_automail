module AutoMail.App.Context where

import Control.Concurrent.STM (STM, atomically, check, newTVarIO, readTVar, writeTVar)
import Control.Monad.Reader (ReaderT, ask, runReaderT)

import AutoMail.Action.Driver (RegistryAct)
import AutoMail.Analysis.Driver (RegistryAn)
import AutoMail.App.Config (ConfigApp)
import AutoMail.DB.Core (PoolDB)
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
    , poolEA :: PoolDB
    , clockEA :: Clock IO
    , providersEA :: RegistryPrv IO
    , analysesEA :: RegistryAn IO
    , jobsEA :: QueueJob IO
    , jobHandlersEA :: RegistryJob IO
    , workflowEA :: DriverWf IO
    , actionsEA :: RegistryAct IO
    , shutdownEA :: ShutdownApp
  }


type AppM = ReaderT AppContext IO


runAppM :: AppContext -> AppM a -> IO a
runAppM context action = runReaderT action context


envApp :: AppM AppContext
envApp = ask