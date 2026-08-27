{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module AutoMail.Blob.Types where

import Data.Aeson (Value)
import Data.ByteString (ByteString)
import Data.Int (Int64)
import Data.Text (Text)
import GHC.Generics (Generic)

import AutoMail.Model.Common (HashSha256)
import AutoMail.Model.Id (BlobUid, TenantUid)


data KindBlob =
    RawMessageKB
  | AttachmentKB
  | InlinePartKB
  | GeneratedKB
  deriving stock (Eq, Show, Generic)


data StorageBlob =
    InlineSB
  | ExternalSB Text
  deriving stock (Eq, Show, Generic)


data MetaBlob = MetaBlob {
    uidMB :: BlobUid
    , tenantUidMB :: TenantUid
    , kindMB :: KindBlob
    , mimeTypeMB :: Maybe Text
    , hashMB :: HashSha256
    , sizeBytesMB :: Int64
    , storageMB :: StorageBlob
    , metadataMB :: Value
  }
  deriving stock (Eq, Show, Generic)


data InputBlob = InputBlob {
    tenantUidIB :: TenantUid
    , kindIB :: KindBlob
    , mimeTypeIB :: Maybe Text
    , contentIB :: ByteString
    , metadataIB :: Value
  }
  deriving stock (Eq, Show, Generic)