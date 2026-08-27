{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module AutoMail.Mail.Event where

import Data.Aeson (FromJSON, ToJSON, Value)
import Data.Time (UTCTime)
import GHC.Generics (Generic)

import AutoMail.Model.Id (AccountUid, CorrelationKey, MessageUid, TenantUid)


data KindEventMail =
    StoredKEM
  | NormalizedKEM
  | AttachmentAvailableKEM
  | DeletedKEM
  | DraftUpdatedKEM
  | SentKEM
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data EventMail = EventMail {
    tenantUidEM :: TenantUid
    , accountUidEM :: AccountUid
    , messageUidEM :: MessageUid
    , kindEM :: KindEventMail
    , correlationKeyEM :: CorrelationKey
    , occurredAtEM :: UTCTime
    , metadataEM :: Value
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)