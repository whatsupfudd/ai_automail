{-# LANGUAGE DuplicateRecordFields #-}

module AutoMail.Credential.Crypto where

import Control.Exception (SomeException, try)

import Data.ByteArray (convert)
import qualified Data.ByteString as Bs
import qualified Data.ByteString.Base64 as B64
import qualified Data.Char as Ch
import Data.Int (Int64)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Mp
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import qualified Data.Text as Tx
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Encoding.Error as TEE
import Data.Word (Word8)

import System.Environment (lookupEnv)

import Crypto.Cipher.AES (AES256)
import Crypto.Cipher.Types (AEAD, AEADMode(..), AuthTag(..), aeadInit, aeadSimpleDecrypt, aeadSimpleEncrypt, cipherInit, makeIV)
import qualified Crypto.Cipher.Types as CtT
import Crypto.Error (CryptoFailable(..))
import Crypto.Random (getRandomBytes)

import qualified Data.Aeson as Ae
import Data.Aeson (FromJSON, Value, eitherDecodeStrict', object, withObject, (.:?), (.!=), (.=))
import qualified Data.Aeson.Types as AeT

import AutoMail.App.Config (ConfigCrypto(..))
import AutoMail.App.Error (ErrorCred, mkErrorCred)
import AutoMail.Credential.Types (ContextCred(..), EncryptedCred(..), KindCred(..), SecretCred(..))
import AutoMail.Model.Id (CredentialUid(..), TenantUid(..))
import Data.Int (Int64)


data CryptoCred m = CryptoCred {
    encryptCC :: ContextCred -> SecretCred -> m (Either ErrorCred EncryptedCred)
    , decryptCC :: ContextCred -> EncryptedCred -> m (Either ErrorCred SecretCred)
  }


data KeyRingCred = KeyRingCred {
    activeKeyRefKRC :: Text
    , keysKRC :: Map Text Bs.ByteString
  }


data SourceCred =
    TextSC Text
  | BytesSC Bs.ByteString


data SpecKeyRingCred = SpecKeyRingCred {
    activeSKRC :: Maybe Text
    , keySKRC :: Maybe Text
    , keysSKRC :: Map Text Text
  }


instance FromJSON SpecKeyRingCred where
  parseJSON = withObject "SpecKeyRingCred" $ \value -> do
    active <- value .:? "active"
    key <- value .:? "key"
    keys <- value .:? "keys" .!= Mp.empty
    pure SpecKeyRingCred { activeSKRC = active, keySKRC = key, keysSKRC = keys }


keyBytesCred :: Int
keyBytesCred = 32


nonceBytesCred :: Int
nonceBytesCred = 16


tagBytesCred :: Int
tagBytesCred = 16


algorithmCred :: Text
algorithmCred = "aes-256-gcm"


mkCryptoCred :: ConfigCrypto -> IO (Either ErrorCred (CryptoCred IO))
mkCryptoCred config = do
  loaded <- loadKeyRingCred config
  pure $ case loaded of
    Left err -> Left $ mkErrorCred err
    Right keyRing -> Right CryptoCred {
        encryptCC = encryptCred keyRing
        , decryptCC = decryptCred keyRing
      }


loadKeyRingCred :: ConfigCrypto -> IO (Either ErrorCred KeyRingCred)
loadKeyRingCred config =
  let
    activeRef = Tx.strip config.keyRefCC
  in
  if Tx.null activeRef
    then pure $ Left $ mkErrorCred "credential crypto key_ref is blank"
    else do
      loaded <- loadSourceCred config.keySourceCC
      pure $ do
        source <- loaded
        keyRing <- parseKeyRingSourceCred activeRef source
        validateKeyRingCred keyRing


loadSourceCred :: Text -> IO (Either ErrorCred SourceCred)
loadSourceCred source0 =
  let
    source = Tx.strip source0
  in
  case Tx.stripPrefix "env:" source of
    Just name -> loadEnvSourceCred $ Tx.strip name
    Nothing ->
      case Tx.stripPrefix "file:" source of
        Just path -> loadFileSourceCred $ Tx.strip path
        Nothing -> pure $ Right $ TextSC source


loadEnvSourceCred :: Text -> IO (Either ErrorCred SourceCred)
loadEnvSourceCred name
  | Tx.null name = pure $ Left $ mkErrorCred "credential crypto env source has blank variable name"
  | otherwise = do
      value <- lookupEnv $ Tx.unpack name
      pure $ case value of
        Nothing -> Left $ mkErrorCred $ "credential crypto environment variable is missing: " <> name
        Just found -> Right $ TextSC $ Tx.pack found


loadFileSourceCred :: Text -> IO (Either ErrorCred SourceCred)
loadFileSourceCred path
  | Tx.null path = pure $ Left $ mkErrorCred "credential crypto file source has blank path"
  | otherwise = do
      result <- tryReadFileCred $ Tx.unpack path
      pure $ case result of
        Left exception -> Left $ mkErrorCred $ "credential crypto key file could not be read: " <> path <> ": " <> Tx.pack (show exception)
        Right content -> Right $ BytesSC content


tryReadFileCred :: FilePath -> IO (Either SomeException Bs.ByteString)
tryReadFileCred path = try $ Bs.readFile path


parseKeyRingSourceCred :: Text -> SourceCred -> Either ErrorCred KeyRingCred
parseKeyRingSourceCred activeRef source =
  case source of
    TextSC text -> parseKeyRingTextCred activeRef text
    BytesSC bytes -> parseKeyRingBytesCred activeRef bytes


parseKeyRingBytesCred :: Text -> Bs.ByteString -> Either ErrorCred KeyRingCred
parseKeyRingBytesCred activeRef bytes =
  case TE.decodeUtf8' bytes of
    Right text ->
      case parseKeyRingTextCred activeRef text of
        Right keyRing -> Right keyRing
        Left textError ->
          case parseSingleRawBytesCred activeRef $ trimBytesCred bytes of
            Right keyRing -> Right keyRing
            Left _ -> Left textError
    Left _ -> parseSingleRawBytesCred activeRef $ trimBytesCred bytes


parseKeyRingTextCred :: Text -> Text -> Either ErrorCred KeyRingCred
parseKeyRingTextCred activeRef text0 =
  let
    text = Tx.strip text0
  in
  if Tx.null text
    then Left $ mkErrorCred "credential crypto key source is blank"
    else if Tx.isPrefixOf "{" text
      then parseJsonKeyRingCred activeRef text
      else case parseLineKeyRingCred activeRef text of
        Just result -> result
        Nothing -> parseSingleTextCred activeRef text


parseJsonKeyRingCred :: Text -> Text -> Either ErrorCred KeyRingCred
parseJsonKeyRingCred activeRef text =
  case eitherDecodeStrict' (TE.encodeUtf8 text) :: Either String SpecKeyRingCred of
    Left reason -> Left $ mkErrorCred $ "credential crypto JSON keyring is invalid: " <> Tx.pack reason
    Right spec -> do
      keyedPairs <- traverse parsePair $ Mp.toList spec.keysSKRC
      singlePairs <- case spec.keySKRC of
        Nothing -> Right []
        Just material -> do
          key <- parseMaterialCred material
          let singleRef = fromMaybe activeRef spec.activeSKRC
          pure [(singleRef, key)]
      mkKeyRingCred activeRef $ keyedPairs <> singlePairs
  where
  parsePair (keyRef, material) = do
    key <- parseMaterialCred material
    pure (Tx.strip keyRef, key)


parseLineKeyRingCred :: Text -> Text -> Maybe (Either ErrorCred KeyRingCred)
parseLineKeyRingCred activeRef text =
  let
    usefulLines = filter usefulLineCred $ Tx.lines text
    shouldParse = length usefulLines > 1 || any strongLineCred usefulLines
  in
  if null usefulLines || not shouldParse
    then Nothing
    else Just $ do
      pairs <- traverse parseLine usefulLines
      mkKeyRingCred activeRef pairs
  where
  parseLine line =
    let
      (left, right0) = Tx.breakOn "=" line
      right = Tx.drop 1 right0
      keyRef = Tx.strip left
      material = Tx.strip right
    in
    if Tx.null right0 || Tx.null keyRef || Tx.null material
      then Left $ mkErrorCred $ "credential crypto keyring line is invalid: " <> line
      else do
        key <- parseMaterialCred material
        pure (keyRef, key)


usefulLineCred :: Text -> Bool
usefulLineCred line =
  let
    stripped = Tx.strip line
  in
  not (Tx.null stripped) && not (Tx.isPrefixOf "#" stripped)


strongLineCred :: Text -> Bool
strongLineCred line =
  let
    (_, right0) = Tx.breakOn "=" line
    material = Tx.strip $ Tx.drop 1 right0
  in
  not (Tx.null right0) && hasMaterialPrefixCred material


hasMaterialPrefixCred :: Text -> Bool
hasMaterialPrefixCred value =
  any (`Tx.isPrefixOf` value) ["base64:", "b64:", "hex:", "raw:", "utf8:", "text:", "literal:"]


parseSingleTextCred :: Text -> Text -> Either ErrorCred KeyRingCred
parseSingleTextCred activeRef text = do
  key <- parseMaterialCred text
  pure KeyRingCred { activeKeyRefKRC = activeRef, keysKRC = Mp.singleton activeRef key }


parseSingleRawBytesCred :: Text -> Bs.ByteString -> Either ErrorCred KeyRingCred
parseSingleRawBytesCred activeRef bytes = do
  key <- checkKeyBytesCred "raw key file" bytes
  pure KeyRingCred { activeKeyRefKRC = activeRef, keysKRC = Mp.singleton activeRef key }


mkKeyRingCred :: Text -> [(Text, Bs.ByteString)] -> Either ErrorCred KeyRingCred
mkKeyRingCred activeRef pairs0 =
  let
    pairs = filter (not . Tx.null . fst) pairs0
    keys = Mp.fromList pairs
  in
  if null pairs
    then Left $ mkErrorCred "credential crypto keyring contains no keys"
    else if length pairs /= Mp.size keys
      then Left $ mkErrorCred "credential crypto keyring contains duplicate key references"
      else Right KeyRingCred { activeKeyRefKRC = activeRef, keysKRC = keys }


validateKeyRingCred :: KeyRingCred -> Either ErrorCred KeyRingCred
validateKeyRingCred keyRing =
  case Mp.lookup keyRing.activeKeyRefKRC keyRing.keysKRC of
    Nothing -> Left $ mkErrorCred $ "credential crypto active key is missing from keyring: " <> keyRing.activeKeyRefKRC
    Just _ -> Right keyRing


parseMaterialCred :: Text -> Either ErrorCred Bs.ByteString
parseMaterialCred material0 =
  let
    material = Tx.strip material0
  in
  case Tx.stripPrefix "base64:" material of
    Just value -> decodeBase64MaterialCred value
    Nothing ->
      case Tx.stripPrefix "b64:" material of
        Just value -> decodeBase64MaterialCred value
        Nothing ->
          case Tx.stripPrefix "hex:" material of
            Just value -> decodeHexMaterialCred value
            Nothing ->
              case Tx.stripPrefix "raw:" material of
                Just value -> decodeUtf8MaterialCred value
                Nothing ->
                  case Tx.stripPrefix "utf8:" material of
                    Just value -> decodeUtf8MaterialCred value
                    Nothing ->
                      case Tx.stripPrefix "text:" material of
                        Just value -> decodeUtf8MaterialCred value
                        Nothing ->
                          case Tx.stripPrefix "literal:" material of
                            Just value -> decodeUtf8MaterialCred value
                            Nothing -> decodeUnprefixedMaterialCred material


decodeUnprefixedMaterialCred :: Text -> Either ErrorCred Bs.ByteString
decodeUnprefixedMaterialCred material =
  case decodeBase64MaterialMaybeCred material of
    Just key -> Right key
    Nothing ->
      case decodeHexMaterialMaybeCred material of
        Just key -> Right key
        Nothing -> decodeUtf8MaterialCred material


decodeBase64MaterialCred :: Text -> Either ErrorCred Bs.ByteString
decodeBase64MaterialCred material =
  case decodeBase64RawCred material of
    Left reason -> Left reason
    Right bytes -> checkKeyBytesCred "base64 key material" bytes


decodeBase64MaterialMaybeCred :: Text -> Maybe Bs.ByteString
decodeBase64MaterialMaybeCred material =
  case decodeBase64RawCred material >>= checkKeyBytesCred "base64 key material" of
    Left _ -> Nothing
    Right bytes -> Just bytes


decodeBase64RawCred :: Text -> Either ErrorCred Bs.ByteString
decodeBase64RawCred material =
  let
    compact = Tx.filter (not . Ch.isSpace) material
  in
  case B64.decode $ TE.encodeUtf8 compact of
    Left reason -> Left $ mkErrorCred $ "credential crypto base64 key material is invalid: " <> Tx.pack reason
    Right bytes -> Right bytes


decodeHexMaterialCred :: Text -> Either ErrorCred Bs.ByteString
decodeHexMaterialCred material =
  decodeHexRawCred material >>= checkKeyBytesCred "hex key material"


decodeHexMaterialMaybeCred :: Text -> Maybe Bs.ByteString
decodeHexMaterialMaybeCred material =
  case decodeHexRawCred material >>= checkKeyBytesCred "hex key material" of
    Left _ -> Nothing
    Right bytes -> Just bytes


decodeHexRawCred :: Text -> Either ErrorCred Bs.ByteString
decodeHexRawCred material =
  let
    chars = Tx.unpack $ Tx.filter (not . Ch.isSpace) material
  in
  if odd $ length chars
    then Left $ mkErrorCred "credential crypto hex key material has odd length"
    else Bs.pack <$> decodePairs chars
  where
  decodePairs [] = Right []
  decodePairs (left:right:rest) = do
    hi <- hexNibbleCred left
    lo <- hexNibbleCred right
    others <- decodePairs rest
    pure (fromIntegral (hi * 16 + lo) : others)
  decodePairs _ = Left $ mkErrorCred "credential crypto hex key material is invalid"


hexNibbleCred :: Char -> Either ErrorCred Int
hexNibbleCred char
  | char >= '0' && char <= '9' = Right $ Ch.ord char - Ch.ord '0'
  | char >= 'a' && char <= 'f' = Right $ 10 + Ch.ord char - Ch.ord 'a'
  | char >= 'A' && char <= 'F' = Right $ 10 + Ch.ord char - Ch.ord 'A'
  | otherwise = Left $ mkErrorCred $ "credential crypto hex key material contains invalid character: " <> Tx.singleton char


decodeUtf8MaterialCred :: Text -> Either ErrorCred Bs.ByteString
decodeUtf8MaterialCred material =
  checkKeyBytesCred "utf8 key material" $ TE.encodeUtf8 material


checkKeyBytesCred :: Text -> Bs.ByteString -> Either ErrorCred Bs.ByteString
checkKeyBytesCred label bytes =
  if Bs.length bytes == keyBytesCred
    then Right bytes
    else Left $ mkErrorCred $ "credential crypto " <> label <> " must be exactly 32 bytes, got " <> Tx.pack (show $ Bs.length bytes)


encryptCred :: KeyRingCred -> ContextCred -> SecretCred -> IO (Either ErrorCred EncryptedCred)
encryptCred keyRing context secret = do
  nonce <- getRandomBytes nonceBytesCred
  pure $ do
    keyRef <- keyRefEncryptCred keyRing context
    key <- lookupKeyCred keyRing keyRef
    aead <- initAeadCred key nonce
    let
      SecretCred plain = secret
      includeCredentialUid = isJust context.credentialUidCC
      aad = aadCred includeCredentialUid keyRef context
      (AuthTag cipherBytes, tag) = aeadSimpleEncrypt aead aad plain tagBytesCred
      tagBytes = convert tag :: Bs.ByteString
    Right EncryptedCred {
        keyRefEC = keyRef
        , ciphertextEC = (convert cipherBytes) <> tagBytes
        , nonceEC = nonce
        , metadataEC = metadataEncryptedCred includeCredentialUid
      }


decryptCred :: KeyRingCred -> ContextCred -> EncryptedCred -> IO (Either ErrorCred SecretCred)
decryptCred keyRing context encrypted =
  pure $ do
    checkKeyRefDecryptCred context encrypted.keyRefEC
    key <- lookupKeyCred keyRing encrypted.keyRefEC
    (ciphertext, authTag) <- splitCiphertextCred encrypted.ciphertextEC
    aead <- initAeadCred key encrypted.nonceEC
    let candidates = aadCredentialCandidatesCred context encrypted
    case firstJustCred $ map (decryptWithAadCred aead encrypted.keyRefEC context ciphertext authTag) candidates of
      Nothing -> Left $ mkErrorCred "credential crypto authentication failed"
      Just plain -> Right $ SecretCred plain


decryptWithAadCred :: AEAD AES256 -> Text -> ContextCred -> Bs.ByteString -> AuthTag -> Bool -> Maybe Bs.ByteString
decryptWithAadCred aead keyRef context ciphertext authTag includeCredentialUid =
  aeadSimpleDecrypt aead (aadCred includeCredentialUid keyRef context) ciphertext authTag


keyRefEncryptCred :: KeyRingCred -> ContextCred -> Either ErrorCred Text
keyRefEncryptCred keyRing context =
  let
    keyRef = Tx.strip context.keyRefCC
  in
  if Tx.null keyRef
    then Right keyRing.activeKeyRefKRC
    else Right keyRef


checkKeyRefDecryptCred :: ContextCred -> Text -> Either ErrorCred ()
checkKeyRefDecryptCred context encryptedKeyRef =
  let
    contextKeyRef = Tx.strip context.keyRefCC
  in
  if Tx.null encryptedKeyRef
    then Left $ mkErrorCred "credential crypto encrypted key_ref is blank"
    else if Tx.null contextKeyRef || contextKeyRef == encryptedKeyRef
      then Right ()
      else Left $ mkErrorCred $ "credential crypto context key_ref does not match encrypted key_ref: " <> contextKeyRef <> " /= " <> encryptedKeyRef


lookupKeyCred :: KeyRingCred -> Text -> Either ErrorCred Bs.ByteString
lookupKeyCred keyRing keyRef =
  case Mp.lookup keyRef keyRing.keysKRC of
    Nothing -> Left $ mkErrorCred $ "credential crypto key is not available in keyring: " <> keyRef
    Just key -> Right key


initAeadCred :: Bs.ByteString -> Bs.ByteString -> Either ErrorCred (AEAD AES256)
initAeadCred key nonce = do
  if Bs.length nonce == nonceBytesCred
    then Right ()
    else Left $ mkErrorCred $ "credential crypto nonce must be exactly " <> Tx.pack (show nonceBytesCred) <> " bytes"
  cipher <- case cipherInit key of
    CryptoFailed failure -> Left $ mkErrorCred $ "credential crypto AES-256 initialisation failed: " <> Tx.pack (show failure)
    CryptoPassed cipher -> Right cipher
  iv <- case makeIV nonce :: Maybe (CtT.IV AES256) of
    Nothing -> Left $ mkErrorCred "credential crypto nonce could not be converted into an AES IV"
    Just iv -> Right iv
  case aeadInit AEAD_GCM cipher iv of
    CryptoFailed failure -> Left $ mkErrorCred $ "credential crypto AEAD initialisation failed: " <> Tx.pack (show failure)
    CryptoPassed aead -> Right aead


splitCiphertextCred :: Bs.ByteString -> Either ErrorCred (Bs.ByteString, AuthTag)
splitCiphertextCred payload =
  let
    size = Bs.length payload
  in
  if size < tagBytesCred
    then Left $ mkErrorCred "credential crypto ciphertext is shorter than authentication tag"
    else
      let
        cipherSize = size - tagBytesCred
        ciphertext = Bs.take cipherSize payload
        tagBytes = Bs.drop cipherSize payload
      in
      Right (ciphertext, AuthTag $ convert tagBytes)


aadCredentialCandidatesCred :: ContextCred -> EncryptedCred -> [Bool]
aadCredentialCandidatesCred context encrypted
  | isJust context.credentialUidCC && usesCredentialUidCred encrypted = [True, False]
  | isJust context.credentialUidCC = [False, True]
  | otherwise = [False]


usesCredentialUidCred :: EncryptedCred -> Bool
usesCredentialUidCred encrypted =
  isJust $ AeT.parseMaybe parse encrypted.metadataEC
  where
  parse :: Value -> AeT.Parser (Maybe Int64)
  parse = withObject "EncryptedCred.metadata" $ \value -> value .:? "aad_credential_uid"


metadataEncryptedCred :: Bool -> Value
metadataEncryptedCred includeCredentialUid =
  object [
      "algorithm" .= algorithmCred
      , "version" .= (1 :: Int)
      , "nonce_bytes" .= nonceBytesCred
      , "tag_bytes" .= tagBytesCred
      , "aad_credential_uid" .= includeCredentialUid
    ]


aadCred :: Bool -> Text -> ContextCred -> Bs.ByteString
aadCred includeCredentialUid keyRef context =
  Bs.intercalate "\n" [
      "automail.credential.v1"
      , "tenant_uid=" <> encodeTextCred (renderTenantUidCred context.tenantUidCC)
      , "credential_uid=" <> encodeTextCred (renderCredentialUidMaybeCred includeCredentialUid context.credentialUidCC)
      , "kind=" <> encodeTextCred (renderKindCred context.kindCC)
      , "key_ref=" <> encodeTextCred keyRef
    ]


renderTenantUidCred :: TenantUid -> Text
renderTenantUidCred (TenantUid uid) = Tx.pack $ show uid


renderCredentialUidCred :: CredentialUid -> Text
renderCredentialUidCred (CredentialUid uid) = Tx.pack $ show uid


renderCredentialUidMaybeCred :: Bool -> Maybe CredentialUid -> Text
renderCredentialUidMaybeCred includeCredentialUid credentialUid =
  if includeCredentialUid
    then maybe "" renderCredentialUidCred credentialUid
    else ""


renderKindCred :: KindCred -> Text
renderKindCred kind =
  case kind of
    OAuthRefreshKC -> "oauth_refresh"
    PasswordKC -> "password"
    ServiceAccountKC -> "service_account"
    ExternalKC -> "external"


encodeTextCred :: Text -> Bs.ByteString
encodeTextCred = TE.encodeUtf8


firstJustCred :: [Maybe a] -> Maybe a
firstJustCred values =
  case values of
    [] -> Nothing
    Nothing:rest -> firstJustCred rest
    Just value:_ -> Just value


trimBytesCred :: Bs.ByteString -> Bs.ByteString
trimBytesCred =
  dropEnd . Bs.dropWhile asciiSpaceCred
  where
  dropEnd = Bs.reverse . Bs.dropWhile asciiSpaceCred . Bs.reverse


asciiSpaceCred :: Word8 -> Bool
asciiSpaceCred word =
  word == 9 || word == 10 || word == 11 || word == 12 || word == 13 || word == 32
