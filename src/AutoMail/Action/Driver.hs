module AutoMail.Action.Driver where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M

import AutoMail.Action.Types (KindAct, RequestExecuteAct, ResultAct)
import AutoMail.App.Error (ErrorAct)


data ExecutorAct m = ExecutorAct {
    kindEA :: KindAct
    , executeEA :: RequestExecuteAct -> m (Either ErrorAct ResultAct)
  }


newtype RegistryAct m = RegistryAct (Map KindAct (ExecutorAct m))


emptyRegistryAct :: RegistryAct m
emptyRegistryAct = RegistryAct M.empty


registerAct :: ExecutorAct m -> RegistryAct m -> RegistryAct m
registerAct executor (RegistryAct executors) =
  RegistryAct $ M.insert executor.kindEA executor executors


lookupAct :: KindAct -> RegistryAct m -> Maybe (ExecutorAct m)
lookupAct kind (RegistryAct executors) =
  M.lookup kind executors