{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

module AutoMail.App.Config (
    ConfigApp(..), ConfigDb(..), ConfigHttp(..), ConfigWorkers(..), ConfigCrypto(..), ConfigGoogle(..), ConfigRuntime(..)
    , EnvironmentConfig, DecodeConfig(..)
    {-, loadConfigApp, decodeConfigApp, decodeEnvironmentConfig, applyEnvConfigApp
    , decodeHttpConfig, decodeWorkersConfig, decodeCryptoConfig, decodeGoogleConfig, decodeRuntimeConfig
    , instanceDefaultConfig, decodeRequiredText, decodeRequiredBytes, decodeOptionalText, decodeTextDefault, decodeIntDefault
    , decodeSecondsDefault, lookupTextConfig, validateConfigApp, validateDatabaseConfig, validateHttpConfig, validateWorkersConfig
    , validateCryptoConfig, validateGoogleConfig, validateRuntimeConfig, checkConfig, checkTextConfig, checkOptionalTextConfig
    , checkHttpUriConfig, checkOptionalHttpUriConfig, nonBlankBytes, quotedConfig, quotedTextConfig, renderErrorsConfig
    -}
  ) where

import Control.Applicative ((<|>))
import Control.Exception (SomeException, try)
import Data.ByteString (ByteString)
import qualified Data.ByteString as Bs
import qualified Data.ByteString.Char8 as Bc
import Data.Char (isAlphaNum)
import Data.List (foldl')
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe, isJust)
import Data.Text (Text)
import qualified Data.Text as Tx
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Encoding.Error as TEE
import Data.Time (NominalDiffTime)
import GHC.Generics (Generic)
import System.Environment (getEnvironment)
import Text.Read (readMaybe)

import AutoMail.App.Error
import DB.Connect (PgDbConfig)


data ConfigApp = ConfigApp {
    databaseCA :: ConfigDb
    , httpCA :: ConfigHttp
    , workersCA :: ConfigWorkers
    , cryptoCA :: ConfigCrypto
    , googleCA :: ConfigGoogle
    , runtimeCA :: ConfigRuntime
  }
  deriving stock (Eq, Generic)


instance Show ConfigApp where
  show config =
    "ConfigApp {databaseCA = " <> show config.databaseCA
      <> ", httpCA = " <> show config.httpCA
      <> ", workersCA = " <> show config.workersCA
      <> ", cryptoCA = " <> show config.cryptoCA
      <> ", googleCA = " <> show config.googleCA
      <> ", runtimeCA = " <> show config.runtimeCA <> "}"


{-
data ConfigDb = ConfigDb {
    connectionCD :: ByteString
    , poolSizeCD :: Int
    , poolAcquireTimeoutCD :: NominalDiffTime
  }
  deriving stock (Eq, Generic)
-}


data ConfigDb = ConfigDb {
    tenantConf :: PgDbConfig
    , controlConf :: PgDbConfig
  }
  deriving stock (Eq, Generic, Show)

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
  deriving stock (Eq, Show, Generic)


instance Functor DecodeConfig where
  fmap fn decoded =
    case decoded of
      ValidDC value -> ValidDC $ fn value
      InvalidDC errors -> InvalidDC errors


instance Applicative DecodeConfig where
  pure = ValidDC

  decodedFn <*> decodedValue =
    case (decodedFn, decodedValue) of
      (ValidDC fn, ValidDC value) -> ValidDC $ fn value
      (InvalidDC leftErrors, InvalidDC rightErrors) -> InvalidDC $ leftErrors <> rightErrors
      (InvalidDC errors, _) -> InvalidDC errors
      (_, InvalidDC errors) -> InvalidDC errors


{-
loadConfigApp :: Maybe FilePath -> IO (Either ErrorConfig ConfigApp)
loadConfigApp maybeConfigPath = do
  processEnv <- environmentProcessConfig
  let configPath = maybeConfigPath <|> fmap Tx.unpack (lookupNonBlankConfig processEnv "AUTOMAIL_CONFIG")
  fileResult <- maybe (pure $ Right Map.empty) readEnvironmentFileConfig configPath
  pure $ case fileResult of
    Left errorConfig -> Left errorConfig
    Right fileEnv -> decodeEnvironmentConfig $ Map.unions [processEnv, fileEnv]


decodeConfigApp :: ByteString -> Either ErrorConfig ConfigApp
decodeConfigApp content = do
  fileEnv <- parseEnvironmentConfig content
  decodeEnvironmentConfig fileEnv


decodeEnvironmentConfig :: EnvironmentConfig -> Either ErrorConfig ConfigApp
decodeEnvironmentConfig env =
  let
    fullEnv = Map.union env environmentDefaultConfig
    decoded =
      ConfigApp <$> decodeDatabaseConfig fullEnv <*> decodeHttpConfig fullEnv <*> decodeWorkersConfig fullEnv
        <*> decodeCryptoConfig fullEnv <*> decodeGoogleConfig fullEnv <*> decodeRuntimeConfig fullEnv
  in
  case decoded of
    ValidDC config -> validateConfigApp config
    InvalidDC errors -> Left $ ErrorConfig $ renderErrorsConfig "invalid AutoMail configuration" errors


applyEnvConfigApp :: ConfigApp -> IO (Either ErrorConfig ConfigApp)
applyEnvConfigApp config = do
  processEnv <- environmentProcessConfig
  pure $ decodeEnvironmentConfig $ Map.union processEnv $ environmentFromConfig config


decodeHttpConfig :: EnvironmentConfig -> DecodeConfig ConfigHttp
decodeHttpConfig env =
  ConfigHttp
    <$> decodeTextDefault env "AUTOMAIL_HTTP_HOST" "127.0.0.1"
    <*> decodeIntDefaultAny env ["AUTOMAIL_HTTP_PORT", "PORT"] 8080
    <*> decodeOptionalText env "AUTOMAIL_PUBLIC_BASE"


decodeWorkersConfig :: EnvironmentConfig -> DecodeConfig ConfigWorkers
decodeWorkersConfig env =
  ConfigWorkers
    <$> decodeIntDefault env "AUTOMAIL_WORKER_COUNT" 4
    <*> decodeIntDefault env "AUTOMAIL_WORKER_LEASE_SECONDS" 300
    <*> decodeIntDefault env "AUTOMAIL_WORKER_POLLING_MS" 1000
    <*> decodeIntDefault env "AUTOMAIL_WORKER_RETRY_MAX" 5


decodeCryptoConfig :: EnvironmentConfig -> DecodeConfig ConfigCrypto
decodeCryptoConfig env =
  ConfigCrypto
    <$> decodeRequiredText env "AUTOMAIL_CRYPTO_KEY_SOURCE"
    <*> decodeTextDefault env "AUTOMAIL_CRYPTO_KEY_REF" "default"


decodeGoogleConfig :: EnvironmentConfig -> DecodeConfig ConfigGoogle
decodeGoogleConfig env =
  ConfigGoogle
    <$> decodeTextDefault env "AUTOMAIL_GOOGLE_CLIENT_ID" ""
    <*> decodeTextDefault env "AUTOMAIL_GOOGLE_CLIENT_SECRET_REF" ""
    <*> decodeTextDefault env "AUTOMAIL_GOOGLE_REDIRECT_URI" ""
    <*> decodeOptionalText env "AUTOMAIL_GOOGLE_PUBSUB_PROJECT"
    <*> decodeOptionalText env "AUTOMAIL_GOOGLE_PUBSUB_TOPIC"


decodeRuntimeConfig :: EnvironmentConfig -> DecodeConfig ConfigRuntime
decodeRuntimeConfig env =
  ConfigRuntime
    <$> decodeTextDefault env "AUTOMAIL_INSTANCE_ID" (instanceDefaultConfig env)
    <*> decodeIntDefault env "AUTOMAIL_SHUTDOWN_SECONDS" 15
    <*> decodeIntDefault env "AUTOMAIL_ACCOUNT_REFRESH_SECONDS" 60
    <*> decodeIntDefault env "AUTOMAIL_MAINTENANCE_SECONDS" 60


instanceDefaultConfig :: EnvironmentConfig -> Text
instanceDefaultConfig env =
  fromMaybe "automail" $ lookupNonBlankConfig env "HOSTNAME" <|> lookupNonBlankConfig env "COMPUTERNAME"


decodeRequiredText :: EnvironmentConfig -> String -> DecodeConfig Text
decodeRequiredText env key =
  case lookupTextConfig env key of
    Nothing -> InvalidDC [quotedConfig key <> " is required"]
    Just value
      | Tx.null (Tx.strip value) -> InvalidDC [quotedConfig key <> " must not be blank"]
      | otherwise -> ValidDC $ Tx.strip value


decodeRequiredBytes :: EnvironmentConfig -> String -> DecodeConfig ByteString
decodeRequiredBytes env key =
  TE.encodeUtf8 <$> decodeRequiredText env key


decodeOptionalText :: EnvironmentConfig -> String -> DecodeConfig (Maybe Text)
decodeOptionalText env key =
  case lookupTextConfig env key of
    Nothing -> ValidDC Nothing
    Just value
      | Tx.null (Tx.strip value) -> ValidDC Nothing
      | otherwise -> ValidDC $ Just $ Tx.strip value


decodeTextDefault :: EnvironmentConfig -> String -> Text -> DecodeConfig Text
decodeTextDefault env key defaultValue =
  case lookupTextConfig env key of
    Nothing -> ValidDC defaultValue
    Just value
      | Tx.null (Tx.strip value) -> ValidDC defaultValue
      | otherwise -> ValidDC $ Tx.strip value


decodeIntDefault :: EnvironmentConfig -> String -> Int -> DecodeConfig Int
decodeIntDefault env key defaultValue =
  case lookupTextConfig env key of
    Nothing -> ValidDC defaultValue
    Just value
      | Tx.null (Tx.strip value) -> ValidDC defaultValue
      | otherwise ->
          case readMaybe (Tx.unpack $ Tx.strip value) of
            Just parsed -> ValidDC parsed
            Nothing -> InvalidDC [quotedConfig key <> " must be an integer"]


decodeSecondsDefault :: EnvironmentConfig -> String -> Double -> DecodeConfig NominalDiffTime
decodeSecondsDefault env key defaultValue =
  case lookupTextConfig env key of
    Nothing -> ValidDC $ realToFrac defaultValue
    Just value
      | Tx.null (Tx.strip value) -> ValidDC $ realToFrac defaultValue
      | otherwise ->
          case readMaybe (Tx.unpack $ Tx.strip value) of
            Just parsed -> ValidDC $ realToFrac (parsed :: Double)
            Nothing -> InvalidDC [quotedConfig key <> " must be a number of seconds"]


lookupTextConfig :: EnvironmentConfig -> String -> Maybe Text
lookupTextConfig env key =
  Tx.pack <$> Map.lookup key env


validateConfigApp :: ConfigApp -> Either ErrorConfig ConfigApp
validateConfigApp config =
  let
    errors =
      validateDatabaseConfig config.databaseCA <> validateHttpConfig config.httpCA <> validateWorkersConfig config.workersCA
        <> validateCryptoConfig config.cryptoCA <> validateGoogleConfig config.googleCA <> validateRuntimeConfig config.runtimeCA
  in
  case errors of
    [] -> Right config
    _ -> Left $ ErrorConfig $ renderErrorsConfig "invalid AutoMail configuration" errors


validateDatabaseConfig :: ConfigDb -> [Text]
validateDatabaseConfig config =
  checkConfig (nonBlankBytes config.connectionTenantCD) "database connection is required"
    <> checkConfig (nonBlankBytes config.connectionControlCD) "control database connection is required"
    <> checkConfig (config.poolSizeTenantCD > 0) "database pool size must be greater than zero"
    <> checkConfig (config.poolSizeControlCD > 0) "control database pool size must be greater than zero"
    <> checkConfig (config.poolAcquireTimeoutCD > 0) "database pool acquire timeout must be greater than zero"


validateHttpConfig :: ConfigHttp -> [Text]
validateHttpConfig config =
  checkTextConfig "AUTOMAIL_HTTP_HOST" config.hostCH
    <> checkConfig (config.portCH > 0 && config.portCH <= 65535) "AUTOMAIL_HTTP_PORT must be between 1 and 65535"
    <> checkOptionalHttpUriConfig "AUTOMAIL_PUBLIC_BASE" config.publicBaseCH


validateWorkersConfig :: ConfigWorkers -> [Text]
validateWorkersConfig config =
  checkConfig (config.countCW > 0) "AUTOMAIL_WORKER_COUNT must be greater than zero"
    <> checkConfig (config.leaseSecondsCW > 0) "AUTOMAIL_WORKER_LEASE_SECONDS must be greater than zero"
    <> checkConfig (config.pollingMsCW > 0) "AUTOMAIL_WORKER_POLLING_MS must be greater than zero"
    <> checkConfig (config.retryMaxCW >= 0) "AUTOMAIL_WORKER_RETRY_MAX must be non-negative"


validateCryptoConfig :: ConfigCrypto -> [Text]
validateCryptoConfig config =
  checkTextConfig "AUTOMAIL_CRYPTO_KEY_SOURCE" config.keySourceCC
    <> checkTextConfig "AUTOMAIL_CRYPTO_KEY_REF" config.keyRefCC


validateGoogleConfig :: ConfigGoogle -> [Text]
validateGoogleConfig config =
  let
    oauthPresent =
      any (not . Tx.null . Tx.strip) [config.clientIdCG, config.clientSecretRefCG, config.redirectUriCG]
    oauthErrors
      | oauthPresent =
          checkTextConfig "AUTOMAIL_GOOGLE_CLIENT_ID" config.clientIdCG
            <> checkTextConfig "AUTOMAIL_GOOGLE_CLIENT_SECRET_REF" config.clientSecretRefCG
            <> checkHttpUriConfig "AUTOMAIL_GOOGLE_REDIRECT_URI" config.redirectUriCG
      | otherwise = []
    pubsubErrors =
      checkOptionalTextConfig "AUTOMAIL_GOOGLE_PUBSUB_PROJECT" config.pubsubProjectCG
        <> checkOptionalTextConfig "AUTOMAIL_GOOGLE_PUBSUB_TOPIC" config.pubsubTopicCG
        <> checkConfig (isJust config.pubsubProjectCG == isJust config.pubsubTopicCG)
          "AUTOMAIL_GOOGLE_PUBSUB_PROJECT and AUTOMAIL_GOOGLE_PUBSUB_TOPIC must either both be set or both be absent"
  in
  oauthErrors <> pubsubErrors


validateRuntimeConfig :: ConfigRuntime -> [Text]
validateRuntimeConfig config =
  checkTextConfig "AUTOMAIL_INSTANCE_ID" config.instanceIdCR
    <> checkConfig (config.shutdownSecondsCR >= 0) "AUTOMAIL_SHUTDOWN_SECONDS must be non-negative"
    <> checkConfig (config.accountRefreshSecondsCR > 0) "AUTOMAIL_ACCOUNT_REFRESH_SECONDS must be greater than zero"
    <> checkConfig (config.maintenanceSecondsCR > 0) "AUTOMAIL_MAINTENANCE_SECONDS must be greater than zero"


checkConfig :: Bool -> Text -> [Text]
checkConfig valid message =
  if valid then [] else [message]


checkTextConfig :: Text -> Text -> [Text]
checkTextConfig label value =
  checkConfig (not $ Tx.null $ Tx.strip value) (label <> " must not be blank")


checkOptionalTextConfig :: Text -> Maybe Text -> [Text]
checkOptionalTextConfig label maybeValue =
  maybe [] (checkTextConfig label) maybeValue


checkHttpUriConfig :: Text -> Text -> [Text]
checkHttpUriConfig label value =
  checkConfig (validHttpUriConfig value) (label <> " must be an HTTP or HTTPS URI")


checkOptionalHttpUriConfig :: Text -> Maybe Text -> [Text]
checkOptionalHttpUriConfig label maybeValue =
  maybe [] (checkHttpUriConfig label) maybeValue


nonBlankBytes :: ByteString -> Bool
nonBlankBytes bytes =
  not $ Bs.null $ Bc.strip bytes


quotedConfig :: String -> Text
quotedConfig key =
  "`" <> Tx.pack key <> "`"


quotedTextConfig :: Text -> Text
quotedTextConfig value =
  "`" <> value <> "`"


renderErrorsConfig :: Text -> [Text] -> Text
renderErrorsConfig heading errors =
  case errors of
    [] -> heading
    _ -> heading <> ":\n" <> Tx.unlines (fmap ("- " <>) errors)


environmentDefaultConfig :: EnvironmentConfig
environmentDefaultConfig =
  Map.fromList [
      ("AUTOMAIL_HTTP_HOST", "127.0.0.1")
      , ("AUTOMAIL_HTTP_PORT", "8080")
      , ("AUTOMAIL_DB_POOL_SIZE", "10")
      , ("AUTOMAIL_DB_POOL_ACQUIRE_SECONDS", "5")
      , ("AUTOMAIL_WORKER_COUNT", "4")
      , ("AUTOMAIL_WORKER_LEASE_SECONDS", "300")
      , ("AUTOMAIL_WORKER_POLLING_MS", "1000")
      , ("AUTOMAIL_WORKER_RETRY_MAX", "5")
      , ("AUTOMAIL_CRYPTO_KEY_REF", "default")
      , ("AUTOMAIL_SHUTDOWN_SECONDS", "15")
      , ("AUTOMAIL_ACCOUNT_REFRESH_SECONDS", "60")
      , ("AUTOMAIL_MAINTENANCE_SECONDS", "60")
    ]


environmentFromConfig :: ConfigApp -> EnvironmentConfig
environmentFromConfig config =
  Map.fromList $ catMaybes [
      Just ("AUTOMAIL_DB_CONNECTION", bytesStringConfig config.databaseCA.connectionTenantCD)
      , Just ("AUTOMAIL_DB_CONNECTION", bytesStringConfig config.databaseCA.connectionControlCD)
      , Just ("AUTOMAIL_DB_POOL_SIZE", show config.databaseCA.poolSizeTenantCD)
      , Just ("AUTOMAIL_DB_POOL_SIZE", show config.databaseCA.poolSizeControlCD)
      , Just ("AUTOMAIL_DB_POOL_ACQUIRE_SECONDS", showSecondsConfig config.databaseCA.poolAcquireTimeoutCD)
      , Just ("AUTOMAIL_HTTP_HOST", Tx.unpack config.httpCA.hostCH)
      , Just ("AUTOMAIL_HTTP_PORT", show config.httpCA.portCH)
      , pairOptionalConfig "AUTOMAIL_PUBLIC_BASE" config.httpCA.publicBaseCH
      , Just ("AUTOMAIL_WORKER_COUNT", show config.workersCA.countCW)
      , Just ("AUTOMAIL_WORKER_LEASE_SECONDS", show config.workersCA.leaseSecondsCW)
      , Just ("AUTOMAIL_WORKER_POLLING_MS", show config.workersCA.pollingMsCW)
      , Just ("AUTOMAIL_WORKER_RETRY_MAX", show config.workersCA.retryMaxCW)
      , Just ("AUTOMAIL_CRYPTO_KEY_SOURCE", Tx.unpack config.cryptoCA.keySourceCC)
      , Just ("AUTOMAIL_CRYPTO_KEY_REF", Tx.unpack config.cryptoCA.keyRefCC)
      , Just ("AUTOMAIL_GOOGLE_CLIENT_ID", Tx.unpack config.googleCA.clientIdCG)
      , Just ("AUTOMAIL_GOOGLE_CLIENT_SECRET_REF", Tx.unpack config.googleCA.clientSecretRefCG)
      , Just ("AUTOMAIL_GOOGLE_REDIRECT_URI", Tx.unpack config.googleCA.redirectUriCG)
      , pairOptionalConfig "AUTOMAIL_GOOGLE_PUBSUB_PROJECT" config.googleCA.pubsubProjectCG
      , pairOptionalConfig "AUTOMAIL_GOOGLE_PUBSUB_TOPIC" config.googleCA.pubsubTopicCG
      , Just ("AUTOMAIL_INSTANCE_ID", Tx.unpack config.runtimeCA.instanceIdCR)
      , Just ("AUTOMAIL_SHUTDOWN_SECONDS", show config.runtimeCA.shutdownSecondsCR)
      , Just ("AUTOMAIL_ACCOUNT_REFRESH_SECONDS", show config.runtimeCA.accountRefreshSecondsCR)
      , Just ("AUTOMAIL_MAINTENANCE_SECONDS", show config.runtimeCA.maintenanceSecondsCR)
    ]


environmentProcessConfig :: IO EnvironmentConfig
environmentProcessConfig =
  Map.fromList <$> getEnvironment


readEnvironmentFileConfig :: FilePath -> IO (Either ErrorConfig EnvironmentConfig)
readEnvironmentFileConfig path = do
  readResult <- try (Bs.readFile path) :: IO (Either SomeException ByteString)
  pure $ case readResult of
    Left exception -> Left $ ErrorConfig $ "failed to read AutoMail configuration file " <> quotedTextConfig (Tx.pack path) <> ": " <> Tx.pack (show exception)
    Right content -> parseEnvironmentConfig content


parseEnvironmentConfig :: ByteString -> Either ErrorConfig EnvironmentConfig
parseEnvironmentConfig content =
  case TE.decodeUtf8' content of
    Left exception -> Left $ ErrorConfig $ "configuration file is not valid UTF-8: " <> Tx.pack (show exception)
    Right decoded -> do
      parsedLines <- traverse (uncurry parseLineConfig) $ zip [1 :: Int ..] $ Tx.lines decoded
      pure $ foldl' insertPairConfig Map.empty $ catMaybes parsedLines


parseLineConfig :: Int -> Text -> Either ErrorConfig (Maybe (String, String))
parseLineConfig lineNo rawLine =
  let
    stripped = Tx.strip rawLine
  in
  if Tx.null stripped || "#" `Tx.isPrefixOf` stripped then
    Right Nothing
  else
    let
      usable = fromMaybe stripped $ Tx.stripPrefix "export " stripped
      (keyPart, restPart) = Tx.breakOn "=" usable
      key = Tx.strip keyPart
      value = Tx.strip $ Tx.drop 1 restPart
    in
    if Tx.null restPart then
      Left $ ErrorConfig $ "invalid configuration line " <> Tx.pack (show lineNo) <> ": expected KEY=VALUE"
    else if not $ validKeyConfig key then
      Left $ ErrorConfig $ "invalid configuration key on line " <> Tx.pack (show lineNo) <> ": " <> quotedTextConfig key
    else
      Right $ Just (Tx.unpack key, Tx.unpack $ unquoteValueConfig value)


insertPairConfig :: EnvironmentConfig -> (String, String) -> EnvironmentConfig
insertPairConfig env (key, value) =
  Map.insert key value env


validKeyConfig :: Text -> Bool
validKeyConfig key =
  not (Tx.null key) && Tx.all validCharConfig key
  where
  validCharConfig char =
    isAlphaNum char || char == '_'


unquoteValueConfig :: Text -> Text
unquoteValueConfig value
  | Tx.length value >= 2 && Tx.head value == '"' && Tx.last value == '"' =
      unescapeDoubleConfig $ Tx.dropEnd 1 $ Tx.drop 1 value
  | Tx.length value >= 2 && Tx.head value == '\'' && Tx.last value == '\'' =
      Tx.dropEnd 1 $ Tx.drop 1 value
  | otherwise = value


unescapeDoubleConfig :: Text -> Text
unescapeDoubleConfig value =
  case Tx.uncons value of
    Nothing -> ""
    Just ('\\', rest) ->
      case Tx.uncons rest of
        Nothing -> "\\"
        Just ('n', restNext) -> "\n" <> unescapeDoubleConfig restNext
        Just ('r', restNext) -> "\r" <> unescapeDoubleConfig restNext
        Just ('t', restNext) -> "\t" <> unescapeDoubleConfig restNext
        Just ('\\', restNext) -> "\\" <> unescapeDoubleConfig restNext
        Just ('"', restNext) -> "\"" <> unescapeDoubleConfig restNext
        Just (char, restNext) -> Tx.cons char $ unescapeDoubleConfig restNext
    Just (char, rest) -> Tx.cons char $ unescapeDoubleConfig rest


decodeRequiredTextAny :: EnvironmentConfig -> Text -> [String] -> DecodeConfig Text
decodeRequiredTextAny env label keys =
  case lookupTextAnyConfig env keys of
    Nothing -> InvalidDC [label <> " is required; set one of " <> Tx.intercalate ", " (fmap quotedConfig keys)]
    Just value
      | Tx.null (Tx.strip value) -> InvalidDC [label <> " must not be blank"]
      | otherwise -> ValidDC $ Tx.strip value


decodeRequiredBytesAny :: EnvironmentConfig -> Text -> [String] -> DecodeConfig ByteString
decodeRequiredBytesAny env label keys =
  TE.encodeUtf8 <$> decodeRequiredTextAny env label keys


decodeTextDefaultAny :: EnvironmentConfig -> [String] -> Text -> DecodeConfig Text
decodeTextDefaultAny env keys defaultValue =
  case lookupTextAnyConfig env keys of
    Nothing -> ValidDC defaultValue
    Just value
      | Tx.null (Tx.strip value) -> ValidDC defaultValue
      | otherwise -> ValidDC $ Tx.strip value


decodeIntDefaultAny :: EnvironmentConfig -> [String] -> Int -> DecodeConfig Int
decodeIntDefaultAny env keys defaultValue =
  case lookupTextAnyConfig env keys of
    Nothing -> ValidDC defaultValue
    Just value
      | Tx.null (Tx.strip value) -> ValidDC defaultValue
      | otherwise ->
          case readMaybe (Tx.unpack $ Tx.strip value) of
            Just parsed -> ValidDC parsed
            Nothing -> InvalidDC [Tx.intercalate " or " (fmap quotedConfig keys) <> " must be an integer"]


decodeSecondsDefaultAny :: EnvironmentConfig -> [String] -> Double -> DecodeConfig NominalDiffTime
decodeSecondsDefaultAny env keys defaultValue =
  case lookupTextAnyConfig env keys of
    Nothing -> ValidDC $ realToFrac defaultValue
    Just value
      | Tx.null (Tx.strip value) -> ValidDC $ realToFrac defaultValue
      | otherwise ->
          case readMaybe (Tx.unpack $ Tx.strip value) of
            Just parsed -> ValidDC $ realToFrac (parsed :: Double)
            Nothing -> InvalidDC [Tx.intercalate " or " (fmap quotedConfig keys) <> " must be a number of seconds"]


lookupTextAnyConfig :: EnvironmentConfig -> [String] -> Maybe Text
lookupTextAnyConfig env keys =
  foldl' (\result key -> result <|> lookupTextConfig env key) Nothing keys


lookupNonBlankConfig :: EnvironmentConfig -> String -> Maybe Text
lookupNonBlankConfig env key = do
  value <- lookupTextConfig env key
  let stripped = Tx.strip value
  if Tx.null stripped then Nothing else Just stripped


validHttpUriConfig :: Text -> Bool
validHttpUriConfig value =
  let
    stripped = Tx.strip value
    lowered = Tx.toLower stripped
  in
  ("http://" `Tx.isPrefixOf` lowered && Tx.length stripped > 7)
    || ("https://" `Tx.isPrefixOf` lowered && Tx.length stripped > 8)


pairOptionalConfig :: String -> Maybe Text -> Maybe (String, String)
pairOptionalConfig key maybeValue = fmap ((key,) . Tx.unpack) maybeValue


bytesStringConfig :: ByteString -> String
bytesStringConfig =
  Tx.unpack . TE.decodeUtf8With TEE.lenientDecode


showSecondsConfig :: NominalDiffTime -> String
showSecondsConfig seconds =
  show (realToFrac seconds :: Double)
-}