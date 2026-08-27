{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE DeriveAnyClass #-}

module AutoMail.Action.Types where

import Data.Text (Text)
import Data.Time (UTCTime)

import GHC.Generics (Generic)
import Data.Aeson (FromJSON, ToJSON, Value)

import AutoMail.App.Error (RetryError)
import AutoMail.Model.Id (
    ActionUid
    , AnalysisUid
    , CorrelationKey
    , IdempotencyKey
    , MessageUid
    , PrincipalUid
    , SpaceUid
    , TenantUid
    , WorkflowEventUid
    , WorkflowInstanceUid
  )


newtype KindAct = KindAct Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


data AuthorityAct =
    ObserveAA
  | SafeProviderAA
  | InternalAA
  | DraftAA
  | ConditionalSendAA
  | ApprovalAA
  | ProhibitedAA
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)
  deriving anyclass (FromJSON, ToJSON)


data StatusAct =
    ProposedSA
  | ApprovalRequiredSA
  | ApprovedSA
  | ExecutingSA
  | CompletedSA
  | FailedSA
  | RejectedSA
  | CancelledSA
  | ExpiredSA
  deriving stock (Eq, Show, Generic)


data ProposalAct = ProposalAct {
    tenantUidPA :: TenantUid
    , spaceUidPA :: Maybe SpaceUid
    , workflowInstanceUidPA :: Maybe WorkflowInstanceUid
    , workflowEventUidPA :: Maybe WorkflowEventUid
    , sourceMessageUidPA :: Maybe MessageUid
    , analysisUidPA :: Maybe AnalysisUid
    , kindPA :: KindAct
    , payloadPA :: Value
    , idempotencyKeyPA :: IdempotencyKey
    , notBeforePA :: Maybe UTCTime
    , expiresAtPA :: Maybe UTCTime
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data Action = Action {
    uidA :: ActionUid
    , tenantUidA :: TenantUid
    , kindA :: KindAct
    , statusA :: StatusAct
    , authorityA :: AuthorityAct
    , idempotencyKeyA :: IdempotencyKey
    , payloadA :: Value
    , createdAtA :: UTCTime
    , notBeforeA :: Maybe UTCTime
    , expiresAtA :: Maybe UTCTime
  }
  deriving stock (Eq, Show, Generic)


data DecisionApprovalAct =
    ApproveDAA
  | RejectDAA
  | CancelDAA
  deriving stock (Eq, Show, Generic)


data ApprovalAct = ApprovalAct {
    actionUidAA :: ActionUid
    , principalUidAA :: PrincipalUid
    , decisionAA :: DecisionApprovalAct
    , noteAA :: Maybe Text
    , decidedAtAA :: UTCTime
  }
  deriving stock (Eq, Show, Generic)


data RequestExecuteAct = RequestExecuteAct {
    actionREA :: Action
    , attemptNoREA :: Int
    , correlationKeyREA :: CorrelationKey
  }
  deriving stock (Eq, Show, Generic)


data ResultAct =
    CompletedRA Value
  | FailedRA Text RetryError
  | IndeterminateRA Text
  deriving stock (Eq, Show, Generic)