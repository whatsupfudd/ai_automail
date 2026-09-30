# Automail

**AI-native email ingestion, knowledge extraction, workflow orchestration, and
controlled action execution for the FUDD ecosystem.**

Automail is the email automation service in FUDD's AI project.

It is designed to turn email from a passive messaging channel into a
structured, durable, AI-assisted operating environment.

Rather than treating an inbox as a collection of strings to be classified or
answered, Automail models the complete lifecycle:

```text
provider
   |
   v
mail synchronization
   |
   v
canonical messages / MIME / attachments
   |
   v
normalization
   |
   v
analysis
   |
   v
knowledge
   |
   v
workflow
   |
   v
policy
   |
   v
proposed action
   |
   +--------> human approval when required
   |
   v
provider action
   |
   v
audit trail
```

The architecture is explicitly designed for applications such as:

```text
mail triage
information extraction
conversation tracking
AI-assisted drafting
follow-up workflows
operational objectives
knowledge management
safe automated actions
human-approved sending
multi-account supervision
```

Automail is implemented in Haskell and currently uses:

```text
Hasql / Hasql.TH
PostgreSQL
STM
async
Aeson
Crypton
Servant/WAI dependencies
Stack
```

The current package version is:

```text
0.1.0.0
```

> **Development status**
>
> Automail currently contains a substantial domain architecture and persistence
> layer, but it is **not yet an operational autonomous mail server**.
>
> The current `automail server` command establishes the database connections,
> checks database connectivity, creates an application context, installs signal
> handlers, and waits for shutdown. Concrete provider drivers, workers, AI
> engines, workflows, action executors, and the HTTP server are not yet wired
> into that startup path.

---

## Contents

- [Role in FUDD](#role-in-fudd)
- [What Automail is](#what-automail-is)
- [What Automail is not](#what-automail-is-not)
- [Current implementation status](#current-implementation-status)
- [Architecture](#architecture)
- [Core information model](#core-information-model)
- [Getting started](#getting-started)
- [Command-line interface](#command-line-interface)
- [Configuration](#configuration)
- [Application runtime](#application-runtime)
- [Multi-tenancy](#multi-tenancy)
- [Provider abstraction](#provider-abstraction)
- [Provider accounts](#provider-accounts)
- [Mail model](#mail-model)
- [Synchronization](#synchronization)
- [Provider events](#provider-events)
- [Binary and attachment storage](#binary-and-attachment-storage)
- [Credential security](#credential-security)
- [AI and deterministic analysis](#ai-and-deterministic-analysis)
- [Knowledge model](#knowledge-model)
- [Objectives and workflows](#objectives-and-workflows)
- [Policy and authority](#policy-and-authority)
- [Actions and approval](#actions-and-approval)
- [Durable jobs](#durable-jobs)
- [Auditability](#auditability)
- [Database architecture](#database-architecture)
- [Supervision](#supervision)
- [Current runtime gaps](#current-runtime-gaps)
- [Testing strategy](#testing-strategy)
- [Development roadmap](#development-roadmap)
- [Module map](#module-map)
- [Design principles](#design-principles)
- [Repository housekeeping](#repository-housekeeping)
- [License](#license)

---

# Role in FUDD

Automail sits at the boundary between external email infrastructure and
FUDD's higher-level AI, workflow, and knowledge-management systems.

Conceptually:

```text
 Gmail / IMAP / JMAP
          |
          v
     +----------+
     | Automail |
     +----------+
          |
          +------> canonical mail repository
          |
          +------> AI analysis
          |
          +------> knowledge extraction
          |
          +------> workflow events
          |
          +------> proposed actions
          |
          `------> controlled outbound mail
```

This makes Automail useful as infrastructure for multiple FUDD applications
rather than as one narrowly configured personal email assistant.

For example, the same mail infrastructure could support:

```text
0to1,Done
customer/contact workflows
project development
fundraising
legal correspondence
support operations
venture pipelines
administrative monitoring
```

without each project implementing its own Gmail/IMAP synchronization,
credential management, MIME parsing, AI provenance, and action safety logic.

---

# What Automail is

Automail is designed as a **durable mail intelligence and automation engine**.

Its internal model separates several concerns that are often collapsed into
one "AI email agent":

```text
provider transport
        |
mail representation
        |
analysis
        |
knowledge
        |
workflow
        |
policy
        |
action
```

This separation is deliberate.

An LLM analysis result is not automatically an operational fact.

A fact is not automatically permission to act.

A proposed action is not automatically permission to send mail.

Automail represents those transitions explicitly.

---

# What Automail is not

Automail should not be understood merely as:

```text
incoming email
     |
     v
LLM prompt
     |
     v
send reply
```

That architecture would be too fragile for important business operations.

Automail instead introduces explicit concepts for:

```text
tenant isolation
mail provenance
analysis evidence
confidence
facts
workflow state
authority
approval
idempotency
retry behavior
audit
```

The goal is to make increasing levels of automation possible without losing
control over why an action occurred.

---

# Current implementation status

The repository contains a mixture of:

```text
implemented infrastructure

implemented domain abstractions

partially implemented components

future-facing architecture
```

The distinction matters.

| Capability | Current state |
| --- | --- |
| Haskell executable | Implemented |
| CLI/config loading | Implemented |
| Tenant/control PostgreSQL pools | Implemented |
| Tenant DB context propagation | Implemented |
| PostgreSQL row-level tenant isolation design | Implemented in schema |
| Tenant persistence | Implemented |
| Space persistence | Implemented |
| Principal persistence | Implemented |
| Account persistence | Implemented |
| Credential persistence | Implemented |
| Credential AES-256-GCM crypto | Implemented |
| Credential create/rotate/revoke | Implemented |
| Credential load/decrypt | **Incomplete** |
| Provider-neutral driver interfaces | Implemented |
| Gmail driver | **Not implemented** |
| IMAP/SMTP driver | **Not implemented** |
| JMAP driver | **Not implemented** |
| Provider event persistence | Implemented |
| Sync-state persistence | Implemented |
| Account runtime loading | Implemented |
| Account reconciliation supervisor | Implemented |
| General component supervisor | Implemented |
| Mail canonical types | Implemented |
| MIME/mail parser | **Not implemented** |
| Mail persistence implementation | **Not yet present** |
| Analysis model | Implemented |
| Analysis-driver registry | Implemented |
| Concrete AI engine | **Not implemented** |
| Knowledge model | Implemented |
| Knowledge persistence | Schema exists; service layer incomplete |
| Versioned workflow model | Implemented |
| Workflow driver interface | Implemented |
| Workflow evaluator/runtime | **Not implemented** |
| Policy model | Implemented |
| Action model | Implemented |
| Action-executor registry | Implemented |
| Concrete action executors | **Not implemented** |
| Durable job model | Implemented |
| Job queue interface | Implemented |
| DB job schema | Implemented |
| Job queue implementation | **Not implemented** |
| Job workers | **Not implemented** |
| Immutable audit persistence | Implemented |
| Database migration loader/checksums | Implemented |
| Database migration execution | **Disabled/incomplete** |
| HTTP configuration | Implemented |
| HTTP server | **Not currently started** |
| Automated tests | **Not implemented** |

---

# Architecture

The intended architecture is capability-oriented.

```text
+------------------------------------------------------------+
|                       Automail                             |
|                                                            |
|  +----------------------+                                  |
|  | Account supervision  |                                  |
|  +----------+-----------+                                  |
|             |                                              |
|             v                                              |
|  +----------------------+        +----------------------+   |
|  | Provider drivers     |<------>| Credential store     |   |
|  +----------+-----------+        +----------------------+   |
|             |                                              |
|             v                                              |
|  +----------------------+                                  |
|  | Mail repository      |                                  |
|  +----------+-----------+                                  |
|             |                                              |
|             v                                              |
|  +----------------------+                                  |
|  | Analysis engines     |                                  |
|  +----------+-----------+                                  |
|             |                                              |
|             v                                              |
|  +----------------------+                                  |
|  | Knowledge model      |                                  |
|  +----------+-----------+                                  |
|             |                                              |
|             v                                              |
|  +----------------------+                                  |
|  | Workflow engine      |                                  |
|  +----------+-----------+                                  |
|             |                                              |
|             v                                              |
|  +----------------------+                                  |
|  | Policy engine        |                                  |
|  +----------+-----------+                                  |
|             |                                              |
|             v                                              |
|  +----------------------+                                  |
|  | Actions / approvals  |                                  |
|  +----------+-----------+                                  |
|             |                                              |
|             v                                              |
|  +----------------------+                                  |
|  | Provider execution   |                                  |
|  +----------------------+                                  |
|                                                            |
+-------------------------+----------------------------------+
                          |
                          v
                     PostgreSQL
```

The application environment represents those dependencies explicitly through
`AppContext`.

Important capabilities include:

```haskell
StoreCred IO

RegistryAccountPrv IO

RegistryPrv IO

RegistryAn IO

QueueJob IO

RegistryJob IO

DriverWf IO

RegistryAct IO
```

This provides useful dependency boundaries for testing and for replacing one
implementation without changing unrelated domain code.

---

# Core information model

The planned end-to-end model is roughly:

```text
Tenant
  |
  +--> Space
  |
  +--> Principal
  |
  `--> Account
          |
          +--> Credential
          |
          +--> Mailbox
          |
          +--> Thread
          |
          `--> Message
                 |
                 +--> MIME Parts
                 |
                 +--> Attachments
                 |
                 +--> Content
                 |
                 +--> Analysis
                 |      |
                 |      v
                 |   Evidence
                 |
                 +--> Mentions
                 |
                 +--> Observations
                 |      |
                 |      v
                 |     Facts
                 |      |
                 |      v
                 |   Relations
                 |
                 +--> Conversation
                 |
                 `--> Workflow
                        |
                        v
                     Action
                        |
                        +--> Approval
                        |
                        v
                     Attempt
```

Supporting infrastructure includes:

```text
sync state
provider events
processing state
jobs
job attempts
audit events
blobs
objectives
policies
```

---

# Getting started

## Requirements

The repository currently targets:

```text
Stack snapshot: LTS 24.56
Package:        automail-0.1.0.0
```

A PostgreSQL server is required for the current `server` command.

---

## Clone

```bash
git clone git@github.com:whatsupfudd/ai_automail.git
cd ai_automail
```

---

## Build

```bash
stack build
```

---

## Run help

```bash
stack exec -- automail --help
```

---

## Version

```bash
stack exec -- automail version
```

---

# Command-line interface

The current command set is:

```text
help
version
server
migrate
```

---

## Server

```bash
stack exec -- automail server
```

The current server command:

```text
loads configuration
     |
     v
opens tenant DB pool
     |
     v
opens control DB pool
     |
     v
checks connectivity
     |
     v
constructs AppContext
     |
     v
installs SIGINT/SIGTERM handlers
     |
     v
waits for shutdown
```

It does **not** currently start:

```text
Warp
provider synchronization
account supervision
job workers
AI processing
workflow execution
```

despite the corresponding architecture already existing elsewhere in the
codebase.

---

## Migration command

The CLI exposes:

```text
automail migrate
```

with options for:

```text
configuration path
migration directory
dry-run
```

The migration subsystem can already:

```text
load numbered SQL files
calculate SHA-256 checksums
validate migration numbering
compare applied checksums
detect pending migrations
record migration metadata
```

However, actual migration application is currently disabled in
`applyMigrationsDB`.

Therefore the migration command should not yet be relied upon for production
database provisioning.

---

# Configuration

The default YAML configuration path is:

```text
~/.fudd/automail/config.yaml
```

It can be overridden through:

```text
--config
-c
```

or:

```text
automailCONF
```

The application home can be configured through:

```text
automailHOME
```

---

## Example development configuration

A representative configuration is:

```yaml
debug: 1

tenantDb:
  host: "127.0.0.1"
  port: 5432
  user: "automail_tenant"
  passwd: "development-password"
  dbase: "automail"

controlDb:
  host: "127.0.0.1"
  port: 5432
  user: "automail_control"
  passwd: "development-password"
  dbase: "automail"

server:
  host: "127.0.0.1"
  port: 8885

workers:
  count: 4
  leaseSeconds: 300
  pollingMs: 1000
  retryMax: 5

crypto:
  keySource: "env:AUTOMAIL_MASTER_KEY"
  keyRef: "default"

google:
  clientId: ""
  clientSecretRef: ""
  redirectUri: ""
  pubsubProject: null
  pubsubTopic: null

runtime:
  instanceId: "automail-dev"
  shutdownSeconds: 15
  accountRefreshSeconds: 60
  maintenanceSeconds: 60
```

Production deployments should never store real credential encryption keys or
provider client secrets directly in source-controlled configuration.

---

# Application runtime

`AppContext` is the central runtime dependency record.

It currently contains:

```haskell
configEA

poolsEA

clockEA

credentialsEA

accountResolversEA

providersEA

analysesEA

jobsEA

jobHandlersEA

workflowEA

actionsEA

shutdownEA
```

This gives Automail an explicit dependency-injection architecture.

For example, business logic can depend on:

```haskell
RegistryAn IO
```

rather than directly importing an OpenAI, local-model, or other analysis
client.

Likewise, mail logic can depend on:

```haskell
DriverPrv IO
```

rather than knowing how Gmail or IMAP works internally.

---

## Current server context

The current `server` command constructs the environment using:

```text
empty credential store

empty provider-account resolver registry

empty provider registry

empty analysis registry

unavailable job queue

empty job-handler registry

no-op workflow driver

empty action registry
```

This is intentional development scaffolding, but it means the current process
does not yet execute the conceptual mail pipeline.

---

# Multi-tenancy

Automail is designed as a multi-tenant system from the database boundary
upward.

The principal application context passed to tenant database operations is:

```haskell
data ContextTenant = ContextTenant {
    tenantUidCT
    , principalUidCT
    , correlationKeyCT
  }
```

Before a tenant transaction runs, Automail installs PostgreSQL-local settings:

```text
automail.tenant_uid

automail.principal_uid

automail.correlation_key
```

using `set_config(..., true)`.

These settings exist only for the current transaction.

---

## PostgreSQL row-level security

The reference schema enables PostgreSQL row-level security across tenant-owned
tables.

A helper function:

```sql
am.current_tenant_uid()
```

reads:

```text
automail.tenant_uid
```

and RLS policies enforce:

```text
tenant_fk = am.current_tenant_uid()
```

for reads and writes.

This gives Automail two complementary tenant boundaries:

```text
application context

+

PostgreSQL row-level security
```

rather than relying entirely on developers remembering to add
`WHERE tenant_fk = ...` to every query.

---

# Tenant and control database pools

Automail distinguishes:

```text
TenantPoolDB

ControlPoolDB
```

even though both may point to the same PostgreSQL installation.

The tenant pool is intended for work performed inside an explicit tenant
context.

The control pool exists for global operations such as:

```text
discover active tenants

discover active accounts

supervision

system maintenance
```

where the application must operate across tenant boundaries.

This is a useful security distinction and should eventually correspond to
separate PostgreSQL roles with appropriately different privileges.

---

# Provider abstraction

Mail providers are represented by the provider-neutral:

```haskell
DriverPrv m
```

interface.

The domain currently recognizes three provider families:

```text
Gmail

IMAP / SMTP

JMAP
```

through:

```haskell
data KindPrv =
    GmailKP
  | ImapSmtpKP
  | JmapKP
```

---

## Provider capabilities

Capabilities are explicit:

```text
Read

Change

Watch

Draft

Send

Collection
```

A driver exposes only the operations it actually supports.

For example:

```text
Gmail
  |
  +--> read
  +--> change cursor
  +--> watch
  +--> drafts
  +--> send
  `--> labels

IMAP/SMTP
  |
  +--> read
  +--> change detection
  +--> folders
  `--> send
```

can be represented without pretending that the protocols expose identical
semantics.

---

## Reader interface

The common reader can:

```text
fetch account profile

list collections

perform full synchronization

fetch a message

fetch an attachment
```

---

## Incremental synchronization

Providers supporting incremental history expose:

```haskell
ChangerPrv
```

with:

```text
syncChanges
```

based on an opaque provider cursor.

---

## Watch interface

Push-capable providers can implement:

```haskell
WatcherPrv
```

supporting:

```text
start watch

renew watch

stop watch
```

The provider event itself remains opaque to the Automail core until the
adapter normalizes it.

---

## Draft and send interfaces

Drafting and sending are deliberately distinct:

```text
DrafterPrv

SenderPrv
```

This supports safer workflows such as:

```text
AI proposes response
       |
       v
create provider draft
       |
       v
human reviews
       |
       v
send existing draft
```

rather than requiring generation and sending to be one atomic action.

---

# Provider accounts

The durable account record includes:

```text
tenant

default space

credential

provider kind

email address

normalized address

display name

status

provider configuration
```

Current account statuses include:

```text
active

disabled

error

archived
```

---

## Runtime account resolution

A persistent account is converted into a runtime account through:

```text
database account
      |
      v
load encrypted credential
      |
      v
decrypt credential
      |
      v
locate provider resolver
      |
      v
construct provider AccountPrv
      |
      v
RuntimeAccount
```

The resulting provider account contains credential material and deliberately
has no generic `Show` or JSON instance.

That reduces the chance of accidentally logging live secrets.

---

# Account supervision

Automail contains a substantial account supervisor.

It periodically reads the desired active account set through the control
database and reconciles it with the currently loaded runtime set.

Conceptually:

```text
active account refs in DB
          |
          v
     reconcile
       / | \
      /  |  \
     v   v   v
 activate reload deactivate
```

An account is reloaded when relevant persistent state changes, including its
credential state.

Runtime account states include:

```text
Starting

Ready

Reauthorise

Error

Stopping

Stopped
```

---

## Runtime generations

Reloaded accounts receive a new:

```haskell
GenerationAccount
```

This creates a simple way to distinguish a current runtime instance from an
older one associated with the same database account.

---

## Account hooks

Lifecycle events are exposed through hooks:

```text
Activated

Reloaded

Deactivated

Reauthorise
```

This creates a natural place for provider-specific components to start or
stop:

```text
mail synchronization

watch renewal

event consumers

pollers
```

when an account enters or leaves the runtime.

---

# Mail model

Automail defines a canonical provider-neutral representation of email.

The provider's own message representation is intentionally separate from the
stored canonical mail model.

---

## Provider message

`MessagePrv` represents what came from the provider:

```text
provider message ID

provider thread ID

RFC Message-ID

provider timestamp

collections

size

optional RFC 5322 / MIME raw source

provider-specific JSON
```

---

## Canonical message

`MessageMail` represents the normalized durable message:

```text
Automail message UID

tenant

account

thread

provider message ID

RFC Message-ID

direction

timestamps

subject

snippet

size
```

Directions include:

```text
Inbound

Outbound

Draft

System
```

---

## Addresses

The mail model distinguishes:

```text
From

Sender

Reply-To

To

Cc

Bcc
```

and stores both:

```text
normalized address

display name
```

---

## MIME structure

`ParsedMail` and `PartParsedMail` model the MIME tree explicitly.

A part can include:

```text
part path

parent path

provider part ID

MIME type

charset

disposition

content ID

filename

transfer encoding

content bytes

provider attachment ID
```

This provides the structure required for robust processing of:

```text
multipart/alternative

multipart/mixed

inline images

attachments

HTML mail

plain-text mail
```

without flattening everything prematurely.

---

## Normalized content

`ContentMail` distinguishes:

```text
plain

HTML

clean text

delta text

language

normalizer

normalizer version

content hash
```

The separation is useful because AI analysis should generally operate on a
stable normalized representation rather than directly on arbitrary MIME
source.

---

# Synchronization

Provider synchronization is explicitly checkpointed.

The durable synchronization state contains:

```text
account

sync kind

scope

cursor

checkpoint

status

last success

last full synchronization

next synchronization

error count

last error
```

States include:

```text
ready

syncing

error

disabled
```

---

## Full synchronization

A provider can return pages of message IDs:

```text
RequestSyncPrv
       |
       v
PageSyncPrv
       |
       +--> messages
       +--> next page token
       `--> provider cursor
```

The opaque cursor can then become the basis for incremental synchronization.

---

## Incremental changes

A change page contains:

```text
message added

message deleted

collection added

collection removed
```

together with the new cursor.

An important design note in the provider model states that the cursor should
only be persisted **after the corresponding changes have been durably
recorded**.

That ordering is essential.

The safe sequence is:

```text
provider returns changes + cursor N
           |
           v
persist changes
           |
           v
commit
           |
           v
persist/advance cursor N
```

rather than:

```text
advance cursor
      |
      v
crash
      |
      v
permanently lose changes
```

---

# Provider events

Push notifications are not treated as trusted state.

They become durable `provider_event` records first.

A provider event records:

```text
tenant

account

provider event ID

kind

cursor

payload

provider occurrence time

receipt time

processing time

status

error
```

States include:

```text
pending

processing

processed

failed

ignored
```

---

## Deduplication

The schema includes:

```text
UNIQUE (account_fk, provider_event_id)
```

and insertion distinguishes:

```text
new event

existing event
```

This is important because webhook and push-delivery systems commonly deliver
the same event more than once.

---

# Binary and attachment storage

Automail separates mail metadata from binary content.

`Blob` represents content such as:

```text
raw RFC message

attachment

inline MIME part

generated content
```

Blob metadata includes:

```text
kind

media type

SHA-256

size

storage location

metadata
```

Storage can be:

```text
Inline

External <reference>
```

This gives the architecture a path from simple PostgreSQL-backed storage to
object storage without changing the mail model.

---

## Content-addressable behavior

The reference schema applies a uniqueness constraint over:

```text
tenant

SHA-256

size
```

allowing binary content to be deduplicated within a tenant.

---

# Credential security

Automail does not store provider passwords or refresh tokens as ordinary
plaintext database values.

The architecture separates:

```text
credential metadata

encrypted credential

runtime secret
```

---

## Credential kinds

Current credential kinds are:

```text
OAuth refresh token

password

service account

external credential
```

---

## Encryption

`AutoMail.Credential.Crypto` implements authenticated encryption using:

```text
AES-256-GCM
```

with:

```text
32-byte key

16-byte nonce

16-byte authentication tag
```

Credential encryption also includes additional authenticated data derived
from:

```text
tenant UID

credential UID where available

credential kind

key reference
```

Conceptually:

```text
secret
  |
  +---- encryption key
  |
  +---- tenant identity
  |
  +---- credential identity
  |
  `---- credential kind
          |
          v
      AES-256-GCM
          |
          v
 ciphertext + nonce + metadata
```

This reduces the risk of encrypted credential material being copied into an
unrelated tenant/credential context unnoticed.

---

## Key sources

The crypto layer can load key material from:

```text
environment variable

file

literal/text source
```

and supports a keyring with an active key reference.

Accepted key material can be encoded as:

```text
base64

hex

raw UTF-8
```

Keyring support provides a foundation for key rotation.

---

## Credential lifecycle

The credential store exposes:

```text
load

create

rotate

revoke
```

and validates:

```text
tenant ownership

expiration

revocation
```

before allowing runtime use.

---

## Current credential-store limitation

Creation, rotation, revocation, persistence, and crypto infrastructure are
substantially implemented.

However, after successfully decrypting a credential,
`loadStoreCred` currently returns an `"implemented"` error rather than the
constructed `RuntimeCred`.

Therefore runtime account activation cannot yet use the otherwise implemented
credential store end-to-end.

---

# AI and deterministic analysis

Automail deliberately calls this subsystem **analysis**, rather than making the
core dependent on one specific LLM.

An analysis request contains:

```text
analysis kind

engine

optional model

output schema

subject context

evidence references

metadata
```

---

## Analysis subjects

Analyses can target:

```text
message

attachment

thread

conversation
```

This allows operations such as:

```text
message classification

attachment extraction

thread summarization

conversation-state interpretation
```

to share the same provenance model.

---

## Explicit schemas

Each analysis can specify:

```text
schema key

schema version

schema definition
```

which makes structured AI output part of the contract rather than merely a
prompt convention.

---

## Usage tracking

Analysis results can track:

```text
input tokens

output tokens

duration
```

along with:

```text
engine

model

model version
```

This is useful for:

```text
cost accounting

model comparison

reproducibility

performance analysis
```

---

## Engine registry

Analysis providers are represented through:

```haskell
DriverAn
```

and registered by:

```haskell
EngineAn
```

This lets Automail support multiple analysis systems:

```text
rules

local models

FUDD AI Server

commercial LLMs

specialized extraction engines
```

without embedding one implementation in mail-domain code.

No concrete analysis engine is currently registered by the server.

---

# Evidence and provenance

One of the stronger design choices is that analysis provenance is explicit.

An evidence reference can identify:

```text
message

MIME part

attachment

text fragment
```

This means an extracted observation can eventually answer:

```text
Where did this claim come from?
```

rather than only:

```text
Which model produced it?
```

The database model additionally supports character offsets and content hashes.

This is important for trustworthy AI-assisted knowledge extraction.

---

# Knowledge model

Automail does not treat analysis output directly as permanent truth.

The knowledge layer distinguishes:

```text
entity

mention

observation

fact

relation
```

---

## Entities

An entity has:

```text
kind

canonical name

optional external key

attributes
```

Examples could include:

```text
person

organization

project

transaction

property

product
```

without hard-coding those categories into the core library.

---

## Mentions

A mention represents something found in source material.

It can include:

```text
value

candidate entity

resolved entity

confidence

source

metadata
```

---

## Observations

An observation is an interpreted claim derived from source material.

Statuses include:

```text
Proposed

Accepted

Rejected

Superseded
```

That distinction is critical.

An AI output can enter the knowledge pipeline as:

```text
Proposed
```

rather than automatically becoming fact.

---

## Facts

Facts can be:

```text
Active

Superseded

Rejected

Expired
```

and have optional:

```text
valid-from

valid-until

confidence
```

This supports information that changes over time.

For example:

```text
"John works at Company A"
```

may be true during one interval and superseded later.

---

## Relations

Relations connect two entities with:

```text
kind

attributes

confidence

validity interval
```

This provides a foundation for a lightweight operational knowledge graph
derived from communications.

---

# Objectives and workflows

Automail contains an explicit operational objective model in its database
schema.

An objective can represent something such as:

```text
obtain a reply

schedule a meeting

collect documents

resolve a support case

complete onboarding

follow up with an investor

obtain legal clarification
```

Objectives can be hierarchical and have:

```text
owner

priority

status

target

context

due date
```

---

# Versioned workflow model

Automail workflows are state-machine-like specifications.

A workflow contains:

```text
states

transitions

matchers

guards

effects
```

---

## Workflow state

An instance tracks:

```text
current state

status

context

subject entity

objective

space

workflow version
```

Statuses include:

```text
Active

Waiting

Completed

Failed

Cancelled
```

---

## Inputs

Workflow inputs can originate from:

```text
Observation

MailEvent

Manual action

Timer
```

This is important because a business process may advance because:

```text
a message arrived

AI extracted a fact

a person approved something

a deadline elapsed
```

without requiring separate workflow mechanisms for each source.

---

## Transitions

A transition contains:

```text
from state

observation matcher

optional guard

to state

effects
```

---

## Effects

Workflow effects currently include:

```text
propose action

enqueue job

assert fact

modify context

complete objective
```

This makes the workflow engine the coordination layer rather than the direct
executor of external side effects.

---

# Policy and authority

Automail separates:

```text
what a workflow wants to do
```

from:

```text
what the system is allowed to do automatically
```

That distinction is represented by the policy subsystem.

---

## Authority levels

The current `AuthorityAct` model defines:

```text
Observe

SafeProvider

Internal

Draft

ConditionalSend

Approval

Prohibited
```

This is a particularly important part of the architecture.

It provides a continuum from:

```text
read-only observation
```

through:

```text
safe internal/provider operations
```

and:

```text
draft generation
```

to:

```text
conditional sending

mandatory human approval

prohibited action
```

---

## Policy decisions

A policy can return:

```text
Allow <authority>

Approval <authority> <reason>

Deny <reason>
```

Policy rules have:

```text
priority

condition

decision
```

with a default decision.

---

## Rule expressions

The core already contains a small rule-expression model supporting:

```text
exists

equals

not equals

less / greater

contains

starts with

ends with

in

all

any

not
```

over structured paths.

This means many approval and automation rules can remain deterministic and
inspectable instead of requiring an LLM call.

---

# Actions and approval

Actions are durable objects rather than direct function calls.

A proposal carries:

```text
tenant

space

workflow

workflow event

source message

analysis

action kind

payload

idempotency key

not-before time

expiration
```

---

## Action states

Current action states are:

```text
Proposed

ApprovalRequired

Approved

Executing

Completed

Failed

Rejected

Cancelled

Expired
```

---

## Explicit approval

Approval decisions include:

```text
Approve

Reject

Cancel
```

and record:

```text
principal

decision

note

timestamp
```

This creates an auditable human-in-the-loop mechanism.

---

## Why this matters for email

Sending email is consequential.

A generated draft and a sent message should therefore be distinct operations.

A safe flow can be:

```text
incoming mail
      |
      v
AI analysis
      |
      v
workflow proposes reply
      |
      v
policy => Approval required
      |
      v
create draft
      |
      v
human approval
      |
      v
send
      |
      v
audit
```

Automail's data model supports that distinction explicitly.

---

# Idempotency

Actions include:

```haskell
IdempotencyKey
```

and the schema enforces:

```text
UNIQUE (tenant_fk, idempotency_key)
```

This is important for operations such as sending mail.

If a workflow or worker retries after a crash, the system must not silently
create multiple equivalent outbound actions.

---

# Durable jobs

Automail defines a durable job abstraction for work that should outlive a
request or process.

A job contains:

```text
tenant

kind

priority

deduplication key

payload

not-before time

attempt count

maximum attempts

lease owner

lease expiration

correlation key
```

States are:

```text
Pending

Running

Completed

Failed

Cancelled
```

---

## Queue capability

The abstract queue supports:

```text
enqueue

claim

heartbeat

complete

retry

fail

cancel

recover
```

The leasing model allows a worker to claim a job temporarily.

If the worker disappears, recovery logic can eventually make the operation
eligible again.

---

## Job handlers

Handlers are registered by job kind:

```text
KindJob
   |
   v
HandlerJob
```

This supports independent workers for operations such as:

```text
message synchronization

attachment retrieval

analysis

workflow processing

action execution

watch renewal
```

---

## Current job limitation

The queue and handler interfaces exist, and the database schema contains
`am.job` and `am.job_attempt`.

However, the current server constructs:

```haskell
unavailableQueueJob
```

and:

```haskell
emptyRegistryJob
```

There is not yet a concrete DB queue/worker runtime comparable to the more
advanced job execution system found in some other FUDD services.

---

# Auditability

Automail contains an immutable audit-event table and typed DB operations.

An audit event can record:

```text
tenant

principal

kind

object kind

object UID

correlation key

payload

timestamp
```

Correlation keys are also propagated through tenant execution context.

This creates a path toward answering:

```text
Why was this email sent?

Which workflow proposed it?

Which analysis contributed?

Which policy allowed it?

Who approved it?

Which execution attempt performed it?
```

That level of traceability is especially important as AI autonomy increases.

---

# Database architecture

The reference schema uses:

```text
am
```

as the PostgreSQL schema.

It is comprehensive and already models most of the intended system.

Major groups include:

```text
tenant / space / principal

credentials / accounts

Gmail / IMAP / SMTP configuration

sync state / provider events

blobs

mailboxes / threads / messages

addresses / MIME parts / attachments

conversations

analysis / evidence / feedback

entities / mentions / observations / facts / relations

objectives

workflow definitions / versions / instances / events

policy definitions / versions

actions / approvals / attempts

drafts

processing state

jobs / attempts

audit events
```

---

## Typed identifiers

Database identities use dedicated Haskell newtypes, for example:

```haskell
TenantUid

AccountUid

MessageUid

AnalysisUid

EntityUid

ObservationUid

WorkflowInstanceUid

ActionUid

JobUid
```

Provider identifiers are separately typed:

```haskell
MessageIdPrv

ThreadIdPrv

CollectionIdPrv

AttachmentIdPrv

DraftIdPrv

EventIdPrv

CursorPrv
```

This avoids accidentally mixing a Gmail/IMAP identifier with an Automail
database identity.

---

# Schema migration framework

Automail includes a versioned migration subsystem.

Migration files are expected to be immutable numbered SQL files.

Each migration carries:

```text
version

name

SHA-256 checksum

SQL
```

Applied migration metadata is stored in:

```text
am.schema_migration
```

The runtime has an expected schema version:

```text
1
```

and contains logic to detect:

```text
missing schema

schema too old

schema newer than binary
```

---

## Current migration limitation

Despite the surrounding migration implementation,
`applyMigrationsDB` currently returns an error immediately.

The underlying connection/application code has been commented out.

Also, the repository currently contains:

```text
Support/dbDef_1.sql
```

as a schema definition/reference rather than a ready migration directory
matching the migration command's intended production workflow.

Finishing database provisioning is therefore a prerequisite for making a
clean deployment process.

---

# Current schema check limitation

`AutoMail.DB.Schema.verifySchemaDB` contains proper schema-version checking.

However, the current server startup calls:

```haskell
healthDB
```

through `verifySchemaServer`, rather than invoking `verifySchemaDB`.

As a result, `automail server` currently verifies database connectivity but
does **not** enforce that the connected database is at schema version 1.

That should be corrected before production deployment.

---

# General component supervision

Automail already contains a reusable application supervisor.

A component declares:

```text
name

criticality

restart policy

run function
```

Criticality can be:

```text
Critical

Restartable
```

Restart policy can be:

```text
Never

Fixed delay

Exponential backoff
```

---

## Critical components

If a critical component exits unexpectedly:

```text
component failure
       |
       v
supervisor marks fatal
       |
       v
global shutdown requested
       |
       v
other components cancelled
```

---

## Restartable components

A restartable component can be restarted with:

```text
fixed delay
```

or bounded:

```text
exponential backoff
```

This is a useful base for eventually supervising:

```text
HTTP server

account supervisor

provider listeners

workers

maintenance loop
```

---

## Current supervision limitation

`runSupervisorApp` is implemented but the current `Commands.Server` does not
use it.

The server simply waits on:

```haskell
shutdownEA.awaitSA
```

after constructing the context.

---

# Error and retry semantics

Provider failures are modeled more richly than simple text errors.

Error kinds include:

```text
Authentication

Authorization

RateLimit

Transport

InvalidRequest

CursorExpired

NotFound

Conflict

ProviderState

Unknown
```

Retry policy can be:

```text
Never

Immediate

Delayed

Reauthorise

Resynchronise
```

This is especially useful for mail synchronization.

For example:

```text
401 / expired authorization
        ->
Reauthorise

expired provider history cursor
        ->
Resynchronise

temporary provider outage
        ->
Delayed retry
```

Those cases should not all be treated identically.

---

# Current runtime gaps

The largest remaining tasks are integration tasks rather than fundamental
domain-design tasks.

---

## No concrete provider adapters

The common interfaces for:

```text
Gmail

IMAP / SMTP

JMAP
```

exist, and the SQL schema already contains Gmail and IMAP/SMTP account
configuration.

There are currently no concrete provider modules implementing those drivers.

---

## Credential loading is unfinished

The crypto and persistence infrastructure is largely implemented, but
`loadStoreCred` deliberately returns an error after decryption.

---

## No mail ingestion pipeline

The canonical mail representation exists, but the code that converts
`MessagePrv` into:

```text
blob

thread

message

addresses

parts

attachments

normalized content
```

is not yet present.

---

## No HTTP server

Although the project depends on:

```text
Servant

Warp

WAI

CORS
```

and has HTTP configuration, the current application starts no HTTP listener.

---

## No live account supervisor

The account supervisor is implemented but not added as an application
component during startup.

---

## No concrete AI engine

The analysis interface and registry exist, but the server registers no
analysis driver.

---

## No workflow runtime

Workflow types are sophisticated, but the current server uses:

```haskell
noopDriverWf
```

which returns no workflow events.

---

## No action executors

The action registry is empty.

Therefore even an approved action currently has no concrete executor.

---

## No durable job implementation

The job capability exists but the current runtime uses:

```haskell
unavailableQueueJob
```

---

## Migration execution is disabled

`automail migrate` cannot currently apply pending migrations.

---

## Schema compatibility is not enforced on startup

Server startup checks DB connectivity only.

---

## Configuration has two generations

There is an older active configuration pipeline:

```text
Options.*

YAML
```

and a newer, mostly commented-out configuration system in:

```text
AutoMail.App.Config
```

which supports environment-style variables such as:

```text
AUTOMAIL_HTTP_PORT

AUTOMAIL_WORKER_COUNT

AUTOMAIL_CRYPTO_KEY_SOURCE

AUTOMAIL_GOOGLE_CLIENT_ID
```

The project should converge on one configuration system rather than maintain
two overlapping representations.

---

# Testing strategy

The current test suite is:

```haskell
main =
  putStrLn "Test suite not yet implemented"
```

The architecture now justifies a significant automated test programme.

---

## Pure model tests

These should cover:

```text
confidence validation

rule expressions

policy decisions

workflow matching

workflow transitions

action authority

job states

retry classification

hash parsing/rendering

provider capability detection
```

---

## Crypto tests

Test:

```text
encrypt -> decrypt

wrong tenant

wrong credential

wrong key

wrong key reference

modified ciphertext

modified nonce

modified authentication tag

key rotation

legacy AAD compatibility

expired credential

revoked credential
```

Property tests would be valuable here.

---

## PostgreSQL tenant-isolation tests

Use at least two tenants and verify that:

```text
tenant A cannot see tenant B messages

tenant A cannot update tenant B accounts

tenant A cannot fetch tenant B credentials

tenant A cannot read tenant B knowledge

tenant context disappears after transaction
```

This is one of the most important security test groups.

---

## Account-supervisor tests

Exercise:

```text
new account activation

account removal

account configuration change

credential rotation

provider resolver missing

credential load failure

reauthorization requirement

hook failure

graceful shutdown
```

---

## Provider contract tests

Every provider adapter should eventually pass a common suite covering:

```text
profile

collections

full sync

incremental changes

cursor expiry

message retrieval

attachment retrieval

draft creation

sending

watch renewal

duplicate provider event
```

---

## Mail fixtures

Create a fixture corpus including:

```text
simple text mail

HTML-only mail

multipart alternative

nested multipart

attachments

inline CID images

Unicode headers

encoded subjects

quoted-printable

base64

malformed MIME

large attachments
```

---

## Synchronization recovery tests

Particularly test crash boundaries:

```text
fetch changes
    |
    v
persist half
    |
   crash
```

and:

```text
persist all
    |
   crash
    |
    v
before cursor advance
```

A restart must never silently lose provider history.

---

## Workflow tests

Use deterministic fixtures for:

```text
no matching transition

single transition

guard failure

proposed action

job creation

fact assertion

context update

objective completion
```

---

## Action-safety tests

Test:

```text
duplicate idempotency key

expired action

mandatory approval

rejected approval

prohibited action

executor failure

indeterminate provider outcome
```

---

# Development roadmap

## Phase 1 — Make database provisioning real

Complete:

```text
migration directory convention

applyMigrationsDB

transaction-safe migration execution

schema-version startup check
```

Convert the current:

```text
Support/dbDef_1.sql
```

into the canonical migration baseline.

---

## Phase 2 — Finish credential loading

Complete:

```haskell
loadStoreCred
```

so encrypted credentials can become runtime provider credentials.

Then add comprehensive crypto tests before provider integration.

---

## Phase 3 — Gmail adapter

Gmail is the most natural first complete provider because the schema and
configuration already anticipate:

```text
OAuth

Google user ID

history ID

Pub/Sub topic

watch expiration

message totals

thread totals
```

Implement:

```text
OAuth credential resolution

profile

labels

full synchronization

history synchronization

message fetch

attachment fetch

watch start/renew

draft create/update/delete

send
```

---

## Phase 4 — Canonical mail importer

Implement the pipeline:

```text
MessagePrv
    |
    v
RFC/MIME parser
    |
    +--> raw Blob
    |
    +--> Message
    |
    +--> Thread
    |
    +--> addresses
    |
    +--> MIME parts
    |
    +--> attachments
    |
    `--> normalized ContentMail
```

This becomes the stable provider-independent boundary.

---

## Phase 5 — Activate account supervision

Build:

```text
Credential Store

Provider Resolver Registry

Provider Registry
```

and wire `runSupervisorAccount` into `runSupervisorApp`.

---

## Phase 6 — Durable job queue and workers

Implement PostgreSQL operations for:

```text
enqueue

atomic claim

lease

heartbeat

complete

retry

fail

recovery
```

then build supervised worker components.

---

## Phase 7 — AI Server integration

Implement an analysis driver for the FUDD AI Server.

The preferred boundary is:

```text
Automail
   |
   v
RequestAn
   |
   v
AI Server
   |
   v
ResultAn
```

rather than embedding model-provider calls directly in mail processing.

Store:

```text
model

model version

token usage

schema

evidence

result

timing
```

with every analysis.

---

## Phase 8 — Knowledge extraction

Turn selected analysis results into:

```text
mentions

candidate entities

observations

facts

relations
```

while preserving their evidence chain.

Require explicit rules for when a proposed observation becomes an accepted
fact.

---

## Phase 9 — Workflow engine

Implement evaluation of:

```text
states

matchers

guards

effects
```

and persist:

```text
workflow instance

sequence-numbered workflow events
```

as the durable record of operational progression.

---

## Phase 10 — Policy engine

Evaluate each proposed action against versioned policy.

Use the existing authority model to distinguish:

```text
read-only

safe provider operation

internal action

draft generation

conditional send

mandatory approval

prohibited
```

---

## Phase 11 — Action execution

Implement action executors beginning with lower-risk actions:

```text
apply label/folder

create draft

update draft
```

before enabling automated sending.

Sending should remain strongly idempotent and policy-controlled.

---

## Phase 12 — HTTP / EasyWordy interface

Only once the core runtime is operational, add a narrow management API for:

```text
account status

reauthorization

message search

analysis review

knowledge review

workflow monitoring

action approval

draft review

audit inspection
```

The natural FUDD operator interface can then be implemented as an
EasyWordy/Fuddle Wapp.

---

## Phase 13 — IMAP / SMTP

Implement the second provider family after the Gmail semantics have validated
the provider abstraction.

This will test whether the core really is provider-neutral.

---

## Phase 14 — JMAP

JMAP can become a third implementation and a strong validation that provider
capabilities have not become accidentally Gmail-specific.

---

# Module map

## Application

| Module | Responsibility |
| --- | --- |
| `AutoMail.App.Context` | runtime dependency environment |
| `AutoMail.App.Config` | newer typed configuration model |
| `AutoMail.App.Error` | application/provider retry semantics |
| `AutoMail.App.Runtime` | component criticality/restart policy |
| `AutoMail.App.Supervisor` | process component supervision |

---

## Account runtime

| Module | Responsibility |
| --- | --- |
| `AutoMail.App.Account.Types` | runtime account state/events |
| `AutoMail.App.Account.Runtime` | load/resolve one account |
| `AutoMail.App.Account.Supervisor` | reconcile active runtime accounts |

---

## Providers

| Module | Responsibility |
| --- | --- |
| `AutoMail.Provider.Types` | provider-neutral mail/provider types |
| `AutoMail.Provider.Driver` | provider capability interfaces/registry |

Concrete provider adapters have not yet been added.

---

## Mail

| Module | Responsibility |
| --- | --- |
| `AutoMail.Mail.Types` | canonical mail and MIME representation |
| `AutoMail.Mail.Event` | durable mail lifecycle events |

---

## Credentials

| Module | Responsibility |
| --- | --- |
| `AutoMail.Credential.Types` | secret/encrypted/runtime credential types |
| `AutoMail.Credential.Crypto` | AES-256-GCM and keyring management |
| `AutoMail.Credential.Store` | credential persistence lifecycle |

---

## Analysis

| Module | Responsibility |
| --- | --- |
| `AutoMail.Analysis.Types` | analysis requests/results/evidence |
| `AutoMail.Analysis.Driver` | analysis engine registry |

---

## Knowledge

| Module | Responsibility |
| --- | --- |
| `AutoMail.Knowledge.Types` | entities, mentions, observations, facts, relations |

---

## Workflow

| Module | Responsibility |
| --- | --- |
| `AutoMail.Workflow.Types` | versioned workflow state-machine model |
| `AutoMail.Workflow.Driver` | workflow processing interface |

---

## Policy

| Module | Responsibility |
| --- | --- |
| `AutoMail.Policy.Types` | authority rules and policy decisions |

---

## Actions

| Module | Responsibility |
| --- | --- |
| `AutoMail.Action.Types` | proposed/executable action model |
| `AutoMail.Action.Driver` | action executor registry |

---

## Jobs

| Module | Responsibility |
| --- | --- |
| `AutoMail.Job.Types` | durable job model |
| `AutoMail.Job.Capability` | queue and handler interfaces |

---

## Persistence

Current `AutoMail.DB.*` modules include:

```text
Account

Audit

Core

Credential

Migrate

Principal

ProviderEvent

Schema

Space

Sync

Tenant
```

The SQL reference schema is broader than the currently implemented Haskell DB
module set.

---

## CLI and legacy runtime support

```text
Commands.*

Options.*

DB.Connect

HttpSup.*
```

contain the command-line/configuration infrastructure inherited and evolved
from the generic FUDD application template.

---

# Design principles

## Preserve the original evidence

Never let an AI summary replace the original email.

Store the original source and maintain provenance.

---

## Providers are transports, not the domain

Gmail labels and IMAP folders are provider concepts.

Automail workflows should be expressed in Automail concepts.

---

## AI output is an observation, not automatically a fact

The progression should remain explicit:

```text
source

-> analysis

-> observation

-> validation/policy

-> fact
```

when the application requires trustworthy knowledge.

---

## Drafting is safer than sending

The architecture intentionally has a `Draft` authority level before
conditional or approved sending.

Use it.

---

## Automation authority should be explicit

Do not scatter logic such as:

```haskell
if confidence > 0.9 then send
```

through arbitrary worker code.

Centralize automation permission in versioned policies.

---

## Side effects must be idempotent

Mail sending cannot safely rely on "just retry it."

Use:

```text
idempotency keys

action attempts

provider reconciliation
```

for consequential actions.

---

## Tenant identity is database context

Every tenant transaction should carry:

```text
tenant

principal

correlation
```

and let PostgreSQL RLS enforce the tenant boundary.

---

## Global control access is exceptional

Cross-tenant operations belong behind the explicitly separate control
capability, not ordinary tenant application queries.

---

## Credentials should not be loggable

Runtime credential types deliberately avoid ordinary `Show`/JSON instances.

Maintain that property as provider integrations are added.

---

## Workflows coordinate; executors perform side effects

A workflow should propose:

```text
send this message
```

rather than calling SMTP directly.

Policy and execution must remain independent layers.

---

## AI engines should be replaceable

Mail-domain logic should not depend on:

```text
OpenAI

Anthropic

local model

specific FUDD AI implementation
```

Directly depend on the Automail analysis contract.

---

## Every consequential action should be explainable

Eventually, an operator should be able to traverse:

```text
sent email
    |
    v
action attempt
    |
    v
approved action
    |
    v
policy decision
    |
    v
workflow event
    |
    v
observation / fact
    |
    v
analysis
    |
    v
source email
```

That is the central architectural advantage of Automail over a simple
LLM-connected mailbox.

---

# Repository housekeeping

Several package/template fields still need cleanup.

---

## Repository metadata

`package.yaml` currently references:

```text
githubuser/automail
```

instead of:

```text
whatsupfudd/ai_automail
```

Update:

```text
github

description

README URL

package metadata
```

---

## Author metadata

Current fields still contain template values:

```text
Author name here

example@example.com
```

These should be replaced with the project's actual metadata.

---

## License metadata

The included `LICENSE` also still contains:

```text
Author name here
```

and should be reconciled with the actual copyright owner.

---

## Changelog

The changelog still contains:

```text
0.1.0.0 - YYYY-MM-DD
```

The first meaningful implementation milestone should receive an actual date
and summary.

---

## CLI wording

Some CLI help still contains generic template language such as:

```text
Shows the version number of importer.
```

This should say:

```text
Shows the Automail version.
```

The advertised configuration path also refers to:

```text
~/.automail/config.yaml
```

while the implementation actually defaults to:

```text
~/.fudd/automail/config.yaml
```

---

## Migration parser

The `migrate` subcommand currently defines its local `--config` option as an
`option auto` producing `Maybe FilePath`, despite the global configuration
option already existing.

This should be simplified when the configuration systems are consolidated.

---

## PostgreSQL pool configuration

`DB.Connect.configPg` currently applies:

```haskell
Pc.acquisitionTimeout
```

both for the configured acquisition timeout and again for the value named
`poolIdleTime`.

The latter almost certainly intends:

```haskell
Pc.idlenessTimeout
```

and should be reviewed.

---

## Duplicate/legacy configuration

The active YAML stack and the newer `AutoMail.App.Config` environment decoder
should not evolve independently.

Choose one canonical configuration path and remove the other after migration.

---

# Recommended near-term milestone

The next useful milestone is not "AI automatically answers email."

It is a much more foundational end-to-end slice:

```text
PostgreSQL schema
      |
      v
encrypted Gmail credential
      |
      v
account supervisor
      |
      v
Gmail provider
      |
      v
synchronize one mailbox
      |
      v
store one canonical message
      |
      v
normalize its content
      |
      v
run one structured analysis
      |
      v
store analysis + evidence
      |
      v
emit one workflow input
```

Once that vertical slice is reliable, the system can incrementally add:

```text
knowledge extraction

draft generation

workflow progression

approval

sending
```

without changing the core architecture.

---

# Long-term position

Automail has the foundations to become a general **communications intelligence
and controlled automation substrate** for FUDD.

The intended system can be summarized as:

```text
                         EMAIL WORLD
                             |
           +-----------------+-----------------+
           |                                   |
           v                                   v
        Gmail                             IMAP/JMAP
           |                                   |
           +-----------------+-----------------+
                             |
                             v
                    +----------------+
                    | Provider layer |
                    +-------+--------+
                            |
                            v
                   +-----------------+
                   | Canonical mail  |
                   +--------+--------+
                            |
             +--------------+--------------+
             |                             |
             v                             v
        normalized                     attachments
          content
             |
             v
       +-------------+
       |  Analysis   |
       +------+------+
              |
              v
       +-------------+
       | Knowledge   |
       +------+------+
              |
              v
       +-------------+
       | Workflow    |
       +------+------+
              |
              v
       +-------------+
       | Policy      |
       +------+------+
              |
              v
       +-------------+
       | Action      |
       +------+------+
              |
        +-----+------+
        |            |
        v            v
     execute       approval
        |            |
        +-----+------+
              |
              v
           provider
              |
              v
        sent / changed
              |
              v
           audit
```

The key architectural insight is that Automail is not fundamentally about
generating text.

It is about creating a trustworthy bridge between:

```text
unstructured human communication

and

structured machine-assisted operations
```

while maintaining:

```text
provenance
tenant isolation
security
authority
human control
idempotency
recoverability
auditability
```

That makes Automail potentially much more important to the FUDD AI ecosystem
than a conventional automated-email application.

---

# License

The repository contains a BSD 3-Clause license.

The current license file still contains placeholder author metadata and should
be updated before formal distribution.
