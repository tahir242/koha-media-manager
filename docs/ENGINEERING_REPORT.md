# Engineering report

Completed implementation review: 2026-10-23. Current version: **2.4.0** (2026-10-24).

> Sections 1–10 describe the 2.0.0 hardening as delivered; per-version changes follow.
> Since then the plugin has been runtime-tested on a Koha 26.05 test server with the DAM
> (see COMPATIBILITY.md and TESTING.md), which supersedes the "not runtime-tested" statements below.
Branch: **feature/plugin-security-hardening**.
Base: initial beta commit **4c7f526**, clean main working tree when work began.
No commits, pushes, merges, production configuration changes, Koha core modifications,
bibliographic database writes, or Laravel project creation were performed.

## 1. Changes

Upgraded the plugin candidate to 2.0.0. Preserved the catalogue action, administration,
audit history and connection diagnostics while replacing the unsafe authentication
transport. The native no-argument toolbar hook now emits a permission-aware CSRF POST.
The external application remains independently developed.

## 2. Security findings addressed

Removed partially signed browser identity/TTL, replayable redirects, wildcard permission
policy, nonexistent-record acceptance, secret rendering, unvalidated configuration,
missing plugin CSRF checks, fragile JavaScript interpolation, unrestricted diagnostic
requests and random request-time cleanup. Added original-session and browser-state
binding to prevent forwarded initiation/callback login CSRF.

Sensitive operations revalidate staff account/permissions and record existence.
Exchange requires a dedicated random client credential and commits consumption with
audit before returning identity.

## 3. Architecture

A two-stage browser handoff creates an opaque session-bound initiation, lets the DAM
establish browser state, then issues a short-lived code bound to that state. An InnoDB
transaction atomically consumes the code using a primary-key row lock. Code hashes and
shared rate counters work across processes. Client secret digests support one bounded
previous credential. Audit history remains in the original qualified log table.

## 4. Files

Modified:
- Koha/Plugin/Com/Library/MediaManager.pm
- Koha/Plugin/Com/Library/MediaManager/configure.tt
- Koha/Plugin/Com/Library/MediaManager/tool.tt
- build_kpz.ps1
- README.md

Added:
- Plugin modules Security.pm, Store.pm, Health.pm and Controller.pm
- Plugin continue.tt and openapi.json
- scripts/build_kpz.py and scripts/maintenance.pl
- t/security.t, store.t, plugin.t, exchange.t, lifecycle.t, browser_binding.t,
  health.t, configure.t, controller.t
- t/lib/MockKoha.pm and t/integration/concurrency.t
- docs/ARCHITECTURE.md, CONFIGURATION.md, SSO_PROTOCOL.md, SECURITY.md,
  KOHA_API_INTEGRATION.md, COMPATIBILITY.md, DEPLOYMENT.md, TESTING.md and this report

The existing error.tt was reviewed and retained. Generated MediaManager.kpz remains
ignored by Git. No development files or credentials are packaged.

## 5. Dependencies

Uses existing Koha/Perl dependencies: DBI, CGI, Modern::Perl, JSON::PP, Digest::SHA,
Bytes::Random::Secure, IO::Socket::SSL, Socket and POSIX. No new framework is introduced.
Verify module availability in the exact target instance; installation guidance is in
DEPLOYMENT.md. Standalone tests use Test::More and isolated fixtures, avoiding an
unavailable local Test::MockModule dependency.

## 6. Compatibility

26.05 is the primary source-review target. Native toolbar, plugin REST registration,
permission/session and CSRF APIs were checked against official source, with explicit
22.11/23.11 comparisons. The original assertion that the native toolbar first appears
in 23.11 was incorrect: it exists in 22.11 and takes no arguments.

The core bibliographic PUT endpoint is absent in inspected 22.11 and present in 23.11
and later inspected specs. Patron read permissions differ across releases.
COMPATIBILITY.md records source links and file revisions. No Koha release is claimed
runtime-tested; the former unconditional 22.11–26.05+ guarantee was removed.

## 7. Validation executed

- **149 assertions passed across nine isolated Perl test files.**
- Security, Store and Health standalone syntax checks passed. Main plugin and REST
  controller compile/load under isolated fixtures as part of tests.
- Real database concurrency test invoked and **skipped**, because no disposable
  MM_TEST_DSN/DBI runtime is configured.
- PowerShell KPZ build passed; ten entries have correct forward-slash paths and
  match the working source byte contents.
- OpenAPI JSON parsed by tests; explicit success/error response schemas included.
- Git whitespace/diff checks passed after fixes.

Initial tests found a Perl SQL-string interpolation error; it was fixed and audit
timestamps now use epoch conversion to UTC. All subsequent isolated tests passed.
The local prove/TAP::Harness runner is missing, so each Test::More file was executed
directly with Git's bundled Perl and its exit status/TAP plan checked.

## 8. Outstanding validation and limitations

There is no configured Koha installation, DBI/database driver or running Docker Linux
engine in this environment; no WSL distribution was listed. Live Template Toolkit,
OpenAPI registration/middleware, Koha account semantics, SQL migrations and concurrent
database consumption still need the documented staging validation.

The Python portable builder was not executed; the available Python command is an
unusable Windows application alias. The PowerShell builder was executed successfully.
No production claim is made from mocked tests.

IPv6-only diagnostics are unsupported. Reverse proxy header trust, request limits and
log redaction need deployment configuration. Middleware-generated errors can use native
Koha envelopes. DAM session revocation remains the consumer's responsibility.
Legacy v1 secret storage is preserved for rollback but unused; remove it under normal
administrative change control after migration. At-rest encryption is an operational
database responsibility.

## 9. Deployment and migration

Back up the existing plugin/settings/audit table; deploy the independent v2 consumer;
upload/enable the new KPZ; restart API workers; configure a new client credential,
instance/client IDs and staff policy; set trusted TLS/proxy controls; install the daily
maintenance command; execute the staging checklist.

V1 redirects are deliberately disabled. This is a coordinated breaking migration,
not an in-place compatible replacement for an unchanged HMAC consumer.
Uninstall invalidates pending grants and retains historical audit data.

## 10. Future Laravel contract

The independent consumer implements the start and callback URLs, browser-bound state,
server-to-server exchange, issuer/audience/state verification and its own session.
It receives only approved Koha identity, record/branch context and capabilities.
Core API access uses a separate least-privilege service account. Media processing,
storage, dashboards and MARC 856 publication remain entirely outside this repository.

SSO_PROTOCOL.md is the implementation contract; KOHA_API_INTEGRATION.md defines core
API boundaries, version differences, formats, permissions and safe update expectations.

## 2.0.1 template and CSRF correction

The configuration fields now use a shared responsive layout: labels and controls align
in columns, helpers sit below their controls, and small screens stack the fields.
The audit filter and action spacing are consistent across plugin templates.

POST forms now use Koha.GenerateCSRF with an explicitly supplied sessionID and a
nonempty plugin-generated fallback for older releases. Missing sessions or failed
token generation cannot silently render an empty token. Existing Koha middleware and
plugin token validation remain enabled. The /intranet/plugins/run.pl path in middleware
messages is not treated as a reason to bypass CSRF or change Koha core.

Validation: 167 assertions passed across ten isolated test files, including 18 new
CSRF form regressions. The package now contains eleven production files, including
layout.tt. Live Template Toolkit/browser verification is still outstanding: the local
Perl installation lacks Template Toolkit and a running Koha instance.

## 2.0.2 HTTP configuration-page correction

The HTTPS guard previously rejected configuration GET requests with HTTP 400, which
the web server could replace with Koha's generic error page. HTTP GET now renders a
read-only configuration view with an explicit HTTPS notice. Fields and Save are
disabled; server-side HTTPS enforcement still rejects HTTP POST. Existing secret and
SSO protections are unchanged. Five new regression assertions cover this behavior.

## 2.1.0 test-only HTTP mode and consumer integration

* Added an operator-only switch for isolated test networks without TLS:
  `<media_manager_insecure_http>1</media_manager_insecure_http>` inside `<config>` in the
  instance's koha-conf.xml. It is read through `C4::Context->config` only; it cannot be set
  from plugin_data or the web interface, and it is off when absent. When on, the HTTPS checks
  for the toolbar, configuration save, initiation, completion and the exchange controller are
  relaxed, an `http://` Application URL is accepted, the health test can use plain HTTP, the
  configuration and dashboard pages show a red warning, and `sso_authorization_issued` audit
  rows record `transport: insecure_http_test`. Production behaviour is unchanged when unset.
* Fixed `tool()`: an early `return` inside `eval` printed a second "Service unavailable"
  page after the access-denied or CSRF error page.
* Interoperability verified end to end against the DAM code-v2 consumer by driving this
  plugin's real `_authorize`, `_complete` and `Controller::exchange` code (Koha internals mocked
  with t/lib/MockKoha.pm) from a running DAM instance: start, continue, callback, exchange,
  state verification and session creation all succeeded; unknown code (400 invalid_grant),
  wrong secret (401 invalid_client) and replay were rejected.
* New tests: t/insecure_http.t (18), t/tool_errors.t (3).

## 2.2.0 test-only HTTP mode from the Configure page

The test-only HTTP mode can now be switched on and off by a superlibrarian with buttons on the
Configure page (`op=cud-insecure-http-on/off`: POST, Koha CSRF, audited as
`insecure_http_enabled`/`insecure_http_disabled`, stored as plugin_data `insecure_http`), so no
koha-conf.xml edit is needed. The koha-conf.xml switch remains as an alternative. All checks now go
through the plugin method `_insecure_http`; the exchange controller and health test use the same
setting. End-to-end interoperability with the DAM re-verified with only the stored setting.
New assertions in t/insecure_http.t (13); t/csrf_forms.t now checks every POST form.

## 2.2.1 page layout and breadcrumbs

* All plugin pages now follow Koha's page structure: `</head>` and `<body id="plug_mediamanager_*" class="plugins">`
  after `doc-head-close.inc` (Koha's include does not close the head), then header, breadcrumbs, content.
* Breadcrumbs restored (as in 1.0.0) via the shared `breadcrumbs.tt`, using Koha's `#sub-header nav#breadcrumbs`
  markup: Home › Administration › Plugins › Media Asset Management (MAM) › page for administrator pages, and
  Home › Cataloguing › page for the hand-off and error pages that cataloguers can see.
* Configuration form uses Koha's native `fieldset.rows` layout (right-aligned label, input, "Required" marker,
  `div.hint` aligned under the input) instead of a custom grid that conflicted with Koha's floats; shorter labels
  fit Koha's label column; narrow screens stack label, input and hint. `btn-danger` replaced by Koha's `btn-default`
  (Koha restyles all buttons, so `btn-danger` rendered white on white).
* Verified by rendering the real templates with Template Toolkit 3.106 against Koha 26.05's compiled
  staff-global.css (stand-in header/footer includes), at desktop and phone widths.

## 2.2.2 upgrade fix: stale templates after re-upload

Cause: both build scripts stamped every KPZ entry with a fixed date (2026-01-01). Koha keeps the extracted
file times, and its Template Toolkit cache recompiles a template only when the file is newer than the
cached copy, so after an upgrade Koha kept serving templates cached from an older version (including a
form without the csrf_token field: "Programming error - No CSRF token passed for POST"). Both build
scripts now stamp entries with the build time. Pages show the running plugin version. Upgrading also
requires restarting Plack so new Perl modules are loaded (see DEPLOYMENT.md "Upgrading").

## 2.2.3 exchange route fix (found on the live Koha 26.05 test server)

`POST /api/v1/contrib/media-manager/exchange` answered HTTP 500 for every request. Koha adds
`Koha::Plugin` to the REST route namespaces, so a plugin's `x-mojo-to` must be relative
(`Com::Library::MediaManager::Controller#exchange`, like other plugins' `Com::<Vendor>::<Plugin>::Controller#...`).
The fully qualified value resolved to the non-existent `Koha::Plugin::Koha::Plugin::...` class.
t/plugin.t now asserts the relative target and that it maps to the real controller module.

## 2.3.0 simplification

* Test-only HTTP mode is a single **Allow HTTP** checkbox on the Configure form (no banner or extra
  buttons). Saving over plain HTTP requires the box to be ticked; changes are audited.
* Configure page: Save, Cancel (back to the plugin list) and a **Dashboard** button on the right.
* Dashboard: **Go to MAM** button (opens `{Application URL}/staff`), "Test connection", a short status
  table and an audit log with numbered pagination (20 per page, first/previous/next/last, "Showing x–y of N").
* Shorter plugin description and README introduction.
* New test t/dashboard.t (pagination); configure/insecure_http tests updated for the checkbox.

## 2.4.0 fixes and usability

* **Configuration save no longer reports a false error.** `configure()` looked up the staff user
  inside the save transaction; `check_cookie_auth` creates a CGI::Session whose DBI driver commits
  any open transaction when it is destroyed. The settings were committed early and the final
  `commit` then failed, so "Configuration could not be saved." appeared although everything was saved.
  The lookup now happens before the transaction, and real save failures are logged to the Koha error log.
* **The MAM opens in a new tab** (`target="_blank" rel="noopener"`), so staff keep their place in Koha
  and the browser Back button no longer lands on a used single-use hand-off step.
* **Button renamed to "Attach Media"** (paperclip icon). Installs still on the old default
  "Upload Secure Media" are renamed on upgrade; custom labels are kept.
* Plugin version removed from the Configure and Dashboard page introductions.
* Build scripts moved to `scripts/`: `build_kpz.ps1`, new `build_kpz.bat` (Windows, no
  execution-policy change) and `build_kpz.sh` (Linux/macOS, wraps `build_kpz.py`). The PowerShell
  builder hashes with .NET because `Get-FileHash` is missing when started from PowerShell 7.
* Tests: configure.t regression test with a DBI-like commit mock; plugin.t covers the new tab,
  screen-reader text and label migration.
