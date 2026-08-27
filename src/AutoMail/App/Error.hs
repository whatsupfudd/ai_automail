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


data ErrorConfig = ErrorConfig Text
  deriving stock (Eq, Show, Generic)


data ErrorDb = ErrorDb Text
  deriving stock (Eq, Show, Generic)


data ErrorMail = ErrorMail Text
  deriving stock (Eq, Show, Generic)


data ErrorBlob = ErrorBlob Text
  deriving stock (Eq, Show, Generic)


data ErrorJob = ErrorJob Text
  deriving stock (Eq, Show, Generic)


data ErrorAn = ErrorAn Text
  deriving stock (Eq, Show, Generic)


data ErrorKn = ErrorKn Text
  deriving stock (Eq, Show, Generic)


data ErrorWf = ErrorWf Text
  deriving stock (Eq, Show, Generic)


data ErrorPol = ErrorPol Text
  deriving stock (Eq, Show, Generic)


data ErrorAct = ErrorAct Text
  deriving stock (Eq, Show, Generic)


data ErrorApp =
    ConfigEA ErrorConfig
  | DatabaseEA ErrorDb
  | ProviderEA ErrorPrv
  | MailEA ErrorMail
  | BlobEA ErrorBlob
  | JobEA ErrorJob
  | AnalysisEA ErrorAn
  | KnowledgeEA ErrorKn
  | WorkflowEA ErrorWf
  | PolicyEA ErrorPol
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