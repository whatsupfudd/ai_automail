{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module AutoMail.Model.Id (
    TenantUid(..), SpaceUid(..), PrincipalUid(..), CredentialUid(..)
    , AccountUid(..), MailboxUid(..), ThreadUid(..), MessageUid(..)
    , PartUid(..), AttachmentUid(..), BlobUid(..), ConversationUid(..)
    , AnalysisUid(..), EvidenceUid(..), FeedbackUid(..)
    , EntityUid(..), MentionUid(..), ObservationUid(..), FactUid(..)
    , RelationUid(..), ObjectiveUid(..)
    , WorkflowDefUid(..), WorkflowVersionUid(..), WorkflowInstanceUid(..)
    , WorkflowEventUid(..)
    , PolicyDefUid(..), PolicyVersionUid(..)
    , ActionUid(..), ApprovalUid(..), ActionAttemptUid(..)
    , DraftUid(..), JobUid(..), JobAttemptUid(..), AuditUid(..)
    , MessageIdPrv(..), ThreadIdPrv(..), CollectionIdPrv(..)
    , AttachmentIdPrv(..), DraftIdPrv(..), EventIdPrv(..), UserIdPrv(..)
    , CursorPrv(..), MessageIdRfc(..), CorrelationKey(..)
    , DedupeKey(..), IdempotencyKey(..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Hashable (Hashable)
import Data.Int (Int64)
import Data.Text (Text)
import GHC.Generics (Generic)


newtype TenantUid = TenantUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype SpaceUid = SpaceUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype PrincipalUid = PrincipalUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype CredentialUid = CredentialUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype AccountUid = AccountUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype MailboxUid = MailboxUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype ThreadUid = ThreadUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype MessageUid = MessageUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype PartUid = PartUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype AttachmentUid = AttachmentUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype BlobUid = BlobUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype ConversationUid = ConversationUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype AnalysisUid = AnalysisUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype EvidenceUid = EvidenceUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype FeedbackUid = FeedbackUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype EntityUid = EntityUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype MentionUid = MentionUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype ObservationUid = ObservationUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype FactUid = FactUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype RelationUid = RelationUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype ObjectiveUid = ObjectiveUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype WorkflowDefUid = WorkflowDefUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype WorkflowVersionUid = WorkflowVersionUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype WorkflowInstanceUid = WorkflowInstanceUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype WorkflowEventUid = WorkflowEventUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype PolicyDefUid = PolicyDefUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype PolicyVersionUid = PolicyVersionUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype ActionUid = ActionUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype ApprovalUid = ApprovalUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype ActionAttemptUid = ActionAttemptUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype DraftUid = DraftUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype JobUid = JobUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype JobAttemptUid = JobAttemptUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype AuditUid = AuditUid Int64
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype MessageIdPrv = MessageIdPrv Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype ThreadIdPrv = ThreadIdPrv Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype CollectionIdPrv = CollectionIdPrv Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype AttachmentIdPrv = AttachmentIdPrv Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype DraftIdPrv = DraftIdPrv Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype EventIdPrv = EventIdPrv Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype UserIdPrv = UserIdPrv Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype CursorPrv = CursorPrv Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype MessageIdRfc = MessageIdRfc Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype CorrelationKey = CorrelationKey Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype DedupeKey = DedupeKey Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)


newtype IdempotencyKey = IdempotencyKey Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, Hashable)