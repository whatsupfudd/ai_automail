{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module AutoMail.Analysis.Types where

import Data.Aeson (FromJSON, ToJSON, Value)
import Data.Text (Text)
import qualified Data.Vector as V
import GHC.Generics (Generic)

import AutoMail.Model.Common (VersionNo)
import AutoMail.Model.Id (
    AttachmentUid
    , ConversationUid
    , MessageUid
    , PartUid
    , TenantUid
    , ThreadUid
  )


newtype KindAn = KindAn Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


newtype EngineAn = EngineAn Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


data SubjectAn =
    MessageSA MessageUid
  | AttachmentSA AttachmentUid
  | ThreadSA ThreadUid
  | ConversationSA ConversationUid
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data SchemaAn = SchemaAn {
    keySA :: Text
    , versionSA :: VersionNo
    , valueSA :: Value
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data ContextAn = ContextAn {
    tenantUidCA :: TenantUid
    , subjectCA :: SubjectAn
    , textCA :: Text
    , contextCA :: Value
    , evidenceCA :: V.Vector EvidenceInputAn
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data EvidenceInputAn = EvidenceInputAn {
    messageUidEIA :: MessageUid
    , partUidEIA :: Maybe PartUid
    , attachmentUidEIA :: Maybe AttachmentUid
    , fragmentEIA :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data RequestAn = RequestAn {
    kindRA :: KindAn
    , engineRA :: EngineAn
    , modelRA :: Maybe Text
    , schemaRA :: SchemaAn
    , contextRA :: ContextAn
    , metadataRA :: Value
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data UsageAn = UsageAn {
    inputTokensUA :: Maybe Int
    , outputTokensUA :: Maybe Int
    , durationMsUA :: Maybe Int
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data ResultAn = ResultAn {
    engineRA :: EngineAn
    , modelRA :: Maybe Text
    , modelVersionRA :: Maybe Text
    , outputRA :: Value
    , usageRA :: UsageAn
    , metadataRA :: Value
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)