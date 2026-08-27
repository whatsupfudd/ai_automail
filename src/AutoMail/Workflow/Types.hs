{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module AutoMail.Workflow.Types where

import Data.Int (Int64)
import Data.Text (Text)
import Data.Time (NominalDiffTime, UTCTime)
import qualified Data.Vector as V

import GHC.Generics (Generic)
import Data.Aeson (FromJSON, ToJSON, Value)

import AutoMail.Action.Types (KindAct)
import AutoMail.Job.Types (KindJob)
import AutoMail.Knowledge.Types (Confidence, KindFact, KindObservation, ObservationKn)
import AutoMail.Mail.Event (EventMail)
import AutoMail.Model.Common (ExpressionRule, PathRule, VersionNo)
import AutoMail.Model.Id (
    EntityUid
    , MessageUid
    , ObjectiveUid
    , ObservationUid
    , PrincipalUid
    , SpaceUid
    , TenantUid
    , WorkflowEventUid
    , WorkflowInstanceUid
    , WorkflowVersionUid
  )


newtype KeyWorkflow = KeyWorkflow Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


newtype KeyStateWf = KeyStateWf Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


newtype KeyTransitionWf = KeyTransitionWf Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


newtype KeyEffectWf = KeyEffectWf Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


data StatusInstanceWf =
    ActiveSIW
  | WaitingSIW
  | CompletedSIW
  | FailedSIW
  | CancelledSIW
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data StateWf = StateWf {
    keySW :: KeyStateWf
    , terminalSW :: Bool
    , metadataSW :: Value
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data MatchObservationWf = MatchObservationWf {
    kindMOW :: Maybe KindObservation
    , conditionMOW :: Maybe ExpressionRule
    , minConfidenceMOW :: Maybe Confidence
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data ProposalTemplateAct = ProposalTemplateAct {
    kindPTA :: KindAct
    , payloadPTA :: Value
    , idempotencyScopePTA :: Text
    , notBeforePTA :: Maybe NominalDiffTime
    , expiresAfterPTA :: Maybe NominalDiffTime
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data RequestTemplateJob = RequestTemplateJob {
    kindRTJ :: KindJob
    , priorityRTJ :: Int
    , payloadRTJ :: Value
    , dedupeScopeRTJ :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data TemplateFactKn = TemplateFactKn {
    kindTFK :: KindFact
    , valueTFK :: Value
    , entityPathTFK :: Maybe PathRule
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data EffectWf =
    ProposeActionEW ProposalTemplateAct
  | EnqueueJobEW RequestTemplateJob
  | AssertFactEW TemplateFactKn
  | SetContextEW PathRule Value
  | CompleteObjectiveEW
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data TransitionWf = TransitionWf {
    keyTW :: KeyTransitionWf
    , fromTW :: KeyStateWf
    , matcherTW :: MatchObservationWf
    , guardTW :: Maybe ExpressionRule
    , toTW :: KeyStateWf
    , effectsTW :: V.Vector EffectWf
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data SpecWf = SpecWf {
    keySW :: KeyWorkflow
    , versionSW :: VersionNo
    , initialStateSW :: KeyStateWf
    , statesSW :: V.Vector StateWf
    , transitionsSW :: V.Vector TransitionWf
    , metadataSW :: Value
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data InstanceWf = InstanceWf {
    uidIW :: WorkflowInstanceUid
    , tenantUidIW :: TenantUid
    , spaceUidIW :: Maybe SpaceUid
    , objectiveUidIW :: Maybe ObjectiveUid
    , workflowVersionUidIW :: WorkflowVersionUid
    , subjectEntityUidIW :: Maybe EntityUid
    , keyIW :: Maybe Text
    , stateIW :: KeyStateWf
    , statusIW :: StatusInstanceWf
    , contextIW :: Value
    , startedAtIW :: UTCTime
    , updatedAtIW :: UTCTime
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data InputWf =
    ObservationIW ObservationKn
  | MailEventIW EventMail
  | ManualIW PrincipalUid Text Value
  | TimerIW Text Value
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data PlanTransitionWf = PlanTransitionWf {
    transitionPTW :: TransitionWf
    , fromPTW :: KeyStateWf
    , toPTW :: KeyStateWf
    , effectsPTW :: V.Vector EffectWf
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data ResultWf =
    NoMatchRW
  | TransitionRW PlanTransitionWf
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data EventWf = EventWf {
    uidEW :: WorkflowEventUid
    , workflowInstanceUidEW :: WorkflowInstanceUid
    , sequenceNoEW :: Int64
    , sourceMessageUidEW :: Maybe MessageUid
    , observationUidEW :: Maybe ObservationUid
    , principalUidEW :: Maybe PrincipalUid
    , kindEW :: Text
    , fromStateEW :: Maybe KeyStateWf
    , toStateEW :: Maybe KeyStateWf
    , payloadEW :: Value
    , createdAtEW :: UTCTime
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)