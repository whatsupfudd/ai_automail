{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module AutoMail.Policy.Types where

import Data.Aeson (FromJSON, ToJSON, Value)
import Data.Text (Text)
import qualified Data.Vector as V
import GHC.Generics (Generic)

import AutoMail.Action.Types (AuthorityAct, ProposalAct)
import AutoMail.Knowledge.Types (FactKn)
import AutoMail.Model.Common (ExpressionRule, VersionNo)
import AutoMail.Model.Id (PrincipalUid, TenantUid)


newtype KeyPolicy = KeyPolicy Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


newtype KeyRulePol = KeyRulePol Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


data DecisionPol =
    AllowDP AuthorityAct
  | ApprovalDP AuthorityAct Text
  | DenyDP Text
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data RulePol = RulePol {
    keyRP :: KeyRulePol
    , priorityRP :: Int
    , whenRP :: ExpressionRule
    , decisionRP :: DecisionPol
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data SpecPol = SpecPol {
    keySP :: KeyPolicy
    , versionSP :: VersionNo
    , defaultSP :: DecisionPol
    , rulesSP :: V.Vector RulePol
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data ContextPol = ContextPol {
    tenantUidCP :: TenantUid
    , principalUidCP :: Maybe PrincipalUid
    , actionCP :: ProposalAct
    , factsCP :: V.Vector FactKn
    , contextCP :: Value
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)