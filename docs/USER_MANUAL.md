# Media Asset Management (MAM) for Koha — User Manual

**Version 1.0.0 (beta)** · For Koha 26.05 (minimum 22.11) · Author: Tahir Ali Channa

This manual is for **library staff and Koha administrators**: what the plugin does, how to install
and configure it, and how cataloguers use it every day. Developers and integrators should read the
[Developer Guide](DEVELOPER_GUIDE.md).

---

## Contents

1. [What it does](#1-what-it-does)
2. [How it works for staff](#2-how-it-works-for-staff)
3. [Requirements](#3-requirements)
4. [Installation](#4-installation)
5. [Configuration](#5-configuration)
6. [Connecting the MAM application](#6-connecting-the-mam-application)
7. [Who can use it](#7-who-can-use-it)
8. [Daily use](#8-daily-use)
9. [Where published media appears](#9-where-published-media-appears)
10. [The dashboard: status, connection test and audit log](#10-the-dashboard-status-connection-test-and-audit-log)
11. [Security at a glance](#11-security-at-a-glance)
12. [Maintenance](#12-maintenance)
13. [Upgrading and uninstalling](#13-upgrading-and-uninstalling)
14. [Troubleshooting](#14-troubleshooting)
15. [Frequently asked questions](#15-frequently-asked-questions)
16. [Glossary](#16-glossary)

---

## 1. What it does

**Media Asset Management (MAM) for Koha** brings digital media into the catalogue. Cataloguers attach
scanned books, PDFs, images, audio and video to a **bibliographic record** or to a **specific item
(copy)** straight from Koha — with one click and no second password.

| | |
|---|---|
| **One-click access** | An **Attach Media** button on every record, and an **Attach Media** entry in every item's **Actions** menu. |
| **Single sign-on** | Staff are signed in to the MAM automatically with their Koha identity. No extra accounts, no passwords to remember. |
| **Record and item level** | Attach media to the whole title, or to one copy — even a copy that has no barcode yet. |
| **Published into Koha** | Approved media appears in the staff interface and the OPAC: record media as an online resource (MARC 856), item media in the item's **URL** column (952$u). |
| **Koha stays in charge** | Koha decides who may attach media. Permissions are checked again at every step. |
| **Secure by design** | Short-lived single-use codes, hashed secrets, CSRF protection, rate limits and a complete audit trail. |
| **Lightweight** | The plugin stores no media and never edits records itself; the MAM application does the work through Koha's official REST API. |

The solution has two parts:

- **This Koha plugin** — the button, the menu entries, the secure sign-in, administration and audit log.
- **The MAM application** — a separate web application where files are uploaded, checked, converted for
  viewing, reviewed, approved and published back to Koha, with view statistics. It has its own repository,
  releases and [User Guide](https://github.com/tahir242/koha-mam/blob/main/docs/USER_GUIDE.md):
  **[github.com/tahir242/koha-mam](https://github.com/tahir242/koha-mam)**.

## 2. How it works for staff

```
 Koha record or item                MAM application                       Koha catalogue
 ───────────────────                ───────────────                       ──────────────
 Attach Media  ──── one click ────►  Upload files   ─► Review / approve ─►  Link appears on the
 (signed in automatically)           Processed for                          record (856) or the
                                     safe viewing                           item URL (952$u)
```

1. A cataloguer opens a record (or an item) in the Koha staff interface and chooses **Attach Media**.
2. A new browser tab opens the MAM, already signed in, on that record or item.
3. The cataloguer uploads files. The MAM validates and scans them, and prepares them for viewing
   (for example, page images for documents and streaming versions for video).
4. Depending on the library's policy, a reviewer approves the media, or trusted staff publish directly.
5. The MAM adds the link to Koha. Staff and patrons open the media in the MAM's secure viewer.

## 3. Requirements

**Koha**

- Koha **26.05** recommended (minimum **22.11**), with plugins enabled
  (`enable_plugins` in `koha-conf.xml`; on by default in Koha packages).
- MariaDB/MySQL with InnoDB (the standard Koha database).
- **HTTPS** on the staff interface for production use.
- Perl modules already used by Koha: `Bytes::Random::Secure`, `IO::Socket::SSL`, `Digest::SHA`, `JSON::PP`.
  Check them on the Koha server:

  ```bash
  perl -MBytes::Random::Secure -MIO::Socket::SSL -MDigest::SHA -MJSON::PP -e 'print "OK\n"'
  ```

**MAM application** ([koha-mam](https://github.com/tahir242/koha-mam/releases))

- Reachable from staff browsers, and able to reach the Koha staff interface (for the sign-in exchange
  and the REST API).
- For publishing back to Koha: a Koha API account with `catalogue` and `editcatalogue`
  (`edit_catalogue` for record links, `edit_items` for item links). Writing record links requires Koha 23.11 or later.

## 4. Installation

1. **Back up** the Koha database (at least the plugin tables and `plugin_data`).
2. Download `koha-media-manager-v1.0.0-beta.kpz` from the project's **GitHub Releases** page
   (or build it yourself — see the [Developer Guide](DEVELOPER_GUIDE.md#9-building-the-plugin-package)).
3. In Koha: **Administration → Plugins → Manage plugins → Upload plugin**, choose the `.kpz` file.
4. Enable the plugin if it is not already enabled.
5. Restart Koha so it loads the plugin's code and its REST route, and clear the template cache:

   ```bash
   sudo koha-plack --restart <instance>
   sudo rm -rf /var/cache/koha/<instance>/templates/*
   sudo systemctl restart apache2
   ```

6. **Check the route.** This request must answer `401 invalid_client` (or `400 https_required` on plain
   HTTP before *Allow HTTP* is ticked) — **not** `404`:

   ```bash
   curl -i -X POST https://<koha-staff>/api/v1/contrib/media-manager/exchange
   ```

Installation creates four small tables (audit log, sign-in codes, sign-in requests, rate counters) and
default settings. It creates no scheduled jobs and changes no records.

## 5. Configuration

Open **Administration → Plugins → Media Asset Management (MAM) → Actions → Configure**
(superlibrarians only).

| Field | What to enter | Default |
|---|---|---|
| **Application URL** | Address of the MAM, e.g. `https://mam.example.org`. Must be HTTPS (HTTP and an IP:port are accepted only with *Allow HTTP*). | — |
| **Allow HTTP** | Tick only on an isolated test network without HTTPS. | off |
| **Instance ID** | A short name for this Koha (letters, digits, `.`, `_`, `-`; up to 64). Must match the MAM. | — |
| **Client ID** | The MAM's name in this integration (same rules). Must match the MAM. | — |
| **Client secret** | 64 lowercase hexadecimal characters, e.g. from `openssl rand -hex 32`. Must match the MAM. Leave blank to keep the stored secret. | — |
| **Rotation overlap** | Seconds the previous secret keeps working after you set a new one (120–3600). | 300 |
| **Code lifetime** | Seconds a sign-in code stays valid (30–120). | 60 |
| **Allowed staff** | *Cataloguers and superlibrarians*, or *Superlibrarians only*. | cataloguers |
| **Toolbar label** | Text of the button and menu entries (1–80 characters). | Attach Media |
| **Health check IPs** | IPv4 addresses the connection test may contact. Blank disables the test (sign-in still works). | — |
| **Audit retention** | Days to keep audit entries (1–3650). Applied by the maintenance job. | 90 |

Good to know:

- The secret is stored only as a one-way hash and is **never shown again**.
- Saving over plain HTTP is refused unless **Allow HTTP** is ticked; every change is recorded in the audit log.
- Changing the Instance ID, Client ID or Application URL cancels sign-ins that are in progress —
  plan such changes together with the MAM administrator.

### Rotating the client secret

1. Generate a new secret (`openssl rand -hex 32`) and save it in the plugin.
2. Put the same secret in the MAM within the **rotation overlap** (default 5 minutes).
   During the overlap both the old and the new secret work.
3. Wait for the overlap to end before rotating again.

### Test networks without HTTPS (Allow HTTP)

For an isolated test network only, tick **Allow HTTP**. Sign-in codes, secrets and sessions then travel
unencrypted, so **untick it and replace the secret before going live**. A server administrator can
also enable it for one instance in `koha-conf.xml`
(`<media_manager_insecure_http>1</media_manager_insecure_http>` inside `<config>`).
While it is on, the dashboard shows **Allow HTTP: Yes**.

## 6. Connecting the MAM application

The MAM must hold the same values as the plugin. In the MAM's `.env`:

```dotenv
APP_URL=https://mam.example.org                 # = plugin "Application URL"
KOHA_INSTANCE_ID=mylibrary                      # = plugin "Instance ID"
KOHA_STAFF_URL=https://staff.koha.example.org   # Koha staff interface
KOHA_SSO_CLIENT_ID=koha-mam                     # = plugin "Client ID"
KOHA_SSO_CLIENT_SECRET=<64 hex characters>      # = plugin "Client secret"
```

Then, on the MAM server, reload its configuration and run its built-in check:

```bash
php artisan config:cache
php artisan dam:sso:doctor
```

Finally, open the plugin's dashboard and press **Test connection**.

## 7. Who can use it

| Koha staff member | Needs these Koha permissions | Can do in the MAM |
|---|---|---|
| **Cataloguer** | `catalogue` **and** `plugins → tool` **and** `editcatalogue → edit_catalogue` | View and upload media (`media.access`, `media.upload`) |
| **Superlibrarian** | (all) | Everything, including management and administration |

- With **Allowed staff = Superlibrarians only**, cataloguers do not see the button.
- Locked, expired, lost-card, gone-no-address or debarred accounts are refused.
- OPAC (patron) sessions are never accepted.
- Configuration, the dashboard and the audit log are for superlibrarians only.
- Koha's permissions are an upper limit: the MAM never gives a staff member more than Koha allows.

## 8. Daily use

### Attach media to a record

1. Open the record in the staff interface (**Catalog → record details**).
2. Click **Attach Media** in the toolbar. The MAM opens in a new tab on that record.
3. Drag files into the upload area. Large files (video, for example) are uploaded in parts and can be
   paused or cancelled.
4. Follow the status: *Uploaded → Processing → Ready for review → Published*.

### Attach media to an item (a specific copy)

1. On the record's **Holdings** table, open the item's **Actions** menu
   (the small arrow next to **Edit**) and choose **Attach Media** — or, on **Edit items**
   (*Add/Edit item* page), open the item's **Actions** menu and choose **Attach Media**.
2. The MAM opens on that item and shows **Item #&lt;number&gt;** with its barcode, copy number and
   call number when Koha has them. Files uploaded there belong to that item.

Tips:

- **New items:** save the item first (**Add item**). The entry appears in its Actions menu as soon as
  the item exists.
- **No barcode yet?** No problem. Items are identified by their item number, which every saved item
  has. The barcode is shown once it is assigned.
- **Return to Koha** with the links at the top of the MAM page, or simply switch back to the Koha tab.

## 9. Where published media appears

| Attached to | Shown in Koha as | Where staff and patrons see it |
|---|---|---|
| **Record** | An online resource link (MARC **856**) | Record details in the staff interface and the OPAC |
| **Item** | The item's **URL** (MARC **952$u**, `items.uri`) | **URL** column of the holdings table, staff interface and OPAC |

- Each item has **one** link, however many files it has: the link opens the file directly, or a list
  when the item has several.
- A URL catalogued by hand on the item is kept; the MAM link is added after it.
- Unpublishing removes only the MAM's own link (for an item, once none of its media is published).
- Patrons see public media only; media marked *restricted* is shown to signed-in staff only.

## 10. The dashboard: status, connection test and audit log

Open **Plugins → Media Asset Management (MAM) → Actions → Run tool** (superlibrarians only).

- **Go to MAM** opens the MAM; **Configure** opens the settings.
- **Status** shows whether the plugin is configured, the Application URL, *Allow HTTP*, the last
  connection test and whether the plugin's tables are available.
- **Test connection** checks that the MAM answers and advertises the expected protocol
  (for example "HTTP 200; protocol advertised"). It does not sign anybody in.
- **Audit log** lists every sign-in and administrative action, 20 per page, filterable by event.
  Common events:

| Event | Meaning |
|---|---|
| `sso_authorization_started` | A staff member clicked Attach Media |
| `sso_authorization_issued` | Koha issued a one-time sign-in code |
| `sso_exchange_success` | The MAM signed the staff member in |
| `sso_exchange_failed`, `sso_replay_rejected`, `sso_code_expired` | A sign-in was refused (wrong credentials, reused or expired code) |
| `permission_denied` | The staff member lacks the required permissions |
| `configuration_updated` | Settings were saved |
| `insecure_http_enabled` / `insecure_http_disabled` | *Allow HTTP* was switched on or off |
| `connection_test_success` / `connection_test_failed` | Result of **Test connection** |

Each entry carries a correlation ID that also appears in the MAM's logs, so one sign-in can be traced
across both systems.

## 11. Security at a glance

- **No passwords leave Koha.** The browser only ever carries random, single-use values; the identity is
  handed over directly between the two servers.
- **Short-lived, single-use codes** (60 seconds by default), stored only as hashes.
- **Bound to the browser:** a forwarded or copied sign-in link does not work in another session.
- **Permissions checked twice:** when the code is issued and again when it is redeemed.
- **Hashed client secret** with a safe rotation window.
- **CSRF protection** on every form; administration for superlibrarians only.
- **Rate limits:** 20 sign-ins per staff member per minute; 60 exchanges per address and 600 in total per minute.
- **Complete audit trail** with retention control. Secrets and codes are never written to the log.

For production, also follow the server checklist in the
[Developer Guide → Security model](DEVELOPER_GUIDE.md#6-security-model) (HTTPS, proxy and log settings).

## 12. Maintenance

The plugin creates no scheduled jobs. Install the maintenance script once and run it daily; it
removes expired sign-in data and applies the audit retention:

```bash
sudo mkdir -p /opt/koha-media-manager/scripts
sudo cp scripts/maintenance.pl /opt/koha-media-manager/scripts/
sudo koha-shell <instance> -c "perl /opt/koha-media-manager/scripts/maintenance.pl --run"
```

Schedule the last command daily (for example with cron) in the instance's environment.

## 13. Upgrading and uninstalling

**Upgrade**

1. Back up the database.
2. Upload the new `.kpz` over the installed plugin. Settings and the audit log are kept.
3. Restart Plack, clear the template cache and restart Apache (as in [Installation](#4-installation)).
4. Open any record once: the plugin re-registers its menu entries if Koha missed them during the upload.

> **Moving to 1.0.0 from a pre-release build (2.x):** Koha only runs upgrades for a *higher* version
> number. Uninstall the old plugin, then install 1.0.0. The audit log is kept; settings must be
> entered again.

**Uninstall** removes the sign-in and rate tables (sign-ins in progress stop working) and keeps the
audit log for your records. Links already published in Koha are not removed — unpublish them in the MAM first
if you want them gone.

## 14. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| No **Attach Media** button on a record | Plugin disabled or not configured; on plain HTTP *Allow HTTP* not ticked; the staff member lacks the [permissions](#7-who-can-use-it). |
| No **Attach Media** in an item's Actions menu | Same causes as above; the item is not saved yet; the staff member cannot edit items (no Actions menu); after an upgrade, open any record once or restart Plack. |
| "Access denied" on `run.pl` | Koha requires the `plugins → tool` permission for any tool plugin. |
| Old layout after an upgrade, or "No CSRF token passed" | Template cache not cleared or Plack not restarted. |
| "Koha is opened over plain HTTP…" when saving | Tick *Allow HTTP* (test only) or use HTTPS. |
| Exchange answers `404` | Plugin not enabled, or Plack/API workers not restarted. |
| Exchange answers `401 invalid_client` | Client ID or secret differ between Koha and the MAM, or the rotation overlap ended. |
| Exchange answers `400` | The code expired, was already used, or belongs to another browser: click Attach Media again. |
| Exchange answers `429` | Rate limit reached; wait one minute. |
| **Test connection** fails | The MAM's IP is not in *Health check IPs*; DNS, firewall or certificate problem; or the MAM is down. |
| Published item media not shown in Koha | The MAM's publication worker is not running, or its Koha API account lacks `edit_items`. |
| Audit entries are never removed | The maintenance job is not scheduled. |

Logs: the plugin's audit log; Koha's `/var/log/koha/<instance>/plack-error.log` and `api-error.log`.

## 15. Frequently asked questions

**Does the plugin store our files in Koha?**
No. Files are stored and served by the MAM. Koha holds only the links.

**Does it change our catalogue records?**
The plugin never does. The MAM adds or removes only its own links (856 on records, the URL on items)
through Koha's official API, and leaves every other field untouched.

**Do staff need a separate account or password?**
No. Their Koha login is used; the MAM creates its user record automatically on first sign-in.

**Can patrons see the media?**
Published public media, yes — through the links in the OPAC. Restricted media is staff-only.

**Can we attach media to an item without a barcode?**
Yes. Items are identified by item number.

**What if Koha and the MAM disagree about permissions?**
Koha wins. The MAM never grants more than the capabilities Koha sends at sign-in.

**Which Koha versions are supported?**
Koha 26.05 is the tested target; the plugin is designed for 22.11 and later. Test your exact version on a
staging server first.

## 16. Glossary

| Term | Meaning |
|---|---|
| **MAM** | Media Asset Management — the application where media is uploaded, reviewed and published. |
| **Record** | A Koha bibliographic record (title). |
| **Item** | One physical copy of a record, with its own item number (and usually a barcode). |
| **856** | The MARC field for online resources on a record. |
| **952$u** | The MARC subfield for an item's URL (`items.uri`). |
| **Client ID / secret** | The credentials the MAM uses to redeem sign-in codes at Koha. |
| **Instance ID** | The name that identifies this Koha to the MAM. |
| **Capabilities** | What a staff member may do in the MAM, derived from their Koha permissions. |
| **KPZ** | The plugin package file uploaded to Koha. |
