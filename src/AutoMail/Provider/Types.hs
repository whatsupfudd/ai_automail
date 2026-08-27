{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}

module AutoMail.Provider.Types where

import Data.Aeson (FromJSON, ToJSON, Value)
import qualified Data.ByteString as Bs
import Data.Int (Int64)
import Data.Text (Text)
import Data.Time (UTCTime)
import qualified Data.Vector as V
import GHC.Generics (Generic)

import AutoMail.Model.Common (TokenPage)
import AutoMail.Model.Id (AccountUid, AttachmentIdPrv, CollectionIdPrv, CursorPrv, EventIdPrv, MessageIdPrv, MessageIdRfc, TenantUid, ThreadIdPrv, UserIdPrv)


data KindPrv =
    GmailKP
  | ImapSmtpKP
  | JmapKP
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data CapabilityPrv =
    ReadCP
  | ChangeCP
  | WatchCP
  | DraftCP
  | SendCP
  | CollectionCP
  deriving stock (Eq, Ord, Show, Generic)


-- Runtime-only resolved provider credential. This type deliberately has no
-- Show or JSON instances so secrets cannot be logged or serialized through
-- ordinary generic mechanisms.
data CredentialPrv = CredentialPrv {
    kindCP :: Text
    , secretCP :: Bs.ByteString
    , metadataCP :: Value
  }


-- Runtime provider account context. Provider-specific configuration remains
-- opaque to the AutoMail core and is decoded by the relevant provider adapter.
--
-- This type deliberately has no Show or JSON instances because it contains a
-- resolved CredentialPrv.
data AccountPrv = AccountPrv {
    tenantUidAP :: TenantUid
    , accountUidAP :: AccountUid
    , kindAP :: KindPrv
    , addressAP :: Text
    , credentialAP :: CredentialPrv
    , configAP :: Value
  }


data ProfilePrv = ProfilePrv {
    userIdPP :: Maybe UserIdPrv
    , addressPP :: Text
    , messagesTotalPP :: Maybe Int64
    , threadsTotalPP :: Maybe Int64
    , metadataPP :: Value
  }
  deriving stock (Eq, Show, Generic)


data KindCollectionPrv =
    MailboxKCP
  | LabelKCP
  | FolderKCP
  | SystemKCP
  deriving stock (Eq, Show, Generic)


data CollectionPrv = CollectionPrv {
    collectionIdCP :: CollectionIdPrv
    , parentIdCP :: Maybe CollectionIdPrv
    , nameCP :: Text
    , kindCP :: KindCollectionPrv
    , selectableCP :: Bool
    , attributesCP :: Value
  }
  deriving stock (Eq, Show, Generic)


-- Provider-neutral message representation.
--
-- rawMP contains the original RFC 5322/MIME source when the provider makes it
-- available. payloadMP preserves additional provider metadata without exposing
-- its provider-specific structure to the AutoMail core.
data MessagePrv = MessagePrv {
    messageIdMP :: MessageIdPrv
    , threadIdMP :: Maybe ThreadIdPrv
    , messageIdRfcMP :: Maybe MessageIdRfc
    , internalAtMP :: Maybe UTCTime
    , collectionsMP :: V.Vector CollectionIdPrv
    , sizeBytesMP :: Maybe Int64
    , rawMP :: Maybe Bs.ByteString
    , payloadMP :: Value
  }
  deriving stock (Eq, Show, Generic)


data AttachmentPrv = AttachmentPrv {
    attachmentIdAP :: AttachmentIdPrv
    , messageIdAP :: MessageIdPrv
    , dataAP :: Bs.ByteString
    , metadataAP :: Value
  }
  deriving stock (Eq, Show, Generic)


data RequestSyncPrv = RequestSyncPrv {
    pageSizeRSP :: Int
    , pageTokenRSP :: Maybe TokenPage
    , newerThanRSP :: Maybe UTCTime
    , metadataRSP :: Value
  }
  deriving stock (Eq, Show, Generic)


data PageSyncPrv = PageSyncPrv {
    messagesPSP :: V.Vector MessageIdPrv
    , nextPSP :: Maybe TokenPage
    , cursorPSP :: Maybe CursorPrv
    , metadataPSP :: Value
  }
  deriving stock (Eq, Show, Generic)


data KindChangePrv =
    MessageAddedKCP
  | MessageDeletedKCP
  | CollectionAddedKCP
  | CollectionRemovedKCP
  deriving stock (Eq, Show, Generic)


data ChangePrv = ChangePrv {
    kindCP :: KindChangePrv
    , messageIdCP :: MessageIdPrv
    , collectionIdCP :: Maybe CollectionIdPrv
    , metadataCP :: Value
  }
  deriving stock (Eq, Show, Generic)


-- cursorPCP is the provider checkpoint reached after all changes in changesPCP.
-- AutoMail must persist the cursor only after those changes have been recorded
-- durably.
data PageChangePrv = PageChangePrv {
    changesPCP :: V.Vector ChangePrv
    , cursorPCP :: CursorPrv
    , nextPCP :: Maybe TokenPage
    , metadataPCP :: Value
  }
  deriving stock (Eq, Show, Generic)


data RequestWatchPrv = RequestWatchPrv {
    targetRWP :: Maybe Text
    , collectionsRWP :: V.Vector CollectionIdPrv
    , metadataRWP :: Value
  }
  deriving stock (Eq, Show, Generic)


data WatchPrv = WatchPrv {
    cursorWP :: Maybe CursorPrv
    , expiresAtWP :: Maybe UTCTime
    , metadataWP :: Value
  }
  deriving stock (Eq, Show, Generic)


data EventPrv = EventPrv {
    eventIdEP :: Maybe EventIdPrv
    , cursorEP :: Maybe CursorPrv
    , occurredAtEP :: Maybe UTCTime
    , payloadEP :: Value
  }
  deriving stock (Eq, Show, Generic)