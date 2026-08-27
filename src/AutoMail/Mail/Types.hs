{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module AutoMail.Mail.Types where

import Data.ByteString (ByteString)
import Data.Int (Int64)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Vector (Vector)
import GHC.Generics (Generic)

import AutoMail.Model.Common (HashSha256, VersionNo)
import AutoMail.Model.Id (
    AccountUid
    , AttachmentIdPrv
    , BlobUid
    , MessageIdPrv
    , MessageIdRfc
    , MessageUid
    , TenantUid
    , ThreadIdPrv
    , ThreadUid
  )


data DirectionMail =
    InboundDM
  | OutboundDM
  | DraftDM
  | SystemDM
  deriving stock (Eq, Show, Generic)


data AddressMail = AddressMail {
    addressAM :: Text
    , normalizedAM :: Text
    , displayNameAM :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)


data RoleAddressMail =
    FromRAM
  | SenderRAM
  | ReplyToRAM
  | ToRAM
  | CcRAM
  | BccRAM
  deriving stock (Eq, Show, Generic)


data HeaderMail = HeaderMail {
    nameHM :: Text
    , valueHM :: Text
  }
  deriving stock (Eq, Show, Generic)


data MessageMail = MessageMail {
    uidMM :: MessageUid
    , tenantUidMM :: TenantUid
    , accountUidMM :: AccountUid
    , threadUidMM :: Maybe ThreadUid
    , messageIdPrvMM :: MessageIdPrv
    , messageIdRfcMM :: Maybe MessageIdRfc
    , directionMM :: DirectionMail
    , internalAtMM :: Maybe UTCTime
    , sentAtMM :: Maybe UTCTime
    , receivedAtMM :: Maybe UTCTime
    , subjectMM :: Maybe Text
    , snippetMM :: Maybe Text
    , sizeBytesMM :: Maybe Int64
  }
  deriving stock (Eq, Show, Generic)


data ParsedMail = ParsedMail {
    messageIdPrvPM :: MessageIdPrv
    , threadIdPrvPM :: Maybe ThreadIdPrv
    , messageIdRfcPM :: Maybe MessageIdRfc
    , headersPM :: Vector HeaderMail
    , addressesPM :: Vector AddressRoleMail
    , partsPM :: Vector PartParsedMail
    , subjectPM :: Maybe Text
    , sentAtPM :: Maybe UTCTime
    , plainPM :: Maybe Text
    , htmlPM :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)


data AddressRoleMail = AddressRoleMail {
    roleARM :: RoleAddressMail
    , ordinalARM :: Int
    , valueARM :: AddressMail
    , rawARM :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)


data PartParsedMail = PartParsedMail {
    pathPPM :: Text
    , parentPathPPM :: Maybe Text
    , providerPartIdPPM :: Maybe Text
    , mimeTypePPM :: Text
    , charsetPPM :: Maybe Text
    , dispositionPPM :: Maybe Text
    , contentIdPPM :: Maybe Text
    , filenamePPM :: Maybe Text
    , transferEncodingPPM :: Maybe Text
    , contentPPM :: Maybe ByteString
    , attachmentIdPrvPPM :: Maybe AttachmentIdPrv
  }
  deriving stock (Eq, Show, Generic)


data ContentMail = ContentMail {
    plainCM :: Maybe Text
    , htmlCM :: Maybe Text
    , cleanCM :: Maybe Text
    , deltaCM :: Maybe Text
    , languageCM :: Maybe Text
    , normalizerCM :: Text
    , versionCM :: VersionNo
    , hashCM :: Maybe HashSha256
  }
  deriving stock (Eq, Show, Generic)


data OutgoingMail = OutgoingMail {
    fromOM :: AddressMail
    , replyToOM :: Vector AddressMail
    , toOM :: Vector AddressMail
    , ccOM :: Vector AddressMail
    , bccOM :: Vector AddressMail
    , subjectOM :: Text
    , textOM :: Maybe Text
    , htmlOM :: Maybe Text
    , headersOM :: Vector HeaderMail
    , attachmentsOM :: Vector AttachmentOutgoingMail
    , replyMessageUidOM :: Maybe MessageUid
    , threadIdPrvOM :: Maybe ThreadIdPrv
  }
  deriving stock (Eq, Show, Generic)


data AttachmentOutgoingMail = AttachmentOutgoingMail {
    filenameAOM :: Text
    , mimeTypeAOM :: Text
    , blobUidAOM :: BlobUid
    , dispositionAOM :: Maybe Text
    , contentIdAOM :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)