# Architecture

Koha owns staff identity, sessions, permissions and record existence. The SIUT DAM
(separate Laravel application)
owns its sessions, media processing/storage/viewers and MARC 856 publication through
supported Koha APIs. This repository implements only the integration bridge.

## Components

- MediaManager.pm: lifecycle, native toolbar, CGI administration, permissions,
  initiation, exchange orchestration, audit and retention.
- Security.pm: strict validation, CSPRNG codes, credential hashes, escaping, the test-only HTTP switch.
- Store.pm: parameterized persistence and transactional single-use consumption.
- Controller.pm and openapi.json: native plugin REST registration and adapter.
- Health.pm: pinned-address TLS diagnostic, no redirects.
- Template Toolkit: configuration, dashboard, continuation and error pages, shared layout and breadcrumbs.

## Persistence

Tables use Koha's get_qualified_table_name convention. No patron or bibliographic
table writes or custom staff accounts are introduced.

| Suffix | Purpose |
|---|---|
| log | Existing audit schema/records preserved; safe JSON details include correlation ID |
| requests | Hashed initiation and staff session; record/branch/configuration binding; expiration/consumption |
| codes | Hashed code; staff/context, issuer/audience/client, browser state, expiration/consumption |
| rates | Shared fixed-window counters |

InnoDB is mandatory. V1 already specified InnoDB for log; confirm it was not manually
changed. Schema version 2 creates new tables idempotently and fills missing defaults
without replacing existing configuration. Plugin settings use Koha plugin_data
(including `insecure_http` for the **Allow HTTP** checkbox).

Database storage replaces the need for process-local memory or a shared cache.
SELECT FOR UPDATE locks a code's primary-key row; revalidation, consumption and audit
commit together. A second worker waits and then sees consumption. Audit failure
returns no identity and rolls back consumption. A lost successful HTTP response still
consumes the code; start another handoff.

Initiation is similarly consumed atomically with code issuance. It is bound to the
original staff session, application destination, instance and client. It cannot be
redeemed at the exchange endpoint.

## Trust boundaries

Koha run.pl keeps its native plugin permission gate. The plugin also requires a staff
session interface and current patron record. Configuration/dashboard access requires
a superlibrarian. Exchange authenticates a dedicated application credential and then
independently revalidates the original staff member.

The account policy is deliberately conservative: locked, expired, restricted,
lost-card and invalid-address accounts cannot hand off. No passwords are rechecked
and no original login timestamp is invented. issued_at describes grant creation.

The grant is a snapshot: permissions can change after exchange. The consumer must use
appropriate short sessions/revalidation for sensitive operations. Remote logout,
introspection and long-lived plugin access tokens are not implemented. Branch means
the authenticated working branch at initiation, not necessarily the patron's home branch.
