{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module AutoMail.App.Config (
    ConfigApp(..)
    , ConfigDb(..)
    , ConfigHttp(..)
    , ConfigWorkers(..)
    , ConfigCrypto(..)
    , ConfigGoogle(..)
    , ConfigRuntime(..)
    , loadConfigApp
    , validateConfigApp
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BC
import Data.Char (isSpace)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Tx
import qualified Data.Text.Encoding as TE
import Data.Time (NominalDiffTime)
import GHC.Generics (Generic)
import System.Environment (getEnvironment)
import Text.Read (readMaybe)

import AutoMail.App.Error (ErrorConfig(..))


data ConfigApp = ConfigApp {
    databaseCA :: ConfigDb
    , httpCA :: ConfigHttp
    , workersCA :: ConfigWorkers
    , cryptoCA :: ConfigCrypto
    , googleCA :: ConfigGoogle
    , runtimeCA :: ConfigRuntime
  }
  deriving stock (Eq, Show, Generic)


data ConfigDb = ConfigDb {
    connectionCD :: ByteString
    , poolSizeCD :: Int
    , poolAcquireTimeoutCD :: NominalDiffTime
  }
  deriving stock (Eq, Show, Generic)


data ConfigHttp = ConfigHttp {
    hostCH :: Text
    , portCH :: Int
    , publicBaseCH :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)


data ConfigWorkers = ConfigWorkers {
    countCW :: Int
    , leaseSecondsCW :: Int
    , pollingMsCW :: Int
    , retryMaxCW :: Int
  }
  deriving stock (Eq, Show, Generic)


data ConfigCrypto = ConfigCrypto {
    keySourceCC :: Text
    , keyRefCC :: Text
  }
  deriving stock (Eq, Show, Generic)


data ConfigGoogle = ConfigGoogle {
    clientIdCG :: Text
    , clientSecretRefCG :: Text
    , redirectUriCG :: Text
    , pubsubProjectCG :: Maybe Text
    , pubsubTopicCG :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)


data ConfigRuntime = ConfigRuntime {
    instanceIdCR :: Text
    , shutdownSecondsCR :: Int
    , accountRefreshSecondsCR :: Int
    , maintenanceSecondsCR :: Int
  }
  deriving stock (Eq, Show, Generic)


type EnvironmentConfig = Map String String


data DecodeConfig a =
    ValidDC a
  | InvalidDC [Text]


instance Functor DecodeConfig where
  fmap function decoded =
    case decoded of
      ValidDC value -> ValidDC $ function value
      InvalidDC errors -> InvalidDC errors


instance Applicative DecodeConfig where
  pure = ValidDC

  decodedFunction <*> decodedValue =
    case (decodedFunction, decodedValue) of
      (ValidDC function, ValidDC value) -> ValidDC $ function value
      (InvalidDC leftErrors, InvalidDC rightErrors) -> InvalidDC $ leftErrors <> rightErrors
      (InvalidDC errors, _) -> InvalidDC errors
      (_, InvalidDC errors) -> InvalidDC errors


loadConfigApp :: IO (Either ErrorConfig ConfigApp)
loadConfigApp = do
  environment <- Map.fromList <$> getEnvironment
  pure $ decodeConfigApp environment


decodeConfigApp :: EnvironmentConfig -> Either ErrorConfig ConfigApp
decodeConfigApp environment =
  let
    decoded =
      ConfigApp
        <$> decodeDatabaseConfig environment
        <*> decodeHttpConfig environment
        <*> decodeWorkersConfig environment
        <*> decodeCryptoConfig environment
        <*> decodeGoogleConfig environment
        <*> decodeRuntimeConfig environment
  in
  case decoded of
    ValidDC config -> validateConfigApp config
    InvalidDC errors -> Left $ ErrorConfig $ renderErrorsConfig "Unable to load AutoMail configuration" errors


decodeDatabaseConfig :: EnvironmentConfig -> DecodeConfig ConfigDb
decodeDatabaseConfig environment =
  ConfigDb
    <$> decodeRequiredBytes environment "AUTOMAIL_DATABASE_CONNECTION"
    <*> decodeIntDefault environment "AUTOMAIL_DATABASE_POOL_SIZE" 10
    <*> decodeSecondsDefault environment "AUTOMAIL_DATABASE_POOL_ACQUIRE_TIMEOUT_SECONDS" 10


decodeHttpConfig :: EnvironmentConfig -> DecodeConfig ConfigHttp
decodeHttpConfig environment =
  ConfigHttp
    <$> decodeTextDefault environment "AUTOMAIL_HTTP_HOST" "127.0.0.1"
    <*> decodeIntDefault environment "AUTOMAIL_HTTP_PORT" 8080
    <*> decodeOptionalText environment "AUTOMAIL_HTTP_PUBLIC_BASE"


decodeWorkersConfig :: EnvironmentConfig -> DecodeConfig ConfigWorkers
decodeWorkersConfig environment =
  ConfigWorkers
    <$> decodeIntDefault environment "AUTOMAIL_WORKERS_COUNT" 4
    <*> decodeIntDefault environment "AUTOMAIL_WORKERS_LEASE_SECONDS" 120
    <*> decodeIntDefault environment "AUTOMAIL_WORKERS_POLLING_MS" 500
    <*> decodeIntDefault environment "AUTOMAIL_WORKERS_RETRY_MAX" 5


decodeCryptoConfig :: EnvironmentConfig -> DecodeConfig ConfigCrypto
decodeCryptoConfig environment =
  ConfigCrypto
    <$> decodeRequiredText environment "AUTOMAIL_CRYPTO_KEY_SOURCE"
    <*> decodeRequiredText environment "AUTOMAIL_CRYPTO_KEY_REF"


decodeGoogleConfig :: EnvironmentConfig -> DecodeConfig ConfigGoogle
decodeGoogleConfig environment =
  ConfigGoogle
    <$> decodeRequiredText environment "AUTOMAIL_GOOGLE_CLIENT_ID"
    <*> decodeRequiredText environment "AUTOMAIL_GOOGLE_CLIENT_SECRET_REF"
    <*> decodeRequiredText environment "AUTOMAIL_GOOGLE_REDIRECT_URI"
    <*> decodeOptionalText environment "AUTOMAIL_GOOGLE_PUBSUB_PROJECT"
    <*> decodeOptionalText environment "AUTOMAIL_GOOGLE_PUBSUB_TOPIC"


decodeRuntimeConfig :: EnvironmentConfig -> DecodeConfig ConfigRuntime
decodeRuntimeConfig environment =
  let
    defaultInstance = instanceDefaultConfig environment
  in
  ConfigRuntime
    <$> decodeTextDefault environment "AUTOMAIL_INSTANCE_ID" defaultInstance
    <*> decodeIntDefault environment "AUTOMAIL_SHUTDOWN_SECONDS" 30
    <*> decodeIntDefault environment "AUTOMAIL_ACCOUNT_REFRESH_SECONDS" 30
    <*> decodeIntDefault environment "AUTOMAIL_MAINTENANCE_SECONDS" 60


instanceDefaultConfig :: EnvironmentConfig -> Text
instanceDefaultConfig environment =
  case lookupTextConfig environment "HOSTNAME" of
    Just hostname | not $ Tx.null hostname -> hostname
    _ ->
      case lookupTextConfig environment "COMPUTERNAME" of
        Just computerName | not $ Tx.null computerName -> computerName
        _ -> "automail"


decodeRequiredText :: EnvironmentConfig -> String -> DecodeConfig Text
decodeRequiredText environment name =
  case lookupTextConfig environment name of
    Nothing -> InvalidDC ["Required environment variable " <> quotedConfig name <> " is not set"]
    Just value
      | Tx.null value -> InvalidDC ["Required environment variable " <> quotedConfig name <> " is empty"]
      | otherwise -> ValidDC value


decodeRequiredBytes :: EnvironmentConfig -> String -> DecodeConfig ByteString
decodeRequiredBytes environment name =
  TE.encodeUtf8 <$> decodeRequiredText environment name


decodeOptionalText :: EnvironmentConfig -> String -> DecodeConfig (Maybe Text)
decodeOptionalText environment name =
  case lookupTextConfig environment name of
    Nothing -> ValidDC Nothing
    Just value
      | Tx.null value -> ValidDC Nothing
      | otherwise -> ValidDC $ Just value


decodeTextDefault :: EnvironmentConfig -> String -> Text -> DecodeConfig Text
decodeTextDefault environment name defaultValue =
  case lookupTextConfig environment name of
    Nothing -> ValidDC defaultValue
    Just value
      | Tx.null value -> InvalidDC ["Environment variable " <> quotedConfig name <> " must not be empty"]
      | otherwise -> ValidDC value


decodeIntDefault :: EnvironmentConfig -> String -> Int -> DecodeConfig Int
decodeIntDefault environment name defaultValue =
  case lookupTextConfig environment name of
    Nothing -> ValidDC defaultValue
    Just value ->
      case readMaybe $ Tx.unpack value of
        Just parsed -> ValidDC parsed
        Nothing -> InvalidDC ["Environment variable " <> quotedConfig name <> " must contain an integer, but contains " <> quotedTextConfig value]


decodeSecondsDefault :: EnvironmentConfig -> String -> Double -> DecodeConfig NominalDiffTime
decodeSecondsDefault environment name defaultValue =
  case lookupTextConfig environment name of
    Nothing -> ValidDC $ realToFrac defaultValue
    Just value ->
      case readMaybe $ Tx.unpack value of
        Just parsed | not (isNaN parsed) && not (isInfinite parsed) -> ValidDC $ realToFrac (parsed :: Double)
        _ -> InvalidDC ["Environment variable " <> quotedConfig name <> " must contain a finite number of seconds, but contains " <> quotedTextConfig value]


lookupTextConfig :: EnvironmentConfig -> String -> Maybe Text
lookupTextConfig environment name =
  Tx.strip . Tx.pack <$> Map.lookup name environment


validateConfigApp :: ConfigApp -> Either ErrorConfig ConfigApp
validateConfigApp config =
  let
    errors =
      validateDatabaseConfig config.databaseCA
        <> validateHttpConfig config.httpCA
        <> validateWorkersConfig config.workersCA
        <> validateCryptoConfig config.cryptoCA
        <> validateGoogleConfig config.googleCA
        <> validateRuntimeConfig config.runtimeCA
  in
  if null errors
    then Right config
    else Left $ ErrorConfig $ renderErrorsConfig "Invalid AutoMail configuration" errors


validateDatabaseConfig :: ConfigDb -> [Text]
validateDatabaseConfig config =
  checkConfig (nonBlankBytes config.connectionCD) "Database connection must not be empty"
    <> checkConfig (config.poolSizeCD > 0) "Database pool size must be greater than zero"
    <> checkConfig (config.poolAcquireTimeoutCD > 0) "Database pool acquisition timeout must be greater than zero seconds"


validateHttpConfig :: ConfigHttp -> [Text]
validateHttpConfig config =
  checkTextConfig "HTTP host" config.hostCH
    <> checkConfig (config.portCH >= 1 && config.portCH <= 65535) "HTTP port must be between 1 and 65535"
    <> checkOptionalHttpUriConfig "HTTP public base URI" config.publicBaseCH


validateWorkersConfig :: ConfigWorkers -> [Text]
validateWorkersConfig config =
  checkConfig (config.countCW > 0) "Worker count must be greater than zero"
    <> checkConfig (config.leaseSecondsCW > 0) "Worker lease duration must be greater than zero seconds"
    <> checkConfig (config.pollingMsCW > 0) "Worker polling interval must be greater than zero milliseconds"
    <> checkConfig (config.retryMaxCW >= 0) "Worker retry maximum must not be negative"


validateCryptoConfig :: ConfigCrypto -> [Text]
validateCryptoConfig config =
  checkTextConfig "Crypto key source" config.keySourceCC
    <> checkTextConfig "Crypto key reference" config.keyRefCC


validateGoogleConfig :: ConfigGoogle -> [Text]
validateGoogleConfig config =
  checkTextConfig "Google client ID" config.clientIdCG
    <> checkTextConfig "Google client secret reference" config.clientSecretRefCG
    <> checkHttpUriConfig "Google redirect URI" config.redirectUriCG
    <> checkOptionalTextConfig "Google Pub/Sub project" config.pubsubProjectCG
    <> checkOptionalTextConfig "Google Pub/Sub topic" config.pubsubTopicCG


validateRuntimeConfig :: ConfigRuntime -> [Text]
validateRuntimeConfig config =
  checkTextConfig "Runtime instance ID" config.instanceIdCR
    <> checkConfig (config.shutdownSecondsCR > 0) "Shutdown timeout must be greater than zero seconds"
    <> checkConfig (config.accountRefreshSecondsCR > 0) "Account refresh interval must be greater than zero seconds"
    <> checkConfig (config.maintenanceSecondsCR > 0) "Maintenance interval must be greater than zero seconds"


checkConfig :: Bool -> Text -> [Text]
checkConfig valid message =
  if valid then [] else [message]


checkTextConfig :: Text -> Text -> [Text]
checkTextConfig label value =
  checkConfig (not $ Tx.null $ Tx.strip value) $ label <> " must not be empty"


checkOptionalTextConfig :: Text -> Maybe Text -> [Text]
checkOptionalTextConfig label value =
  case value of
    Nothing -> []
    Just present -> checkTextConfig label present


checkHttpUriConfig :: Text -> Text -> [Text]
checkHttpUriConfig label value =
  let
    stripped = Tx.strip value
    folded = Tx.toCaseFold stripped
    valid = "http://" `Tx.isPrefixOf` folded || "https://" `Tx.isPrefixOf` folded
  in
  if Tx.null stripped
    then [label <> " must not be empty"]
    else checkConfig valid $ label <> " must be an absolute HTTP or HTTPS URI"


checkOptionalHttpUriConfig :: Text -> Maybe Text -> [Text]
checkOptionalHttpUriConfig label value =
  case value of
    Nothing -> []
    Just present -> checkHttpUriConfig label present


nonBlankBytes :: ByteString -> Bool
nonBlankBytes value =
  not $ BC.null $ BC.dropWhile isSpace value


quotedConfig :: String -> Text
quotedConfig value =
  quotedTextConfig $ Tx.pack value


quotedTextConfig :: Text -> Text
quotedTextConfig value =
  "\"" <> value <> "\""


renderErrorsConfig :: Text -> [Text] -> Text
renderErrorsConfig heading errors =
  heading <> ":- " <> Tx.intercalate "- " errors