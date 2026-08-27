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

import qualified Options.Cli as Cl (CliOptions (..), EnvOptions (..))
import qualified Options.ConfFile as Fo (FileOptions (..), PgDbOpts (..), ServerOpts (..), CorsOpts (..), JwtOpts (..))
import qualified Options.Runtime as Rt (RunOptions (..), defaultRun, PgDbConfig (..), defaultPgDbConf)


type ConfError = Either String ()
type RunOptSt = State Rt.RunOptions ConfError
type RunOptIOSt = StateT Rt.RunOptions IO ConfError
type PgDbOptIOSt = StateT Rt.PgDbConfig (StateT Rt.RunOptions IO) ConfError


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
    innerConf (\nVal s -> s { Rt.pgDbConf = nVal }) parsePgDb Rt.defaultPgDbConf file.db
    pure $ Right ()

  parsePgDb :: Fo.PgDbOpts -> PgDbOptIOSt
  parsePgDb dbO = do
    mconf dbO.host $ \nVal s -> s { Rt.host = T.encodeUtf8 . T.pack $ nVal }
    mconf dbO.port $ \nVal s -> s { Rt.port = fromIntegral nVal }
    mconf dbO.user $ \nVal s -> s { Rt.user = T.encodeUtf8 . T.pack $ nVal }
    mconf dbO.passwd $ \nVal s -> s { Rt.passwd = T.encodeUtf8 . T.pack $ nVal }
    mconf dbO.dbase $ \nVal s -> s { Rt.dbase = T.encodeUtf8 . T.pack $ nVal }
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
      Just False ->
        modify $ \s -> s { Rt.corsPolicy = Nothing }
      _ ->
        mconf co.allowed $ \nVal s -> s { Rt.corsPolicy = Just $ Hcrs.defaultCorsPolicy { Hcrs.allowedOrigins = map T.pack nVal } }
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

