BEGIN;

CREATE SCHEMA am;


-- ---------------------------------------------------------------------------
-- Tenant and operational context
-- ---------------------------------------------------------------------------

CREATE TABLE am.tenant (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  timezone text NOT NULL DEFAULT 'UTC',
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (status IN ('active', 'disabled', 'archived'))
);


CREATE TABLE am.space (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  code text NOT NULL,
  name text NOT NULL,
  kind text NOT NULL DEFAULT 'general',
  status text NOT NULL DEFAULT 'active',
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_fk, code),
  CHECK (status IN ('active', 'disabled', 'archived'))
);


CREATE TABLE am.principal (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  kind text NOT NULL,
  external_key text,
  name text NOT NULL,
  address text,
  status text NOT NULL DEFAULT 'active',
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_fk, kind, external_key),
  CHECK (kind IN ('human', 'service', 'system', 'model')),
  CHECK (status IN ('active', 'disabled'))
);


-- ---------------------------------------------------------------------------
-- Credentials and provider accounts
-- ---------------------------------------------------------------------------

CREATE TABLE am.credential (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  kind text NOT NULL,
  key_ref text NOT NULL,
  ciphertext bytea NOT NULL,
  nonce bytea,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  rotated_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz
);


CREATE TABLE am.account (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  default_space_fk bigint REFERENCES am.space(uid),
  credential_fk bigint REFERENCES am.credential(uid),
  kind text NOT NULL,
  address text NOT NULL,
  normalized_address text NOT NULL,
  display_name text,
  status text NOT NULL DEFAULT 'active',
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_fk, kind, normalized_address),
  CHECK (kind IN ('gmail', 'imap_smtp')),
  CHECK (status IN ('active', 'disabled', 'error', 'archived'))
);


CREATE TABLE am.space_account (
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  space_fk bigint NOT NULL REFERENCES am.space(uid),
  account_fk bigint NOT NULL REFERENCES am.account(uid),
  kind text NOT NULL DEFAULT 'member',
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (space_fk, account_fk)
);


CREATE TABLE am.account_alias (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  account_fk bigint NOT NULL REFERENCES am.account(uid),
  address text NOT NULL,
  normalized_address text NOT NULL,
  kind text NOT NULL DEFAULT 'alias',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_fk, normalized_address)
);


-- ---------------------------------------------------------------------------
-- Gmail provider configuration
-- ---------------------------------------------------------------------------

CREATE TABLE am.gmail_account (
  account_fk bigint PRIMARY KEY REFERENCES am.account(uid),
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  google_user_id text,
  profile_address text,
  auth_mode text NOT NULL DEFAULT 'oauth',
  delegated_subject text,
  history_id text,
  pubsub_topic text,
  watch_expiration timestamptz,
  watch_updated_at timestamptz,
  messages_total bigint,
  threads_total bigint,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (auth_mode IN ('oauth', 'domain_delegation'))
);


-- ---------------------------------------------------------------------------
-- IMAP / SMTP provider configuration
-- ---------------------------------------------------------------------------

CREATE TABLE am.imap_account (
  account_fk bigint PRIMARY KEY REFERENCES am.account(uid),
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  host text NOT NULL,
  port integer NOT NULL DEFAULT 993,
  tls_kind text NOT NULL DEFAULT 'implicit',
  username text NOT NULL,
  auth_kind text NOT NULL DEFAULT 'oauth2',
  inbox_name text NOT NULL DEFAULT 'INBOX',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (tls_kind IN ('implicit', 'starttls', 'none')),
  CHECK (auth_kind IN ('oauth2', 'password', 'external'))
);


CREATE TABLE am.smtp_account (
  account_fk bigint PRIMARY KEY REFERENCES am.account(uid),
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  host text NOT NULL,
  port integer NOT NULL DEFAULT 587,
  tls_kind text NOT NULL DEFAULT 'starttls',
  username text,
  auth_kind text NOT NULL DEFAULT 'oauth2',
  envelope_address text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CHECK (tls_kind IN ('implicit', 'starttls', 'none')),
  CHECK (auth_kind IN ('oauth2', 'password', 'external', 'none'))
);


-- ---------------------------------------------------------------------------
-- Provider synchronization
-- ---------------------------------------------------------------------------

CREATE TABLE am.sync_state (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  account_fk bigint NOT NULL REFERENCES am.account(uid),
  kind text NOT NULL,
  scope_key text NOT NULL DEFAULT '*',
  cursor text,
  checkpoint jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'ready',
  last_success_at timestamptz,
  last_full_sync_at timestamptz,
  next_sync_at timestamptz,
  error_count integer NOT NULL DEFAULT 0,
  last_error text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_fk, kind, scope_key),
  CHECK (status IN ('ready', 'syncing', 'error', 'disabled'))
);


CREATE TABLE am.provider_event (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  account_fk bigint NOT NULL REFERENCES am.account(uid),
  provider_event_id text,
  kind text NOT NULL,
  cursor text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz,
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  status text NOT NULL DEFAULT 'pending',
  error text,
  UNIQUE (account_fk, provider_event_id),
  CHECK (status IN ('pending', 'processing', 'processed', 'failed', 'ignored'))
);


-- ---------------------------------------------------------------------------
-- Binary repository
-- ---------------------------------------------------------------------------

CREATE TABLE am.blob (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  kind text NOT NULL,
  media_type text,
  sha256 bytea NOT NULL,
  size_bytes bigint NOT NULL,
  storage_kind text NOT NULL,
  content bytea,
  storage_ref text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_fk, sha256, size_bytes),
  CHECK (size_bytes >= 0),
  CHECK (
    (storage_kind = 'inline' AND content IS NOT NULL AND storage_ref IS NULL)
    OR
    (storage_kind = 'external' AND content IS NULL AND storage_ref IS NOT NULL)
  )
);


-- ---------------------------------------------------------------------------
-- Mailboxes / Gmail labels / IMAP folders
-- ---------------------------------------------------------------------------

CREATE TABLE am.mailbox (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  account_fk bigint NOT NULL REFERENCES am.account(uid),
  parent_fk bigint REFERENCES am.mailbox(uid),
  provider_id text,
  name text NOT NULL,
  kind text NOT NULL,
  selectable boolean NOT NULL DEFAULT true,
  attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  UNIQUE (account_fk, provider_id)
);


-- ---------------------------------------------------------------------------
-- Provider threads
-- ---------------------------------------------------------------------------

CREATE TABLE am.thread (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  account_fk bigint NOT NULL REFERENCES am.account(uid),
  provider_thread_id text NOT NULL,
  subject text,
  first_message_at timestamptz,
  last_message_at timestamptz,
  message_count integer NOT NULL DEFAULT 0,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  UNIQUE (account_fk, provider_thread_id)
);


-- ---------------------------------------------------------------------------
-- Canonical email message
-- ---------------------------------------------------------------------------

CREATE TABLE am.message (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  account_fk bigint NOT NULL REFERENCES am.account(uid),
  thread_fk bigint REFERENCES am.thread(uid),
  raw_blob_fk bigint REFERENCES am.blob(uid),
  provider_message_id text NOT NULL,
  rfc_message_id text,
  kind text NOT NULL,
  provider_internal_at timestamptz,
  sent_at timestamptz,
  received_at timestamptz,
  subject text,
  snippet text,
  size_bytes bigint,
  headers jsonb NOT NULL DEFAULT '{}'::jsonb,
  provider_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  UNIQUE (account_fk, provider_message_id),
  CHECK (kind IN ('inbound', 'outbound', 'draft', 'system'))
);


CREATE TABLE am.message_mailbox (
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  message_fk bigint NOT NULL REFERENCES am.message(uid),
  mailbox_fk bigint NOT NULL REFERENCES am.mailbox(uid),
  applied_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_fk, mailbox_fk)
);


-- ---------------------------------------------------------------------------
-- Addresses and message participants
-- ---------------------------------------------------------------------------

CREATE TABLE am.address (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  address text NOT NULL,
  normalized_address text NOT NULL,
  display_name text,
  kind text NOT NULL DEFAULT 'email',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_fk, normalized_address)
);


CREATE TABLE am.message_address (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  message_fk bigint NOT NULL REFERENCES am.message(uid),
  address_fk bigint REFERENCES am.address(uid),
  role text NOT NULL,
  ordinal integer NOT NULL DEFAULT 0,
  raw_value text,
  address text,
  display_name text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (message_fk, role, ordinal),
  CHECK (role IN ('from', 'sender', 'reply_to', 'to', 'cc', 'bcc'))
);


-- ---------------------------------------------------------------------------
-- MIME message tree
-- ---------------------------------------------------------------------------

CREATE TABLE am.message_part (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  message_fk bigint NOT NULL REFERENCES am.message(uid),
  parent_fk bigint REFERENCES am.message_part(uid),
  blob_fk bigint REFERENCES am.blob(uid),
  part_path text NOT NULL,
  provider_part_id text,
  mime_type text NOT NULL,
  charset text,
  disposition text,
  content_id text,
  filename text,
  transfer_encoding text,
  size_bytes bigint,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (message_fk, part_path)
);


CREATE TABLE am.message_content (
  message_fk bigint PRIMARY KEY REFERENCES am.message(uid),
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  plain_text text,
  html_text text,
  clean_text text,
  delta_text text,
  language text,
  normalizer text,
  normalizer_version text,
  content_hash bytea,
  search_doc tsvector GENERATED ALWAYS AS (
    to_tsvector('simple'::regconfig, coalesce(clean_text, plain_text, ''))
  ) STORED,
  updated_at timestamptz NOT NULL DEFAULT now()
);


CREATE TABLE am.attachment (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  message_fk bigint NOT NULL REFERENCES am.message(uid),
  part_fk bigint REFERENCES am.message_part(uid),
  blob_fk bigint REFERENCES am.blob(uid),
  provider_attachment_id text,
  filename text,
  mime_type text,
  size_bytes bigint,
  sha256 bytea,
  state text NOT NULL DEFAULT 'known',
  extracted_text text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (message_fk, part_fk),
  CHECK (state IN ('known', 'fetching', 'available', 'failed', 'ignored'))
);


-- ---------------------------------------------------------------------------
-- Logical conversations
-- ---------------------------------------------------------------------------

CREATE TABLE am.conversation (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  space_fk bigint REFERENCES am.space(uid),
  key text,
  kind text NOT NULL DEFAULT 'general',
  subject text,
  status text NOT NULL DEFAULT 'open',
  summary text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  opened_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_fk, key),
  CHECK (status IN ('open', 'waiting', 'closed', 'archived'))
);


CREATE TABLE am.conversation_message (
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  conversation_fk bigint NOT NULL REFERENCES am.conversation(uid),
  message_fk bigint NOT NULL REFERENCES am.message(uid),
  kind text NOT NULL DEFAULT 'member',
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_fk, message_fk)
);


-- ---------------------------------------------------------------------------
-- AI / deterministic analysis runs
-- ---------------------------------------------------------------------------

CREATE TABLE am.analysis_run (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  message_fk bigint REFERENCES am.message(uid),
  thread_fk bigint REFERENCES am.thread(uid),
  conversation_fk bigint REFERENCES am.conversation(uid),
  attachment_fk bigint REFERENCES am.attachment(uid),
  kind text NOT NULL,
  engine text NOT NULL,
  model text,
  model_version text,
  schema_key text,
  schema_version integer,
  input_hash bytea,
  input_meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  output jsonb,
  status text NOT NULL DEFAULT 'pending',
  input_tokens integer,
  output_tokens integer,
  duration_ms integer,
  error text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled'))
);


CREATE TABLE am.analysis_evidence (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  analysis_fk bigint NOT NULL REFERENCES am.analysis_run(uid),
  message_fk bigint NOT NULL REFERENCES am.message(uid),
  part_fk bigint REFERENCES am.message_part(uid),
  attachment_fk bigint REFERENCES am.attachment(uid),
  fragment text,
  char_start integer,
  char_end integer,
  content_hash bytea,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);


CREATE TABLE am.analysis_feedback (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  analysis_fk bigint NOT NULL REFERENCES am.analysis_run(uid),
  principal_fk bigint REFERENCES am.principal(uid),
  kind text NOT NULL,
  original jsonb,
  corrected jsonb,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);


-- ---------------------------------------------------------------------------
-- Knowledge representation
-- ---------------------------------------------------------------------------

CREATE TABLE am.entity (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  kind text NOT NULL,
  canonical_name text NOT NULL,
  external_key text,
  status text NOT NULL DEFAULT 'active',
  attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_fk, kind, external_key),
  CHECK (status IN ('active', 'inactive', 'merged', 'archived'))
);


CREATE TABLE am.entity_alias (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  entity_fk bigint NOT NULL REFERENCES am.entity(uid),
  alias text NOT NULL,
  kind text NOT NULL DEFAULT 'name',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (entity_fk, kind, alias)
);


CREATE TABLE am.entity_address (
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  entity_fk bigint NOT NULL REFERENCES am.entity(uid),
  address_fk bigint NOT NULL REFERENCES am.address(uid),
  kind text NOT NULL DEFAULT 'email',
  confidence double precision NOT NULL DEFAULT 1.0,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (entity_fk, address_fk),
  CHECK (confidence >= 0.0 AND confidence <= 1.0)
);


CREATE TABLE am.mention (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  message_fk bigint NOT NULL REFERENCES am.message(uid),
  part_fk bigint REFERENCES am.message_part(uid),
  entity_fk bigint REFERENCES am.entity(uid),
  analysis_fk bigint REFERENCES am.analysis_run(uid),
  kind text NOT NULL,
  value text NOT NULL,
  char_start integer,
  char_end integer,
  confidence double precision,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (confidence IS NULL OR (confidence >= 0.0 AND confidence <= 1.0))
);


CREATE TABLE am.observation (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  message_fk bigint REFERENCES am.message(uid),
  thread_fk bigint REFERENCES am.thread(uid),
  analysis_fk bigint REFERENCES am.analysis_run(uid),
  kind text NOT NULL,
  payload jsonb NOT NULL,
  confidence double precision,
  status text NOT NULL DEFAULT 'proposed',
  observed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (confidence IS NULL OR (confidence >= 0.0 AND confidence <= 1.0)),
  CHECK (status IN ('proposed', 'accepted', 'rejected', 'superseded'))
);


CREATE TABLE am.fact (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  entity_fk bigint REFERENCES am.entity(uid),
  observation_fk bigint REFERENCES am.observation(uid),
  message_fk bigint REFERENCES am.message(uid),
  supersedes_fk bigint REFERENCES am.fact(uid),
  kind text NOT NULL,
  value jsonb NOT NULL,
  value_text text,
  confidence double precision,
  status text NOT NULL DEFAULT 'active',
  valid_from timestamptz,
  valid_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (confidence IS NULL OR (confidence >= 0.0 AND confidence <= 1.0)),
  CHECK (status IN ('active', 'superseded', 'rejected', 'expired'))
);


CREATE TABLE am.relation (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  left_entity_fk bigint NOT NULL REFERENCES am.entity(uid),
  right_entity_fk bigint NOT NULL REFERENCES am.entity(uid),
  observation_fk bigint REFERENCES am.observation(uid),
  message_fk bigint REFERENCES am.message(uid),
  kind text NOT NULL,
  attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
  confidence double precision,
  status text NOT NULL DEFAULT 'active',
  valid_from timestamptz,
  valid_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (confidence IS NULL OR (confidence >= 0.0 AND confidence <= 1.0)),
  CHECK (status IN ('active', 'superseded', 'rejected', 'expired'))
);


-- ---------------------------------------------------------------------------
-- Operational objectives
-- ---------------------------------------------------------------------------

CREATE TABLE am.objective (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  space_fk bigint REFERENCES am.space(uid),
  parent_fk bigint REFERENCES am.objective(uid),
  owner_fk bigint REFERENCES am.principal(uid),
  kind text NOT NULL,
  name text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  priority integer NOT NULL DEFAULT 0,
  target jsonb NOT NULL DEFAULT '{}'::jsonb,
  context jsonb NOT NULL DEFAULT '{}'::jsonb,
  due_at timestamptz,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (status IN ('active', 'blocked', 'completed', 'cancelled', 'archived'))
);


-- ---------------------------------------------------------------------------
-- Versioned workflow definitions
-- ---------------------------------------------------------------------------

CREATE TABLE am.workflow_def (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  key text NOT NULL,
  name text NOT NULL,
  kind text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_fk, key),
  CHECK (status IN ('active', 'disabled', 'archived'))
);


CREATE TABLE am.workflow_version (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  workflow_fk bigint NOT NULL REFERENCES am.workflow_def(uid),
  created_by_fk bigint REFERENCES am.principal(uid),
  version integer NOT NULL,
  spec jsonb NOT NULL,
  spec_hash bytea NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  activated_at timestamptz,
  retired_at timestamptz,
  UNIQUE (workflow_fk, version)
);


CREATE TABLE am.workflow_instance (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  space_fk bigint REFERENCES am.space(uid),
  objective_fk bigint REFERENCES am.objective(uid),
  workflow_version_fk bigint NOT NULL REFERENCES am.workflow_version(uid),
  subject_entity_fk bigint REFERENCES am.entity(uid),
  key text,
  title text,
  state_key text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  context jsonb NOT NULL DEFAULT '{}'::jsonb,
  started_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  UNIQUE (tenant_fk, key),
  CHECK (status IN ('active', 'waiting', 'completed', 'failed', 'cancelled'))
);


CREATE TABLE am.workflow_message (
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  workflow_instance_fk bigint NOT NULL REFERENCES am.workflow_instance(uid),
  message_fk bigint NOT NULL REFERENCES am.message(uid),
  kind text NOT NULL DEFAULT 'evidence',
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (workflow_instance_fk, message_fk)
);


CREATE TABLE am.workflow_observation (
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  workflow_instance_fk bigint NOT NULL REFERENCES am.workflow_instance(uid),
  observation_fk bigint NOT NULL REFERENCES am.observation(uid),
  kind text NOT NULL DEFAULT 'input',
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (workflow_instance_fk, observation_fk)
);


CREATE TABLE am.workflow_event (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  workflow_instance_fk bigint NOT NULL REFERENCES am.workflow_instance(uid),
  source_message_fk bigint REFERENCES am.message(uid),
  observation_fk bigint REFERENCES am.observation(uid),
  principal_fk bigint REFERENCES am.principal(uid),
  sequence_no bigint NOT NULL,
  kind text NOT NULL,
  from_state text,
  to_state text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workflow_instance_fk, sequence_no)
);


-- ---------------------------------------------------------------------------
-- Versioned automation / authority policies
-- ---------------------------------------------------------------------------

CREATE TABLE am.policy_def (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  key text NOT NULL,
  name text NOT NULL,
  kind text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_fk, key),
  CHECK (status IN ('active', 'disabled', 'archived'))
);


CREATE TABLE am.policy_version (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  policy_fk bigint NOT NULL REFERENCES am.policy_def(uid),
  created_by_fk bigint REFERENCES am.principal(uid),
  version integer NOT NULL,
  spec jsonb NOT NULL,
  spec_hash bytea NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  activated_at timestamptz,
  retired_at timestamptz,
  UNIQUE (policy_fk, version)
);


-- ---------------------------------------------------------------------------
-- Proposed and executed actions
-- ---------------------------------------------------------------------------

CREATE TABLE am.action (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  space_fk bigint REFERENCES am.space(uid),
  workflow_instance_fk bigint REFERENCES am.workflow_instance(uid),
  workflow_event_fk bigint REFERENCES am.workflow_event(uid),
  source_message_fk bigint REFERENCES am.message(uid),
  proposed_analysis_fk bigint REFERENCES am.analysis_run(uid),
  proposed_by_fk bigint REFERENCES am.principal(uid),
  kind text NOT NULL,
  status text NOT NULL DEFAULT 'proposed',
  authority integer NOT NULL DEFAULT 0,
  idempotency_key text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  not_before timestamptz,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  UNIQUE (tenant_fk, idempotency_key),
  CHECK (authority BETWEEN 0 AND 6),
  CHECK (
    status IN (
      'proposed', 'approval_required', 'approved', 'executing',
      'completed', 'failed', 'rejected', 'cancelled', 'expired'
    )
  )
);


CREATE TABLE am.action_approval (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  action_fk bigint NOT NULL REFERENCES am.action(uid),
  principal_fk bigint NOT NULL REFERENCES am.principal(uid),
  decision text NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (action_fk, principal_fk),
  CHECK (decision IN ('approve', 'reject', 'cancel'))
);


CREATE TABLE am.action_attempt (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  action_fk bigint NOT NULL REFERENCES am.action(uid),
  attempt_no integer NOT NULL,
  status text NOT NULL,
  request jsonb,
  response jsonb,
  error_kind text,
  error_message text,
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  UNIQUE (action_fk, attempt_no),
  CHECK (status IN ('running', 'completed', 'failed', 'indeterminate'))
);


-- ---------------------------------------------------------------------------
-- Locally prepared / provider-backed drafts
-- ---------------------------------------------------------------------------

CREATE TABLE am.draft (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  account_fk bigint NOT NULL REFERENCES am.account(uid),
  space_fk bigint REFERENCES am.space(uid),
  workflow_instance_fk bigint REFERENCES am.workflow_instance(uid),
  in_reply_to_fk bigint REFERENCES am.message(uid),
  action_fk bigint REFERENCES am.action(uid),
  status text NOT NULL DEFAULT 'local',
  subject text,
  body_text text,
  body_html text,
  headers jsonb NOT NULL DEFAULT '{}'::jsonb,
  provider_draft_id text,
  provider_message_id text,
  revision integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  synced_at timestamptz,
  UNIQUE (account_fk, provider_draft_id),
  CHECK (status IN ('local', 'provider', 'approved', 'sent', 'discarded', 'error'))
);


CREATE TABLE am.draft_address (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  draft_fk bigint NOT NULL REFERENCES am.draft(uid),
  address_fk bigint REFERENCES am.address(uid),
  role text NOT NULL,
  ordinal integer NOT NULL DEFAULT 0,
  address text NOT NULL,
  display_name text,
  UNIQUE (draft_fk, role, ordinal),
  CHECK (role IN ('from', 'reply_to', 'to', 'cc', 'bcc'))
);


-- ---------------------------------------------------------------------------
-- Processing pipeline
-- ---------------------------------------------------------------------------

CREATE TABLE am.processing_state (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  message_fk bigint NOT NULL REFERENCES am.message(uid),
  stage text NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  version integer NOT NULL DEFAULT 1,
  attempts integer NOT NULL DEFAULT 0,
  last_error text,
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (message_fk, stage),
  CHECK (status IN ('pending', 'running', 'completed', 'failed', 'ignored'))
);


-- ---------------------------------------------------------------------------
-- Durable PostgreSQL work queue
-- ---------------------------------------------------------------------------

CREATE TABLE am.job (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  kind text NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  priority integer NOT NULL DEFAULT 0,
  dedupe_key text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  not_before timestamptz NOT NULL DEFAULT now(),
  attempt_count integer NOT NULL DEFAULT 0,
  max_attempts integer NOT NULL DEFAULT 5,
  lease_owner text,
  lease_until timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  UNIQUE (tenant_fk, dedupe_key),
  CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled'))
);


CREATE TABLE am.job_attempt (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  job_fk bigint NOT NULL REFERENCES am.job(uid),
  attempt_no integer NOT NULL,
  worker text,
  status text NOT NULL,
  error text,
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  UNIQUE (job_fk, attempt_no),
  CHECK (status IN ('running', 'completed', 'failed'))
);


-- ---------------------------------------------------------------------------
-- Immutable audit trail
-- ---------------------------------------------------------------------------

CREATE TABLE am.audit_event (
  uid bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_fk bigint NOT NULL REFERENCES am.tenant(uid),
  principal_fk bigint REFERENCES am.principal(uid),
  kind text NOT NULL,
  object_kind text,
  object_uid bigint,
  correlation_key text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);


-- ---------------------------------------------------------------------------
-- Core indexes
-- ---------------------------------------------------------------------------

CREATE INDEX am_space_tenant_idx ON am.space(tenant_fk, status);
CREATE INDEX am_account_tenant_idx ON am.account(tenant_fk, status);
CREATE INDEX am_account_address_idx ON am.account(tenant_fk, normalized_address);

CREATE INDEX am_provider_event_pending_idx
  ON am.provider_event(account_fk, received_at)
  WHERE status IN ('pending', 'failed');

CREATE INDEX am_thread_recent_idx ON am.thread(account_fk, last_message_at DESC);

CREATE INDEX am_message_account_date_idx
  ON am.message(account_fk, provider_internal_at DESC);

CREATE INDEX am_message_tenant_date_idx
  ON am.message(tenant_fk, provider_internal_at DESC);

CREATE INDEX am_message_rfc_id_idx
  ON am.message(tenant_fk, rfc_message_id)
  WHERE rfc_message_id IS NOT NULL;

CREATE INDEX am_message_subject_idx
  ON am.message USING gin(to_tsvector('simple'::regconfig, coalesce(subject, '')));

CREATE INDEX am_message_content_search_idx
  ON am.message_content USING gin(search_doc);

CREATE INDEX am_message_address_address_idx
  ON am.message_address(address_fk, message_fk);

CREATE INDEX am_attachment_message_idx
  ON am.attachment(message_fk);

CREATE INDEX am_conversation_space_idx
  ON am.conversation(space_fk, status, updated_at DESC);

CREATE INDEX am_analysis_message_idx
  ON am.analysis_run(message_fk, kind, created_at DESC);

CREATE INDEX am_analysis_status_idx
  ON am.analysis_run(tenant_fk, status, created_at);

CREATE INDEX am_entity_name_idx
  ON am.entity(tenant_fk, kind, canonical_name);

CREATE INDEX am_observation_message_idx
  ON am.observation(message_fk, kind);

CREATE INDEX am_observation_payload_idx
  ON am.observation USING gin(payload);

CREATE INDEX am_fact_entity_idx
  ON am.fact(entity_fk, kind, status);

CREATE INDEX am_fact_value_idx
  ON am.fact USING gin(value);

CREATE INDEX am_relation_left_idx
  ON am.relation(left_entity_fk, kind, status);

CREATE INDEX am_relation_right_idx
  ON am.relation(right_entity_fk, kind, status);

CREATE INDEX am_objective_active_idx
  ON am.objective(tenant_fk, status, priority DESC, due_at);

CREATE INDEX am_workflow_active_idx
  ON am.workflow_instance(tenant_fk, status, updated_at DESC);

CREATE INDEX am_workflow_objective_idx
  ON am.workflow_instance(objective_fk, status);

CREATE INDEX am_workflow_event_idx
  ON am.workflow_event(workflow_instance_fk, sequence_no);

CREATE INDEX am_action_pending_idx
  ON am.action(tenant_fk, status, not_before)
  WHERE status IN ('proposed', 'approval_required', 'approved', 'failed');

CREATE INDEX am_action_source_idx
  ON am.action(source_message_fk, kind);

CREATE INDEX am_processing_pending_idx
  ON am.processing_state(tenant_fk, status, stage)
  WHERE status IN ('pending', 'failed');

CREATE INDEX am_job_ready_idx
  ON am.job(priority DESC, not_before, uid)
  WHERE status = 'pending';

CREATE INDEX am_job_lease_idx
  ON am.job(lease_until)
  WHERE status = 'running';

CREATE INDEX am_audit_object_idx
  ON am.audit_event(tenant_fk, object_kind, object_uid, created_at DESC);

CREATE INDEX am_audit_time_idx
  ON am.audit_event(tenant_fk, created_at DESC);


-- ---------------------------------------------------------------------------
-- Row-level tenant isolation helper
-- ---------------------------------------------------------------------------

CREATE FUNCTION am.current_tenant_uid()
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
  SELECT nullif(current_setting('automail.tenant_uid', true), '')::bigint
$$;


ALTER TABLE am.tenant ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_scope ON am.tenant
  USING (uid = am.current_tenant_uid())
  WITH CHECK (uid = am.current_tenant_uid());


DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'space', 'principal', 'credential', 'account', 'space_account',
    'account_alias', 'gmail_account', 'imap_account', 'smtp_account',
    'sync_state', 'provider_event', 'blob', 'mailbox', 'thread', 'message',
    'message_mailbox', 'address', 'message_address', 'message_part',
    'message_content', 'attachment', 'conversation', 'conversation_message',
    'analysis_run', 'analysis_evidence', 'analysis_feedback', 'entity',
    'entity_alias', 'entity_address', 'mention', 'observation', 'fact',
    'relation', 'objective', 'workflow_def', 'workflow_version',
    'workflow_instance', 'workflow_message', 'workflow_observation',
    'workflow_event', 'policy_def', 'policy_version', 'action',
    'action_approval', 'action_attempt', 'draft', 'draft_address',
    'processing_state', 'job', 'job_attempt', 'audit_event'
  ]
  LOOP
    EXECUTE format('ALTER TABLE am.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format(
      'CREATE POLICY tenant_scope ON am.%I '
      || 'USING (tenant_fk = am.current_tenant_uid()) '
      || 'WITH CHECK (tenant_fk = am.current_tenant_uid())',
      table_name
    );
  END LOOP;
END
$$;


COMMIT;