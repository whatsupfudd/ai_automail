{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

module AutoMail.App.Account.Runtime (
    ResolverAccountPrv(..), RegistryAccountPrv(..), emptyRegistryAccountPrv, registerAccountPrv, lookupAccountPrv
    , DepsAccountRun(..), loadAccountRun, loadAccountRunGeneration, changedAccountRun
    , contextAccountRun, correlationAccountRun
  ) where

import Control.Concurrent.STM (newTVarIO)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT(..), except, runExceptT)

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Tx

import Data.Aeson (Value, object, (.=))

import Hasql.Transaction.Sessions (IsolationLevel(ReadCommitted), Mode(Read))

import AutoMail.App.Account.Types
import AutoMail.App.Error
import AutoMail.Credential.Store
import AutoMail.Credential.Types
import AutoMail.DB.Account
import AutoMail.DB.Core
import AutoMail.Model.Common
import AutoMail.Model.Id
import AutoMail.Model.Time
import AutoMail.Provider.Types


data ResolverAccountPrv m = ResolverAccountPrv {
    kindRAP :: KindPrv
    , resolveRAP :: AccountDB -> RuntimeCred -> m (Either ErrorPrv AccountPrv)
  }


newtype RegistryAccountPrv m = RegistryAccountPrv (Map KindPrv (ResolverAccountPrv m))


emptyRegistryAccountPrv :: RegistryAccountPrv m
emptyRegistryAccountPrv =
  RegistryAccountPrv Map.empty


registerAccountPrv :: ResolverAccountPrv m -> RegistryAccountPrv m -> RegistryAccountPrv m
registerAccountPrv resolver (RegistryAccountPrv resolvers) =
  RegistryAccountPrv $ Map.insert resolver.kindRAP resolver resolvers


lookupAccountPrv :: KindPrv -> RegistryAccountPrv m -> Maybe (ResolverAccountPrv m)
lookupAccountPrv kind (RegistryAccountPrv resolvers) =
  Map.lookup kind resolvers


data DepsAccountRun = DepsAccountRun {
    tenantPoolDAR :: PoolDB
    , credentialsDAR :: StoreCred IO
    , resolversDAR :: RegistryAccountPrv IO
    , clockDAR :: Clock IO
  }


loadAccountRun :: DepsAccountRun -> AccountRefDB -> IO (Either ErrorApp RuntimeAccount)
loadAccountRun deps accountRef =
  loadAccountRunGeneration deps (GenerationAccount 1) accountRef


loadAccountRunGeneration :: DepsAccountRun -> GenerationAccount -> AccountRefDB -> IO (Either ErrorApp RuntimeAccount)
loadAccountRunGeneration deps generation accountRef =
  runExceptT $ do
    loadedAt <- liftIO deps.clockDAR.nowC
    account <- ExceptT $ fetchAccountForRun deps accountRef
    credentialUid <- except $ credentialUidAccountRun account
    runtimeCred <- ExceptT $ loadCredentialForRun deps account.tenantUidAD credentialUid
    resolver <- except $ resolverAccountRun deps account
    providerAccount <- ExceptT $ resolveAccountForRun resolver account runtimeCred
    except $ validateResolvedAccountRun account providerAccount
    statusVar <- liftIO $ newTVarIO ReadySAR
    pure RuntimeAccount {
        accountRA = account
        , providerRA = providerAccount
        , generationRA = generation
        , startedAtRA = loadedAt
        , statusRA = statusVar
      }


changedAccountRun :: AccountRefDB -> RuntimeAccount -> Bool
changedAccountRun accountRef runtime =
  accountRef.accountUidARD /= runtime.accountRA.uidAD
    || accountRef.kindARD /= runtime.accountRA.kindAD
    || accountRef.updatedAtARD /= runtime.accountRA.updatedAtAD
    || credentialChangedAccountRun accountRef runtime


contextAccountRun :: AccountRefDB -> ContextTenant
contextAccountRun accountRef =
  ContextTenant {
      tenantUidCT = accountRef.tenantUidARD
      , principalUidCT = Nothing
      , correlationKeyCT = correlationAccountRun accountRef
    }


correlationAccountRun :: AccountRefDB -> CorrelationKey
correlationAccountRun accountRef =
  CorrelationKey $ "account-run:" <> renderTenantUidRun accountRef.tenantUidARD
    <> ":" <> renderAccountUidRun accountRef.accountUidARD


fetchAccountForRun :: DepsAccountRun -> AccountRefDB -> IO (Either ErrorApp AccountDB)
fetchAccountForRun deps accountRef = do
  let
    context = contextAccountRun accountRef
    transaction = fetchAccountDB accountRef.accountUidARD

  result <- runTenantDB deps.tenantPoolDAR context ReadCommitted Read transaction
  pure $ case result of
    Left errorDb -> Left $ DatabaseEA errorDb
    Right Nothing -> Left $ missingAccountRun accountRef
    Right (Just account) ->
      case validateAccountRefRun accountRef account of
        Left errorApp -> Left errorApp
        Right () -> Right account


loadCredentialForRun :: DepsAccountRun -> TenantUid -> CredentialUid -> IO (Either ErrorApp RuntimeCred)
loadCredentialForRun deps tenantUid credentialUid = do
  result <- deps.credentialsDAR.loadSC tenantUid credentialUid
  pure $ case result of
    Left _errorCred -> Left $ credentialLoadErrorRun tenantUid credentialUid
    Right runtimeCred -> Right runtimeCred


resolveAccountForRun :: ResolverAccountPrv IO -> AccountDB -> RuntimeCred -> IO (Either ErrorApp AccountPrv)
resolveAccountForRun resolver account runtimeCred = do
  result <- resolver.resolveRAP account runtimeCred
  pure $ case result of
    Left errorPrv -> Left $ ProviderEA errorPrv
    Right accountPrv -> Right accountPrv


resolverAccountRun :: DepsAccountRun -> AccountDB -> Either ErrorApp (ResolverAccountPrv IO)
resolverAccountRun deps account =
  case lookupAccountPrv account.kindAD deps.resolversDAR of
    Nothing -> Left $ missingResolverRun account
    Just resolver -> Right resolver


credentialUidAccountRun :: AccountDB -> Either ErrorApp CredentialUid
credentialUidAccountRun account =
  case account.credentialUidAD of
    Nothing -> Left $ missingCredentialRun account
    Just credentialUid -> Right credentialUid


validateAccountRefRun :: AccountRefDB -> AccountDB -> Either ErrorApp ()
validateAccountRefRun accountRef account
  | accountRef.tenantUidARD /= account.tenantUidAD =
      Left $ inconsistentAccountRun "tenant mismatch while loading account runtime" accountRef account
  | accountRef.accountUidARD /= account.uidAD =
      Left $ inconsistentAccountRun "account uid mismatch while loading account runtime" accountRef account
  | accountRef.kindARD /= account.kindAD =
      Left $ inconsistentAccountRun "provider kind mismatch while loading account runtime" accountRef account
  | otherwise =
      Right ()


validateResolvedAccountRun :: AccountDB -> AccountPrv -> Either ErrorApp ()
validateResolvedAccountRun account accountPrv
  | accountPrv.tenantUidAP /= account.tenantUidAD =
      Left $ invalidResolvedAccountRun "resolved provider account has wrong tenant" account accountPrv
  | accountPrv.accountUidAP /= account.uidAD =
      Left $ invalidResolvedAccountRun "resolved provider account has wrong account uid" account accountPrv
  | accountPrv.kindAP /= account.kindAD =
      Left $ invalidResolvedAccountRun "resolved provider account has wrong provider kind" account accountPrv
  | otherwise =
      Right ()


credentialChangedAccountRun :: AccountRefDB -> RuntimeAccount -> Bool
credentialChangedAccountRun accountRef runtime =
  case accountRef.credentialUpdatedAtARD of
    Nothing -> False
    Just updatedAt -> updatedAt > runtime.startedAtRA


missingAccountRun :: AccountRefDB -> ErrorApp
missingAccountRun accountRef =
  InternalEA $ "active account reference disappeared while loading runtime: tenant "
    <> renderTenantUidRun accountRef.tenantUidARD <> ", account " <> renderAccountUidRun accountRef.accountUidARD


missingResolverRun :: AccountDB -> ErrorApp
missingResolverRun account =
  providerStateErrorRun "no provider account resolver registered for account kind" $ object [
      "tenantUid" .= account.tenantUidAD
      , "accountUid" .= account.uidAD
      , "kind" .= account.kindAD
    ]


missingCredentialRun :: AccountDB -> ErrorApp
missingCredentialRun account =
  providerStateErrorRun "account has no credential configured" $ object [
      "tenantUid" .= account.tenantUidAD
      , "accountUid" .= account.uidAD
      , "kind" .= account.kindAD
    ]


credentialLoadErrorRun :: TenantUid -> CredentialUid -> ErrorApp
credentialLoadErrorRun tenantUid credentialUid =
  InternalEA $ "credential load failed while loading account runtime: tenant "
    <> renderTenantUidRun tenantUid <> ", credential " <> renderCredentialUidRun credentialUid


inconsistentAccountRun :: Text -> AccountRefDB -> AccountDB -> ErrorApp
inconsistentAccountRun message accountRef account =
  InternalEA $ message <> ": ref=" <> renderAccountRefRun accountRef <> ", account=" <> renderAccountRun account


invalidResolvedAccountRun :: Text -> AccountDB -> AccountPrv -> ErrorApp
invalidResolvedAccountRun message account accountPrv =
  InternalEA $ message <> ": account=" <> renderAccountRun account <> ", providerAccount=" <> renderAccountPrvRun accountPrv


providerStateErrorRun :: Text -> Value -> ErrorApp
providerStateErrorRun message details =
  ProviderEA ErrorPrv {
      kindEP = ProviderStateKEP
      , messageEP = message
      , retryEP = NeverRE
      , detailsEP = Just details
    }


renderAccountRefRun :: AccountRefDB -> Text
renderAccountRefRun accountRef =
  "{tenantUid=" <> renderTenantUidRun accountRef.tenantUidARD
    <> ", accountUid=" <> renderAccountUidRun accountRef.accountUidARD
    <> ", kind=" <> Tx.pack (show accountRef.kindARD)
    <> "}"


renderAccountRun :: AccountDB -> Text
renderAccountRun account =
  "{tenantUid=" <> renderTenantUidRun account.tenantUidAD
    <> ", accountUid=" <> renderAccountUidRun account.uidAD
    <> ", kind=" <> Tx.pack (show account.kindAD)
    <> "}"


renderAccountPrvRun :: AccountPrv -> Text
renderAccountPrvRun accountPrv =
  "{tenantUid=" <> renderTenantUidRun accountPrv.tenantUidAP
    <> ", accountUid=" <> renderAccountUidRun accountPrv.accountUidAP
    <> ", kind=" <> Tx.pack (show accountPrv.kindAP)
    <> "}"


renderTenantUidRun :: TenantUid -> Text
renderTenantUidRun (TenantUid uid) =
  Tx.pack $ show uid


renderAccountUidRun :: AccountUid -> Text
renderAccountUidRun (AccountUid uid) =
  Tx.pack $ show uid


renderCredentialUidRun :: CredentialUid -> Text
renderCredentialUidRun (CredentialUid uid) =
  Tx.pack $ show uid