module AutoMail.Analysis.Driver where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Mp

import AutoMail.Analysis.Types
import AutoMail.App.Error (ErrorAn)


data DriverAn m = DriverAn {
    engineDA :: EngineAn
    , analyseDA :: RequestAn -> m (Either ErrorAn ResultAn)
  }


newtype RegistryAn m = RegistryAn (Map EngineAn (DriverAn m))


emptyRegistryAn :: RegistryAn m
emptyRegistryAn = RegistryAn Mp.empty


registerAn :: DriverAn m -> RegistryAn m -> RegistryAn m
registerAn driver (RegistryAn registry) =
  RegistryAn $ Mp.insert driver.engineDA driver registry


lookupAn :: EngineAn -> RegistryAn m -> Maybe (DriverAn m)
lookupAn engine (RegistryAn registry) =
  Mp.lookup engine registry