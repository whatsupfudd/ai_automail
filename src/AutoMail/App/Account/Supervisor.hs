{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}

module AutoMail.App.Account.Supervisor (
    SupervisorAccount(..), DepsSupervisorAccount(..), ResultReconcileAccount(..)
    , newSupervisorAccount, runSupervisorAccount, reconcileAccounts
    , fetchAccountRun, listAccountsRun, statusAccountRun
  ) where

import Control.Concurrent.STM (
    STM, TMVar, TVar, atomically, modifyTVar', newEmptyTMVarIO, newTVarIO, readTVar, registerDelay, retry
    , tryPutTMVar, tryTakeTMVar, writeTVar
  )
import Control.Exception (SomeException, displayException, finally, try)
import Control.Monad (unless, void)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (maybeToList)
import Data.Text (Text)
import qualified Data.Text as Tx
import qualified Data.Vector as V
import GHC.Generics (Generic)

import AutoMail.App.Account.Runtime (DepsAccountRun, changedAccountRun, loadAccountRun)
import AutoMail.App.Account.Types (
    EventAccount(..), GenerationAccount(..), HookAccount(..), RuntimeAccount(..), StatusAccountRun(..)
  )
import AutoMail.App.Context (ShutdownApp(..))
import AutoMail.App.Error (ErrorApp(..), ErrorDb(..), RetryError(..), retryErrorApp)
import AutoMail.DB.Account (AccountRefDB(..), listActiveAccountRefsDB)
import AutoMail.DB.Core (ControlPoolDB, runControlReadDB)
import AutoMail.Model.Id (AccountUid)
import AutoMail.Model.Time (Clock)


data SupervisorAccount = SupervisorAccount {
    accountsSA :: TVar (Map AccountUid RuntimeAccount)
    , stoppedSA :: TMVar ()
  }


data DepsSupervisorAccount = DepsSupervisorAccount {
    controlPoolDSA :: ControlPoolDB
    , accountRunDSA :: DepsAccountRun
    , hooksDSA :: V.Vector (HookAccount IO)
    , refreshSecondsDSA :: Int
    , clockDSA :: Clock IO
  }


data ResultReconcileAccount = ResultReconcileAccount {
    activatedRRA :: V.Vector AccountUid
    , reloadedRRA :: V.Vector AccountUid
    , deactivatedRRA :: V.Vector AccountUid
    , failedRRA :: V.Vector (AccountUid, Text)
  }
  deriving stock (Eq, Show, Generic)


data OutcomeAccount = OutcomeAccount {
    uidOA :: Maybe AccountUid
    , failuresOA :: V.Vector (AccountUid, Text)
  }


newSupervisorAccount :: IO SupervisorAccount
newSupervisorAccount = do
  accounts <- newTVarIO Map.empty
  stopped <- newEmptyTMVarIO
  pure SupervisorAccount {
      accountsSA = accounts
      , stoppedSA = stopped
    }


runSupervisorAccount :: DepsSupervisorAccount -> SupervisorAccount -> ShutdownApp -> IO ()
runSupervisorAccount deps supervisor shutdown =
  finally runSupervisor finaliseSupervisor
  where
  runSupervisor = do
    atomically $ void $ tryTakeTMVar supervisor.stoppedSA
    loopSupervisorAccount deps supervisor shutdown

  finaliseSupervisor = do
    stopAccountsSupervisor deps supervisor
    atomically $ void $ tryPutTMVar supervisor.stoppedSA ()


reconcileAccounts :: DepsSupervisorAccount -> SupervisorAccount -> IO (Either ErrorApp ResultReconcileAccount)
reconcileAccounts deps supervisor = do
  fetchedRefs <- fetchDesiredRefsAccount deps
  case fetchedRefs of
    Left err -> pure $ Left err
    Right refs -> do
      current <- atomically $ readTVar supervisor.accountsSA
      let desired = mapRefsAccount refs
      let removed = Map.toList $ Map.difference current desired
      let newRefs = V.filter (\ref -> Map.notMember ref.accountUidARD current) refs
      let changedRefs = V.filter (\ref -> maybe False (changedAccountRun ref) (Map.lookup ref.accountUidARD current)) refs

      deactivatedOutcomes <- traverse (\(accountUid, runtime) -> deactivateAccount deps supervisor accountUid runtime) removed
      activatedOutcomes <- traverse (activateAccount deps supervisor) $ V.toList newRefs
      reloadedOutcomes <- traverse (reloadSelectedAccount deps supervisor current) $ V.toList changedRefs

      let (deactivated, failedDeactivated) = collectOutcomesAccount deactivatedOutcomes
      let (activated, failedActivated) = collectOutcomesAccount activatedOutcomes
      let (reloaded, failedReloaded) = collectOutcomesAccount reloadedOutcomes

      pure $ Right ResultReconcileAccount {
          activatedRRA = activated
          , reloadedRRA = reloaded
          , deactivatedRRA = deactivated
          , failedRRA = concatVectorsAccount [failedDeactivated, failedActivated, failedReloaded]
        }


fetchAccountRun :: SupervisorAccount -> AccountUid -> STM (Maybe RuntimeAccount)
fetchAccountRun supervisor accountUid = do
  accounts <- readTVar supervisor.accountsSA
  pure $ Map.lookup accountUid accounts


listAccountsRun :: SupervisorAccount -> STM (V.Vector RuntimeAccount)
listAccountsRun supervisor = do
  accounts <- readTVar supervisor.accountsSA
  pure $ V.fromList $ Map.elems accounts


statusAccountRun :: SupervisorAccount -> AccountUid -> STM (Maybe StatusAccountRun)
statusAccountRun supervisor accountUid = do
  accounts <- readTVar supervisor.accountsSA
  case Map.lookup accountUid accounts of
    Nothing -> pure Nothing
    Just runtime -> Just <$> readTVar runtime.statusRA


loopSupervisorAccount :: DepsSupervisorAccount -> SupervisorAccount -> ShutdownApp -> IO ()
loopSupervisorAccount deps supervisor shutdown = do
  requested <- atomically shutdown.requestedSA
  unless requested $ do
    _ <- tryAny $ reconcileAccounts deps supervisor
    waitRefreshSupervisor deps.refreshSecondsDSA shutdown
    loopSupervisorAccount deps supervisor shutdown


waitRefreshSupervisor :: Int -> ShutdownApp -> IO ()
waitRefreshSupervisor seconds shutdown = do
  timer <- registerDelay $ delayMicrosAccount seconds
  atomically $ do
    requested <- shutdown.requestedSA
    elapsed <- readTVar timer
    if requested || elapsed then pure () else retry


delayMicrosAccount :: Int -> Int
delayMicrosAccount seconds =
  fromInteger $ max 100000 $ min 2147483647 $ toInteger seconds * 1000000


fetchDesiredRefsAccount :: DepsSupervisorAccount -> IO (Either ErrorApp (V.Vector AccountRefDB))
fetchDesiredRefsAccount deps = do
  result <- tryAny $ runControlReadDB deps.controlPoolDSA listActiveAccountRefsDB
  case result of
    Left exception -> pure $ Left $ DatabaseEA $ exceptionErrorDB "failed to list active account references" exception
    Right (Left err) -> pure $ Left $ DatabaseEA err
    Right (Right refs) -> pure $ Right refs


mapRefsAccount :: V.Vector AccountRefDB -> Map AccountUid AccountRefDB
mapRefsAccount = V.foldl' (\refs ref -> Map.insert ref.accountUidARD ref refs) Map.empty


activateAccount :: DepsSupervisorAccount -> SupervisorAccount -> AccountRefDB -> IO OutcomeAccount
activateAccount deps supervisor ref = do
  loaded <- tryAny $ loadAccountRun deps.accountRunDSA ref
  case loaded of
    Left exception -> pure $ failureOutcomeAccount ref.accountUidARD $ exceptionTextAccount "failed to activate account" exception
    Right (Left err) -> pure $ failureOutcomeAccount ref.accountUidARD $ renderErrorApp err
    Right (Right runtime) -> do
      atomically $ do
        writeTVar runtime.statusRA ReadySAR
        modifyTVar' supervisor.accountsSA $ Map.insert ref.accountUidARD runtime

      hookFailures <- runHooksAccount deps.hooksDSA runtime $ ActivatedEA ref.accountUidARD runtime.generationRA
      pure OutcomeAccount {
          uidOA = Just ref.accountUidARD
          , failuresOA = hookFailures
        }


reloadSelectedAccount :: DepsSupervisorAccount -> SupervisorAccount -> Map AccountUid RuntimeAccount -> AccountRefDB -> IO OutcomeAccount
reloadSelectedAccount deps supervisor current ref =
  case Map.lookup ref.accountUidARD current of
    Nothing -> pure OutcomeAccount {
        uidOA = Nothing
        , failuresOA = V.empty
      }
    Just runtime -> reloadAccount deps supervisor ref runtime


reloadAccount :: DepsSupervisorAccount -> SupervisorAccount -> AccountRefDB -> RuntimeAccount -> IO OutcomeAccount
reloadAccount deps supervisor ref runtime = do
  loaded <- tryAny $ loadAccountRun deps.accountRunDSA ref
  case loaded of
    Left exception -> do
      let message = exceptionTextAccount "failed to reload account" exception
      atomically $ writeTVar runtime.statusRA $ ErrorSAR message
      pure $ failureOutcomeAccount ref.accountUidARD message

    Right (Left err) -> do
      let message = renderErrorApp err
      atomically $ writeTVar runtime.statusRA $ statusErrorAccount err message
      reauthoriseFailures <- case retryErrorApp err of
        ReauthoriseRE -> runHooksAccount deps.hooksDSA runtime $ ReauthoriseEA ref.accountUidARD
        _ -> pure V.empty

      pure OutcomeAccount {
          uidOA = Nothing
          , failuresOA = concatVectorsAccount [V.singleton (ref.accountUidARD, message), reauthoriseFailures]
        }

    Right (Right loadedRuntime) -> do
      let generation = nextGenerationAccount runtime.generationRA
      let runtimeNew = loadedRuntime {generationRA = generation}

      atomically $ do
        writeTVar runtime.statusRA StoppingSAR
        writeTVar runtimeNew.statusRA ReadySAR
        modifyTVar' supervisor.accountsSA $ Map.insert ref.accountUidARD runtimeNew

      hookFailures <- runHooksAccount deps.hooksDSA runtimeNew $ ReloadedEA ref.accountUidARD generation
      atomically $ writeTVar runtime.statusRA StoppedSAR

      pure OutcomeAccount {
          uidOA = Just ref.accountUidARD
          , failuresOA = hookFailures
        }


deactivateAccount :: DepsSupervisorAccount -> SupervisorAccount -> AccountUid -> RuntimeAccount -> IO OutcomeAccount
deactivateAccount deps supervisor accountUid runtime = do
  atomically $ do
    writeTVar runtime.statusRA StoppingSAR
    modifyTVar' supervisor.accountsSA $ Map.delete accountUid

  hookFailures <- runHooksAccount deps.hooksDSA runtime $ DeactivatedEA accountUid
  atomically $ writeTVar runtime.statusRA StoppedSAR

  pure OutcomeAccount {
      uidOA = Just accountUid
      , failuresOA = hookFailures
    }


stopAccountsSupervisor :: DepsSupervisorAccount -> SupervisorAccount -> IO ()
stopAccountsSupervisor deps supervisor = do
  accounts <- atomically $ do
    accounts <- readTVar supervisor.accountsSA
    writeTVar supervisor.accountsSA Map.empty
    traverse_Stopping accounts
    pure accounts

  void $ traverse (\(accountUid, runtime) -> deactivateRuntimeForStop deps accountUid runtime) $ Map.toList accounts


traverse_Stopping :: Map AccountUid RuntimeAccount -> STM ()
traverse_Stopping accounts =
  mapM_ (\runtime -> writeTVar runtime.statusRA StoppingSAR) $ Map.elems accounts


deactivateRuntimeForStop :: DepsSupervisorAccount -> AccountUid -> RuntimeAccount -> IO ()
deactivateRuntimeForStop deps accountUid runtime = do
  _ <- runHooksAccount deps.hooksDSA runtime $ DeactivatedEA accountUid
  atomically $ writeTVar runtime.statusRA StoppedSAR


runHooksAccount :: V.Vector (HookAccount IO) -> RuntimeAccount -> EventAccount -> IO (V.Vector (AccountUid, Text))
runHooksAccount hooks runtime event = do
  results <- traverse runHook $ V.toList hooks
  pure $ concatVectorsAccount results
  where
  accountUid = uidEventAccount event
  runHook :: HookAccount IO -> IO (V.Vector (AccountUid, Text))
  runHook hook = do
    result <- tryAny $ hook.eventHA runtime event
    case result of
      Left exception -> pure $ V.singleton (accountUid, exceptionTextAccount "account hook failed" exception)
      Right () -> pure V.empty


uidEventAccount :: EventAccount -> AccountUid
uidEventAccount event =
  case event of
    ActivatedEA accountUid _ -> accountUid
    ReloadedEA accountUid _ -> accountUid
    DeactivatedEA accountUid -> accountUid
    ReauthoriseEA accountUid -> accountUid


nextGenerationAccount :: GenerationAccount -> GenerationAccount
nextGenerationAccount (GenerationAccount value) =
  GenerationAccount $ value + 1


statusErrorAccount :: ErrorApp -> Text -> StatusAccountRun
statusErrorAccount err message =
  case retryErrorApp err of
    ReauthoriseRE -> ReauthoriseSAR
    _ -> ErrorSAR message


failureOutcomeAccount :: AccountUid -> Text -> OutcomeAccount
failureOutcomeAccount accountUid message =
  OutcomeAccount {
      uidOA = Nothing
      , failuresOA = V.singleton (accountUid, message)
    }


collectOutcomesAccount :: [OutcomeAccount] -> (V.Vector AccountUid, V.Vector (AccountUid, Text))
collectOutcomesAccount outcomes =
  let
    uids = concatMap (maybeToList . (.uidOA)) outcomes
    failures = concatMap (V.toList . (.failuresOA)) outcomes
  in
  (V.fromList uids, V.fromList failures)


concatVectorsAccount :: [V.Vector a] -> V.Vector a
concatVectorsAccount vectors =
  V.fromList $ concatMap V.toList vectors


renderErrorApp :: ErrorApp -> Text
renderErrorApp =
  Tx.pack . show


exceptionTextAccount :: Text -> SomeException -> Text
exceptionTextAccount context exception =
  context <> ": " <> Tx.pack (displayException exception)


exceptionErrorDB :: Text -> SomeException -> ErrorDb
exceptionErrorDB context exception =
  ErrorDb $ exceptionTextAccount context exception


tryAny :: IO a -> IO (Either SomeException a)
tryAny =
  try