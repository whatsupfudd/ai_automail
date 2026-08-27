{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module AutoMail.Model.Common (
    ContextTenant(..)
    , VersionNo(..)
    , HashSha256
    , mkHashSha256
    , bytesHashSha256
    , parseHashSha256
    , renderHashSha256
    , TokenPage(..)
    , RequestPage(..)
    , ResultPage(..)
    , PathRule(..)
    , OperatorRule(..)
    , ExpressionRule(..)
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), Value, withText)
import qualified Data.ByteString as Bs
import Data.ByteString (ByteString)
import Data.Text (Text)
import qualified Data.Text as Tx
import qualified Data.Vector as V
import Data.Word (Word8)
import GHC.Generics (Generic)
import Numeric (readHex, showHex)

import AutoMail.Model.Id


data ContextTenant = ContextTenant {
    tenantUidCT :: TenantUid
    , principalUidCT :: Maybe PrincipalUid
    , correlationKeyCT :: CorrelationKey
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


newtype VersionNo = VersionNo Int
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


newtype HashSha256 = HashSha256 ByteString
  deriving stock (Eq, Ord, Show, Generic)


mkHashSha256 :: ByteString -> Maybe HashSha256
mkHashSha256 content
  | Bs.length content == 32 = Just $ HashSha256 content
  | otherwise = Nothing


bytesHashSha256 :: HashSha256 -> ByteString
bytesHashSha256 (HashSha256 content) = content


parseHashSha256 :: Text -> Maybe HashSha256
parseHashSha256 value
  | Tx.length value /= 64 = Nothing
  | otherwise = mkHashSha256 . Bs.pack =<< traverse decodeOffset [0, 2 .. 62]
  where
  decodeOffset :: Int -> Maybe Word8
  decodeOffset offset =
    case readHex $ Tx.unpack $ Tx.take 2 $ Tx.drop offset value of
      [(byteValue, "")] -> Just byteValue
      _ -> Nothing


renderHashSha256 :: HashSha256 -> Text
renderHashSha256 hashValue =
  Tx.concat $ map renderByte $ Bs.unpack $ bytesHashSha256 hashValue
  where
  renderByte byteValue =
    let
      rendered = Tx.pack $ showHex byteValue ""
    in
    if Tx.length rendered == 1 then "0" <> rendered else rendered


instance FromJSON HashSha256 where
  parseJSON =
    withText "HashSha256" $ \value ->
      case parseHashSha256 value of
        Just hashValue -> pure hashValue
        Nothing -> fail "expected a 64-character hexadecimal SHA-256 value"


instance ToJSON HashSha256 where
  toJSON = toJSON . renderHashSha256
  toEncoding = toEncoding . renderHashSha256


newtype TokenPage = TokenPage Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


data RequestPage = RequestPage {
    limitRP :: Int
    , tokenRP :: Maybe TokenPage
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data ResultPage a = ResultPage {
    valuesRP :: V.Vector a
    , nextRP :: Maybe TokenPage
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


newtype PathRule = PathRule (V.Vector Text)
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


data OperatorRule =
    EqualOR
  | NotEqualOR
  | LessOR
  | LessEqualOR
  | GreaterOR
  | GreaterEqualOR
  | ContainsOR
  | StartsWithOR
  | EndsWithOR
  | InOR
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data ExpressionRule =
    TrueER
  | FalseER
  | ExistsER PathRule
  | CompareER PathRule OperatorRule Value
  | AllER (V.Vector ExpressionRule)
  | AnyER (V.Vector ExpressionRule)
  | NotER ExpressionRule
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)