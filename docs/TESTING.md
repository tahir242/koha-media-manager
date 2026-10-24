# Testing

## Isolated suite

Run from the repository root on a Perl installation with Test::More:

~~~sh
prove -v t/*.t
~~~

If prove/TAP::Harness is absent, execute each t/*.t with perl; each uses Test::More,
prints its TAP plan, and exits nonzero on assertion failure. t/lib/MockKoha.pm supplies
isolated Koha/CGI fixtures. No production data or network connection is required.

Coverage includes configuration attacks, ID validation, credential comparison, valid/
expired/replayed/invalid grants, missing credentials/code/session, account/permission
revocation, state/context substitution, rotation, CSRF (every POST form), native toolbar output,
schema/default preservation, no-secret audit data, DNS rejection and TLS pinning, the
**Allow HTTP** checkbox (t/insecure_http.t), tool error pages (t/tool_errors.t) and audit
pagination (t/dashboard.t): 228 assertions in 13 files.

Mocks establish local logic behavior; they do not verify real Koha APIs, SQL execution,
Template Toolkit output, middleware registration or production RNG quality.

## Real database concurrency test

Use Linux and DBI plus DBD::mysql or DBD::MariaDB. Create a disposable database named
exactly **mediamanager_test**. Supply MM_TEST_DSN, MM_TEST_USER and MM_TEST_PASSWORD in
the test process environment, not source control. Example DSN:
**dbi:mysql:database=mediamanager_test;host=127.0.0.1**.

~~~sh
prove -v t/integration/concurrency.t
~~~

The test creates an isolated table, forks two independent DB connections, releases both
consumers together, verifies exactly one success and one replay, then drops its table.
It skips unless explicitly configured and never targets ordinary Koha database names.
Run it with the same database engine/isolation settings as deployment.

## Required Koha staging checks

Use an empty/disposable Koha instance and its supported test environment. Install the
KPZ, then verify the following before declaring runtime compatibility:

1. Upload/enable registers the plugin and REST route after worker restart.
2. First install and repeated upgrade preserve existing settings and audit rows.
3. Configuration POST rejects missing/wrong CSRF and never renders stored credentials.
4. Native catalogue page renders exactly one accessible button, including records with
   no covers. Unauthorized staff and invalid/deleted records receive no action.
5. Perform the complete browser round trip using a test consumer conforming to
   SSO_PROTOCOL.md; verify original session binding and both state comparisons.
6. Verify HTTP status, JSON, no-store/no-referrer, TLS proxy handling and log redaction.
7. Exchange under multiple Plack workers; revoke permissions, lock the patron and delete
   the biblio between initiation and exchange. Confirm safe failure and audited events.
8. Rotate the secret during an in-flight grant; old credential expires at the boundary.
9. Exercise DNS changes, approved private destinations, TLS errors and redirects in diagnostics.
10. Populate audit pages and filters; verify UTC timestamps and retention boundaries.
11. Run maintenance, confirm no active requests/codes disappear, then verify uninstall
    retains logs and invalidates pending grants.

No Laravel application is needed in this repository. A staging-only test consumer may
be developed independently; do not call production accounts for tests.

## Execution record

Isolated suite: 228 assertions passed (Git's bundled Perl). The real database concurrency
test is included but was skipped (no disposable DBI database here).

Runtime (2026-10-23, Koha 26.05 test server, plain HTTP with **Allow HTTP**, together with
the DAM): items 1–5 and 10 above were exercised in the browser (install/upgrade,
CSRF-protected configuration, toolbar, full round trip, audit pages and pagination), plus the
connection test and the exchange error answers (401 invalid_client, 400 invalid_grant). Not yet
done: items 6–9 and 11 over HTTPS, under multiple workers, and maintenance/uninstall.
See ENGINEERING_REPORT.md for per-version details.
