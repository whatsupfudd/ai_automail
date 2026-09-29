{-# LANGUAGE DeriveGeneric #-}
module DB.Connect where

import Control.Exception (bracket)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Cont (ContT (..))

import Data.ByteString (ByteString)
import qualified Data.Text.Encoding as Te
import Data.Time.Clock (DiffTime)

import GHC.Word (Word16)
import GHC.Generics (Generic)

import Hasql.Pool (Pool, acquire, release)
import qualified Hasql.Pool.Config as Pc
import qualified Hasql.Connection.Setting.Connection.Param as Cp
import qualified Hasql.Connection.Setting.Connection as Csc
import qualified Hasql.Connection.Setting as Cs


data PgDbConfig = PgDbConfig {
  port :: Word16
  , host :: ByteString
  , user :: ByteString
  , passwd :: ByteString
  , dbase :: ByteString
  , poolSize :: Int
  , acqTimeout :: DiffTime
  , poolTimeOut :: DiffTime
  , poolIdleTime :: DiffTime
  }
  deriving (Eq, Generic)


instance Show PgDbConfig where
  show config = "ConfigDb {host = " <> show config.host <> ", port = " <> show config.port <> ", user = " <> show config.user <> ", passwd = <redacted>, dbase = " <> show config.dbase <> ", poolSize = " <> show config.poolSize <> ", acquireTimeout = " <> show config.acqTimeout <> ", poolTimeOut = " <> show config.poolTimeOut <> ", poolIdleTime = " <> show config.poolIdleTime
    <> ", dbase = " <> show config.dbase
    <> show config.poolSize
    <> ", acquireTimeout = " <> show config.acqTimeout
    <> ", poolTimeOut = " <> show config.poolTimeOut
    <> ", poolIdleTime = " <> show config.poolIdleTime <> "}"



defaultPgDbConf = PgDbConfig {
  port = 5432
  , host = "test"
  , user = "test"
  , passwd = "test"
  , dbase = "test"
  , poolSize = 5
  , acqTimeout = 5
  , poolTimeOut = 60
  , poolIdleTime = 300
  }


startPg :: PgDbConfig -> ContT r IO Pool
startPg dbC =
  let
    dbConfig = configPg dbC
  in do
  liftIO . putStrLn $ "@[startPg] user: " <> show dbC.user <> " db: " <> show dbC.dbase <> "."
  ContT $ bracket (acquire dbConfig) release


configPg :: PgDbConfig -> Pc.Config
configPg dbC =
  let
    connParams = [Cp.host $ Te.decodeUtf8 dbC.host, Cp.port dbC.port, Cp.user $ Te.decodeUtf8 dbC.user, Cp.password $ Te.decodeUtf8 dbC.passwd, Cp.dbname $ Te.decodeUtf8 dbC.dbase]
    csSetting = Cs.connection $ Csc.params connParams
    pcSetting = Pc.staticConnectionSettings [ csSetting ]
    poolSettings = [Pc.size dbC.poolSize, Pc.acquisitionTimeout dbC.acqTimeout, Pc.agingTimeout dbC.poolTimeOut, Pc.acquisitionTimeout dbC.poolIdleTime]
  in
  Pc.settings (pcSetting : poolSettings)
