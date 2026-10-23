# Security review and operational controls

## Findings and remediation

| V1 finding | V2 change |
|---|---|
| TTL/name/branch outside HMAC; reusable signed URLs | Removed v1 flow; opaque one-time codes with server-side context |
| Forwarded callback/session confusion | Initiation bound to original Koha session; code bound to consumer browser state |
| No atomic replay control | InnoDB primary-key row lock, consume + audit transaction |
| Broad wildcard permission configuration | Validated named policy mapped to real Koha subpermissions; recheck at exchange |
| Cached flags / no account-state checks | Current patron and permissions checked at sensitive boundaries |
| Nonexistent/zero biblio accepted | Positive bounded integer and Koha::Biblios existence checks |
| Secret echoed to password input | Blank replacement field, hash-only new credentials, bounded rotation |
| Missing plugin CSRF checks | Koha::Token plus POST for all mutations |
| Fragile JavaScript string interpolation | Native hook and HTML escaping; continuation script has no interpolated data |
| Unrestricted outbound diagnostic | Explicit IPv4 approval, DNS validation, pinned connection, TLS verification, no redirects |
| Random request-time audit cleanup | Explicit bounded daily maintenance |
| Silent database failures | Sensitive operations fail closed; no identity response before audit commit |
| Destructive audit uninstall | Historical logs retained |

## TLS, proxy and logs

Require HTTPS for staff, DAM, return and exchange URLs. The only exception is the test-only
**Allow HTTP** checkbox (or the koha-conf.xml switch) for an isolated test network; turn it off and
replace the client secret before production, because codes, secrets and cookies then travel unencrypted. CGI checks HTTPS=on/1; REST
checks the absolute request scheme. Configure only trusted reverse proxies to convey
TLS termination correctly. The plugin does not trust arbitrary forwarded headers.
Ensure staff/DAM cookies are Secure, HttpOnly and SameSite=Lax for top-level returns.

Both applications and the proxy must redact query strings on start/return/callback
paths and avoid request/response body or X-Media-Secret header logging. Plugin logs
contain neither raw codes nor secrets. Initiations and state are also sensitive:
do not add them to logs or analytics. Disable debug middleware that captures credentials.
Clear callback parameters by redirecting immediately to a clean URL.
Set Cache-Control: no-store and Referrer-Policy: no-referrer at the proxy for all
handoff paths, including the Koha continuation page and middleware-generated failures.
The plugin already adds these on redirects/exchange; its rendered pages disable caching
and the continuation page includes a no-referrer meta directive.

Code leakage has a short window and requires the client credential, but that is not
a substitute for logging controls. A compromised DAM client or Koha administrator is
outside this bridge's ability to defend; restrict database, configuration and backup access.

## Storage and secrets

New client credentials are random 256-bit values stored only as SHA-256 digests.
Only the current and immediately previous digest are used. Database encryption-at-rest
is not provided by the plugin. Patron/context/audit data need normal database/backup
access controls and institution-defined retention.

Legacy v1 shared_secret remains in plugin_data to preserve rollback configuration.
It is not used or rendered. After the rollback window, an administrator should remove
that obsolete key and rotate/revoke it in any former consumer. This release does not
silently erase existing production settings.

A predictable random generator must never replace Bytes::Random::Secure. The isolated
test fixture is intentionally deterministic and must never be on production PERL5LIB.

## Abuse and authorization boundaries

Database rate counters protect validly routed exchange requests. Add proxy request-size
and rate limits for malformed requests rejected before the controller, distributed
attacks and connection exhaustion. The direct peer address is used, so reverse-proxy
deployments may share a rate bucket. Counter tables require scheduled maintenance.
Rate-limit rejections are represented by counters/HTTP 429; they are not individually
inserted into the audit table to avoid unbounded audit amplification.

The new policy intentionally denies accounts with restrictions, expired membership,
lost-card/invalid-address flags or administrative lockout. Removing those flags and
permissions revokes future exchanges; issued DAM sessions need their own lifecycle.
No remote logout/session revocation channel is implemented.

Configuration changes require a superlibrarian, but configuring a malicious trusted
application inherently delegates the integration. Destination IP approval is an explicit
administrative decision. Pinning prevents DNS rebinding; private institution hosts
remain allowed. Loopback/link-local endpoints and redirects are blocked; plain HTTP is used only while
**Allow HTTP** is on.

Audit source IP/user/record fields are personal operational data. Only superlibrarians
can view them. Retention runs separately; active grants are never selected for deletion.
Use DB/server monitoring to detect audit write failures without logging raw request data.
