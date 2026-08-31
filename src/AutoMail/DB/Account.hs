{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE QuasiQuotes #-}

module AutoMail.DB.Account (
    StatusAccount(..)
    , AccountDB(..)
    , CreateAccountDB(..)
    , UpdateAccountDB(..)
    , emptyUpdateAccountDB
    , AliasAccountDB(..)
    , CreateAliasAccountDB(..)
    , MembershipAccountDB(..)
    , AccountRefDB(..)
    , insertAccountDB
    , fetchAccountDB
    , fetchAccountAddressDB
    , listAccountsDB
    , listActiveAccountsDB
    , updateAccountDB
    , setStatusAccountDB
    , insertAliasAccountDB
    , listAliasesAccountDB
    , attachSpaceAccountDB
    , detachSpaceAccountDB
    , listSpacesAccountDB
    , listActiveAccountRefsDB
    , renderStatusAccountDB
    , parseStatusAccountDB
    , renderKindPrvDB
    , parseKindPrvDB
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
import AutoMail.Provider.Types


data StatusAccount =
    ActiveSA
  | DisabledSA
  | ErrorSA
  | ArchivedSA
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data AccountDB = AccountDB {
    uidAD :: AccountUid
    , tenantUidAD :: TenantUid
    , defaultSpaceUidAD :: Maybe SpaceUid
    , credentialUidAD :: Maybe CredentialUid
    , kindAD :: KindPrv
    , addressAD :: Text
    , normalizedAddressAD :: Text
    , displayNameAD :: Maybe Text
    , statusAD :: StatusAccount
    , configAD :: Value
    , createdAtAD :: UTCTime
    , updatedAtAD :: UTCTime
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data CreateAccountDB = CreateAccountDB {
    defaultSpaceUidCAD :: Maybe SpaceUid
    , credentialUidCAD :: Maybe CredentialUid
    , kindCAD :: KindPrv
    , addressCAD :: Text
    , normalizedAddressCAD :: Text
    , displayNameCAD :: Maybe Text
    , statusCAD :: StatusAccount
    , configCAD :: Value
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data UpdateAccountDB = UpdateAccountDB {
    defaultSpaceUidUAD :: Maybe (Maybe SpaceUid)
    , credentialUidUAD :: Maybe (Maybe CredentialUid)
    , kindUAD :: Maybe KindPrv
    , addressUAD :: Maybe Text
    , normalizedAddressUAD :: Maybe Text
    , displayNameUAD :: Maybe (Maybe Text)
    , statusUAD :: Maybe StatusAccount
    , configUAD :: Maybe Value
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


emptyUpdateAccountDB :: UpdateAccountDB
emptyUpdateAccountDB =
  UpdateAccountDB {
      defaultSpaceUidUAD = Nothing
      , credentialUidUAD = Nothing
      , kindUAD = Nothing
      , addressUAD = Nothing
      , normalizedAddressUAD = Nothing
      , displayNameUAD = Nothing
      , statusUAD = Nothing
      , configUAD = Nothing
    }


data AliasAccountDB = AliasAccountDB {
    uidAAD :: Int64
    , accountUidAAD :: AccountUid
    , addressAAD :: Text
    , normalizedAddressAAD :: Text
    , kindAAD :: Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data CreateAliasAccountDB = CreateAliasAccountDB {
    addressCAAD :: Text
    , normalizedAddressCAAD :: Text
    , kindCAAD :: Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data MembershipAccountDB = MembershipAccountDB {
    accountUidMAD :: AccountUid
    , spaceUidMAD :: SpaceUid
    , kindMAD :: Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


data AccountRefDB = AccountRefDB {
    tenantUidARD :: TenantUid
    , accountUidARD :: AccountUid
    , kindARD :: KindPrv
    , updatedAtARD :: UTCTime
    , credentialUpdatedAtARD :: Maybe UTCTime
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)


-- SQL-facing representations. These deliberately contain only primitive
-- values understood directly by hasql-th.

type AccountRowSqlDB =
  ( Int64, Int64, Maybe Int64, Maybe Int64, Text, Text, Text
  , Maybe Text, Text, Value, UTCTime, UTCTime
  )


type CreateAccountParamsSqlDB =
  ( Maybe Int64, Maybe Int64, Text, Text, Text, Maybe Text, Text, Value )


type UpdateAccountParamsSqlDB =
  ( Int64, Bool, Maybe Int64, Bool, Maybe Int64, Maybe Text, Maybe Text
  , Maybe Text, Bool, Maybe Text, Maybe Text, Maybe Value
  )


type AliasAccountRowSqlDB =
  (Int64, Int64, Text, Text, Text)


type MembershipAccountRowSqlDB =
  (Int64, Int64, Text)


type AccountRefRowSqlDB =
  (Int64, Int64, Text, UTCTime, Maybe UTCTime)


insertAccountDB :: CreateAccountDB -> Transaction AccountDB
insertAccountDB create =
  HT.statement create insertAccountStatementDB


fetchAccountDB :: AccountUid -> Transaction (Maybe AccountDB)
fetchAccountDB uid =
  HT.statement uid fetchAccountStatementDB


fetchAccountAddressDB :: Text -> Transaction (Maybe AccountDB)
fetchAccountAddressDB normalizedAddress =
  HT.statement normalizedAddress fetchAccountAddressStatementDB


listAccountsDB :: Transaction (Vector AccountDB)
listAccountsDB =
  HT.statement () listAccountsStatementDB


listActiveAccountsDB :: Transaction (Vector AccountDB)
listActiveAccountsDB =
  HT.statement () listActiveAccountsStatementDB


updateAccountDB ::
  AccountUid -> UpdateAccountDB -> Transaction (Maybe AccountDB)
updateAccountDB uid update =
  HT.statement (uid, update) updateAccountStatementDB


setStatusAccountDB ::
  AccountUid -> StatusAccount -> Transaction (Maybe AccountDB)
setStatusAccountDB uid status =
  HT.statement (uid, status) setStatusAccountStatementDB


insertAliasAccountDB ::
  AccountUid -> CreateAliasAccountDB -> Transaction AliasAccountDB
insertAliasAccountDB accountUid create =
  HT.statement (accountUid, create) insertAliasAccountStatementDB


listAliasesAccountDB ::
  AccountUid -> Transaction (Vector AliasAccountDB)
listAliasesAccountDB accountUid =
  HT.statement accountUid listAliasesAccountStatementDB


attachSpaceAccountDB ::
  AccountUid -> SpaceUid -> Text -> Transaction ()
attachSpaceAccountDB accountUid spaceUid kind =
  HT.statement
    (accountUid, spaceUid, kind)
    attachSpaceAccountStatementDB


detachSpaceAccountDB ::
  AccountUid -> SpaceUid -> Transaction ()
detachSpaceAccountDB accountUid spaceUid =
  HT.statement
    (accountUid, spaceUid)
    detachSpaceAccountStatementDB


listSpacesAccountDB ::
  AccountUid -> Transaction (Vector MembershipAccountDB)
listSpacesAccountDB accountUid =
  HT.statement accountUid listSpacesAccountStatementDB


listActiveAccountRefsDB :: Transaction (Vector AccountRefDB)
listActiveAccountRefsDB =
  HT.statement () listActiveAccountRefsStatementDB


insertAccountStatementDB :: Statement CreateAccountDB AccountDB
insertAccountStatementDB =
  dimap createAccountToParamsDB accountFromRowDB
    [HTH.singletonStatement|
      INSERT INTO am.account (
        tenant_fk,
        default_space_fk,
        credential_fk,
        kind,
        address,
        normalized_address,
        display_name,
        status,
        config
      )
      VALUES (
        am.current_tenant_uid(),
        $1 :: int8?,
        $2 :: int8?,
        $3 :: text,
        $4 :: text,
        $5 :: text,
        $6 :: text?,
        $7 :: text,
        $8 :: jsonb
      )
      RETURNING
        uid :: int8,
        tenant_fk :: int8,
        default_space_fk :: int8?,
        credential_fk :: int8?,
        kind :: text,
        address :: text,
        normalized_address :: text,
        display_name :: text?,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
    |]


fetchAccountStatementDB ::
  Statement AccountUid (Maybe AccountDB)
fetchAccountStatementDB =
  dimap valueAccountUidDB (fmap accountFromRowDB)
    [HTH.maybeStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        default_space_fk :: int8?,
        credential_fk :: int8?,
        kind :: text,
        address :: text,
        normalized_address :: text,
        display_name :: text?,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
      FROM am.account
      WHERE uid = $1 :: int8
    |]


fetchAccountAddressStatementDB ::
  Statement Text (Maybe AccountDB)
fetchAccountAddressStatementDB =
  dimap id (fmap accountFromRowDB)
    [HTH.maybeStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        default_space_fk :: int8?,
        credential_fk :: int8?,
        kind :: text,
        address :: text,
        normalized_address :: text,
        display_name :: text?,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
      FROM am.account
      WHERE normalized_address = $1 :: text
      ORDER BY uid
      LIMIT 1
    |]


listAccountsStatementDB ::
  Statement () (Vector AccountDB)
listAccountsStatementDB =
  dimap id (fmap accountFromRowDB)
    [HTH.vectorStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        default_space_fk :: int8?,
        credential_fk :: int8?,
        kind :: text,
        address :: text,
        normalized_address :: text,
        display_name :: text?,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
      FROM am.account
      ORDER BY normalized_address, uid
    |]


listActiveAccountsStatementDB ::
  Statement () (Vector AccountDB)
listActiveAccountsStatementDB =
  dimap id (fmap accountFromRowDB)
    [HTH.vectorStatement|
      SELECT
        uid :: int8,
        tenant_fk :: int8,
        default_space_fk :: int8?,
        credential_fk :: int8?,
        kind :: text,
        address :: text,
        normalized_address :: text,
        display_name :: text?,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
      FROM am.account
      WHERE status = 'active'
      ORDER BY normalized_address, uid
    |]


updateAccountStatementDB ::
  Statement (AccountUid, UpdateAccountDB) (Maybe AccountDB)
updateAccountStatementDB =
  dimap updateAccountToParamsDB (fmap accountFromRowDB)
    [HTH.maybeStatement|
      UPDATE am.account
      SET
        default_space_fk = CASE
          WHEN $2 :: bool THEN $3 :: int8?
          ELSE default_space_fk
        END,
        credential_fk = CASE
          WHEN $4 :: bool THEN $5 :: int8?
          ELSE credential_fk
        END,
        kind = coalesce($6 :: text?, kind),
        address = coalesce($7 :: text?, address),
        normalized_address =
          coalesce($8 :: text?, normalized_address),
        display_name = CASE
          WHEN $9 :: bool THEN $10 :: text?
          ELSE display_name
        END,
        status = coalesce($11 :: text?, status),
        config = coalesce($12 :: jsonb?, config),
        updated_at = now()
      WHERE uid = $1 :: int8
      RETURNING
        uid :: int8,
        tenant_fk :: int8,
        default_space_fk :: int8?,
        credential_fk :: int8?,
        kind :: text,
        address :: text,
        normalized_address :: text,
        display_name :: text?,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
    |]


setStatusAccountStatementDB ::
  Statement (AccountUid, StatusAccount) (Maybe AccountDB)
setStatusAccountStatementDB =
  dimap toParams (fmap accountFromRowDB)
    [HTH.maybeStatement|
      UPDATE am.account
      SET
        status = $2 :: text,
        updated_at = now()
      WHERE uid = $1 :: int8
      RETURNING
        uid :: int8,
        tenant_fk :: int8,
        default_space_fk :: int8?,
        credential_fk :: int8?,
        kind :: text,
        address :: text,
        normalized_address :: text,
        display_name :: text?,
        status :: text,
        config :: jsonb,
        created_at :: timestamptz,
        updated_at :: timestamptz
    |]
  where
  toParams (uid, status) =
    (valueAccountUidDB uid, renderStatusAccountDB status)


insertAliasAccountStatementDB :: Statement (AccountUid, CreateAliasAccountDB) AliasAccountDB
insertAliasAccountStatementDB =
  dimap toParams aliasAccountFromRowDB
    [HTH.singletonStatement|
      INSERT INTO am.account_alias (
        tenant_fk,
        account_fk,
        address,
        normalized_address,
        kind
      )
      VALUES (
        am.current_tenant_uid(),
        $1 :: int8,
        $2 :: text,
        $3 :: text,
        $4 :: text
      )
      ON CONFLICT (account_fk, normalized_address)
      DO UPDATE
      SET
        address = EXCLUDED.address,
        kind = EXCLUDED.kind
      RETURNING
        uid :: int8,
        account_fk :: int8,
        address :: text,
        normalized_address :: text,
        kind :: text
    |]
  where
  toParams :: (AccountUid, CreateAliasAccountDB) -> (Int64, Text, Text, Text)
  toParams (accountUid, create) =
    ( valueAccountUidDB accountUid
    , create.addressCAAD
    , create.normalizedAddressCAAD
    , create.kindCAAD
    )


listAliasesAccountStatementDB ::
  Statement AccountUid (Vector AliasAccountDB)
listAliasesAccountStatementDB =
  dimap valueAccountUidDB (fmap aliasAccountFromRowDB)
    [HTH.vectorStatement|
      SELECT
        uid :: int8,
        account_fk :: int8,
        address :: text,
        normalized_address :: text,
        kind :: text
      FROM am.account_alias
      WHERE account_fk = $1 :: int8
      ORDER BY normalized_address, uid
    |]


attachSpaceAccountStatementDB ::
  Statement (AccountUid, SpaceUid, Text) ()
attachSpaceAccountStatementDB =
  dimap toParams id
    [HTH.resultlessStatement|
      INSERT INTO am.space_account (
        tenant_fk,
        space_fk,
        account_fk,
        kind
      )
      VALUES (
        am.current_tenant_uid(),
        $2 :: int8,
        $1 :: int8,
        $3 :: text
      )
      ON CONFLICT (space_fk, account_fk)
      DO UPDATE
      SET kind = EXCLUDED.kind
    |]
  where
  toParams (accountUid, spaceUid, kind) =
    ( valueAccountUidDB accountUid
    , valueSpaceUidDB spaceUid
    , kind
    )


detachSpaceAccountStatementDB ::
  Statement (AccountUid, SpaceUid) ()
detachSpaceAccountStatementDB =
  dimap toParams id
    [HTH.resultlessStatement|
      DELETE FROM am.space_account
      WHERE
        account_fk = $1 :: int8
        AND space_fk = $2 :: int8
    |]
  where
  toParams (accountUid, spaceUid) =
    (valueAccountUidDB accountUid, valueSpaceUidDB spaceUid)


listSpacesAccountStatementDB ::
  Statement AccountUid (Vector MembershipAccountDB)
listSpacesAccountStatementDB =
  dimap valueAccountUidDB (fmap membershipAccountFromRowDB)
    [HTH.vectorStatement|
      SELECT
        account_fk :: int8,
        space_fk :: int8,
        kind :: text
      FROM am.space_account
      WHERE account_fk = $1 :: int8
      ORDER BY space_fk
    |]


listActiveAccountRefsStatementDB ::
  Statement () (Vector AccountRefDB)
listActiveAccountRefsStatementDB =
  dimap id (fmap accountRefFromRowDB)
    [HTH.vectorStatement|
      SELECT
        a.tenant_fk :: int8,
        a.uid :: int8,
        a.kind :: text,
        a.updated_at :: timestamptz,
        (
          CASE
            WHEN c.uid IS NULL THEN NULL
            ELSE greatest(
              c.created_at,
              coalesce(c.rotated_at, c.created_at),
              coalesce(c.revoked_at, c.created_at)
            )
          END
        ) :: timestamptz?
      FROM am.account a
      LEFT JOIN am.credential c
        ON
          c.tenant_fk = a.tenant_fk
          AND c.uid = a.credential_fk
      WHERE a.status = 'active'
      ORDER BY a.tenant_fk, a.uid
    |]


createAccountToParamsDB ::
  CreateAccountDB -> CreateAccountParamsSqlDB
createAccountToParamsDB create =
  ( fmap valueSpaceUidDB create.defaultSpaceUidCAD
  , fmap valueCredentialUidDB create.credentialUidCAD
  , renderKindPrvDB create.kindCAD
  , create.addressCAD
  , create.normalizedAddressCAD
  , create.displayNameCAD
  , renderStatusAccountDB create.statusCAD
  , create.configCAD
  )


updateAccountToParamsDB ::
  (AccountUid, UpdateAccountDB) -> UpdateAccountParamsSqlDB
updateAccountToParamsDB (uid, update) =
  ( valueAccountUidDB uid
  , isJust update.defaultSpaceUidUAD
  , fmap valueSpaceUidDB $ join update.defaultSpaceUidUAD
  , isJust update.credentialUidUAD
  , fmap valueCredentialUidDB $ join update.credentialUidUAD
  , renderKindPrvDB <$> update.kindUAD
  , update.addressUAD
  , update.normalizedAddressUAD
  , isJust update.displayNameUAD
  , join update.displayNameUAD
  , renderStatusAccountDB <$> update.statusUAD
  , update.configUAD
  )


accountFromRowDB :: AccountRowSqlDB -> AccountDB
accountFromRowDB
  ( uid
  , tenantUid
  , defaultSpaceUid
  , credentialUid
  , kind
  , address
  , normalizedAddress
  , displayName
  , status
  , config
  , createdAt
  , updatedAt
  ) =
  AccountDB {
      uidAD = AccountUid uid
      , tenantUidAD = TenantUid tenantUid
      , defaultSpaceUidAD = SpaceUid <$> defaultSpaceUid
      , credentialUidAD = CredentialUid <$> credentialUid
      , kindAD = parseKindPrvDB kind
      , addressAD = address
      , normalizedAddressAD = normalizedAddress
      , displayNameAD = displayName
      , statusAD = parseStatusAccountDB status
      , configAD = config
      , createdAtAD = createdAt
      , updatedAtAD = updatedAt
    }


aliasAccountFromRowDB ::
  AliasAccountRowSqlDB -> AliasAccountDB
aliasAccountFromRowDB
  (uid, accountUid, address, normalizedAddress, kind) =
  AliasAccountDB {
      uidAAD = uid
      , accountUidAAD = AccountUid accountUid
      , addressAAD = address
      , normalizedAddressAAD = normalizedAddress
      , kindAAD = kind
    }


membershipAccountFromRowDB ::
  MembershipAccountRowSqlDB -> MembershipAccountDB
membershipAccountFromRowDB
  (accountUid, spaceUid, kind) =
  MembershipAccountDB {
      accountUidMAD = AccountUid accountUid
      , spaceUidMAD = SpaceUid spaceUid
      , kindMAD = kind
    }


accountRefFromRowDB ::
  AccountRefRowSqlDB -> AccountRefDB
accountRefFromRowDB
  (tenantUid, accountUid, kind, updatedAt, credentialUpdatedAt) =
  AccountRefDB {
      tenantUidARD = TenantUid tenantUid
      , accountUidARD = AccountUid accountUid
      , kindARD = parseKindPrvDB kind
      , updatedAtARD = updatedAt
      , credentialUpdatedAtARD = credentialUpdatedAt
    }


valueAccountUidDB :: AccountUid -> Int64
valueAccountUidDB (AccountUid value) =
  value


valueSpaceUidDB :: SpaceUid -> Int64
valueSpaceUidDB (SpaceUid value) =
  value


valueCredentialUidDB :: CredentialUid -> Int64
valueCredentialUidDB (CredentialUid value) =
  value


renderStatusAccountDB :: StatusAccount -> Text
renderStatusAccountDB status =
  case status of
    ActiveSA -> "active"
    DisabledSA -> "disabled"
    ErrorSA -> "error"
    ArchivedSA -> "archived"


parseStatusAccountDB :: Text -> StatusAccount
parseStatusAccountDB value =
  case value of
    "active" -> ActiveSA
    "disabled" -> DisabledSA
    "error" -> ErrorSA
    "archived" -> ArchivedSA
    _ ->
      error $
        "Unknown am.account.status: " <> Tx.unpack value


renderKindPrvDB :: KindPrv -> Text
renderKindPrvDB kind =
  case kind of
    GmailKP -> "gmail"
    ImapSmtpKP -> "imap_smtp"
    JmapKP -> "jmap"


parseKindPrvDB :: Text -> KindPrv
parseKindPrvDB value =
  case value of
    "gmail" -> GmailKP
    "imap_smtp" -> ImapSmtpKP
    "jmap" -> JmapKP
    _ ->
      error $
        "Unknown am.account.kind: " <> Tx.unpack value