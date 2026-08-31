{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE QuasiQuotes #-}

module AutoMail.DB.Sync (
    KindSyncDB(..), StatusSyncDB(..), KeySyncDB(..), StateSyncDB(..)
    , fetchStateSyncDB, upsertStateSyncDB, beginSyncDB, completeSyncDB
    , failSyncDB, scheduleSyncDB, advanceCursorSyncDB, completeFullSyncDB
    , textStatusSyncDB, parseStatusSyncDB
  ) where

import Data.Aeson (FromJSON, ToJSON, Value)
import Data.Int (Int32, Int64)
import Data.Maybe (fromMaybe)
import Data.Profunctor (dimap)
import Data.Text (Text)
import Data.Time (UTCTime)

import GHC.Generics (Generic)

import Hasql.Statement (Statement)
import qualified Hasql.TH as HTH
import Hasql.Transaction (Transaction)
import qualified Hasql.Transaction as HT

import AutoMail.Model.Common
import AutoMail.Model.Id


newtype KindSyncDB = KindSyncDB Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON)


data StatusSyncDB =
    ReadySSD
  | SyncingSSD
  | ErrorSSD
  | DisabledSSD
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data KeySyncDB = KeySyncDB {
    accountUidKSD :: AccountUid
    , kindKSD :: KindSyncDB
    , scopeKeyKSD :: Text
  }
  deriving stock (Eq, Ord, Show, Generic)


data StateSyncDB = StateSyncDB {
    uidSSD :: Int64
    , keySSD :: KeySyncDB
    , cursorSSD :: Maybe CursorPrv
    , checkpointSSD :: Value
    , statusSSD :: StatusSyncDB
    , lastSuccessAtSSD :: Maybe UTCTime
    , lastFullSyncAtSSD :: Maybe UTCTime
    , nextSyncAtSSD :: Maybe UTCTime
    , errorCountSSD :: Int
    , lastErrorSSD :: Maybe Text
    , updatedAtSSD :: UTCTime
  }
  deriving stock (Eq, Show, Generic)


-- SQL-facing representations.

type StateSyncRowSqlDB =
  ( Int64
  , Int64
  , Text
  , Text
  , Maybe Text
  , Value
  , Text
  , Maybe UTCTime
  , Maybe UTCTime
  , Maybe UTCTime
  , Int32
  , Maybe Text
  , UTCTime
  )


type KeySyncParamsSqlDB =
  ( Int64
  , Text
  , Text
  )


type TimedSyncParamsSqlDB =
  ( Int64
  , Text
  , Text
  , UTCTime
  )


type FailedSyncParamsSqlDB =
  ( Int64
  , Text
  , Text
  , UTCTime
  , Text
  )


type CursorSyncParamsSqlDB =
  ( Int64
  , Text
  , Text
  , Maybe Text
  , Text
  , Value
  , UTCTime
  )


fetchStateSyncDB ::
  KeySyncDB -> Transaction (Maybe StateSyncDB)
fetchStateSyncDB key =
  HT.statement key fetchStateStatementSyncDB


upsertStateSyncDB ::
  KeySyncDB -> Transaction StateSyncDB
upsertStateSyncDB key =
  HT.statement key upsertStateStatementSyncDB


beginSyncDB ::
  KeySyncDB -> UTCTime -> Transaction StateSyncDB
beginSyncDB key at =
  HT.statement
    (key, at)
    beginSyncStatementSyncDB


completeSyncDB ::
  KeySyncDB -> UTCTime -> Transaction StateSyncDB
completeSyncDB key at =
  HT.statement
    (key, at)
    completeSyncStatementSyncDB


failSyncDB ::
  KeySyncDB -> UTCTime -> Text -> Transaction StateSyncDB
failSyncDB key at errorText =
  HT.statement
    (key, at, errorText)
    failSyncStatementSyncDB


scheduleSyncDB ::
  KeySyncDB -> UTCTime -> Transaction StateSyncDB
scheduleSyncDB key nextAt =
  HT.statement
    (key, nextAt)
    scheduleSyncStatementSyncDB


advanceCursorSyncDB ::
  KeySyncDB
  -> Maybe CursorPrv
  -> CursorPrv
  -> Value
  -> UTCTime
  -> Transaction Bool
advanceCursorSyncDB key expected cursor checkpoint at =
  HT.statement
    (key, expected, cursor, checkpoint, at)
    advanceCursorStatementSyncDB


completeFullSyncDB ::
  KeySyncDB
  -> Maybe CursorPrv
  -> CursorPrv
  -> Value
  -> UTCTime
  -> Transaction Bool
completeFullSyncDB key expected cursor checkpoint at =
  HT.statement
    (key, expected, cursor, checkpoint, at)
    completeFullSyncStatementSyncDB


fetchStateStatementSyncDB ::
  Statement KeySyncDB (Maybe StateSyncDB)
fetchStateStatementSyncDB =
  dimap keySyncToParamsDB (fmap stateSyncFromRowDB)
    [HTH.maybeStatement|
      SELECT
        uid :: int8,
        account_fk :: int8,
        kind :: text,
        scope_key :: text,
        cursor :: text?,
        checkpoint :: jsonb,
        status :: text,
        last_success_at :: timestamptz?,
        last_full_sync_at :: timestamptz?,
        next_sync_at :: timestamptz?,
        error_count :: int4,
        last_error :: text?,
        updated_at :: timestamptz
      FROM am.sync_state
      WHERE
        tenant_fk =
          current_setting('automail.tenant_uid')::bigint
        AND account_fk = $1 :: int8
        AND kind = $2 :: text
        AND scope_key = $3 :: text
    |]


upsertStateStatementSyncDB ::
  Statement KeySyncDB StateSyncDB
upsertStateStatementSyncDB =
  dimap keySyncToParamsDB stateSyncFromRowDB
    [HTH.singletonStatement|
      INSERT INTO am.sync_state (
        tenant_fk,
        account_fk,
        kind,
        scope_key,
        checkpoint,
        status,
        updated_at
      )
      VALUES (
        current_setting('automail.tenant_uid')::bigint,
        $1 :: int8,
        $2 :: text,
        $3 :: text,
        '{}'::jsonb,
        'ready',
        now()
      )
      ON CONFLICT (account_fk, kind, scope_key)
      DO UPDATE
      SET updated_at = am.sync_state.updated_at
      RETURNING
        uid :: int8,
        account_fk :: int8,
        kind :: text,
        scope_key :: text,
        cursor :: text?,
        checkpoint :: jsonb,
        status :: text,
        last_success_at :: timestamptz?,
        last_full_sync_at :: timestamptz?,
        next_sync_at :: timestamptz?,
        error_count :: int4,
        last_error :: text?,
        updated_at :: timestamptz
    |]


beginSyncStatementSyncDB ::
  Statement (KeySyncDB, UTCTime) StateSyncDB
beginSyncStatementSyncDB =
  dimap timedSyncToParamsDB stateSyncFromRowDB
    [HTH.singletonStatement|
      INSERT INTO am.sync_state (
        tenant_fk,
        account_fk,
        kind,
        scope_key,
        checkpoint,
        status,
        updated_at
      )
      VALUES (
        current_setting('automail.tenant_uid')::bigint,
        $1 :: int8,
        $2 :: text,
        $3 :: text,
        '{}'::jsonb,
        'syncing',
        $4 :: timestamptz
      )
      ON CONFLICT (account_fk, kind, scope_key)
      DO UPDATE
      SET
        status = 'syncing',
        updated_at = EXCLUDED.updated_at
      RETURNING
        uid :: int8,
        account_fk :: int8,
        kind :: text,
        scope_key :: text,
        cursor :: text?,
        checkpoint :: jsonb,
        status :: text,
        last_success_at :: timestamptz?,
        last_full_sync_at :: timestamptz?,
        next_sync_at :: timestamptz?,
        error_count :: int4,
        last_error :: text?,
        updated_at :: timestamptz
    |]


completeSyncStatementSyncDB ::
  Statement (KeySyncDB, UTCTime) StateSyncDB
completeSyncStatementSyncDB =
  dimap timedSyncToParamsDB stateSyncFromRowDB
    [HTH.singletonStatement|
      INSERT INTO am.sync_state (
        tenant_fk,
        account_fk,
        kind,
        scope_key,
        checkpoint,
        status,
        last_success_at,
        error_count,
        last_error,
        updated_at
      )
      VALUES (
        current_setting('automail.tenant_uid')::bigint,
        $1 :: int8,
        $2 :: text,
        $3 :: text,
        '{}'::jsonb,
        'ready',
        $4 :: timestamptz,
        0,
        NULL,
        $4 :: timestamptz
      )
      ON CONFLICT (account_fk, kind, scope_key)
      DO UPDATE
      SET
        status = 'ready',
        last_success_at = EXCLUDED.last_success_at,
        error_count = 0,
        last_error = NULL,
        updated_at = EXCLUDED.updated_at
      RETURNING
        uid :: int8,
        account_fk :: int8,
        kind :: text,
        scope_key :: text,
        cursor :: text?,
        checkpoint :: jsonb,
        status :: text,
        last_success_at :: timestamptz?,
        last_full_sync_at :: timestamptz?,
        next_sync_at :: timestamptz?,
        error_count :: int4,
        last_error :: text?,
        updated_at :: timestamptz
    |]


failSyncStatementSyncDB ::
  Statement (KeySyncDB, UTCTime, Text) StateSyncDB
failSyncStatementSyncDB =
  dimap failedSyncToParamsDB stateSyncFromRowDB
    [HTH.singletonStatement|
      INSERT INTO am.sync_state (
        tenant_fk,
        account_fk,
        kind,
        scope_key,
        checkpoint,
        status,
        error_count,
        last_error,
        updated_at
      )
      VALUES (
        current_setting('automail.tenant_uid')::bigint,
        $1 :: int8,
        $2 :: text,
        $3 :: text,
        '{}'::jsonb,
        'error',
        1,
        $5 :: text,
        $4 :: timestamptz
      )
      ON CONFLICT (account_fk, kind, scope_key)
      DO UPDATE
      SET
        status = 'error',
        error_count = am.sync_state.error_count + 1,
        last_error = EXCLUDED.last_error,
        updated_at = EXCLUDED.updated_at
      RETURNING
        uid :: int8,
        account_fk :: int8,
        kind :: text,
        scope_key :: text,
        cursor :: text?,
        checkpoint :: jsonb,
        status :: text,
        last_success_at :: timestamptz?,
        last_full_sync_at :: timestamptz?,
        next_sync_at :: timestamptz?,
        error_count :: int4,
        last_error :: text?,
        updated_at :: timestamptz
    |]


scheduleSyncStatementSyncDB ::
  Statement (KeySyncDB, UTCTime) StateSyncDB
scheduleSyncStatementSyncDB =
  dimap timedSyncToParamsDB stateSyncFromRowDB
    [HTH.singletonStatement|
      INSERT INTO am.sync_state (
        tenant_fk,
        account_fk,
        kind,
        scope_key,
        checkpoint,
        status,
        next_sync_at,
        updated_at
      )
      VALUES (
        current_setting('automail.tenant_uid')::bigint,
        $1 :: int8,
        $2 :: text,
        $3 :: text,
        '{}'::jsonb,
        'ready',
        $4 :: timestamptz,
        now()
      )
      ON CONFLICT (account_fk, kind, scope_key)
      DO UPDATE
      SET
        next_sync_at = EXCLUDED.next_sync_at,
        updated_at = now()
      RETURNING
        uid :: int8,
        account_fk :: int8,
        kind :: text,
        scope_key :: text,
        cursor :: text?,
        checkpoint :: jsonb,
        status :: text,
        last_success_at :: timestamptz?,
        last_full_sync_at :: timestamptz?,
        next_sync_at :: timestamptz?,
        error_count :: int4,
        last_error :: text?,
        updated_at :: timestamptz
    |]


advanceCursorStatementSyncDB ::
  Statement
    (KeySyncDB, Maybe CursorPrv, CursorPrv, Value, UTCTime)
    Bool
advanceCursorStatementSyncDB =
  dimap cursorSyncToParamsDB id
    [HTH.singletonStatement|
      WITH updated AS (
        UPDATE am.sync_state
        SET
          cursor = $5 :: text,
          checkpoint = $6 :: jsonb,
          status = 'ready',
          last_success_at = $7 :: timestamptz,
          error_count = 0,
          last_error = NULL,
          updated_at = $7 :: timestamptz
        WHERE
          tenant_fk =
            current_setting('automail.tenant_uid')::bigint
          AND account_fk = $1 :: int8
          AND kind = $2 :: text
          AND scope_key = $3 :: text
          AND cursor IS NOT DISTINCT FROM $4 :: text?
        RETURNING uid
      )
      SELECT
        (EXISTS (SELECT 1 FROM updated)) :: bool
    |]


completeFullSyncStatementSyncDB ::
  Statement
    (KeySyncDB, Maybe CursorPrv, CursorPrv, Value, UTCTime)
    Bool
completeFullSyncStatementSyncDB =
  dimap cursorSyncToParamsDB id
    [HTH.singletonStatement|
      WITH updated AS (
        UPDATE am.sync_state
        SET
          cursor = $5 :: text,
          checkpoint = $6 :: jsonb,
          status = 'ready',
          last_success_at = $7 :: timestamptz,
          last_full_sync_at = $7 :: timestamptz,
          error_count = 0,
          last_error = NULL,
          updated_at = $7 :: timestamptz
        WHERE
          tenant_fk =
            current_setting('automail.tenant_uid')::bigint
          AND account_fk = $1 :: int8
          AND kind = $2 :: text
          AND scope_key = $3 :: text
          AND cursor IS NOT DISTINCT FROM $4 :: text?
        RETURNING uid
      )
      SELECT
        (EXISTS (SELECT 1 FROM updated)) :: bool
    |]


keySyncToParamsDB ::
  KeySyncDB -> KeySyncParamsSqlDB
keySyncToParamsDB key =
  ( valueAccountUidDB key.accountUidKSD
  , textKindSyncDB key.kindKSD
  , key.scopeKeyKSD
  )


timedSyncToParamsDB ::
  (KeySyncDB, UTCTime) -> TimedSyncParamsSqlDB
timedSyncToParamsDB (key, at) =
  ( valueAccountUidDB key.accountUidKSD
  , textKindSyncDB key.kindKSD
  , key.scopeKeyKSD
  , at
  )


failedSyncToParamsDB ::
  (KeySyncDB, UTCTime, Text) -> FailedSyncParamsSqlDB
failedSyncToParamsDB (key, at, errorText) =
  ( valueAccountUidDB key.accountUidKSD
  , textKindSyncDB key.kindKSD
  , key.scopeKeyKSD
  , at
  , errorText
  )


cursorSyncToParamsDB ::
  (KeySyncDB, Maybe CursorPrv, CursorPrv, Value, UTCTime)
  -> CursorSyncParamsSqlDB
cursorSyncToParamsDB
  (key, expected, cursor, checkpoint, at) =
  ( valueAccountUidDB key.accountUidKSD
  , textKindSyncDB key.kindKSD
  , key.scopeKeyKSD
  , textCursorPrv <$> expected
  , textCursorPrv cursor
  , checkpoint
  , at
  )


stateSyncFromRowDB ::
  StateSyncRowSqlDB -> StateSyncDB
stateSyncFromRowDB
  ( uid
  , accountUid
  , kind
  , scopeKey
  , cursor
  , checkpoint
  , status
  , lastSuccessAt
  , lastFullSyncAt
  , nextSyncAt
  , errorCount
  , lastError
  , updatedAt
  ) =
  StateSyncDB {
      uidSSD = uid
      , keySSD =
          KeySyncDB {
              accountUidKSD = AccountUid accountUid
              , kindKSD = KindSyncDB kind
              , scopeKeyKSD = scopeKey
            }
      , cursorSSD = CursorPrv <$> cursor
      , checkpointSSD = checkpoint
      , statusSSD =
          fromMaybe ErrorSSD $
            parseStatusSyncDB status
      , lastSuccessAtSSD = lastSuccessAt
      , lastFullSyncAtSSD = lastFullSyncAt
      , nextSyncAtSSD = nextSyncAt
      , errorCountSSD = fromIntegral errorCount
      , lastErrorSSD = lastError
      , updatedAtSSD = updatedAt
    }


textStatusSyncDB ::
  StatusSyncDB -> Text
textStatusSyncDB status =
  case status of
    ReadySSD -> "ready"
    SyncingSSD -> "syncing"
    ErrorSSD -> "error"
    DisabledSSD -> "disabled"


parseStatusSyncDB ::
  Text -> Maybe StatusSyncDB
parseStatusSyncDB value =
  case value of
    "ready" -> Just ReadySSD
    "syncing" -> Just SyncingSSD
    "error" -> Just ErrorSSD
    "disabled" -> Just DisabledSSD
    _ -> Nothing


valueAccountUidDB ::
  AccountUid -> Int64
valueAccountUidDB (AccountUid value) =
  value


textKindSyncDB ::
  KindSyncDB -> Text
textKindSyncDB (KindSyncDB value) =
  value


textCursorPrv ::
  CursorPrv -> Text
textCursorPrv (CursorPrv value) =
  value
