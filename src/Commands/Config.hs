module Commands.Config (convertConfig) where

import qualified AutoMail.App.Config as Acf
import qualified Options.Runtime as Rt


convertConfig :: Rt.RunOptions -> Acf.ConfigApp
convertConfig rtOpts =
  let
    dbConf = Acf.ConfigDb {
      tenantConf = rtOpts.tenantConf
      , controlConf = rtOpts.controlConf
    }
    httpConf = Acf.ConfigHttp {
      hostCH = rtOpts.serverHost
      , portCH = rtOpts.serverPort
      , publicBaseCH = rtOpts.httpConf.publicBase
    }
    workersConf = Acf.ConfigWorkers {
      countCW = rtOpts.workersConf.count
      , leaseSecondsCW = rtOpts.workersConf.leaseSeconds
      , pollingMsCW = rtOpts.workersConf.pollingMs
      , retryMaxCW = rtOpts.workersConf.retryMax
    }
    cryptoConf = Acf.ConfigCrypto {
      keySourceCC = rtOpts.cryptoConf.keySource
      , keyRefCC = rtOpts.cryptoConf.keyRef
    }
    googleConf = Acf.ConfigGoogle {
      clientIdCG = rtOpts.googleConf.clientId
      , clientSecretRefCG = rtOpts.googleConf.clientSecretRef
      , redirectUriCG = rtOpts.googleConf.redirectUri
      , pubsubProjectCG = rtOpts.googleConf.pubsubProject
      , pubsubTopicCG = rtOpts.googleConf.pubsubTopic
    }
    rtConf = Acf.ConfigRuntime {
      instanceIdCR = rtOpts.runtimeConf.instanceId
      , shutdownSecondsCR = rtOpts.runtimeConf.shutdownSeconds
      , accountRefreshSecondsCR = rtOpts.runtimeConf.accountRefreshSeconds
      , maintenanceSecondsCR = rtOpts.runtimeConf.maintenanceSeconds
    }
  in
  Acf.ConfigApp {
    databaseCA = dbConf
    , httpCA = httpConf
    , workersCA = workersConf
    , cryptoCA = cryptoConf
    , googleCA = googleConf
    , runtimeCA = rtConf
    }

