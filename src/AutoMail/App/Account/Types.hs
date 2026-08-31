{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module AutoMail.App.Account.Types (
    StatusAccountRun(..)
    , GenerationAccount(..)
    , RuntimeAccount(..)
    , EventAccount(..)
    , HookAccount(..)
    , generationInitialAccount
    , generationNextAccount
    , readStatusAccountRun
    , writeStatusAccountRun
    , modifyStatusAccountRun
    , hookNoopAccount
  ) where

import Control.Concurrent.STM (STM, TVar, modifyTVar', readTVar, writeTVar)

import Data.Int (Int64)
import qualified Data.Map as Mp
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)

import AutoMail.DB.Account (AccountDB)
import AutoMail.Model.Id (AccountUid)
import AutoMail.Provider.Types (AccountPrv, KindPrv)
import AutoMail.Credential.Types (RuntimeCred)
import AutoMail.App.Error (ErrorPrv)


data StatusAccountRun =
    StartingSAR
  | ReadySAR
  | ReauthoriseSAR
  | ErrorSAR Text
  | StoppingSAR
  | StoppedSAR
  deriving stock (Eq, Show, Generic)


newtype GenerationAccount = GenerationAccount Int64
  deriving stock (Eq, Ord, Show, Generic)


data RuntimeAccount = RuntimeAccount {
    accountRA :: AccountDB
    , providerRA :: AccountPrv
    , generationRA :: GenerationAccount
    , startedAtRA :: UTCTime
    , statusRA :: TVar StatusAccountRun
  }


data EventAccount =
    ActivatedEA AccountUid GenerationAccount
  | ReloadedEA AccountUid GenerationAccount
  | DeactivatedEA AccountUid
  | ReauthoriseEA AccountUid
  deriving stock (Eq, Show, Generic)


data HookAccount m = HookAccount {
    eventHA :: RuntimeAccount -> EventAccount -> m ()
  }


generationInitialAccount :: GenerationAccount
generationInitialAccount =
  GenerationAccount 1


generationNextAccount :: GenerationAccount -> GenerationAccount
generationNextAccount generation =
  case generation of
    GenerationAccount value -> GenerationAccount $ value + 1


readStatusAccountRun :: RuntimeAccount -> STM StatusAccountRun
readStatusAccountRun runtime =
  readTVar runtime.statusRA


writeStatusAccountRun :: RuntimeAccount -> StatusAccountRun -> STM ()
writeStatusAccountRun runtime status =
  writeTVar runtime.statusRA status


modifyStatusAccountRun :: RuntimeAccount -> (StatusAccountRun -> StatusAccountRun) -> STM ()
modifyStatusAccountRun runtime update =
  modifyTVar' runtime.statusRA update


hookNoopAccount :: Applicative m => HookAccount m
hookNoopAccount =
  HookAccount $ \_ _ -> pure ()
