{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE DeriveAnyClass #-}

module AutoMail.Knowledge.Types (
    KindEntity(..)
    , KindMention(..)
    , KindObservation(..)
    , KindFact(..)
    , KindRelation(..)
    , Confidence
    , mkConfidence
    , valueConfidence
    , EntityKn(..)
    , CandidateEntityKn(..)
    , SourceKn(..)
    , MentionKn(..)
    , StatusObservationKn(..)
    , ObservationKn(..)
    , StatusFactKn(..)
    , FactKn(..)
    , RelationKn(..)
  ) where

import Data.Scientific (toRealFloat)
import Data.Text (Text)
import Data.Time (UTCTime)

import GHC.Generics (Generic)
import Data.Aeson (FromJSON(..), ToJSON(..), Value, withScientific)

import AutoMail.Model.Common (HashSha256)
import AutoMail.Model.Id (
    AnalysisUid
    , AttachmentUid
    , EntityUid
    , FactUid
    , MentionUid
    , MessageUid
    , ObservationUid
    , PartUid
    , RelationUid
    , TenantUid
  )


newtype KindEntity = KindEntity Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


newtype KindMention = KindMention Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


newtype KindObservation = KindObservation Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


newtype KindFact = KindFact Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


newtype KindRelation = KindRelation Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


newtype Confidence = Confidence Double
  deriving stock (Eq, Ord, Show, Generic)


mkConfidence :: Double -> Maybe Confidence
mkConfidence value
  | value >= 0.0 && value <= 1.0 = Just $ Confidence value
  | otherwise = Nothing


valueConfidence :: Confidence -> Double
valueConfidence (Confidence value) = value


instance FromJSON Confidence where
  parseJSON = withScientific "Confidence" $ \value ->
    case mkConfidence $ toRealFloat value of
      Just confidence -> pure confidence
      Nothing -> fail "Confidence must be a finite number between 0.0 and 1.0"


instance ToJSON Confidence where
  toJSON = toJSON . valueConfidence
  toEncoding = toEncoding . valueConfidence


data EntityKn = EntityKn {
    uidEK :: EntityUid
    , tenantUidEK :: TenantUid
    , kindEK :: KindEntity
    , canonicalNameEK :: Text
    , externalKeyEK :: Maybe Text
    , attributesEK :: Value
  }
  deriving stock (Eq, Show, Generic)


data CandidateEntityKn = CandidateEntityKn {
    kindCEK :: KindEntity
    , nameCEK :: Text
    , externalKeyCEK :: Maybe Text
    , attributesCEK :: Value
  }
  deriving stock (Eq, Show, Generic)


data SourceKn = SourceKn {
    messageUidSK :: MessageUid
    , partUidSK :: Maybe PartUid
    , attachmentUidSK :: Maybe AttachmentUid
    , analysisUidSK :: Maybe AnalysisUid
    , fragmentSK :: Maybe Text
    , charStartSK :: Maybe Int
    , charEndSK :: Maybe Int
    , contentHashSK :: Maybe HashSha256
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data MentionKn = MentionKn {
    uidMK :: Maybe MentionUid
    , kindMK :: KindMention
    , valueMK :: Text
    , entityUidMK :: Maybe EntityUid
    , confidenceMK :: Maybe Confidence
    , sourceMK :: SourceKn
    , metadataMK :: Value
  }
  deriving stock (Eq, Show, Generic)


data StatusObservationKn =
    ProposedSOK
  | AcceptedSOK
  | RejectedSOK
  | SupersededSOK
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data ObservationKn = ObservationKn {
    uidOK :: Maybe ObservationUid
    , tenantUidOK :: TenantUid
    , kindOK :: KindObservation
    , payloadOK :: Value
    , confidenceOK :: Maybe Confidence
    , statusOK :: StatusObservationKn
    , observedAtOK :: Maybe UTCTime
    , sourceOK :: SourceKn
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data StatusFactKn =
    ActiveSFK
  | SupersededSFK
  | RejectedSFK
  | ExpiredSFK
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data FactKn = FactKn {
    uidFK :: Maybe FactUid
    , tenantUidFK :: TenantUid
    , entityUidFK :: Maybe EntityUid
    , observationUidFK :: Maybe ObservationUid
    , supersedesUidFK :: Maybe FactUid
    , kindFK :: KindFact
    , valueFK :: Value
    , valueTextFK :: Maybe Text
    , confidenceFK :: Maybe Confidence
    , statusFK :: StatusFactKn
    , validFromFK :: Maybe UTCTime
    , validUntilFK :: Maybe UTCTime
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data RelationKn = RelationKn {
    uidRK :: Maybe RelationUid
    , tenantUidRK :: TenantUid
    , leftEntityUidRK :: EntityUid
    , rightEntityUidRK :: EntityUid
    , observationUidRK :: Maybe ObservationUid
    , kindRK :: KindRelation
    , attributesRK :: Value
    , confidenceRK :: Maybe Confidence
    , validFromRK :: Maybe UTCTime
    , validUntilRK :: Maybe UTCTime
  }
  deriving stock (Eq, Show, Generic)