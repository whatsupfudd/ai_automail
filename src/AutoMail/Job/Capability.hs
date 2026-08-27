module AutoMail.Job.Capability where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Mp
import Data.Text (Text)
import Data.Time (UTCTime)

import AutoMail.App.Error (ErrorJob)
import AutoMail.Job.Types (Job, KindJob, RequestClaimJob, RequestJob, ResultJob)
import AutoMail.Model.Id (JobUid)


data QueueJob m = QueueJob {
    enqueueQJ :: RequestJob -> m (Either ErrorJob JobUid)
    , claimQJ :: RequestClaimJob -> m (Either ErrorJob (Maybe Job))
    , heartbeatQJ :: JobUid -> Text -> UTCTime -> m (Either ErrorJob ())
    , completeQJ :: JobUid -> Text -> m (Either ErrorJob ())
    , retryQJ :: JobUid -> Text -> UTCTime -> Text -> m (Either ErrorJob ())
    , failQJ :: JobUid -> Text -> Text -> m (Either ErrorJob ())
    , cancelQJ :: JobUid -> Text -> m (Either ErrorJob ())
    , recoverQJ :: UTCTime -> m (Either ErrorJob Int)
  }


data HandlerJob m = HandlerJob {
    kindHJ :: KindJob
    , runHJ :: Job -> m ResultJob
  }


newtype RegistryJob m = RegistryJob (Map KindJob (HandlerJob m))


emptyRegistryJob :: RegistryJob m
emptyRegistryJob = RegistryJob Mp.empty


registerJob :: HandlerJob m -> RegistryJob m -> RegistryJob m
registerJob handler (RegistryJob handlers) =
  RegistryJob $ Mp.insert handler.kindHJ handler handlers


lookupJob :: KindJob -> RegistryJob m -> Maybe (HandlerJob m)
lookupJob kind (RegistryJob handlers) = Mp.lookup kind handlers