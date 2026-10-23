# SSO protocol: code-v2

This confidential-client authorization exchange is not an OAuth2/OIDC provider.
Koha's own OAuth2 API authentication is separate. The consumer is the separate SIUT DAM
application (Laravel, `App\Auth\Sso\CodeExchangeAdapter`); it is not part of this repository.

## URLs

- DAM start: **GET {base}/sso/koha/start?request={opaque_initiation}**
- Koha return: **GET https://staff.example.org/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ALibrary%3A%3AMediaManager&method=tool&op=continue&request={opaque_initiation}&state={state}**
- DAM callback: **GET {base}/sso/koha?code={opaque_code}&state={state}**
- Exchange: **POST https://staff.example.org/api/v1/contrib/media-manager/exchange**

The DAM must configure the exact trusted Koha return and exchange URLs. Never accept
caller-supplied return URLs, instance URLs or exchange destinations.

## Sequence

~~~mermaid
sequenceDiagram
    participant B as Staff browser
    participant K as Koha plugin
    participant D as DAM
    B->>K: Toolbar POST + Koha CSRF + biblio
    K->>K: Validate staff and record; bind initiation to session
    K-->>B: 303 DAM start with opaque request
    B->>D: Start
    D->>D: Create random state bound to browser session
    D-->>B: 303 fixed Koha return URL with request and state
    B->>K: GET continue with staff cookie
    K-->>B: Local auto-submit form + Koha CSRF
    B->>K: POST complete
    K->>K: Consume initiation; check same session; issue code bound to state
    K-->>B: 303 fixed DAM callback with code and state
    B->>D: Callback with same DAM session
    D->>D: Verify browser state
    D->>K: Authenticated server POST with code
    K->>K: Lock code; validate bindings and staff; consume + audit
    K-->>D: Identity, context, capabilities, state
    D->>D: Verify returned state/issuer/audience; rotate session ID
    D-->>B: 303 clean asset URL
~~~

## Browser binding

Initiations contain 256 random bits, expire after 120 seconds, and are bound to a hash
of the originating staff session. They contain no identity and cannot be exchanged.
A forwarded initiation fails under another Koha session. JavaScript-disabled users
can press Continue on the local completion page.

The DAM generates at least 256 random bits of state, encoded as 43–128 base64url
characters (A-Z, a-z, 0-9, underscore, hyphen). Associate state server-side with the
browser session and pending initiation; expire it within 120 seconds and permit one
use. Use Secure, HttpOnly, SameSite=Lax cookies. Concurrent tabs need distinct states.

Reject unsolicited/mismatched state BEFORE exchanging a callback. Afterwards compare
the exchange response state with the same pending browser state. Never establish or
replace a session merely because a code exists. The returned-state check prevents
substitution of another user's code. No third-party content should load on callbacks.

## Exchange request

~~~http
POST /api/v1/contrib/media-manager/exchange HTTP/1.1
Host: staff.example.org
Content-Type: application/json
Accept: application/json
X-Media-Client: library-dam
X-Media-Secret: <64-character random secret>

{"code":"<64 lowercase hexadecimal characters>"}
~~~

Never send credentials in URLs. Do not send staff cookies or an Authorization header:
Koha processes OAuth/Basic headers before the plugin controller. The route deliberately
omits x-koha-authorization and performs mandatory dedicated client authentication.

Only code is accepted in the body. Identity/context overrides are rejected.
Controller body limit is 1024 bytes; enforce a matching proxy limit because OpenAPI
parses requests before controller execution.

## Success: HTTP 200

~~~json
{
  "success": true,
  "protocol": "code-v2",
  "iss": "main-library",
  "aud": "media-manager",
  "identity": {
    "provider": "koha",
    "instance": "main-library",
    "patron_id": 1001,
    "userid": "cataloguer01"
  },
  "context": {"biblio_id": 12345, "branch": "MAIN"},
  "capabilities": ["media.access", "media.upload"],
  "issued_at": 1792584000,
  "expires_at": 1792584060,
  "correlation_id": "<64 hex characters>",
  "state": "<browser-bound state>"
}
~~~

All shown properties are required. IDs/timestamps are JSON integers. identity.instance
equals iss; aud is exactly media-manager. Capabilities come from the fixed policy.
No name, email, password, session cookie, access token or fabricated auth_time is returned.

Verify protocol, expected issuer/audience, state and positive IDs. Link accounts by
(instance, patron_id), not globally by username. Capabilities are an upper bound;
biblio_id is the authorized record context. A service credential grants no extra staff
authority. The consumer independently creates and protects its session.

## Errors

Controller errors use an object with one error property:

| HTTP | Error | Action |
|---|---|---|
| 400 | https_required | Correct TLS/proxy setup (or tick **Allow HTTP** on an isolated test network) |
| 400 | invalid_request | Correct body/format |
| 400 | invalid_grant | Expired, replayed, invalid or wrongly bound code; restart |
| 401 | invalid_client | Correct client headers |
| 403 | access_denied | Staff or record authorization no longer valid |
| 413 | invalid_request | Reduce body size |
| 429 | rate_limited | Retry-After: 60; restart if expired |
| 503 | temporarily_unavailable | Check configuration/storage |

Koha middleware may reject JSON, query parameters, media types or headers before the
controller, using its native error envelope. Consumers must handle HTTP status without
requiring the plugin envelope for such errors. Infrastructure can also return 404/502/503.

## Code lifecycle and rate limits

Codes contain 256 CSPRNG bits, persist only as SHA-256 hashes, and expire when database
time reaches expires_at. TTL defaults to 60 seconds (30–120). Primary-key row locks
serialize consumption. Identity is returned only after consumption and audit commit.
Revoked grants are consumed and denied. Audit/storage failure returns no identity.

Exchange limits are 60 attempts/minute per direct peer IP and 600/minute globally;
initiation is 20/minute per patron. Shared database counters work across workers.
Fixed-window boundaries allow bursts. Add proxy rate limits for malformed/pre-controller
traffic. Forwarded IP headers are not trusted; proxy peer limits may be shared.

A lost successful response does not restore a consumed code. Start another handoff.

## Rotation and versioning

Supply a newly generated secret in Koha, then deploy it to the DAM within the overlap
(default 300 seconds, configurable 120–3600). Current and immediately previous digests
are accepted. Blank preserves the credential. Wait for the overlap before rotating again.

Legacy v1 HMAC redirects are disabled, not reinterpreted. Coordinate v2 consumer
deployment. Future incompatible changes require an explicit new protocol version.

## Optional health endpoint

GET **{base}/.well-known/koha-media-manager** may return:

~~~json
{"protocol":"code-v2","audience":"media-manager"}
~~~

No credentials are sent. This confirms only advertised protocol support, never a
successful authenticated integration.
