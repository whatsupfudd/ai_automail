{-# LANGUAGE DeriveGeneric #-}
module Options.Runtime -- (defaultRun, RunOptions (..), PgDbConfig (..), defaultPgDbConf)
where
-- import Data.Int (Int)

import Data.Text (Text)

import GHC.Generics (Generic)

import HttpSup.CorsPolicy (CORSConfig, defaultCorsPolicy)
import DB.Connect (PgDbConfig (..), defaultPgDbConf)

data HttpConf = HttpConf {
    host :: Text
    , port :: Int
    , publicBase :: Maybe Text
  }
  deriving (Eq, Show, Generic)

defaultHttpConf :: HttpConf
defaultHttpConf =
  HttpConf {
    host = "localhost"
    , port = 8080
    , publicBase = Nothing
  }


data WorkersConf = WorkersConf {
    count :: Int
    , leaseSeconds :: Int
    , pollingMs :: Int
    , retryMax :: Int
  }
  deriving (Eq, Show, Generic)

defaultWorkersConf :: WorkersConf
defaultWorkersConf =
  WorkersConf {
    count = 10
    , leaseSeconds = 60
    , pollingMs = 1000
    , retryMax = 3
  }


data CryptoConf = CryptoConf {
    keySource :: Text
    , keyRef :: Text
  }
  deriving (Eq, Show, Generic)


defaultCryptoConf :: CryptoConf
defaultCryptoConf =
  CryptoConf {
    keySource = "file"
    , keyRef = "jwkConf.json"
  }


data GoogleConf = GoogleConf {
    clientId :: Text
    , clientSecretRef :: Text
    , redirectUri :: Text
    , pubsubProject :: Maybe Text
    , pubsubTopic :: Maybe Text
  }
  deriving (Eq, Show, Generic)

defaultGoogleConf :: GoogleConf
defaultGoogleConf =
  GoogleConf {
    clientId = "clientId"
    , clientSecretRef = "clientSecretRef"
    , redirectUri = "redirectUri"
    , pubsubProject = Nothing
    , pubsubTopic = Nothing
  }


data RuntimeConf = RuntimeConf {
    instanceId :: Text
    , shutdownSeconds :: Int
    , accountRefreshSeconds :: Int
    , maintenanceSeconds :: Int
  }
  deriving (Show)


defaultRuntimeConf :: RuntimeConf
defaultRuntimeConf =
  RuntimeConf {
    instanceId = "instanceId"
    , shutdownSeconds = 60
    , accountRefreshSeconds = 60
    , maintenanceSeconds = 60
  }

data RunOptions = RunOptions {
    debug :: Int
    , corsPolicy :: Maybe CORSConfig
    , jwkConfFile :: Maybe FilePath
    , serverPort :: Int
    , serverHost :: Text
    , tenantConf :: PgDbConfig
    , controlConf :: PgDbConfig
    , httpConf :: HttpConf
    , workersConf :: WorkersConf
    , cryptoConf :: CryptoConf
    , googleConf :: GoogleConf
    , runtimeConf :: RuntimeConf
  }
  deriving (Show)


defaultRun :: FilePath -> Text -> Int -> RunOptions
defaultRun homeDir server port =
  RunOptions {
    debug = 0
    , corsPolicy = Just defaultCorsPolicy
    , jwkConfFile = Just (homeDir <> "/jwkConf.json")
    , serverHost = server
    , serverPort = port
    , tenantConf = defaultPgDbConf
    , controlConf = defaultPgDbConf
    , httpConf = defaultHttpConf
    , workersConf = defaultWorkersConf
    , cryptoConf = defaultCryptoConf
    , googleConf = defaultGoogleConf
    , runtimeConf = defaultRuntimeConf
  }
