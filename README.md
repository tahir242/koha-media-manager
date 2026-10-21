# Media Asset Management (MAM) – Koha Plugin

**Version:** 1.0.0 (initial beta)  
**Compatibility:** Koha 22.11 – 26.05+  
**Author:** Tahir Ali Channa

**Repository:** https://github.com/tahir242/koha-media-manager

This is the initial beta release. Validate the plugin on a test Koha instance
before installing it in production.

## Overview

This Koha plugin provides seamless **Single Sign-On (SSO)** between the Koha
staff interface and a Media Asset Management (MAM) application. Staff click a
single button on any bibliographic detail page and are securely redirected to
the MAM upload dashboard — no separate login required.

## Features

| Feature | Description |
|---------|-------------|
| **HMAC-SHA256 SSO** | Cryptographically signed redirect tokens with configurable TTL |
| **Toolbar Button** | "Upload Secure Media" button injected on catalogue detail pages |
| **Dual Hook Strategy** | Uses both the native `toolbar_button` hook (Koha ≥ 23.11) and `intranet_js` fallback with deduplication |
| **Permission Gating** | Configurable Koha permission requirements; superlibrarians always pass |
| **Audit Logging** | Every redirect, denial, and connection test logged to a dedicated table |
| **Health Dashboard** | Built-in status page with connection testing and activity log viewer |
| **Auto-Cleanup** | Log entries older than 90 days are automatically purged |
| **Clean Lifecycle** | Proper `install()`, `upgrade()`, and `uninstall()` hooks |

## Installation

1. **Clone the repository and build the KPZ file** using PowerShell:
   ```powershell
   git clone https://github.com/tahir242/koha-media-manager.git
   cd koha-media-manager
   .\build_kpz.ps1
   ```
   This produces `MediaManager.kpz`. Generated archives are excluded from Git.

2. **Upload to Koha:**  
   Go to **Koha → Administration → Plugins → Upload plugin** and select the
   `.kpz` file.

3. **Configure:**  
   After installation, click **Configure** on the plugin and enter:
   - **MAM URL** — e.g. `https://media.yourlibrary.com`
   - **Shared Secret** — a long random string matching `KOHA_SSO_SECRET` in
     MAM's `.env`
   - **Token TTL** — how long tokens are valid (default 300 seconds)
   - **Button Label** — text for the toolbar button
   - **Allowed Permissions** — comma-separated Koha permissions
     (e.g. `editcatalogue,superlibrarian`)

   If replacing an earlier development build, re-enter and save the MAM URL
   in Configure. The application URL setting is now stored as `mam_url`.

## SSO Flow

```
┌──────────────────┐     HMAC-signed redirect      ┌──────────────────┐
│   Koha Staff UI  │ ─────────────────────────────► │       MAM        │
│                  │                                │                  │
│  catalogue/      │  userid, borrowernumber,       │                  │
│  detail.pl       │  biblio_id, timestamp,         │  /sso/koha       │
│                  │  ttl, name, branch,            │                  │
│  [Upload Media]  │  signature                     │  Verifies HMAC → │
│     button       │                                │  Creates session │
└──────────────────┘                                └──────────────────┘
```

### Payload Format

The HMAC signature covers: `userid|borrowernumber|biblionumber|timestamp`

MAM must reconstruct this string from the query parameters and verify it
with the shared secret using HMAC-SHA256. Reject the token if
`current_time - timestamp > ttl`.

## MAM Integration

On the MAM side, create a route handler for `/sso/koha` that:

1. Extracts query parameters: `userid`, `borrowernumber`, `biblio_id`,
   `timestamp`, `ttl`, `name`, `branch`, `signature`
2. Reconstructs the payload: `"$userid|$borrowernumber|$biblio_id|$timestamp"`
3. Computes `hash_hmac('sha256', $payload, $secret)` and compares with
   `$signature`
4. Verifies `time() - $timestamp <= $ttl`
5. Creates/finds the user session and redirects to the upload page for the
   given `biblio_id`

## File Structure

```
MediaManager/
├── Koha/
│   └── Plugin/
│       └── Com/
│           └── Library/
│               ├── MediaManager.pm          # Main plugin module
│               └── MediaManager/
│                   ├── configure.tt         # Configuration form
│                   ├── tool.tt              # Dashboard template
│                   └── error.tt             # Error display template
├── build_kpz.ps1                            # KPZ packaging script
└── README.md                                # This file
```

## Uninstallation

Click **Uninstall** in Koha's plugin manager. The plugin will:
- Drop the `koha_plugin_com_library_mediamanager_log` audit table
- Koha automatically removes all `plugin_data` rows for this plugin

## License

This plugin is provided as-is for library use. Modify freely to suit your
institution's requirements.
