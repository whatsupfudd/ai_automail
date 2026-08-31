{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module AutoMail.Credential.Types (
    KindCred(..)
    , SecretCred (..)
    , mkSecretCred
    , bytesSecretCred
    , ContextCred(..)
    , EncryptedCred(..)
    , RuntimeCred
    , mkRuntimeCred
    , kindRC
    , secretRC
    , metadataRC
  ) where

import qualified Data.ByteString as Bs
import Data.Aeson (Value)
import Data.Text (Text)
import GHC.Generics (Generic)

import AutoMail.Model.Id


data KindCred =
    OAuthRefreshKC
  | PasswordKC
  | ServiceAccountKC
  | ExternalKC
  deriving stock (Eq, Show, Generic)


newtype SecretCred = SecretCred Bs.ByteString


mkSecretCred :: Bs.ByteString -> SecretCred
mkSecretCred secret =
  SecretCred secret


bytesSecretCred :: SecretCred -> Bs.ByteString
bytesSecretCred secret =
  case secret of
    SecretCred bytes -> bytes


data ContextCred = ContextCred {
    tenantUidCC :: TenantUid
    , credentialUidCC :: Maybe CredentialUid
    , kindCC :: KindCred
    , keyRefCC :: Text
  }
  deriving stock (Eq, Show, Generic)


data EncryptedCred = EncryptedCred {
    keyRefEC :: Text
    , ciphertextEC :: Bs.ByteString
    , nonceEC :: Bs.ByteString
    , metadataEC :: Value
  }
  deriving stock (Eq, Show, Generic)


data RuntimeCred = RuntimeCred {
    kindRC :: KindCred
    , secretRC :: SecretCred
    , metadataRC :: Value
  }


mkRuntimeCred :: KindCred -> SecretCred -> Value -> RuntimeCred
mkRuntimeCred kind secret metadata =
  RuntimeCred {
    kindRC = kind
    , secretRC = secret
    , metadataRC = metadata
  }