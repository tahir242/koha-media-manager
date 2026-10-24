# Koha Media Manager

Version **2.4.0** · Koha 26.05 (minimum 22.11) · Author: Tahir Ali Channa

Adds an **Attach Media** button to every bibliographic record in the Koha staff
interface. One click signs the staff member in to the Digital Asset Management (MAM)
application (no second password) and opens that record there, where files are uploaded,
reviewed and published. The plugin stores no media and never edits records itself.

**What you configure:** the MAM address, an instance ID, a client ID and a shared secret
(the same values go into the MAM's `.env`). **What you get:** the toolbar button, a dashboard
with a connection test, a link to the MAM and a paginated audit log of every sign-in.

**Tested on:** a live Koha 26.05 server together with the MAM (sign-in, metadata, upload,
publishing of the 856 link), plus 228 isolated Perl tests.
See [compatibility evidence](docs/COMPATIBILITY.md).

---

## Contents

1. [How it works](#how-it-works)
2. [Features](#features)
3. [Requirements](#requirements)
4. [Build](#build)
5. [Install](#install)
6. [Configure](#configure)
7. [Staff permissions](#staff-permissions)
8. [Dashboard](#dashboard)
9. [The MAM side](#the-mam-side)
10. [Upgrade and uninstall](#upgrade-and-uninstall)
11. [Maintenance](#maintenance)
12. [Tests](#tests)
13. [Troubleshooting](#troubleshooting)
14. [Repository layout](#repository-layout)
15. [Documentation](#documentation)

---

## How it works

The plugin implements the **code-v2** hand-off: the browser only ever carries opaque,
single-use values, and identity is handed over server-to-server.

```
Staff clicks "Attach Media" on a record (opens in a new tab) (POST + Koha CSRF token)
 Koha ──303──► MAM  /sso/koha/start?request={64 hex}          opaque initiation, bound to the Koha session
 MAM  ──303──► Koha run.pl?…&op=continue&request&state        MAM adds its own single-use browser state
 Koha (auto-POST op=cud-complete, same staff session)          permissions re-checked, code issued (60 s)
 Koha ──303──► MAM  /sso/koha?code={64 hex}&state
 MAM  ──POST─► Koha /api/v1/contrib/media-manager/exchange    X-Media-Client / X-Media-Secret, {"code"}
 Koha ──200──► identity, record, branch, capabilities          code consumed; permissions re-checked again
 MAM signs the staff member in and opens the record workspace
```

Exchange response fields: `success`, `protocol`, `iss` (instance ID), `aud` (`media-manager`),
`identity {provider, instance, patron_id, userid}`, `context {biblio_id, branch}`,
`capabilities`, `issued_at`, `expires_at`, `correlation_id`, `state`.
The full contract for any consuming application is in [docs/SSO_PROTOCOL.md](docs/SSO_PROTOCOL.md).

## Features

- **Toolbar button** on the record detail page (native hook, shown only to authorized staff on an existing record).
- **No passwords handed over:** opaque, short-lived (30–120 s), single-use authorization codes; no identity in the browser URL.
- **Browser binding:** the initiation is bound to the originating Koha session, and the MAM's state is
  echoed back through the exchange, which blocks forwarded-link and login-CSRF attacks.
- **Koha stays in charge of permissions:** an explicit permission policy, checked when the code is issued
  and again at exchange; the MAM never grants more than the returned capabilities.
- **Hashed client secret** (SHA-256 of a 256-bit random value) with a rotation overlap window.
- **CSRF-protected administration**, superlibrarian only.
- **Rate limits:** 20 initiations per staff member per minute; 60 exchanges per IP and 600 in total per minute.
- **Audit log** with structured events and correlation IDs shared with the MAM, pagination,
  event filter and scheduled retention.
- **Connection test** to the MAM's `/.well-known/koha-media-manager`, limited to approved IP addresses.
- **Test-only HTTP mode:** an **Allow HTTP** checkbox for isolated test networks without TLS.

## Requirements

- Koha 26.05 (minimum 22.11) with plugins enabled (`enable_plugins` in `koha-conf.xml`, on by default in packages).
- MariaDB/MySQL (the Koha database).
- HTTPS on the staff interface for production (plain HTTP only with **Allow HTTP** on a test network).
- The MAM (or another code-v2 consumer) reachable from staff browsers, and able to reach Koha's REST API.
- To build: PowerShell 5+ **or** Python 3.8+. To run tests: Perl 5 with `Test::More` (`prove`).

## Build

All builders write `MediaManager.kpz` to the repository root and print its SHA-256.

```powershell
scripts\build_kpz.bat           # Windows: double-click or run from cmd (no execution-policy change needed)
./scripts/build_kpz.ps1         # Windows PowerShell
```

```bash
./scripts/build_kpz.sh          # Linux/macOS (needs Python 3.8+)
python3 scripts/build_kpz.py    # same, called directly
```

The KPZ entries carry the build time, so Koha's template cache picks up changed templates after an upgrade.

## Install

1. Back up the Koha database (at least the plugin tables and `plugin_data`).
2. **Administration → Plugins → Manage plugins → Upload plugin**, choose `MediaManager.kpz`.
3. Enable the plugin if it is not enabled.
4. Restart Plack so Koha registers the plugin's REST route, and clear the template cache:

   ```bash
   sudo koha-plack --restart <instance>
   sudo rm -rf /var/cache/koha/<instance>/templates/*
   sudo systemctl restart apache2
   ```

5. Check the route: `curl -i -X POST http://<koha-staff>/api/v1/contrib/media-manager/exchange`
   should answer `401 invalid_client` (or `400 https_required` over HTTP before **Allow HTTP** is ticked), not `404`.

Installation creates four tables (`…_log`, `…_codes`, `…_requests`, `…_rates`) and default settings.

## Configure

**Plugin → Actions → Configure** (superlibrarians only). The page has **Save configuration**,
**Cancel** and, on the right, **Dashboard**.

| Field | Value / rule | Default |
|---|---|---|
| Application URL | Address of the MAM, e.g. `https://dam.example.org` (HTTP and IP:port allowed only with Allow HTTP) | — |
| Allow HTTP | Tick only on an isolated test network without HTTPS | off |
| Instance ID | 1–64 letters/digits/`._-`; must equal the MAM's `KOHA_INSTANCE_ID` | — |
| Client ID | Same syntax; must equal the MAM's `KOHA_SSO_CLIENT_ID` | — |
| Client secret | 64 lowercase hex characters (`openssl rand -hex 32`); must equal `KOHA_SSO_CLIENT_SECRET`. Leave blank to keep the stored one | — |
| Rotation overlap | Seconds the previous secret is still accepted after a change (120–3600) | 300 |
| Code lifetime | Seconds an authorization code is valid (30–120) | 60 |
| Allowed staff | Cataloguers and superlibrarians, or superlibrarians only | cataloguers |
| Toolbar label | Button text (1–80 characters) | Attach Media |
| Health check IPs | IPv4 addresses the connection test may contact (blank disables the test) | — |
| Audit retention | Days to keep audit rows (1–3650) | 90 |

The secret is stored only as a hash and is never shown again. Saving over plain HTTP is refused
unless **Allow HTTP** is ticked. Every change is audited. Details: [docs/CONFIGURATION.md](docs/CONFIGURATION.md).

## Staff permissions

| Koha user | Needs | Gets (capabilities sent to the MAM) |
|---|---|---|
| Cataloguer | `catalogue` **and** `plugins → tool` **and** `editcatalogue → edit_catalogue` | `media.access`, `media.upload` |
| Superlibrarian | (all) | `media.access`, `media.upload`, `media.manage`, `media.admin` |

`edit_items` alone is not enough. With **Allowed staff = superlibrarians only**, cataloguers get nothing.
Locked, expired, lost, gone-no-address or debarred accounts are refused, and OPAC sessions are never accepted.
Configuration and the dashboard are superlibrarian-only.

## Dashboard

**Plugin → Actions → Run tool** (superlibrarians only):

- **Go to MAM** opens the MAM dashboard; **Configure** returns to the settings.
- **Status:** Configured, Application URL, Allow HTTP, Connection (last test), Storage.
- **Test connection** fetches the MAM's `/.well-known/koha-media-manager` and shows the result, e.g.
  "HTTP 200; protocol advertised", and **Connection: OK** in the status table. A successful test does
  not prove that sign-in works end to end.
- **Audit log:** 20 rows per page with page links and "Showing x–y of N", filterable by event name. Events include
  `sso_authorization_started`, `sso_authorization_issued`, `sso_exchange_success`, `sso_exchange_failed`,
  `permission_denied`, `configuration_updated`, `insecure_http_enabled` / `insecure_http_disabled`,
  `connection_test_success` / `connection_test_failed`.

## The MAM side

The MAM needs the matching values in its `.env`:

```dotenv
APP_URL=http://10.1.89.51:8015            # = plugin "Application URL"
KOHA_INSTANCE_ID=mylib                    # = plugin "Instance ID"
KOHA_STAFF_URL=http://10.1.10.50:7002     # Koha staff interface (exchange endpoint lives here)
KOHA_SSO_CLIENT_ID=koha-dam               # = plugin "Client ID"
KOHA_SSO_CLIENT_SECRET=<64 hex>           # = plugin "Client secret"
DAM_ALLOW_INSECURE_HTTP=true              # only while "Allow HTTP" is ticked
```

then `php artisan config:cache` and `php artisan dam:sso:doctor` on the MAM. The MAM's README and its
`docs/TEST_SETUP_KOHA_PLUGIN.md` give the full joint setup and end-to-end test.

## Upgrade and uninstall

**Upgrade:** build a new KPZ, upload it over the old one (settings and audit rows are kept), then
restart Plack, clear the template cache and restart Apache as in [Install](#install).

**From v1:** the v1 HMAC redirect is retired (answers "Protocol retired"). Existing settings and
audit rows are kept, but v2 must be configured explicitly and the MAM must use code-v2.
See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

**Uninstall** drops the code, initiation and rate tables (pending sign-ins stop working) and keeps the audit log.

## Maintenance

Install a daily job that purges expired codes and applies audit retention (installation does not create cron jobs):

```bash
sudo cp scripts/maintenance.pl /opt/koha-media-manager/scripts/
sudo koha-shell <instance> -c "perl /opt/koha-media-manager/scripts/maintenance.pl --run"
```

Rotate the client secret by entering a new one (update the MAM within the overlap window).
After testing over HTTP, untick **Allow HTTP** over HTTPS and replace the secret.

## Tests

```bash
prove -v t/*.t                     # 228 isolated tests with a mocked Koha (t/lib/MockKoha.pm)
prove -v t/integration/concurrency.t   # needs a real Koha database
```

Validate the full flow on a staging Koha with the MAM before production: [docs/TESTING.md](docs/TESTING.md).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| No toolbar button | Plugin disabled or not configured; on HTTP, **Allow HTTP** not ticked; record does not exist; staff user lacks the permissions above |
| "Access denied" at run.pl | Koha requires `plugins → tool` to run any tool plugin |
| Old page layout after upgrade, or "No CSRF token passed" | Template cache not cleared or Plack not restarted |
| "Koha is opened over plain HTTP: tick Allow HTTP…" on save | Tick **Allow HTTP**, or use HTTPS |
| Exchange `404` | Plugin not enabled, or Plack/API workers not restarted |
| Exchange `401 invalid_client` | Client ID/secret differ from the MAM, or the rotation overlap expired |
| Exchange `400` | Code expired, reused or for another browser; click the button again |
| Exchange `429` | Rate limit reached; wait a minute |
| Connection test fails | MAM IP not in **Health check IPs**, DNS/firewall/certificate problem, or MAM down |
| Audit rows never purged | Maintenance job not scheduled |

Logs: the plugin dashboard audit log; Koha's `/var/log/koha/<instance>/plack-error.log` and `api-error.log`.

## Repository layout

```
Koha/Plugin/Com/Library/MediaManager.pm   plugin class: install/upgrade, toolbar hook, configure, tool, dashboard
  MediaManager/Controller.pm              REST exchange endpoint
  MediaManager/Store.pm                   codes, initiations, rate limits (atomic SQL)
  MediaManager/Security.pm                validation, secret hashing, HTTP switch
  MediaManager/Health.pm                  connection test (approved IPs, no redirects)
  MediaManager/openapi.json               REST route definition
  MediaManager/*.tt                       configure, dashboard, continue, error pages, layout, breadcrumbs
scripts/build_kpz.{ps1,bat,py,sh}         KPZ builders (.bat wraps .ps1, .sh wraps .py)
scripts/maintenance.pl                    daily purge and retention
t/                                        tests (t/lib/MockKoha.pm, t/integration)
docs/                                     detailed documentation
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [SSO protocol and consumer contract](docs/SSO_PROTOCOL.md)
- [Configuration](docs/CONFIGURATION.md)
- [Security review](docs/SECURITY.md)
- [Koha API integration](docs/KOHA_API_INTEGRATION.md)
- [Compatibility evidence](docs/COMPATIBILITY.md)
- [Deployment and migration](docs/DEPLOYMENT.md)
- [Testing and staging validation](docs/TESTING.md)
- [Engineering report](docs/ENGINEERING_REPORT.md)

## License

The original repository states that this plugin is provided as-is for library use and
may be modified for institutional requirements. This change does not substitute a new
license for that statement.
