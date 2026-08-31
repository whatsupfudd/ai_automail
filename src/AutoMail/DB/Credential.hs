{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE QuasiQuotes #-}

module AutoMail.DB.Credential (
    CredentialDB(..)
    , CreateCredentialDB(..)
    , insertCredentialDB
    , fetchCredentialDB
    , rotateCredentialDB
    , revokeCredentialDB
  ) where

import Data.Aeson (Value)
import Data.ByteString (ByteString)
import Data.Int (Int64)
import Data.Profunctor (dimap)
import Data.Text (Text)
import Data.Time (UTCTime)

import GHC.Generics (Generic)

import Hasql.Statement (Statement)
import qualified Hasql.TH as HTH
import Hasql.Transaction (Transaction)
import qualified Hasql.Transaction as HT

import AutoMail.Credential.Types
import AutoMail.Model.Id


data CredentialDB = CredentialDB {
    uidCD :: CredentialUid
    , tenantUidCD :: TenantUid
    , kindCD :: KindCred
    , keyRefCD :: Text
    , ciphertextCD :: ByteString
    , nonceCD :: ByteString
    , metadataCD :: Value
    , createdAtCD :: UTCTime
    , rotatedAtCD :: Maybe UTCTime
    , expiresAtCD :: Maybe UTCTime
    , revokedAtCD :: Maybe UTCTime
  }
  deriving stock (Eq, Show, Generic)


data CreateCredentialDB = CreateCredentialDB {
    kindCCD :: KindCred
    , encryptedCCD :: EncryptedCred
    , expiresAtCCD :: Maybe UTCTime
  }
  deriving stock (Eq, Show, Generic)


type CredentialRowSqlDB =
  ( Int64
  , Int64
  , Text
  , Text
  , ByteString
  , ByteString
  , Value
  , UTCTime
  , Maybe UTCTime
  , Maybe UTCTime
  , Maybe UTCTime
  )


type CreateCredentialParamsSqlDB =
  ( Text
  , Text
  , ByteString
  , ByteString
  , Value
  , Maybe UTCTime
  )


type RotateCredentialParamsSqlDB =
  ( Int64
  , Text
  , ByteString
  , ByteString
  , Value
  , UTCTime
  )


insertCredentialDB ::
  CreateCredentialDB -> Transaction CredentialDB
insertCredentialDB request =
  HT.statement request insertCredentialStatementDB


fetchCredentialDB ::
  CredentialUid -> Transaction (Maybe CredentialDB)
fetchCredentialDB credentialUid =
  HT.statement credentialUid fetchCredentialStatementDB


rotateCredentialDB ::
  CredentialUid
  -> EncryptedCred
  -> UTCTime
  -> Transaction (Maybe CredentialDB)
rotateCredentialDB credentialUid encrypted rotatedAt =
  HT.statement
    (credentialUid, encrypted, rotatedAt)
    rotateCredentialStatementDB


revokeCredentialDB ::
  CredentialUid -> UTCTime -> Transaction (Maybe CredentialDB)
revokeCredentialDB credentialUid revokedAt =
  HT.statement
    (credentialUid, revokedAt)
    revokeCredentialStatementDB


insertCredentialStatementDB ::
  Statement CreateCredentialDB CredentialDB
insertCredentialStatementDB =
  dimap createCredentialToParamsDB credentialFromRowDB
    [HTH.singletonStatement|
      INSERT INTO am.credential (
        tenant_fk,
        kind,
        key_ref,
        ciphertext,
        nonce,
        metadata,
        expires_at
      )
      VALUES (
        am.current_tenant_uid(),
        $1 :: text,
        $2 :: text,
        $3 :: bytea,
        $4 :: bytea,
        $5 :: jsonb,
        $6 :: timestamptz?
      )
      RETURNING
        uid :: int8,
        tenant_fk :: int8,
        kind :: text,
        key_ref :: text,
        ciphertext :: bytea,
        nonce :: bytea,
        metadata :: jsonb,
        created_at :: timestamptz,
        rotated_at :: timestamptz?,
        expires_at :: timestamptz?,
        revoked_at :: timestamptz?
    |]


fetchCredentialStatementDB ::
  Statement CredentialUid (Maybe CredentialDB)
fetchCredentialStatementDB =
  dimap valueCredentialUidDB (fmap credentialFromRowDB)
    [HTH.maybeStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        kind :: text,
        key_ref :: text,
        ciphertext :: bytea,
        nonce :: bytea,
        metadata :: jsonb,
        created_at :: timestamptz,
        rotated_at :: timestamptz?,
        expires_at :: timestamptz?,
        revoked_at :: timestamptz?
      FROM am.credential
      WHERE uid = $1 :: int8
    |]


rotateCredentialStatementDB ::
  Statement
    (CredentialUid, EncryptedCred, UTCTime)
    (Maybe CredentialDB)
rotateCredentialStatementDB =
  dimap rotateCredentialToParamsDB (fmap credentialFromRowDB)
    [HTH.maybeStatement|
      UPDATE am.credential
      SET
        key_ref = $2 :: text,
        ciphertext = $3 :: bytea,
        nonce = $4 :: bytea,
        metadata = $5 :: jsonb,
        rotated_at = $6 :: timestamptz,
        revoked_at = NULL
      WHERE uid = $1 :: int8
      RETURNING
        uid :: int8,
        tenant_fk :: int8,
        kind :: text,
        key_ref :: text,
        ciphertext :: bytea,
        nonce :: bytea,
        metadata :: jsonb,
        created_at :: timestamptz,
        rotated_at :: timestamptz?,
        expires_at :: timestamptz?,
        revoked_at :: timestamptz?
    |]


revokeCredentialStatementDB ::
  Statement
    (CredentialUid, UTCTime)
    (Maybe CredentialDB)
revokeCredentialStatementDB =
  dimap toParamsDB (fmap credentialFromRowDB)
    [HTH.maybeStatement|
      UPDATE am.credential
      SET revoked_at =
        coalesce(revoked_at, $2 :: timestamptz)
      WHERE uid = $1 :: int8
      RETURNING
        uid :: int8,
        tenant_fk :: int8,
        kind :: text,
        key_ref :: text,
        ciphertext :: bytea,
        nonce :: bytea,
        metadata :: jsonb,
        created_at :: timestamptz,
        rotated_at :: timestamptz?,
        expires_at :: timestamptz?,
        revoked_at :: timestamptz?
    |]
  where
  toParamsDB (credentialUid, revokedAt) =
    (valueCredentialUidDB credentialUid, revokedAt)


createCredentialToParamsDB ::
  CreateCredentialDB -> CreateCredentialParamsSqlDB
createCredentialToParamsDB request =
  ( renderKindCredDB request.kindCCD
  , request.encryptedCCD.keyRefEC
  , request.encryptedCCD.ciphertextEC
  , request.encryptedCCD.nonceEC
  , request.encryptedCCD.metadataEC
  , request.expiresAtCCD
  )


rotateCredentialToParamsDB ::
  (CredentialUid, EncryptedCred, UTCTime)
  -> RotateCredentialParamsSqlDB
rotateCredentialToParamsDB
  (credentialUid, encrypted, rotatedAt) =
  ( valueCredentialUidDB credentialUid
  , encrypted.keyRefEC
  , encrypted.ciphertextEC
  , encrypted.nonceEC
  , encrypted.metadataEC
  , rotatedAt
  )


credentialFromRowDB ::
  CredentialRowSqlDB -> CredentialDB
credentialFromRowDB
  ( uid
  , tenantUid
  , kind
  , keyRef
  , ciphertext
  , nonce
  , metadata
  , createdAt
  , rotatedAt
  , expiresAt
  , revokedAt
  ) =
  CredentialDB {
      uidCD = CredentialUid uid
      , tenantUidCD = TenantUid tenantUid
      , kindCD = parseKindCredDB kind
      , keyRefCD = keyRef
      , ciphertextCD = ciphertext
      , nonceCD = nonce
      , metadataCD = metadata
      , createdAtCD = createdAt
      , rotatedAtCD = rotatedAt
      , expiresAtCD = expiresAt
      , revokedAtCD = revokedAt
    }


valueCredentialUidDB :: CredentialUid -> Int64
valueCredentialUidDB credentialUid =
  case credentialUid of
    CredentialUid value -> value


renderKindCredDB :: KindCred -> Text
renderKindCredDB kindCred =
  case kindCred of
    OAuthRefreshKC -> "oauth_refresh"
    PasswordKC -> "password"
    ServiceAccountKC -> "service_account"
    ExternalKC -> "external"


parseKindCredDB :: Text -> KindCred
parseKindCredDB value =
  case value of
    "oauth_refresh" -> OAuthRefreshKC
    "password" -> PasswordKC
    "service_account" -> ServiceAccountKC
    "external" -> ExternalKC
    _ -> ExternalKC