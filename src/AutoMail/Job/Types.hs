{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module AutoMail.Job.Types where

import Data.Aeson (FromJSON, ToJSON, Value)
import Data.Text (Text)
import Data.Time.Clock (NominalDiffTime, UTCTime)
import qualified Data.Vector as V
import GHC.Generics (Generic)

import AutoMail.Model.Id (CorrelationKey, DedupeKey, JobUid, TenantUid)


newtype KindJob = KindJob Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


data StatusJob =
    PendingSJ
  | RunningSJ
  | CompletedSJ
  | FailedSJ
  | CancelledSJ
  deriving stock (Eq, Show, Generic)


data Job = Job {
    uidJ :: JobUid
    , tenantUidJ :: TenantUid
    , kindJ :: KindJob
    , statusJ :: StatusJob
    , priorityJ :: Int
    , dedupeKeyJ :: Maybe DedupeKey
    , payloadJ :: Value
    , notBeforeJ :: UTCTime
    , attemptCountJ :: Int
    , maxAttemptsJ :: Int
    , leaseOwnerJ :: Maybe Text
    , leaseUntilJ :: Maybe UTCTime
    , correlationKeyJ :: CorrelationKey
  }
  deriving stock (Eq, Show, Generic)


data RequestJob = RequestJob {
    tenantUidRJ :: TenantUid
    , kindRJ :: KindJob
    , priorityRJ :: Int
    , dedupeKeyRJ :: Maybe DedupeKey
    , payloadRJ :: Value
    , notBeforeRJ :: UTCTime
    , maxAttemptsRJ :: Int
    , correlationKeyRJ :: CorrelationKey
  }
  deriving stock (Eq, Show, Generic)


data ResultJob =
    CompleteRJ
  | RetryRJ NominalDiffTime Text
  | FailRJ Text
  | CancelRJ Text
  deriving stock (Eq, Show, Generic)


data RequestClaimJob = RequestClaimJob {
    workerRCJ :: Text
    , kindsRCJ :: V.Vector KindJob
    , leaseSecondsRCJ :: Int
  }
  deriving stock (Eq, Show, Generic)