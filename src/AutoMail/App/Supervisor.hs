{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

module AutoMail.App.Supervisor (
    ExitComponentApp(..)
    , runSupervisorApp
  ) where

import AutoMail.App.Context (ShutdownApp(..))
import AutoMail.App.Error (ErrorApp(..))
import AutoMail.App.Runtime (ComponentApp(..), CriticalityApp(..), RestartApp(..))

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (Async, async, cancel, mapConcurrently_, race, waitCatch)
import Control.Concurrent.STM (TQueue, atomically, check, isEmptyTQueue, newTQueueIO, orElse, readTQueue, writeTQueue)
import Control.Exception (SomeException, displayException, mask, onException, try)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import qualified Data.Text as Tx
import Data.Time.Clock (NominalDiffTime)
import qualified Data.Vector as V
import GHC.Generics (Generic)


data ExitComponentApp = ExitComponentApp {
    nameECA :: Text
    , errorECA :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)


data EventSupervisorApp =
    FatalESA ExitComponentApp
  | StoppedESA ExitComponentApp


data StepMonitorSupervisorApp =
    EventSMS EventSupervisorApp
  | ShutdownSMS


data OutcomeSupervisorApp =
    FinishedOSA (Maybe ExitComponentApp)
  | ShutdownOSA (Maybe ExitComponentApp)


data RunnerSupervisorApp = RunnerSupervisorApp {
    componentRSA :: ComponentApp
    , asyncRSA :: Async ()
  }


runSupervisorApp :: ShutdownApp -> V.Vector ComponentApp -> IO (Either ErrorApp ())
runSupervisorApp shutdown components
  | V.null components = pure $ Right ()
  | otherwise =
      mask $ \restore -> do
        queue <- newTQueueIO
        runners <- startRunnersSupervisorApp restore shutdown queue components
        restore (runStartedSupervisorApp shutdown queue runners)
          `onException` shutdownRunnersSupervisorApp shutdown runners


startRunnersSupervisorApp :: (forall a. IO a -> IO a) -> ShutdownApp -> TQueue EventSupervisorApp
      -> V.Vector ComponentApp -> IO (V.Vector RunnerSupervisorApp)
startRunnersSupervisorApp restore shutdown queue components = do
  runnersRef <- newIORef V.empty
  let
    start component = do
      runner <- async $ restore $ runComponentSupervisorApp shutdown queue component
      modifyIORef' runnersRef (`V.snoc` RunnerSupervisorApp component runner)
  V.mapM_ start components `onException` (readIORef runnersRef >>= shutdownRunnersSupervisorApp shutdown)
  readIORef runnersRef


runStartedSupervisorApp :: ShutdownApp -> TQueue EventSupervisorApp -> V.Vector RunnerSupervisorApp
      -> IO (Either ErrorApp ())
runStartedSupervisorApp shutdown queue runners = do
  outcome <- monitorSupervisorApp shutdown queue (V.length runners) 0 Nothing
  case outcome of
    FinishedOSA fatal -> do
      runnerFailure <- waitRunnersSupervisorApp runners
      pure $ case firstJustSupervisorApp fatal runnerFailure of
        Nothing -> Right ()
        Just exit -> Left $ errorExitSupervisorApp exit

    ShutdownOSA fatal -> do
      shutdownRunnersSupervisorApp shutdown runners
      queuedFatal <- drainFatalSupervisorApp queue
      pure $ case firstJustSupervisorApp fatal queuedFatal of
        Nothing -> Right ()
        Just exit -> Left $ errorExitSupervisorApp exit


monitorSupervisorApp :: ShutdownApp -> TQueue EventSupervisorApp -> Int -> Int -> Maybe ExitComponentApp
      -> IO OutcomeSupervisorApp
monitorSupervisorApp shutdown queue total stopped fatal
  | stopped >= total = pure $ FinishedOSA fatal
  | otherwise = do
      step <- nextMonitorSupervisorApp shutdown queue
      case step of
        ShutdownSMS -> pure $ ShutdownOSA fatal

        EventSMS event ->
          case event of
            FatalESA exit -> do
              shutdown.requestSA
              pure $ ShutdownOSA $ Just exit

            StoppedESA _ ->
              monitorSupervisorApp shutdown queue total (stopped + 1) fatal


nextMonitorSupervisorApp :: ShutdownApp -> TQueue EventSupervisorApp -> IO StepMonitorSupervisorApp
nextMonitorSupervisorApp shutdown queue =
  atomically $ (EventSMS <$> readTQueue queue) `orElse` (do
    requested <- shutdown.requestedSA
    check requested
    pure ShutdownSMS)


runComponentSupervisorApp :: ShutdownApp -> TQueue EventSupervisorApp -> ComponentApp -> IO ()
runComponentSupervisorApp shutdown queue component =
  runLoop 0
  where
  runLoop restartCount = do
    requested <- atomically shutdown.requestedSA
    if requested
      then writeStoppedSupervisorApp queue component Nothing
      else do
        result <- try $ component.runCA shutdown
        requestedAfter <- atomically shutdown.requestedSA
        if requestedAfter
          then writeStoppedSupervisorApp queue component Nothing
          else handleUnexpected restartCount result

  handleUnexpected restartCount result = do
    let
      exit = ExitComponentApp component.nameCA $ messageUnexpectedSupervisorApp result
    case component.criticalityCA of
      CriticalCA -> do
        atomically $ writeTQueue queue $ FatalESA exit
        shutdown.requestSA

      RestartableCA ->
        case delayRestartSupervisorApp component.restartCA (restartCount + 1) of
          Nothing ->
            atomically $ writeTQueue queue $ StoppedESA exit

          Just delay -> do
            stopping <- waitDelaySupervisorApp shutdown delay
            if stopping
              then writeStoppedSupervisorApp queue component Nothing
              else runLoop $ restartCount + 1


writeStoppedSupervisorApp :: TQueue EventSupervisorApp -> ComponentApp -> Maybe Text -> IO ()
writeStoppedSupervisorApp queue component errorMessage =
  atomically $ writeTQueue queue $ StoppedESA ExitComponentApp {
      nameECA = component.nameCA
      , errorECA = errorMessage
    }


shutdownRunnersSupervisorApp :: ShutdownApp -> V.Vector RunnerSupervisorApp -> IO ()
shutdownRunnersSupervisorApp shutdown runners = do
  shutdown.requestSA
  mapConcurrently_ (\runner -> cancel runner.asyncRSA) $ V.toList runners


waitRunnersSupervisorApp :: V.Vector RunnerSupervisorApp -> IO (Maybe ExitComponentApp)
waitRunnersSupervisorApp runners = do
  exits <- V.mapM waitRunnerSupervisorApp runners
  pure $ firstJustVectorSupervisorApp exits


waitRunnerSupervisorApp :: RunnerSupervisorApp -> IO (Maybe ExitComponentApp)
waitRunnerSupervisorApp runner = do
  result <- waitCatch runner.asyncRSA
  pure $ case result of
    Right () -> Nothing
    Left exception ->
      Just ExitComponentApp {
          nameECA = runner.componentRSA.nameCA
          , errorECA = Just $ exceptionTextSupervisorApp exception
        }


drainFatalSupervisorApp :: TQueue EventSupervisorApp -> IO (Maybe ExitComponentApp)
drainFatalSupervisorApp queue =
  atomically drain
  where
  drain = do
    empty <- isEmptyTQueue queue
    if empty
      then pure Nothing
      else do
        event <- readTQueue queue
        case event of
          FatalESA exit -> pure $ Just exit
          StoppedESA _ -> drain


delayRestartSupervisorApp :: RestartApp -> Int -> Maybe NominalDiffTime
delayRestartSupervisorApp restart restartNumber =
  case restart of
    NeverRA -> Nothing
    FixedRA delay -> Just delay
    ExponentialRA initial maximum ->
      let
        factor = 2 ^ max 0 (restartNumber - 1) :: Integer
        delay = initial * fromInteger factor
      in
      Just $ min maximum delay


waitDelaySupervisorApp :: ShutdownApp -> NominalDiffTime -> IO Bool
waitDelaySupervisorApp shutdown delay = do
  requested <- atomically shutdown.requestedSA
  if requested
    then pure True
    else do
      let micros = microsDelaySupervisorApp delay
      if micros <= 0
        then pure False
        else do
          result <- race shutdown.awaitSA $ threadDelay micros
          pure $ case result of
            Left () -> True
            Right () -> False


microsDelaySupervisorApp :: NominalDiffTime -> Int
microsDelaySupervisorApp delay =
  let
    seconds = max 0 $ realToFrac delay
    micros = floor (seconds * 1000000) :: Integer
    maximumMicros = fromIntegral (maxBound :: Int) :: Integer
  in
  fromInteger $ min maximumMicros micros


messageUnexpectedSupervisorApp :: Either SomeException () -> Maybe Text
messageUnexpectedSupervisorApp result =
  case result of
    Right () -> Just "component returned before shutdown"
    Left exception -> Just $ exceptionTextSupervisorApp exception


exceptionTextSupervisorApp :: SomeException -> Text
exceptionTextSupervisorApp exception =
  Tx.pack $ displayException exception


errorExitSupervisorApp :: ExitComponentApp -> ErrorApp
errorExitSupervisorApp exit =
  InternalEA $ "critical component terminated unexpectedly: " <> exit.nameECA <> detail
  where
  detail =
    case exit.errorECA of
      Nothing -> ""
      Just message -> ": " <> message


firstJustSupervisorApp :: Maybe a -> Maybe a -> Maybe a
firstJustSupervisorApp left right =
  case left of
    Just _ -> left
    Nothing -> right


firstJustVectorSupervisorApp :: V.Vector (Maybe a) -> Maybe a
firstJustVectorSupervisorApp =
  V.foldl' firstJustSupervisorApp Nothing