module Options.Runtime (defaultRun, RunOptions (..), PgDbConfig (..), defaultPgDbConf) where
-- import Data.Int (Int)

import Data.Text (Text)

import HttpSup.CorsPolicy (CORSConfig, defaultCorsPolicy)
import DB.Connect (PgDbConfig (..), defaultPgDbConf)


data RunOptions = RunOptions {
    debug :: Int
    , corsPolicy :: Maybe CORSConfig
    , jwkConfFile :: Maybe FilePath
    , serverPort :: Int
    , serverHost :: Text
    , pgDbConf :: PgDbConfig
    -- HERE: Add additional vars for providing runtime parameters:
    -- Eg: , root :: Text
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
    , pgDbConf = defaultPgDbConf
   -- HERE: Set default value for additional runtime parameters:  , root = "/tmp"
  }
