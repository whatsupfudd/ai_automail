module Options  (
  module Cl
  , module Fo
  , module Rt
  , mergeOptions
 )
where

import Control.Monad.State ( MonadState (put), MonadIO, runStateT, State, StateT, modify, lift, liftIO )
import Control.Monad.Except ( ExceptT, MonadError (throwError) )
import Data.Functor.Identity ( Identity (..) )

import Data.Foldable (for_)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T

import qualified System.IO.Error as Serr
import qualified Control.Exception as Cexc
import qualified System.Posix.Env as Senv
import qualified System.Directory as Sdir

import qualified HttpSup.CorsPolicy as Hcrs

import qualified Options.Cli as Cl
import qualified Options.ConfFile as Fo
import qualified Options.Runtime as Rt -- (RunOptions (..), defaultRun, PgDbConfig (..), defaultPgDbConf)
import qualified DB.Connect as DbC

type ConfError = Either String ()
type RunOptSt = State Rt.RunOptions ConfError
type RunOptIOSt = StateT Rt.RunOptions IO ConfError
type PgDbOptIOSt = StateT DbC.PgDbConfig (StateT Rt.RunOptions IO) ConfError
type GoogleOptIOSt = StateT Rt.GoogleConf (StateT Rt.RunOptions IO) ConfError
type RuntimeOptIOSt = StateT Rt.RuntimeConf (StateT Rt.RunOptions IO) ConfError
type WorkersOptIOSt = StateT Rt.WorkersConf (StateT Rt.RunOptions IO) ConfError
type CryptoOptIOSt = StateT Rt.CryptoConf (StateT Rt.RunOptions IO) ConfError


mconf :: MonadState s m => Maybe t -> (t -> s -> s) -> m ()
mconf mbOpt setter =
  case mbOpt of
    Nothing -> pure ()
    Just opt -> modify $ setter opt

innerConf :: MonadState s f => (t1 -> s -> s) -> (t2 -> StateT t1 f (Either a b)) -> t1 -> Maybe t2 -> f ()
innerConf updState innerParser defaultVal mbOpt =
  case mbOpt of
    Nothing -> pure ()
    Just anOpt -> do
      (result, updConf) <- runStateT (innerParser anOpt) defaultVal
      case result of
        Left errMsg -> pure ()
        Right _ -> modify $ updState updConf


mergeOptions :: Cl.CliOptions -> Fo.FileOptions -> Cl.EnvOptions -> IO Rt.RunOptions
mergeOptions cli file env = do
  appHome <- case env.appHome of
    Nothing -> do
      eiHomeDir <- Cexc.try Sdir.getHomeDirectory :: IO (Either Serr.IOError FilePath)
      case eiHomeDir of
        Left err -> pure ".fudd/automail"
        Right aVal -> pure $ aVal <> "/.fudd/automail"
    Just aVal -> pure aVal
  (result, runtimeOpts) <- runStateT (parseOptions cli file) (Rt.defaultRun appHome "http://localhost" 8885)
  case result of
    Left errMsg -> error errMsg
    Right _ -> pure runtimeOpts
  where
  parseOptions :: Cl.CliOptions -> Fo.FileOptions -> RunOptIOSt
  parseOptions cli file = do
    mconf cli.debug $ \nVal s -> s { Rt.debug = nVal }
    for_ file.server parseServer
    for_ file.jwt parseJWT
    for_ file.cors parseCors
    innerConf (\nVal s -> s { Rt.tenantConf = nVal }) parsePgDb DbC.defaultPgDbConf file.tenantDb
    innerConf (\nVal s -> s { Rt.controlConf = nVal }) parsePgDb DbC.defaultPgDbConf file.controlDb
    innerConf (\nVal s -> s { Rt.googleConf = nVal }) parseGoogle Rt.defaultGoogleConf file.google 
    innerConf (\nVal s -> s { Rt.runtimeConf = nVal }) parseRuntime Rt.defaultRuntimeConf file.runtime 
    innerConf (\nVal s -> s { Rt.workersConf = nVal }) parseWorkers Rt.defaultWorkersConf file.workers 
    innerConf (\nVal s -> s { Rt.cryptoConf = nVal }) parseCrypto Rt.defaultCryptoConf file.crypto 
    pure $ Right ()

  parsePgDb :: Fo.PgDbOpts -> PgDbOptIOSt
  parsePgDb dbO = do
    mconf dbO.host $ \nVal s -> s { DbC.host = T.encodeUtf8 . T.pack $ nVal }
    mconf dbO.port $ \nVal s -> s { DbC.port = fromIntegral nVal }
    mconf dbO.user $ \nVal s -> s { DbC.user = T.encodeUtf8 . T.pack $ nVal }
    mconf dbO.passwd $ \nVal s -> s { DbC.passwd = T.encodeUtf8 . T.pack $ nVal }
    mconf dbO.dbase $ \nVal s -> s { DbC.dbase = T.encodeUtf8 . T.pack $ nVal }
    pure $ Right ()


  parseServer :: Fo.ServerOpts -> RunOptIOSt
  parseServer so = do
    mconf so.port $ \nVal s -> s { Rt.serverPort = nVal }
    mconf so.host $ \nVal s -> s { Rt.serverHost = nVal }
    pure $ Right ()

  parseJWT :: Fo.JwtOpts -> RunOptIOSt
  parseJWT jo = do
    case jo.jEnabled of
      Just False -> do
        modify $ \s -> s { Rt.jwkConfFile = Nothing }
        pure $ Right ()
      _ ->
        case jo.keyFile of
          Nothing -> pure $ Right ()
          Just aPath -> do
            mbJwkPath <- liftIO $ resolveEnvValue aPath
            case mbJwkPath of
              Nothing ->
                pure . Left $ "Could not resolve JWK file path: " <> aPath
              Just aPath -> do
                modify $ \s -> s { Rt.jwkConfFile = Just aPath }
                pure $ Right ()


  parseCors :: Fo.CorsOpts -> RunOptIOSt
  parseCors co = do
    case co.oEnabled of
      Just False -> modify $ \s -> s { Rt.corsPolicy = Nothing }
      _ -> mconf co.allowed $ \nVal s ->
          s { Rt.corsPolicy = Just $ Hcrs.defaultCorsPolicy { Hcrs.allowedOrigins = map T.pack nVal } }
    pure $ Right ()


  parseGoogle :: Fo.GoogleOpts -> GoogleOptIOSt
  parseGoogle go = do
    mconf go.clientId $ \nVal s -> s { Rt.clientId = nVal }
    mconf go.clientSecretRef $ \nVal s -> s { Rt.clientSecretRef = nVal }
    mconf go.redirectUri $ \nVal s -> s { Rt.redirectUri = nVal }
    mconf go.pubsubProject $ \nVal s -> s { Rt.pubsubProject = Just nVal }
    mconf go.pubsubTopic $ \nVal s -> s { Rt.pubsubTopic = Just nVal }
    pure $ Right ()

  parseRuntime :: Fo.RuntimeOpts -> RuntimeOptIOSt
  parseRuntime ro = do
    mconf ro.instanceId $ \nVal s -> s { Rt.instanceId = nVal }
    mconf ro.shutdownSeconds $ \nVal s -> s { Rt.shutdownSeconds = nVal }
    mconf ro.accountRefreshSeconds $ \nVal s -> s { Rt.accountRefreshSeconds = nVal }
    mconf ro.maintenanceSeconds $ \nVal s -> s { Rt.maintenanceSeconds = nVal }
    pure $ Right ()

  parseWorkers :: Fo.WorkersOpts -> WorkersOptIOSt
  parseWorkers wo = do
    mconf wo.count $ \nVal s -> s { Rt.count = nVal }
    mconf wo.leaseSeconds $ \nVal s -> s { Rt.leaseSeconds = nVal }
    mconf wo.pollingMs $ \nVal s -> s { Rt.pollingMs = nVal }
    mconf wo.retryMax $ \nVal s -> s { Rt.retryMax = nVal }
    pure $ Right ()

  parseCrypto :: Fo.CryptoOpts -> CryptoOptIOSt
  parseCrypto co = do
    mconf co.keySource $ \nVal s -> s { Rt.keySource = nVal }
    mconf co.keyRef $ \nVal s -> s { Rt.keyRef = nVal }
    pure $ Right ()

-- | resolveEnvValue resolves an environment variable value.
resolveEnvValue :: FilePath -> IO (Maybe FilePath)
resolveEnvValue aVal =
  case aVal of
      '$' : aTail ->
        let
          (envName, leftOver) = break ('/' ==) aVal
        in do
        mbEnvValue <- Senv.getEnv $ aTail
        case mbEnvValue of
          Nothing -> pure Nothing
          Just aVal -> pure . Just $ aVal <> leftOver
      _ -> pure $ Just aVal

