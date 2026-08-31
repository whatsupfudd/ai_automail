{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE QuasiQuotes #-}

module AutoMail.DB.Audit (
    KindAudit(..), ObjectAudit(..), EventAudit(..), CreateAudit(..)
    , insertAuditDB, fetchAuditDB, listAuditObjectDB, listAuditRecentDB
  ) where

import Data.Aeson (FromJSON, ToJSON, Value)
import Data.Int (Int32, Int64)
import Data.Profunctor (dimap)
import Data.Text (Text)
import Data.Time (UTCTime)
import qualified Data.Vector as V

import GHC.Generics (Generic)

import Hasql.Statement (Statement)
import qualified Hasql.TH as HTH
import Hasql.Transaction (Transaction)
import qualified Hasql.Transaction as HT

import AutoMail.Model.Id


newtype KindAudit = KindAudit Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


data ObjectAudit = ObjectAudit {
    kindOA :: Text
    , uidOA :: Maybe Int64
  }
  deriving stock (Eq, Show, Generic)


data EventAudit = EventAudit {
    uidEA :: AuditUid
    , tenantUidEA :: TenantUid
    , principalUidEA :: Maybe PrincipalUid
    , kindEA :: KindAudit
    , objectEA :: Maybe ObjectAudit
    , correlationKeyEA :: Maybe CorrelationKey
    , payloadEA :: Value
    , createdAtEA :: UTCTime
  }
  deriving stock (Eq, Show, Generic)


data CreateAudit = CreateAudit {
    principalUidCA :: Maybe PrincipalUid
    , kindCA :: KindAudit
    , objectCA :: Maybe ObjectAudit
    , correlationKeyCA :: Maybe CorrelationKey
    , payloadCA :: Value
  }
  deriving stock (Eq, Show, Generic)


-- SQL-facing representations.

type EventAuditRowSqlDB =
  ( Int64
  , Int64
  , Maybe Int64
  , Text
  , Maybe Text
  , Maybe Int64
  , Maybe Text
  , Value
  , UTCTime
  )


type CreateAuditParamsSqlDB =
  ( Maybe Int64
  , Text
  , Maybe Text
  , Maybe Int64
  , Maybe Text
  , Value
  )


type ListObjectAuditParamsSqlDB =
  ( Text
  , Int64
  , Int32
  )


insertAuditDB ::
  CreateAudit -> Transaction AuditUid
insertAuditDB createAudit =
  HT.statement createAudit insertStatementAuditDB


fetchAuditDB ::
  AuditUid -> Transaction (Maybe EventAudit)
fetchAuditDB auditUid =
  HT.statement auditUid fetchStatementAuditDB


listAuditObjectDB ::
  Text
  -> Int64
  -> Int
  -> Transaction (V.Vector EventAudit)
listAuditObjectDB objectKind objectUid limit =
  HT.statement
    (objectKind, objectUid, limit)
    listObjectStatementAuditDB


listAuditRecentDB ::
  Int -> Transaction (V.Vector EventAudit)
listAuditRecentDB limit =
  HT.statement limit listRecentStatementAuditDB


insertStatementAuditDB ::
  Statement CreateAudit AuditUid
insertStatementAuditDB =
  dimap createAuditToParamsDB AuditUid
    [HTH.singletonStatement|
      INSERT INTO am.audit_event (
        tenant_fk,
        principal_fk,
        kind,
        object_kind,
        object_uid,
        correlation_key,
        payload
      )
      VALUES (
        am.current_tenant_uid(),
        coalesce(
          $1 :: int8?,
          nullif(
            current_setting(
              'automail.principal_uid',
              true
            ),
            ''
          )::bigint
        ),
        $2 :: text,
        $3 :: text?,
        $4 :: int8?,
        coalesce(
          $5 :: text?,
          nullif(
            current_setting(
              'automail.correlation_key',
              true
            ),
            ''
          )
        ),
        $6 :: jsonb
      )
      RETURNING uid :: int8
    |]


fetchStatementAuditDB ::
  Statement AuditUid (Maybe EventAudit)
fetchStatementAuditDB =
  dimap valueAuditUidAuditDB (fmap eventAuditFromRowDB)
    [HTH.maybeStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        principal_fk :: int8?,
        kind :: text,
        object_kind :: text?,
        object_uid :: int8?,
        correlation_key :: text?,
        payload :: jsonb,
        created_at :: timestamptz
      FROM am.audit_event
      WHERE uid = $1 :: int8
      LIMIT 1
    |]


listObjectStatementAuditDB ::
  Statement
    (Text, Int64, Int)
    (V.Vector EventAudit)
listObjectStatementAuditDB =
  dimap listObjectAuditToParamsDB (fmap eventAuditFromRowDB)
    [HTH.vectorStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        principal_fk :: int8?,
        kind :: text,
        object_kind :: text?,
        object_uid :: int8?,
        correlation_key :: text?,
        payload :: jsonb,
        created_at :: timestamptz
      FROM am.audit_event
      WHERE
        object_kind = $1 :: text
        AND object_uid = $2 :: int8
      ORDER BY created_at DESC, uid DESC
      LIMIT $3 :: int4
    |]


listRecentStatementAuditDB ::
  Statement Int (V.Vector EventAudit)
listRecentStatementAuditDB =
  dimap limitInt32AuditDB (fmap eventAuditFromRowDB)
    [HTH.vectorStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        principal_fk :: int8?,
        kind :: text,
        object_kind :: text?,
        object_uid :: int8?,
        correlation_key :: text?,
        payload :: jsonb,
        created_at :: timestamptz
      FROM am.audit_event
      ORDER BY created_at DESC, uid DESC
      LIMIT $1 :: int4
    |]


createAuditToParamsDB ::
  CreateAudit -> CreateAuditParamsSqlDB
createAuditToParamsDB createAudit =
  ( valuePrincipalUidAuditDB <$> createAudit.principalUidCA
  , valueKindAuditDB createAudit.kindCA
  , fmap objectKind createAudit.objectCA
  , createAudit.objectCA >>= objectUid
  , valueCorrelationKeyAuditDB <$> createAudit.correlationKeyCA
  , createAudit.payloadCA
  )
  where
  objectKind :: ObjectAudit -> Text
  objectKind object =
    object.kindOA

  objectUid :: ObjectAudit -> Maybe Int64
  objectUid object =
    object.uidOA


listObjectAuditToParamsDB ::
  (Text, Int64, Int) -> ListObjectAuditParamsSqlDB
listObjectAuditToParamsDB
  (objectKind, objectUid, limit) =
  ( objectKind
  , objectUid
  , limitInt32AuditDB limit
  )


eventAuditFromRowDB ::
  EventAuditRowSqlDB -> EventAudit
eventAuditFromRowDB
  ( auditUid
  , tenantUid
  , principalUid
  , auditKind
  , objectKind
  , objectUid
  , correlationKey
  , payload
  , createdAt
  ) =
  EventAudit {
      uidEA = AuditUid auditUid
      , tenantUidEA = TenantUid tenantUid
      , principalUidEA = PrincipalUid <$> principalUid
      , kindEA = KindAudit auditKind
      , objectEA = objectAuditDB objectKind objectUid
      , correlationKeyEA = CorrelationKey <$> correlationKey
      , payloadEA = payload
      , createdAtEA = createdAt
    }


objectAuditDB ::
  Maybe Text -> Maybe Int64 -> Maybe ObjectAudit
objectAuditDB objectKind objectUid =
  fmap mkObject objectKind
  where
  mkObject kindValue =
    ObjectAudit {
        kindOA = kindValue
        , uidOA = objectUid
      }


valueAuditUidAuditDB ::
  AuditUid -> Int64
valueAuditUidAuditDB (AuditUid value) =
  value


valuePrincipalUidAuditDB ::
  PrincipalUid -> Int64
valuePrincipalUidAuditDB (PrincipalUid value) =
  value


valueKindAuditDB ::
  KindAudit -> Text
valueKindAuditDB (KindAudit value) =
  value


valueCorrelationKeyAuditDB ::
  CorrelationKey -> Text
valueCorrelationKeyAuditDB (CorrelationKey value) =
  value


limitInt32AuditDB ::
  Int -> Int32
limitInt32AuditDB limit
  | limit <= 0 =
      0

  | limit > fromIntegral (maxBound :: Int32) =
      maxBound

  | otherwise =
      fromIntegral limit
