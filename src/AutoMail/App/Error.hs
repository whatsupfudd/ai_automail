{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module AutoMail.App.Error where

import Data.Aeson (Value)
import Data.Text (Text)
import Data.Time (NominalDiffTime)
import GHC.Generics (Generic)


data RetryError =
    NeverRE
  | ImmediateRE
  | DelayedRE NominalDiffTime
  | ReauthoriseRE
  | ResynchroniseRE
  deriving stock (Eq, Show, Generic)


data KindErrorPrv =
    AuthenticationKEP
  | AuthorizationKEP
  | RateLimitKEP
  | TransportKEP
  | InvalidRequestKEP
  | CursorExpiredKEP
  | NotFoundKEP
  | ConflictKEP
  | ProviderStateKEP
  | UnknownKEP
  deriving stock (Eq, Show, Generic)


data ErrorPrv = ErrorPrv {
    kindEP :: KindErrorPrv
    , messageEP :: Text
    , retryEP :: RetryError
    , detailsEP :: Maybe Value
  }
  deriving stock (Eq, Show, Generic)

-- Initial implementation of these types is just an alias.
type ErrorAn = Text
type ErrorAct = Text
type ErrorConfig = Text
type ErrorJob = Text
mkErrorJob :: Text -> ErrorJob
mkErrorJob = id
type ErrorWf = Text
type ErrorDb = Text
mkErrorDb :: Text -> ErrorDb
mkErrorDb = id
type ErrorCred = Text
mkErrorCred :: Text -> ErrorCred
mkErrorCred = id

data ErrorApp =
    ConfigEA ErrorConfig
  | DatabaseEA ErrorDb
  | CredentialEA Text
  | ProviderEA ErrorPrv
  | MailEA Text
  | BlobEA Text
  | JobEA ErrorJob
  | AnalysisEA ErrorAn
  | KnowledgeEA Text
  | WorkflowEA ErrorWf
  | PolicyEA Text
  | ActionEA ErrorAct
  | InternalEA Text
  deriving stock (Eq, Show, Generic)


retryErrorApp :: ErrorApp -> RetryError
retryErrorApp appError =
  case appError of
    ProviderEA providerError -> providerError.retryEP
    ConfigEA _ -> NeverRE
    DatabaseEA _ -> NeverRE
    MailEA _ -> NeverRE
    BlobEA _ -> NeverRE
    JobEA _ -> NeverRE
    AnalysisEA _ -> NeverRE
    KnowledgeEA _ -> NeverRE
    WorkflowEA _ -> NeverRE
    PolicyEA _ -> NeverRE
    ActionEA _ -> NeverRE
    InternalEA _ -> NeverRE


retryablePrv :: ErrorPrv -> Bool
retryablePrv providerError =
  case providerError.retryEP of
    NeverRE -> False
    ImmediateRE -> True
    DelayedRE _ -> True
    ReauthoriseRE -> False
    ResynchroniseRE -> True