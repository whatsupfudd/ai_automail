{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE QuasiQuotes #-}

module AutoMail.DB.ProviderEvent (
    StatusEventPrvDB(..)
    , CreateEventPrvDB(..)
    , EventPrvDB(..)
    , ResultInsertEventPrvDB(..)
    , insertEventPrvDB
    , fetchEventPrvDB
    , listPendingEventsPrvDB
    , listStalePendingEventsPrvDB
    , markProcessingEventPrvDB
    , markProcessedEventPrvDB
    , failEventPrvDB
    , ignoreEventPrvDB
    , statusTextEventPrvDB
    , parseStatusEventPrvDB
  ) where

import Data.Aeson (Value)
import Data.Int (Int32, Int64)
import Data.Maybe (fromMaybe, isJust)
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


data StatusEventPrvDB =
    PendingSEPD
  | ProcessingSEPD
  | ProcessedSEPD
  | FailedSEPD
  | IgnoredSEPD
  deriving stock (Eq, Show, Generic)


data CreateEventPrvDB = CreateEventPrvDB {
    accountUidCEPD :: AccountUid
    , eventIdPrvCEPD :: Maybe EventIdPrv
    , kindCEPD :: Text
    , cursorPrvCEPD :: Maybe CursorPrv
    , payloadCEPD :: Value
    , occurredAtCEPD :: Maybe UTCTime
    , receivedAtCEPD :: UTCTime
  }
  deriving stock (Eq, Show, Generic)


data EventPrvDB = EventPrvDB {
    uidEPD :: Int64
    , tenantUidEPD :: TenantUid
    , accountUidEPD :: AccountUid
    , eventIdPrvEPD :: Maybe EventIdPrv
    , kindEPD :: Text
    , cursorPrvEPD :: Maybe CursorPrv
    , payloadEPD :: Value
    , occurredAtEPD :: Maybe UTCTime
    , receivedAtEPD :: UTCTime
    , processedAtEPD :: Maybe UTCTime
    , statusEPD :: StatusEventPrvDB
    , errorEPD :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)


data ResultInsertEventPrvDB =
    InsertedRIEPD EventPrvDB
  | ExistingRIEPD EventPrvDB
  deriving stock (Eq, Show, Generic)


-- SQL-facing representations. The embedded statements deal exclusively
-- with values directly understood by Hasql.

type EventRowSqlDB =
  ( Int64
  , Int64
  , Int64
  , Maybe Text
  , Text
  , Maybe Text
  , Value
  , Maybe UTCTime
  , UTCTime
  , Maybe UTCTime
  , Text
  , Maybe Text
  )


type InsertEventRowSqlDB =
  ( Bool
  , Int64
  , Int64
  , Int64
  , Maybe Text
  , Text
  , Maybe Text
  , Value
  , Maybe UTCTime
  , UTCTime
  , Maybe UTCTime
  , Text
  , Maybe Text
  )


type CreateEventParamsSqlDB =
  ( Int64
  , Maybe Text
  , Text
  , Maybe Text
  , Value
  , Maybe UTCTime
  , UTCTime
  )


insertEventPrvDB ::
  CreateEventPrvDB -> Transaction ResultInsertEventPrvDB
insertEventPrvDB create =
  HT.statement create insertStatementEventPrvDB


fetchEventPrvDB ::
  Int64 -> Transaction (Maybe EventPrvDB)
fetchEventPrvDB uid =
  HT.statement uid fetchStatementEventPrvDB


listPendingEventsPrvDB ::
  AccountUid -> Int -> Transaction (Vector EventPrvDB)
listPendingEventsPrvDB accountUid limit =
  HT.statement
    (accountUid, limit)
    listPendingStatementEventPrvDB


listStalePendingEventsPrvDB ::
  UTCTime -> Int -> Transaction (Vector EventPrvDB)
listStalePendingEventsPrvDB before limit =
  HT.statement
    (before, limit)
    listStalePendingStatementEventPrvDB


markProcessingEventPrvDB ::
  Int64 -> Transaction Bool
markProcessingEventPrvDB uid =
  HT.statement uid markProcessingStatementEventPrvDB


markProcessedEventPrvDB ::
  Int64 -> UTCTime -> Transaction Bool
markProcessedEventPrvDB uid processedAt =
  HT.statement
    (uid, processedAt)
    markProcessedStatementEventPrvDB


failEventPrvDB ::
  Int64 -> Text -> Transaction Bool
failEventPrvDB uid message =
  HT.statement
    (uid, message)
    failStatementEventPrvDB


ignoreEventPrvDB ::
  Int64 -> UTCTime -> Text -> Transaction Bool
ignoreEventPrvDB uid processedAt reason =
  HT.statement
    (uid, processedAt, reason)
    ignoreStatementEventPrvDB


insertStatementEventPrvDB ::
  Statement CreateEventPrvDB ResultInsertEventPrvDB
insertStatementEventPrvDB =
  dimap createEventToParamsDB insertEventFromRowDB
    [HTH.singletonStatement|
      INSERT INTO am.provider_event (
        tenant_fk,
        account_fk,
        provider_event_id,
        kind,
        cursor,
        payload,
        occurred_at,
        received_at
      )
      VALUES (
        am.current_tenant_uid(),
        $1 :: int8,
        $2 :: text?,
        $3 :: text,
        $4 :: text?,
        $5 :: jsonb,
        $6 :: timestamptz?,
        $7 :: timestamptz
      )
      ON CONFLICT (account_fk, provider_event_id)
      DO UPDATE
      SET provider_event_id = EXCLUDED.provider_event_id
      RETURNING
        (xmax = '0') :: bool,
        uid :: int8,
        tenant_fk :: int8,
        account_fk :: int8,
        provider_event_id :: text?,
        kind :: text,
        cursor :: text?,
        payload :: jsonb,
        occurred_at :: timestamptz?,
        received_at :: timestamptz,
        processed_at :: timestamptz?,
        status :: text,
        error :: text?
    |]


fetchStatementEventPrvDB ::
  Statement Int64 (Maybe EventPrvDB)
fetchStatementEventPrvDB =
  dimap id (fmap eventFromRowDB)
    [HTH.maybeStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        account_fk :: int8,
        provider_event_id :: text?,
        kind :: text,
        cursor :: text?,
        payload :: jsonb,
        occurred_at :: timestamptz?,
        received_at :: timestamptz,
        processed_at :: timestamptz?,
        status :: text,
        error :: text?
      FROM am.provider_event
      WHERE uid = $1 :: int8
    |]


listPendingStatementEventPrvDB ::
  Statement
    (AccountUid, Int)
    (Vector EventPrvDB)
listPendingStatementEventPrvDB =
  dimap pendingEventsToParamsDB (fmap eventFromRowDB)
    [HTH.vectorStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        account_fk :: int8,
        provider_event_id :: text?,
        kind :: text,
        cursor :: text?,
        payload :: jsonb,
        occurred_at :: timestamptz?,
        received_at :: timestamptz,
        processed_at :: timestamptz?,
        status :: text,
        error :: text?
      FROM am.provider_event
      WHERE
        account_fk = $1 :: int8
        AND status = 'pending'
      ORDER BY received_at, uid
      LIMIT $2 :: int4
    |]


listStalePendingStatementEventPrvDB ::
  Statement
    (UTCTime, Int)
    (Vector EventPrvDB)
listStalePendingStatementEventPrvDB =
  dimap staleEventsToParamsDB (fmap eventFromRowDB)
    [HTH.vectorStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        account_fk :: int8,
        provider_event_id :: text?,
        kind :: text,
        cursor :: text?,
        payload :: jsonb,
        occurred_at :: timestamptz?,
        received_at :: timestamptz,
        processed_at :: timestamptz?,
        status :: text,
        error :: text?
      FROM am.provider_event
      WHERE
        status = 'pending'
        AND received_at <= $1 :: timestamptz
      ORDER BY received_at, uid
      LIMIT $2 :: int4
    |]


markProcessingStatementEventPrvDB ::
  Statement Int64 Bool
markProcessingStatementEventPrvDB =
  dimap id isJust
    [HTH.maybeStatement|
      UPDATE am.provider_event
      SET
        status = 'processing',
        error = NULL
      WHERE
        uid = $1 :: int8
        AND status IN ('pending', 'failed')
      RETURNING true :: bool
    |]


markProcessedStatementEventPrvDB ::
  Statement (Int64, UTCTime) Bool
markProcessedStatementEventPrvDB =
  dimap id isJust
    [HTH.maybeStatement|
      UPDATE am.provider_event
      SET
        status = 'processed',
        processed_at = $2 :: timestamptz,
        error = NULL
      WHERE
        uid = $1 :: int8
        AND status IN (
          'pending',
          'processing',
          'failed'
        )
      RETURNING true :: bool
    |]


failStatementEventPrvDB ::
  Statement (Int64, Text) Bool
failStatementEventPrvDB =
  dimap id isJust
    [HTH.maybeStatement|
      UPDATE am.provider_event
      SET
        status = 'failed',
        error = $2 :: text
      WHERE
        uid = $1 :: int8
        AND status IN (
          'pending',
          'processing',
          'failed'
        )
      RETURNING true :: bool
    |]


ignoreStatementEventPrvDB ::
  Statement (Int64, UTCTime, Text) Bool
ignoreStatementEventPrvDB =
  dimap id isJust
    [HTH.maybeStatement|
      UPDATE am.provider_event
      SET
        status = 'ignored',
        processed_at = $2 :: timestamptz,
        error = $3 :: text
      WHERE
        uid = $1 :: int8
        AND status IN (
          'pending',
          'processing',
          'failed'
        )
      RETURNING true :: bool
    |]


createEventToParamsDB ::
  CreateEventPrvDB -> CreateEventParamsSqlDB
createEventToParamsDB create =
  ( int64AccountUidDB create.accountUidCEPD
  , textEventIdPrvDB <$> create.eventIdPrvCEPD
  , create.kindCEPD
  , textCursorPrvDB <$> create.cursorPrvCEPD
  , create.payloadCEPD
  , create.occurredAtCEPD
  , create.receivedAtCEPD
  )


pendingEventsToParamsDB ::
  (AccountUid, Int) -> (Int64, Int32)
pendingEventsToParamsDB (accountUid, limit) =
  ( int64AccountUidDB accountUid
  , int32LimitEventPrvDB limit
  )


staleEventsToParamsDB ::
  (UTCTime, Int) -> (UTCTime, Int32)
staleEventsToParamsDB (before, limit) =
  (before, int32LimitEventPrvDB limit)


insertEventFromRowDB ::
  InsertEventRowSqlDB -> ResultInsertEventPrvDB
insertEventFromRowDB
  ( inserted
  , uid
  , tenantUid
  , accountUid
  , eventIdPrv
  , kind
  , cursorPrv
  , payload
  , occurredAt
  , receivedAt
  , processedAt
  , status
  , eventError
  ) =
  let
    event =
      eventFromRowDB
        ( uid
        , tenantUid
        , accountUid
        , eventIdPrv
        , kind
        , cursorPrv
        , payload
        , occurredAt
        , receivedAt
        , processedAt
        , status
        , eventError
        )
  in
    if inserted
      then InsertedRIEPD event
      else ExistingRIEPD event


eventFromRowDB ::
  EventRowSqlDB -> EventPrvDB
eventFromRowDB
  ( uid
  , tenantUid
  , accountUid
  , eventIdPrv
  , kind
  , cursorPrv
  , payload
  , occurredAt
  , receivedAt
  , processedAt
  , status
  , eventError
  ) =
  EventPrvDB {
      uidEPD = uid
      , tenantUidEPD = TenantUid tenantUid
      , accountUidEPD = AccountUid accountUid
      , eventIdPrvEPD = EventIdPrv <$> eventIdPrv
      , kindEPD = kind
      , cursorPrvEPD = CursorPrv <$> cursorPrv
      , payloadEPD = payload
      , occurredAtEPD = occurredAt
      , receivedAtEPD = receivedAt
      , processedAtEPD = processedAt
      , statusEPD = statusEventPrvDB status
      , errorEPD = eventError
    }


statusTextEventPrvDB ::
  StatusEventPrvDB -> Text
statusTextEventPrvDB status =
  case status of
    PendingSEPD -> "pending"
    ProcessingSEPD -> "processing"
    ProcessedSEPD -> "processed"
    FailedSEPD -> "failed"
    IgnoredSEPD -> "ignored"


parseStatusEventPrvDB ::
  Text -> Maybe StatusEventPrvDB
parseStatusEventPrvDB value =
  case value of
    "pending" -> Just PendingSEPD
    "processing" -> Just ProcessingSEPD
    "processed" -> Just ProcessedSEPD
    "failed" -> Just FailedSEPD
    "ignored" -> Just IgnoredSEPD
    _ -> Nothing


statusEventPrvDB ::
  Text -> StatusEventPrvDB
statusEventPrvDB value =
  fromMaybe
    (error $ "Unknown provider event status: " <> Tx.unpack value)
    (parseStatusEventPrvDB value)


int64AccountUidDB ::
  AccountUid -> Int64
int64AccountUidDB (AccountUid value) =
  value


textEventIdPrvDB ::
  EventIdPrv -> Text
textEventIdPrvDB (EventIdPrv value) =
  value


textCursorPrvDB ::
  CursorPrv -> Text
textCursorPrvDB (CursorPrv value) =
  value


int32LimitEventPrvDB ::
  Int -> Int32
int32LimitEventPrvDB limit =
  fromIntegral $ max 0 limit
