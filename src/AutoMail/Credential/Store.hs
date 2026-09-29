{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE RankNTypes #-}

module AutoMail.Credential.Store (
    StoreCred(..), mkStoreCred, emptyStoreCred
  ) where

import Data.Bifunctor (first)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as Tx
import qualified Data.Time.Clock as Tm

import Data.Aeson (Value(..), object, (.=))
import qualified Data.Aeson.KeyMap as KM

import Hasql.Transaction.Sessions (IsolationLevel(ReadCommitted), Mode(Read, Write))
import Hasql.Transaction (Transaction)

import AutoMail.App.Error (ErrorCred, ErrorDb, mkErrorCred)
import AutoMail.Credential.Crypto (CryptoCred(..))
import AutoMail.Credential.Types (
    ContextCred(..), EncryptedCred(..), KindCred, RuntimeCred(..), SecretCred (..)
  )
import AutoMail.DB.Core (PoolDB, runTenantDB)
import AutoMail.DB.Credential (
    CreateCredentialDB(..), CredentialDB(..), fetchCredentialDB, insertCredentialDB,
    revokeCredentialDB, rotateCredentialDB
  )
import AutoMail.Model.Common (ContextTenant(..))
import AutoMail.Model.Id (CorrelationKey(..), CredentialUid(..), TenantUid(..))
import AutoMail.Model.Time (Clock(..))


data StoreCred m = StoreCred {
    loadSC :: TenantUid -> CredentialUid -> m (Either ErrorCred RuntimeCred)
    , createSC :: TenantUid -> KindCred -> SecretCred -> Value -> m (Either ErrorCred CredentialUid)
    , rotateSC :: TenantUid -> CredentialUid -> SecretCred -> m (Either ErrorCred ())
    , revokeSC :: TenantUid -> CredentialUid -> m (Either ErrorCred ())
  }


emptyStoreCred :: StoreCred IO
emptyStoreCred =
  StoreCred {
    loadSC = \_ _ -> pure $ Left $ mkErrorCred "loadStoreCred not implemented"
    , createSC = \_ _ _ _ -> pure $ Left $ mkErrorCred "createStoreCred not implemented"
    , rotateSC = \_ _ _ -> pure $ Left $ mkErrorCred "rotateStoreCred not implemented"
    , revokeSC = \_ _ -> pure $ Left $ mkErrorCred "revokeStoreCred not implemented"
  }

mkStoreCred :: PoolDB -> CryptoCred IO -> Clock IO -> StoreCred IO
mkStoreCred pool crypto clock =
  StoreCred {
    loadSC = loadStoreCred pool crypto clock
    , createSC = createStoreCred pool crypto
    , rotateSC = rotateStoreCred pool crypto clock
    , revokeSC = revokeStoreCred pool clock
  }


loadStoreCred :: PoolDB -> CryptoCred IO -> Clock IO -> TenantUid -> CredentialUid -> IO (Either ErrorCred RuntimeCred)
loadStoreCred pool crypto clock tenantUid credentialUid = do
  now <- clock.nowC
  fetched <- fetchCredentialStore pool tenantUid credentialUid "load"
  case fetched of
    Left errorCred -> pure $ Left errorCred
    Right credential ->
      case validateLoadCredential now credential of
        Left errorCred -> pure $ Left errorCred
        Right () ->
          let
            encrypted = encryptedCredentialDB credential
          in do
          decrypted <- crypto.decryptCC (contextCredentialDB credential) encrypted
          pure $ case decrypted of
            Left errorCred -> Left errorCred
            Right secret -> 
              {- Right RuntimeCred {
                  kindRC = credential.kindCD
                  , secretRC = secret
                  , metadataRC = metadataRuntimeCredential credential
                }
              -}
              Left $ mkErrorCred $ "loadStoreCred: implemented" :: Either ErrorCred RuntimeCred


createStoreCred :: PoolDB -> CryptoCred IO -> TenantUid -> KindCred -> SecretCred -> Value -> IO (Either ErrorCred CredentialUid)
createStoreCred pool crypto tenantUid kindCred secret metadata = do
  encryptedResult <- crypto.encryptCC (contextNewCredential tenantUid kindCred) secret
  case encryptedResult of
    Left errorCred -> pure $ Left errorCred
    Right encrypted -> do
      let stored = storeMetadataEncrypted metadata encrypted
      inserted <- runCredWriteDB pool tenantUid "create" $
        insertCredentialDB CreateCredentialDB {
            kindCCD = kindCred
            , encryptedCCD = stored
            , expiresAtCCD = Nothing
          }
      pure $ fmap (\credential -> credential.uidCD) inserted


rotateStoreCred :: PoolDB -> CryptoCred IO -> Clock IO -> TenantUid -> CredentialUid -> SecretCred -> IO (Either  ErrorCred ())
rotateStoreCred pool crypto clock tenantUid credentialUid secret = do
  now <- clock.nowC
  fetched <- fetchCredentialStore pool tenantUid credentialUid "rotate.fetch"
  case fetched of
    Left errorCred -> pure $ Left errorCred
    Right credential ->
      case validateRotateCredential credential of
        Left errorCred -> pure $ Left errorCred
        Right () -> do
          encryptedResult <- crypto.encryptCC (contextCredentialDB credential) secret
          case encryptedResult of
            Left errorCred -> pure $ Left errorCred
            Right encrypted -> do
              let stored = storeMetadataEncrypted (metadataRuntimeCredential credential) encrypted
              rotated <- runCredWriteDB pool tenantUid "rotate.write" $ rotateCredentialDB credentialUid stored now
              pure $ case rotated of
                Left errorCred -> Left errorCred
                Right Nothing -> Left $ missingCredentialError credentialUid
                Right (Just _) -> Right ()


revokeStoreCred :: PoolDB -> Clock IO -> TenantUid -> CredentialUid -> IO (Either  ErrorCred ())
revokeStoreCred pool clock tenantUid credentialUid = do
  now <- clock.nowC
  revoked <- runCredWriteDB pool tenantUid "revoke" $ revokeCredentialDB credentialUid now
  pure $ case revoked of
    Left errorCred -> Left errorCred
    Right Nothing -> Left $ missingCredentialError credentialUid
    Right (Just _) -> Right ()


fetchCredentialStore :: PoolDB -> TenantUid -> CredentialUid -> Text -> IO (Either ErrorCred CredentialDB)
fetchCredentialStore pool tenantUid credentialUid operation = do
  fetched <- runCredReadDB pool tenantUid operation $ fetchCredentialDB credentialUid
  pure $ case fetched of
    Left errorCred -> Left errorCred
    Right Nothing -> Left $ missingCredentialError credentialUid
    Right (Just credential) -> validateTenantCredential tenantUid credential


runCredReadDB :: PoolDB -> TenantUid -> Text -> Transaction a -> IO (Either ErrorCred a)
runCredReadDB pool tenantUid operation transaction =
  runCredDB pool tenantUid operation Read transaction


runCredWriteDB :: PoolDB -> TenantUid -> Text -> Transaction a -> IO (Either ErrorCred a)
runCredWriteDB pool tenantUid operation transaction =
  runCredDB pool tenantUid operation Write transaction


runCredDB :: PoolDB -> TenantUid -> Text -> Mode -> Transaction a -> IO (Either ErrorCred a)
runCredDB pool tenantUid operation mode transaction = do
  result <- runTenantDB pool (contextTenantCred tenantUid operation) ReadCommitted mode transaction
  pure $ first (databaseCredentialError operation) result


contextTenantCred :: TenantUid -> Text -> ContextTenant
contextTenantCred tenantUid operation =
  ContextTenant {
      tenantUidCT = tenantUid
      , principalUidCT = Nothing
      , correlationKeyCT = CorrelationKey $ "credential." <> operation <> "." <> renderTenantUid tenantUid
    }


contextNewCredential :: TenantUid -> KindCred -> ContextCred
contextNewCredential tenantUid kindCred =
  ContextCred {
      tenantUidCC = tenantUid
      , credentialUidCC = Nothing
      , kindCC = kindCred
      , keyRefCC = ""
    }


contextCredentialDB :: CredentialDB -> ContextCred
contextCredentialDB credential =
  ContextCred {
      tenantUidCC = credential.tenantUidCD
      , credentialUidCC = Just credential.uidCD
      , kindCC = credential.kindCD
      , keyRefCC = credential.keyRefCD
    }


encryptedCredentialDB :: CredentialDB -> EncryptedCred
encryptedCredentialDB credential =
  let
    metadata = unpackMetadataCred credential.metadataCD
  in
  EncryptedCred {
      keyRefEC = credential.keyRefCD
      , ciphertextEC = credential.ciphertextCD
      , nonceEC = credential.nonceCD
      , metadataEC = metadata.cryptoMSC
    }


metadataRuntimeCredential :: CredentialDB -> Value
metadataRuntimeCredential credential =
  (unpackMetadataCred credential.metadataCD).credentialMSC


storeMetadataEncrypted :: Value -> EncryptedCred -> EncryptedCred
storeMetadataEncrypted credentialMetadata encrypted =
  encrypted {
      metadataEC = packMetadataCred credentialMetadata encrypted.metadataEC
    }


data MetadataStoreCred = MetadataStoreCred {
    credentialMSC :: Value
    , cryptoMSC :: Value
  }


packMetadataCred :: Value -> Value -> Value
packMetadataCred credentialMetadata cryptoMetadata =
  object [
      "credential" .= credentialMetadata
      , "crypto" .= cryptoMetadata
    ]


unpackMetadataCred :: Value -> MetadataStoreCred
unpackMetadataCred metadata =
  case metadata of
    Object values ->
      MetadataStoreCred {
          credentialMSC = fromMaybe metadata $ KM.lookup "credential" values
          , cryptoMSC = fromMaybe metadata $ KM.lookup "crypto" values
        }

    _ ->
      MetadataStoreCred {
          credentialMSC = metadata
          , cryptoMSC = metadata
        }


validateTenantCredential :: TenantUid -> CredentialDB -> Either ErrorCred CredentialDB
validateTenantCredential tenantUid credential
  | credential.tenantUidCD == tenantUid = Right credential
  | otherwise = Left $ mkErrorCred $
      "credential " <> renderCredentialUid credential.uidCD
        <> " belongs to tenant " <> renderTenantUid credential.tenantUidCD
        <> ", not tenant " <> renderTenantUid tenantUid


validateLoadCredential :: Tm.UTCTime -> CredentialDB -> Either  ErrorCred ()
validateLoadCredential bound credential =
  case credential.revokedAtCD of
    Just revokedAt -> Left $ mkErrorCred $
      "credential " <> renderCredentialUid credential.uidCD <> " was revoked at " <> Tx.pack (show revokedAt)
    Nothing -> case credential.expiresAtCD of
      Just expiresAt | expiresAt <= bound ->
        Left $ mkErrorCred $ "credential " <> renderCredentialUid credential.uidCD <> " expired at " <> Tx.pack (show expiresAt)
      _ -> Right ()


validateRotateCredential :: CredentialDB -> Either  ErrorCred ()
validateRotateCredential credential =
  case credential.revokedAtCD of
    Just revokedAt -> Left $ mkErrorCred $
      "credential " <> renderCredentialUid credential.uidCD <> " was revoked at " <> Tx.pack (show revokedAt)

    Nothing -> Right ()


missingCredentialError :: CredentialUid  -> ErrorCred
missingCredentialError credentialUid =
  mkErrorCred $ "credential not found: " <> renderCredentialUid credentialUid


databaseCredentialError :: Text -> ErrorDb  -> ErrorCred
databaseCredentialError operation errMsg =
  mkErrorCred $ "credential " <> operation <> " database error: " <> errMsg


renderTenantUid :: TenantUid -> Text
renderTenantUid (TenantUid value) =
  Tx.pack $ show value


renderCredentialUid :: CredentialUid -> Text
renderCredentialUid (CredentialUid value) =
  Tx.pack $ show value