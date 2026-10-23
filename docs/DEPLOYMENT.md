# Deployment and migration

## Before installation

1. Use a disposable/staging instance of the exact deployed Koha release first.
2. Back up plugin_data rows and the existing qualified log table. Save the v1 KPZ.
3. Verify InnoDB, required Perl modules, valid TLS and reachable database storage.
4. Deploy the independent consumer's code-v2 contract before enabling staff use.
5. Grant only the documented permissions; reserve configuration/audits for superlibrarians.

Koha 26.05 is the primary target and was used for runtime testing (see COMPATIBILITY.md).
No production Koha configuration was changed during development.

## Dependencies

Existing Koha dependencies used: Modern::Perl, CGI, Koha/C4 modules, DBI, JSON::PP,
Digest::SHA, Bytes::Random::Secure, IO::Socket::SSL, Socket and POSIX.
Bytes::Random::Secure is already used by Koha::Token in inspected releases.
The code deliberately avoids Koha::Token's generic random generator, which uses
String::Random in 22.11. No Laravel, JavaScript framework or new CPAN framework is added.

Confirm on the Koha host:

~~~sh
perl -MBytes::Random::Secure -MIO::Socket::SSL -MDigest::SHA -MJSON::PP -e 'print "Dependencies available\n"'
~~~

On Debian-based hosts missing non-core modules, install the matching distro packages
(e.g. libbytes-random-secure-perl, libio-socket-ssl-perl) through your normal change process.
Verify certificate authorities are installed. Do not install test mocks in production.

## Package and enable

PowerShell: **./build_kpz.ps1**. Linux/macOS with Python 3.8+:
**python3 scripts/build_kpz.py**. Both package only the explicit production file list,
under Koha/Plugin/Com/Library/, including all modules/templates and openapi.json.
They validate contents and print SHA-256. Tests, docs, scripts and secrets are excluded.

Upload the KPZ through Koha plugin administration. Enable the plugin and restart relevant
Plack/API workers using the deployment's standard service management. Clear the template cache (see Upgrading). Check that
POST /api/v1/contrib/media-manager/exchange is registered: an anonymous request must fail with 401
`invalid_client` (or 400 `https_required` over HTTP before **Allow HTTP** is ticked), not 404.

## Upgrading (uploading a newer KPZ)

Koha keeps the old Perl code in memory and caches compiled templates, so after uploading a newer KPZ:

~~~sh
sudo koha-plack --restart <instance>                    # load the new Perl modules
sudo rm -rf /var/cache/koha/<instance>/templates/*      # clear compiled templates (path: <template_cache_dir> in koha-conf.xml)
sudo systemctl restart apache2
~~~

Then open the plugin's Configure page: it shows "Plugin version x.y.z". If it still shows an older
number (or no version at all), the old code is still running: repeat the restart. KPZ files built
before 2.2.2 used a fixed file date and are especially prone to stale templates.

## V1 to v2

The upgrade preserves mam_url, existing toolbar label, old permission configuration,
legacy secret and historical log rows. It adds requests/codes/rates tables and missing
v2 defaults. It does not promote the legacy shared secret into a v2 credential.

The old redirect operation explicitly reports that the protocol is retired.
Administrators must configure a new client ID, instance ID, random secret and staff
policy; legacy CSV permissions are not used. Coordinate a maintenance window with the
consumer deployment. Keep v1 disabled unless consciously rolling back to its known
security risks. Rollback requires restoring the matching plugin/configuration backup;
do not expect v2 codes to work with v1.

New-code and initiation storage is per instance. Do not share plugin tables or clone
a live issuer identifier into a different production instance.

## Reverse proxy and HTTPS

On an isolated test network without TLS, tick **Allow HTTP** on the Configure page instead
(see CONFIGURATION.md); never in production. For production, set trusted TLS/proxy configuration so CGI sees HTTPS=on and Mojolicious sees an HTTPS
absolute request URL. Do not fix scheme detection by accepting untrusted forwarded headers.
Apply no-store/no-referrer and URL/header redaction per SECURITY.md. Limit exchange bodies
to 1024 bytes at the proxy and add request rate limits. Return and exchange URLs must
be fixed configuration in the DAM (it derives both from `KOHA_STAFF_URL`).

## Maintenance

The plugin does not modify cron automatically. Install scripts/maintenance.pl separately
from the checkout to an administrator-controlled location. Run daily as the Koha
instance OS user with KOHA_CONF and PERL5LIB set, including the installed plugin path.

Example inside the instance's normal koha-shell environment:

~~~sh
perl /opt/koha-media-manager/scripts/maintenance.pl --run
~~~

Have cron invoke the same instance environment; do not run against another tenant.
The command processes at most 100 batches of 1000 rows per table per invocation.
Schedule more frequently if needed and monitor backlog. Audit retention defaults to
90 days. Requests/codes remain for one day after expiration for replay classification;
rate windows older than an hour are removed. Active records cannot match cleanup.

## Uninstall

Uninstall removes pending request/code/rate tables, invalidating all in-flight grants.
Audit history is retained intentionally. Koha removes plugin_data through its lifecycle.
After export and the institution's retention approval, a DBA can remove the orphaned
qualified log table separately. Reinstallation reuses retained audit history.
