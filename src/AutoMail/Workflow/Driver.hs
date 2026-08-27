module AutoMail.Workflow.Driver (
    EvaluatorWf(..)
    , DriverWf(..)
  ) where

import qualified Data.Vector as V

import AutoMail.App.Error (ErrorWf)
import AutoMail.Model.Common (ContextTenant)
import AutoMail.Workflow.Types (EventWf, InputWf, InstanceWf, ResultWf, SpecWf)


data EvaluatorWf = EvaluatorWf {
    evaluateEW :: SpecWf -> InstanceWf -> InputWf -> Either ErrorWf ResultWf
  }


data DriverWf m = DriverWf {
    processDW :: ContextTenant -> InputWf -> m (Either ErrorWf (V.Vector EventWf))
  }