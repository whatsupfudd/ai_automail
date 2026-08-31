{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE QuasiQuotes #-}

module AutoMail.DB.Space (
    StatusSpace(..)
    , KindSpace(..)
    , SpaceDB(..)
    , CreateSpaceDB(..)
    , UpdateSpaceDB(..)
    , insertSpaceDB
    , fetchSpaceDB
    , fetchSpaceCodeDB
    , listSpacesDB
    , listActiveSpacesDB
    , updateSpaceDB
  ) where

import Control.Applicative ((<|>))

import Data.Aeson (FromJSON, ToJSON, Value)
import Data.Int (Int64)
import Data.Profunctor (dimap)
import Data.Text (Text)
import qualified Data.Text as Tx
import Data.Time (UTCTime)
import Data.Vector (Vector)

import GHC.Generics (Generic)

import Hasql.Statement (Statement)
import qualified Hasql.TH as HTH
import Hasql.Transaction (Transaction)
import qualified Hasql.Transaction as HT

import AutoMail.Model.Id


data StatusSpace =
    ActiveSS
  | DisabledSS
  | ArchivedSS
  deriving stock (Eq, Show, Generic)


newtype KindSpace = KindSpace Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


data SpaceDB = SpaceDB {
    uidSD :: SpaceUid
    , tenantUidSD :: TenantUid
    , codeSD :: Text
    , nameSD :: Text
    , kindSD :: KindSpace
    , statusSD :: StatusSpace
    , configSD :: Value
    , createdAtSD :: UTCTime
    , updatedAtSD :: UTCTime
  }
  deriving stock (Eq, Show, Generic)


data CreateSpaceDB = CreateSpaceDB {
    codeCSD :: Text
    , nameCSD :: Text
    , kindCSD :: KindSpace
    , configCSD :: Value
  }
  deriving stock (Eq, Show, Generic)


data UpdateSpaceDB = UpdateSpaceDB {
    codeUSD :: Maybe Text
    , nameUSD :: Maybe Text
    , kindUSD :: Maybe KindSpace
    , statusUSD :: Maybe StatusSpace
    , configUSD :: Maybe Value
  }
  deriving stock (Eq, Show, Generic)


type SpaceRowSqlDB =
  ( Int64
  , Int64
  , Text
  , Text
  , Text
  , Text
  , Value
  , UTCTime
  , UTCTime
  )


type CreateSpaceParamsSqlDB =
  ( Text
  , Text
  , Text
  , Value
  )


type UpdateSpaceParamsSqlDB =
  ( Int64
  , Maybe Text
  , Maybe Text
  , Maybe Text
  , Maybe Text
  , Maybe Value
  )


insertSpaceDB ::
  CreateSpaceDB -> Transaction SpaceDB
insertSpaceDB createSpace =
  HT.statement createSpace insertSpaceStatementDB


fetchSpaceDB ::
  SpaceUid -> Transaction (Maybe SpaceDB)
fetchSpaceDB spaceUid =
  HT.statement spaceUid fetchSpaceStatementDB


fetchSpaceCodeDB ::
  Text -> Transaction (Maybe SpaceDB)
fetchSpaceCodeDB code =
  HT.statement code fetchSpaceCodeStatementDB


listSpacesDB ::
  Transaction (Vector SpaceDB)
listSpacesDB =
  HT.statement () listSpacesStatementDB


listActiveSpacesDB ::
  Transaction (Vector SpaceDB)
listActiveSpacesDB =
  HT.statement () listActiveSpacesStatementDB


updateSpaceDB ::
  SpaceUid
  -> UpdateSpaceDB
  -> Transaction (Maybe SpaceDB)
updateSpaceDB spaceUid updateSpace =
  HT.statement
    (spaceUid, updateSpace)
    updateSpaceStatementDB


insertSpaceStatementDB ::
  Statement CreateSpaceDB SpaceDB
insertSpaceStatementDB =
  dimap createSpaceToParamsDB spaceFromRowDB
    [HTH.singletonStatement|
      INSERT INTO am.space (
        tenant_fk,
        code,
        name,
        kind,
        status,
        config
      )
      VALUES (
        am.current_tenant_uid(),
        $1 :: text,
        $2 :: text,
        $3 :: text,
        'active',
        $4 :: jsonb
      )
      RETURNING
        uid :: int8,
        tenant_fk :: int8,
        code :: text,
        name :: text,
        kind :: text,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
    |]


fetchSpaceStatementDB ::
  Statement SpaceUid (Maybe SpaceDB)
fetchSpaceStatementDB =
  dimap valueSpaceUidDB (fmap spaceFromRowDB)
    [HTH.maybeStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        code :: text,
        name :: text,
        kind :: text,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
      FROM am.space
      WHERE
        tenant_fk = am.current_tenant_uid()
        AND uid = $1 :: int8
    |]


fetchSpaceCodeStatementDB ::
  Statement Text (Maybe SpaceDB)
fetchSpaceCodeStatementDB =
  dimap id (fmap spaceFromRowDB)
    [HTH.maybeStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        code :: text,
        name :: text,
        kind :: text,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
      FROM am.space
      WHERE
        tenant_fk = am.current_tenant_uid()
        AND code = $1 :: text
    |]


listSpacesStatementDB ::
  Statement () (Vector SpaceDB)
listSpacesStatementDB =
  dimap id (fmap spaceFromRowDB)
    [HTH.vectorStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        code :: text,
        name :: text,
        kind :: text,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
      FROM am.space
      WHERE tenant_fk = am.current_tenant_uid()
      ORDER BY code, uid
    |]


listActiveSpacesStatementDB ::
  Statement () (Vector SpaceDB)
listActiveSpacesStatementDB =
  dimap id (fmap spaceFromRowDB)
    [HTH.vectorStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        code :: text,
        name :: text,
        kind :: text,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
      FROM am.space
      WHERE
        tenant_fk = am.current_tenant_uid()
        AND status = 'active'
      ORDER BY code, uid
    |]


updateSpaceStatementDB ::
  Statement
    (SpaceUid, UpdateSpaceDB)
    (Maybe SpaceDB)
updateSpaceStatementDB =
  dimap updateSpaceToParamsDB (fmap spaceFromRowDB)
    [HTH.maybeStatement|
      UPDATE am.space
      SET
        code = coalesce(
          $2 :: text?,
          code
        ),
        name = coalesce(
          $3 :: text?,
          name
        ),
        kind = coalesce(
          $4 :: text?,
          kind
        ),
        status = coalesce(
          $5 :: text?,
          status
        ),
        config = coalesce(
          $6 :: jsonb?,
          config
        ),
        updated_at = now()
      WHERE
        tenant_fk = am.current_tenant_uid()
        AND uid = $1 :: int8
      RETURNING
        uid :: int8,
        tenant_fk :: int8,
        code :: text,
        name :: text,
        kind :: text,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
    |]


createSpaceToParamsDB ::
  CreateSpaceDB -> CreateSpaceParamsSqlDB
createSpaceToParamsDB createSpace =
  ( createSpace.codeCSD
  , createSpace.nameCSD
  , textKindSpaceDB createSpace.kindCSD
  , createSpace.configCSD
  )


updateSpaceToParamsDB ::
  (SpaceUid, UpdateSpaceDB)
  -> UpdateSpaceParamsSqlDB
updateSpaceToParamsDB (spaceUid, updateSpace) =
  ( valueSpaceUidDB spaceUid
  , updateSpace.codeUSD
  , updateSpace.nameUSD
  , textKindSpaceDB <$> updateSpace.kindUSD
  , textStatusSpaceDB <$> updateSpace.statusUSD
  , updateSpace.configUSD
  )


spaceFromRowDB ::
  SpaceRowSqlDB -> SpaceDB
spaceFromRowDB
  ( uid
  , tenantUid
  , code
  , name
  , kind
  , status
  , config
  , createdAt
  , updatedAt
  ) =
  SpaceDB {
      uidSD = SpaceUid uid
      , tenantUidSD = TenantUid tenantUid
      , codeSD = code
      , nameSD = name
      , kindSD = KindSpace kind
      , statusSD = parseStatusSpaceDB status
      , configSD = config
      , createdAtSD = createdAt
      , updatedAtSD = updatedAt
    }


valueSpaceUidDB ::
  SpaceUid -> Int64
valueSpaceUidDB (SpaceUid value) =
  value


textKindSpaceDB ::
  KindSpace -> Text
textKindSpaceDB (KindSpace value) =
  value


textStatusSpaceDB ::
  StatusSpace -> Text
textStatusSpaceDB status =
  case status of
    ActiveSS -> "active"
    DisabledSS -> "disabled"
    ArchivedSS -> "archived"


parseStatusSpaceDB ::
  Text -> StatusSpace
parseStatusSpaceDB value =
  case parseStatusSpaceMaybeDB value of
    Just status ->
      status

    Nothing ->
      error $
        "AutoMail.DB.Space.parseStatusSpaceDB: invalid status value "
          <> Tx.unpack value


parseStatusSpaceMaybeDB ::
  Text -> Maybe StatusSpace
parseStatusSpaceMaybeDB value =
  case value of
    "active" -> Just ActiveSS
    "disabled" -> Just DisabledSS
    "archived" -> Just ArchivedSS
    _ -> Nothing


instance Semigroup UpdateSpaceDB where
  left <> right =
    UpdateSpaceDB {
        codeUSD = right.codeUSD <|> left.codeUSD
        , nameUSD = right.nameUSD <|> left.nameUSD
        , kindUSD = right.kindUSD <|> left.kindUSD
        , statusUSD = right.statusUSD <|> left.statusUSD
        , configUSD = right.configUSD <|> left.configUSD
      }


instance Monoid UpdateSpaceDB where
  mempty =
    UpdateSpaceDB {
        codeUSD = Nothing
        , nameUSD = Nothing
        , kindUSD = Nothing
        , statusUSD = Nothing
        , configUSD = Nothing
      }
