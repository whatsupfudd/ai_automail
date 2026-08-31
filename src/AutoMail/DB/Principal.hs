{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE QuasiQuotes #-}

module AutoMail.DB.Principal (
    KindPrincipal(..)
    , StatusPrincipal(..)
    , PrincipalDB(..)
    , CreatePrincipalDB(..)
    , UpdatePrincipalDB(..)
    , insertPrincipalDB
    , fetchPrincipalDB
    , fetchPrincipalKeyDB
    , listPrincipalsDB
    , updatePrincipalDB
    , renderKindPrincipal
    , parseKindPrincipal
    , renderStatusPrincipal
    , parseStatusPrincipal
  ) where

import Control.Monad (join)

import Data.Aeson (FromJSON, ToJSON, Value)
import Data.Int (Int64)
import Data.Maybe (isJust)
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


data KindPrincipal =
    HumanKP
  | ServiceKP
  | SystemKP
  | ModelKP
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data StatusPrincipal =
    ActiveSP
  | DisabledSP
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data PrincipalDB = PrincipalDB {
    uidPD :: PrincipalUid
    , tenantUidPD :: TenantUid
    , kindPD :: KindPrincipal
    , externalKeyPD :: Maybe Text
    , namePD :: Text
    , addressPD :: Maybe Text
    , statusPD :: StatusPrincipal
    , configPD :: Value
    , createdAtPD :: UTCTime
    , updatedAtPD :: UTCTime
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data CreatePrincipalDB = CreatePrincipalDB {
    kindCPD :: KindPrincipal
    , externalKeyCPD :: Maybe Text
    , nameCPD :: Text
    , addressCPD :: Maybe Text
    , statusCPD :: StatusPrincipal
    , configCPD :: Value
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data UpdatePrincipalDB = UpdatePrincipalDB {
    kindUPD :: Maybe KindPrincipal
    , externalKeyUPD :: Maybe (Maybe Text)
    , nameUPD :: Maybe Text
    , addressUPD :: Maybe (Maybe Text)
    , statusUPD :: Maybe StatusPrincipal
    , configUPD :: Maybe Value
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


-- SQL-facing representations. The quasiquoted statements operate only on
-- primitive values directly understood by Hasql.

type PrincipalRowSqlDB =
  ( Int64
  , Int64
  , Text
  , Maybe Text
  , Text
  , Maybe Text
  , Text
  , Value
  , UTCTime
  , UTCTime
  )


type CreatePrincipalParamsSqlDB =
  ( Text
  , Maybe Text
  , Text
  , Maybe Text
  , Text
  , Value
  )


type UpdatePrincipalParamsSqlDB =
  ( Int64
  , Maybe Text
  , Bool
  , Maybe Text
  , Maybe Text
  , Bool
  , Maybe Text
  , Maybe Text
  , Maybe Value
  )


insertPrincipalDB ::
  CreatePrincipalDB -> Transaction PrincipalDB
insertPrincipalDB principal =
  HT.statement principal insertPrincipalStatementDB


fetchPrincipalDB ::
  PrincipalUid -> Transaction (Maybe PrincipalDB)
fetchPrincipalDB principalUid =
  HT.statement principalUid fetchPrincipalStatementDB


fetchPrincipalKeyDB ::
  KindPrincipal -> Text -> Transaction (Maybe PrincipalDB)
fetchPrincipalKeyDB kind externalKey =
  HT.statement (kind, externalKey) fetchPrincipalKeyStatementDB


listPrincipalsDB ::
  Transaction (Vector PrincipalDB)
listPrincipalsDB =
  HT.statement () listPrincipalsStatementDB


updatePrincipalDB ::
  PrincipalUid
  -> UpdatePrincipalDB
  -> Transaction (Maybe PrincipalDB)
updatePrincipalDB principalUid update
  | changesPrincipalUpdateDB update =
      HT.statement
        (principalUid, update)
        updatePrincipalStatementDB
  | otherwise =
      fetchPrincipalDB principalUid


insertPrincipalStatementDB ::
  Statement CreatePrincipalDB PrincipalDB
insertPrincipalStatementDB =
  dimap createPrincipalToParamsDB principalFromRowDB
    [HTH.singletonStatement|
      INSERT INTO am.principal (
        tenant_fk,
        kind,
        external_key,
        name,
        address,
        status,
        config
      )
      VALUES (
        am.current_tenant_uid(),
        $1 :: text,
        $2 :: text?,
        $3 :: text,
        $4 :: text?,
        $5 :: text,
        $6 :: jsonb
      )
      RETURNING
        uid :: int8,
        tenant_fk :: int8,
        kind :: text,
        external_key :: text?,
        name :: text,
        address :: text?,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
    |]


fetchPrincipalStatementDB ::
  Statement PrincipalUid (Maybe PrincipalDB)
fetchPrincipalStatementDB =
  dimap valuePrincipalUidDB (fmap principalFromRowDB)
    [HTH.maybeStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        kind :: text,
        external_key :: text?,
        name :: text,
        address :: text?,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
      FROM am.principal
      WHERE uid = $1 :: int8
    |]


fetchPrincipalKeyStatementDB ::
  Statement (KindPrincipal, Text) (Maybe PrincipalDB)
fetchPrincipalKeyStatementDB =
  dimap toParamsDB (fmap principalFromRowDB)
    [HTH.maybeStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        kind :: text,
        external_key :: text?,
        name :: text,
        address :: text?,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
      FROM am.principal
      WHERE
        kind = $1 :: text
        AND external_key = $2 :: text
      ORDER BY uid
      LIMIT 1
    |]
  where
  toParamsDB (kind, externalKey) =
    (renderKindPrincipal kind, externalKey)


listPrincipalsStatementDB ::
  Statement () (Vector PrincipalDB)
listPrincipalsStatementDB =
  dimap id (fmap principalFromRowDB)
    [HTH.vectorStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        kind :: text,
        external_key :: text?,
        name :: text,
        address :: text?,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
      FROM am.principal
      ORDER BY name, uid
    |]


updatePrincipalStatementDB ::
  Statement
    (PrincipalUid, UpdatePrincipalDB)
    (Maybe PrincipalDB)
updatePrincipalStatementDB =
  dimap updatePrincipalToParamsDB (fmap principalFromRowDB)
    [HTH.maybeStatement|
      UPDATE am.principal
      SET
        kind = coalesce(
          $2 :: text?,
          kind
        ),
        external_key = CASE
          WHEN $3 :: bool THEN $4 :: text?
          ELSE external_key
        END,
        name = coalesce(
          $5 :: text?,
          name
        ),
        address = CASE
          WHEN $6 :: bool THEN $7 :: text?
          ELSE address
        END,
        status = coalesce(
          $8 :: text?,
          status
        ),
        config = coalesce(
          $9 :: jsonb?,
          config
        ),
        updated_at = now()
      WHERE uid = $1 :: int8
      RETURNING
        uid :: int8,
        tenant_fk :: int8,
        kind :: text,
        external_key :: text?,
        name :: text,
        address :: text?,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
    |]


createPrincipalToParamsDB ::
  CreatePrincipalDB -> CreatePrincipalParamsSqlDB
createPrincipalToParamsDB principal =
  ( renderKindPrincipal principal.kindCPD
  , principal.externalKeyCPD
  , principal.nameCPD
  , principal.addressCPD
  , renderStatusPrincipal principal.statusCPD
  , principal.configCPD
  )


updatePrincipalToParamsDB ::
  (PrincipalUid, UpdatePrincipalDB)
  -> UpdatePrincipalParamsSqlDB
updatePrincipalToParamsDB (principalUid, update) =
  ( valuePrincipalUidDB principalUid
  , renderKindPrincipal <$> update.kindUPD
  , isJust update.externalKeyUPD
  , join update.externalKeyUPD
  , update.nameUPD
  , isJust update.addressUPD
  , join update.addressUPD
  , renderStatusPrincipal <$> update.statusUPD
  , update.configUPD
  )


principalFromRowDB ::
  PrincipalRowSqlDB -> PrincipalDB
principalFromRowDB
  ( uid
  , tenantUid
  , kind
  , externalKey
  , name
  , address
  , status
  , config
  , createdAt
  , updatedAt
  ) =
  PrincipalDB {
      uidPD = PrincipalUid uid
      , tenantUidPD = TenantUid tenantUid
      , kindPD = decodeKindPrincipalDB kind
      , externalKeyPD = externalKey
      , namePD = name
      , addressPD = address
      , statusPD = decodeStatusPrincipalDB status
      , configPD = config
      , createdAtPD = createdAt
      , updatedAtPD = updatedAt
    }


changesPrincipalUpdateDB ::
  UpdatePrincipalDB -> Bool
changesPrincipalUpdateDB update =
  isJust update.kindUPD
    || isJust update.externalKeyUPD
    || isJust update.nameUPD
    || isJust update.addressUPD
    || isJust update.statusUPD
    || isJust update.configUPD


renderKindPrincipal :: KindPrincipal -> Text
renderKindPrincipal kind =
  case kind of
    HumanKP -> "human"
    ServiceKP -> "service"
    SystemKP -> "system"
    ModelKP -> "model"


parseKindPrincipal :: Text -> Maybe KindPrincipal
parseKindPrincipal value =
  case value of
    "human" -> Just HumanKP
    "service" -> Just ServiceKP
    "system" -> Just SystemKP
    "model" -> Just ModelKP
    _ -> Nothing


decodeKindPrincipalDB :: Text -> KindPrincipal
decodeKindPrincipalDB value =
  case parseKindPrincipal value of
    Just kind ->
      kind

    Nothing ->
      error $
        "Unknown am.principal.kind value: "
          <> Tx.unpack value


renderStatusPrincipal :: StatusPrincipal -> Text
renderStatusPrincipal status =
  case status of
    ActiveSP -> "active"
    DisabledSP -> "disabled"


parseStatusPrincipal :: Text -> Maybe StatusPrincipal
parseStatusPrincipal value =
  case value of
    "active" -> Just ActiveSP
    "disabled" -> Just DisabledSP
    _ -> Nothing


decodeStatusPrincipalDB :: Text -> StatusPrincipal
decodeStatusPrincipalDB value =
  case parseStatusPrincipal value of
    Just status ->
      status

    Nothing ->
      error $
        "Unknown am.principal.status value: "
          <> Tx.unpack value


valuePrincipalUidDB :: PrincipalUid -> Int64
valuePrincipalUidDB principalUid =
  case principalUid of
    PrincipalUid value ->
      value