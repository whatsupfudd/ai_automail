{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE QuasiQuotes #-}

module AutoMail.DB.Tenant (
    StatusTenant(..)
    , TenantDB(..)
    , CreateTenantDB(..)
    , UpdateTenantDB(..)
    , TenantRefDB(..)
    , fetchTenantDB
    , updateTenantDB
    , insertTenantControlDB
    , listActiveTenantRefsDB
    , encodeStatusTenantDB
    , decodeStatusTenantDB
  ) where

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


data StatusTenant =
    ActiveST
  | DisabledST
  | ArchivedST
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data TenantDB = TenantDB {
    uidTD :: TenantUid
    , codeTD :: Text
    , nameTD :: Text
    , statusTD :: StatusTenant
    , timezoneTD :: Text
    , configTD :: Value
    , createdAtTD :: UTCTime
    , updatedAtTD :: UTCTime
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data CreateTenantDB = CreateTenantDB {
    codeCTD :: Text
    , nameCTD :: Text
    , timezoneCTD :: Text
    , configCTD :: Value
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data UpdateTenantDB = UpdateTenantDB {
    nameUTD :: Maybe Text
    , statusUTD :: Maybe StatusTenant
    , timezoneUTD :: Maybe Text
    , configUTD :: Maybe Value
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data TenantRefDB = TenantRefDB {
    uidTRD :: TenantUid
    , updatedAtTRD :: UTCTime
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


-- SQL-facing representations.

type TenantRowSqlDB =
  ( Int64
  , Text
  , Text
  , Text
  , Text
  , Value
  , UTCTime
  , UTCTime
  )


type UpdateTenantParamsSqlDB =
  ( Maybe Text
  , Maybe Text
  , Maybe Text
  , Maybe Value
  )


type CreateTenantParamsSqlDB =
  ( Text
  , Text
  , Text
  , Value
  )


type TenantRefRowSqlDB =
  ( Int64
  , UTCTime
  )


fetchTenantDB ::
  Transaction (Maybe TenantDB)
fetchTenantDB =
  HT.statement () fetchTenantStatementDB


updateTenantDB ::
  UpdateTenantDB -> Transaction (Maybe TenantDB)
updateTenantDB update =
  HT.statement update updateTenantStatementDB


insertTenantControlDB ::
  CreateTenantDB -> Transaction TenantDB
insertTenantControlDB create =
  HT.statement create insertTenantControlStatementDB


listActiveTenantRefsDB ::
  Transaction (Vector TenantRefDB)
listActiveTenantRefsDB =
  HT.statement () listActiveTenantRefsStatementDB


fetchTenantStatementDB ::
  Statement () (Maybe TenantDB)
fetchTenantStatementDB =
  dimap id (fmap tenantFromRowDB)
    [HTH.maybeStatement|
      SELECT
        uid :: int8,
        code :: text,
        name :: text,
        status :: text,
        timezone :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
      FROM am.tenant
      WHERE uid =
        nullif(
          current_setting(
            'automail.tenant_uid',
            true
          ),
          ''
        )::bigint
    |]


updateTenantStatementDB ::
  Statement UpdateTenantDB (Maybe TenantDB)
updateTenantStatementDB =
  dimap updateTenantToParamsDB (fmap tenantFromRowDB)
    [HTH.maybeStatement|
      UPDATE am.tenant
      SET
        name = coalesce(
          $1 :: text?,
          name
        ),
        status = coalesce(
          $2 :: text?,
          status
        ),
        timezone = coalesce(
          $3 :: text?,
          timezone
        ),
        config = coalesce(
          $4 :: jsonb?,
          config
        ),
        updated_at = now()
      WHERE uid =
        nullif(
          current_setting(
            'automail.tenant_uid',
            true
          ),
          ''
        )::bigint
      RETURNING
        uid :: int8,
        code :: text,
        name :: text,
        status :: text,
        timezone :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
    |]


insertTenantControlStatementDB ::
  Statement CreateTenantDB TenantDB
insertTenantControlStatementDB =
  dimap createTenantToParamsDB tenantFromRowDB
    [HTH.singletonStatement|
      INSERT INTO am.tenant (
        code,
        name,
        timezone,
        config
      )
      VALUES (
        $1 :: text,
        $2 :: text,
        $3 :: text,
        $4 :: jsonb
      )
      RETURNING
        uid :: int8,
        code :: text,
        name :: text,
        status :: text,
        timezone :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
    |]


listActiveTenantRefsStatementDB ::
  Statement () (Vector TenantRefDB)
listActiveTenantRefsStatementDB =
  dimap id (fmap tenantRefFromRowDB)
    [HTH.vectorStatement|
      SELECT
        uid :: int8,
        updated_at :: timestamptz
      FROM am.tenant
      WHERE status = 'active'
      ORDER BY uid
    |]


updateTenantToParamsDB ::
  UpdateTenantDB -> UpdateTenantParamsSqlDB
updateTenantToParamsDB update =
  ( update.nameUTD
  , encodeStatusTenantDB <$> update.statusUTD
  , update.timezoneUTD
  , update.configUTD
  )


createTenantToParamsDB ::
  CreateTenantDB -> CreateTenantParamsSqlDB
createTenantToParamsDB create =
  ( create.codeCTD
  , create.nameCTD
  , create.timezoneCTD
  , create.configCTD
  )


tenantFromRowDB ::
  TenantRowSqlDB -> TenantDB
tenantFromRowDB
  ( uid
  , code
  , name
  , status
  , timezone
  , config
  , createdAt
  , updatedAt
  ) =
  TenantDB {
      uidTD = TenantUid uid
      , codeTD = code
      , nameTD = name
      , statusTD = decodeStatusTenantDB status
      , timezoneTD = timezone
      , configTD = config
      , createdAtTD = createdAt
      , updatedAtTD = updatedAt
    }


tenantRefFromRowDB ::
  TenantRefRowSqlDB -> TenantRefDB
tenantRefFromRowDB (uid, updatedAt) =
  TenantRefDB {
      uidTRD = TenantUid uid
      , updatedAtTRD = updatedAt
    }


encodeStatusTenantDB ::
  StatusTenant -> Text
encodeStatusTenantDB status =
  case status of
    ActiveST -> "active"
    DisabledST -> "disabled"
    ArchivedST -> "archived"


decodeStatusTenantDB ::
  Text -> StatusTenant
decodeStatusTenantDB value =
  case value of
    "active" ->
      ActiveST

    "disabled" ->
      DisabledST

    "archived" ->
      ArchivedST

    other ->
      error $
        "AutoMail.DB.Tenant.decodeStatusTenantDB: "
          <> "unknown tenant status: "
          <> Tx.unpack other
