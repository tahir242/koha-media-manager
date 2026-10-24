# DAM to Koha REST integration

The DAM uses the Koha staff URL from its configuration (`KOHA_STAFF_URL`, API under
/api/v1); it is never inferred from browser input. Implementation and details: the DAM's
`app/Koha/KohaClient.php` and `docs/KOHA_INTEGRATION.md`. Its API service identity is separate from the plugin exchange
credential and from the staff identity returned by SSO.

## Authentication

Use a dedicated least-privilege Koha patron/service account with an API key pair.
Koha supports OAuth2 client_credentials at POST /api/v1/oauth/token when its OAuth
configuration/dependencies are enabled (including RESTOAuth2ClientCredentials).
Send form fields grant_type=client_credentials, client_id and client_secret over TLS;
use the returned bearer access token in Authorization for subsequent core API calls.
Do not put credentials or tokens in URLs. Verify exact API key management and OAuth
support on the deployed release. Avoid enabling RESTBasicAuth solely for this integration.

References: [22.11 REST Auth](https://github.com/Koha-Community/Koha/blob/v22.11.00/Koha/REST/V1/Auth.pm),
[Koha OAuth configuration](https://github.com/Koha-Community/Koha/blob/26.05.x/Koha/OAuth.pm),
[OAuth token controller](https://github.com/Koha-Community/Koha/blob/26.05.x/Koha/REST/V1/OAuth.pm).

## Operations

| Operation | Permission and format |
|---|---|
| GET /biblios/{biblio_id} | catalogue; use Accept: application/marcxml+xml or application/marc-in-json for MARC. Default application/json is not interchangeable with a MARC record. |
| PUT /biblios/{biblio_id} | editcatalogue.edit_catalogue; full MARC record in Content-Type application/marcxml+xml, application/marc-in-json or application/marc. Available in inspected 23.11+ specs, absent in 22.11.00. |
| GET /patrons/{patron_id} | 22.11 uses borrowers.edit_borrowers; 26.05 accepts borrowers.list_borrowers OR borrowers.edit_borrowers. Not used by the DAM: SSO already supplies minimal identity. |

Use separate read/write service identities when practical. Do not grant superlibrarian.
An API service account's ability to update a record does not authorize the current DAM
staff session to do so: enforce returned capabilities and record context separately.

Verified specs:
[22.11 biblios](https://github.com/Koha-Community/Koha/blob/v22.11.00/api/v1/swagger/paths/biblios.yaml),
[23.11 biblios](https://github.com/Koha-Community/Koha/blob/v23.11.00/api/v1/swagger/paths/biblios.yaml),
[26.05 biblios](https://github.com/Koha-Community/Koha/blob/26.05.x/api/v1/swagger/paths/biblios.yaml),
[22.11 patrons](https://github.com/Koha-Community/Koha/blob/v22.11.00/api/v1/swagger/paths/patrons.yaml),
[26.05 patrons](https://github.com/Koha-Community/Koha/blob/26.05.x/api/v1/swagger/paths/patrons.yaml).

## Safe MARC21 856 publication expectations

Publication belongs to the DAM, not this plugin (the DAM implements it as an outbox with
re-read before write and read-back verification). Fetch the complete current
record in an explicit MARC format. Preserve leader, control fields, existing repeated
fields and institution-specific metadata. Apply only the agreed 856 change; define
idempotent URL ownership so repeated publication does not duplicate fields.
Preserve the framework and use supported x-framework-id behavior where needed.

Coordinate concurrent cataloguing edits. Do not assume ETag/If-Match support without
checking the deployed API. Re-fetch and compare before updating; an application-side
lock alone cannot serialize changes by Koha cataloguers. Retain a recoverable change
history and use an explicit institutional conflict policy.

Do not emulate missing 22.11 PUT support through direct SQL or private CGI endpoints.
Upgrade Koha or defer publication. The plugin itself can still perform staff handoffs.

Handle 400 validation, 401 authentication, 403 permissions, 404 deletion, 406 unsupported
Accept formats, 409 conflicts where provided, 415 unsupported media, and 5xx maintenance
or upstream failure. Check the exact deployed OpenAPI spec for endpoint-specific errors.

Do not assume a portable core rate-limit quota. Honor 429/Retry-After when returned by
Koha or its proxy; use bounded retry/backoff for reads. Never blindly retry a full-record
write after a timeout: first determine whether it succeeded. Cache metadata appropriately.
