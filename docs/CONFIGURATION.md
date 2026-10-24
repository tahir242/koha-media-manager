# Configuration

Superlibrarian access and the native Koha runner permission gate are required.
Updates require POST with Koha::Token CSRF validation, over HTTPS (or over HTTP only with **Allow HTTP**
ticked). Field names below are the labels on the Configure page.

| Setting | Validation/default |
|---|---|
| Application URL | HTTPS DNS hostname, optional port 1–65535 and simple path; no credentials, query, fragment, escapes or traversal. With Allow HTTP, `http://` and an IPv4 address are accepted |
| Allow HTTP | Checkbox; test networks without TLS only (see below); default off |
| Instance ID | 1–64 ASCII letters/digits/dot/underscore/hyphen, first alphanumeric; unique within the DAM |
| Client ID | Same syntax; one trusted application |
| Protocol | Fixed code-v2; no legacy option |
| Code lifetime | 30–120 seconds; default 60 |
| Client secret | 64 lowercase hex characters generated from 32 cryptographically random bytes; blank keeps the stored one |
| Rotation overlap | 120–3600 seconds; default 300 |
| Allowed staff | cataloguers and superlibrarians (default), or superlibrarians only |
| Toolbar label | 1–80 printable characters, HTML-escaped; default Attach Media (installs still on the old default "Upload Secure Media" are renamed on upgrade) |
| Health check IPs | Optional canonical IPv4 allowlist for **Test connection**; excludes loopback, unspecified, link-local, multicast |
| Audit retention | 1–3650 days; default 90, applied only by maintenance |

The old comma-separated permission setting remains for rollback but is not interpreted
by v2. The cataloguer policy requires catalogue AND plugins.tool AND
editcatalogue.edit_catalogue. Broad arbitrary permission names are not accepted.

New random credentials are stored as SHA-256 digests. High entropy is essential: this
is not a human password hashing scheme. Comparison processes all 64 digest characters.
Secret inputs remain blank; an empty input preserves the existing credential.

Exactly one previous digest is accepted during the overlap. Wait for overlap expiry
before rotating again. Changing instance/client/destination invalidates pending
initiations; instance/client changes also invalidate codes. Coordinate those changes.

## Test-only HTTP mode

For an isolated test network without TLS, the HTTPS requirement can be relaxed in either way:

* **Configure page (easiest):** tick **Allow HTTP** and save (superlibrarian, POST + Koha CSRF).
  Saving over plain HTTP is refused unless the box is ticked. Changes are audited as
  `insecure_http_enabled` / `insecure_http_disabled`; stored as plugin_data `insecure_http`.
  Untick it (over HTTPS) to switch it off.
* **Server operator:** add `<media_manager_insecure_http>1</media_manager_insecure_http>` inside
  `<config>` in that instance's `koha-conf.xml` and restart Plack and Apache. Remove it to disable.

Effects: the toolbar, configuration save, initiation, completion and exchange accept plain
HTTP; the Application URL may be `http://` (an IP and port are accepted); the health test
uses plain HTTP; the dashboard status table shows **Allow HTTP: Yes**; issued-code audit
rows record `transport: insecure_http_test`. Disable it before production (and replace the client
secret): codes, client secrets and staff sessions travel unencrypted while it is on.

Private destinations such as 10.20.0.8 may be explicitly approved. All resolved DNS
addresses must be approved; the connection uses a numeric IP and verifies the original
hostname. IPv6-only diagnostics are not supported. Blank disables outbound testing
without disabling SSO.
