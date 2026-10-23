# Compatibility evidence

Source review 2026-10-21; runtime test 2026-10-23.

**Runtime-tested:** plugin 2.2.x/2.3.0 on a Koha **26.05** test server (plain HTTP with **Allow HTTP**),
together with the SIUT DAM: install and upgrade by KPZ, Configure and dashboard pages, toolbar
button, the full code-v2 sign-in, REST exchange route, connection test, audit log, and the DAM's
metadata read and 856 publication through Koha's REST API. Not runtime-tested: HTTPS behind a
reverse proxy, other Koha releases (22.11–25.11), concurrency on multiple Plack workers under load.

The primary source target is the stable 26.05 series. The official
site lists [26.05.04](https://koha-community.org/koha-26-05-04-released/); that tag was
not present in the GitHub mirror during review, so its 26.05.x branch was inspected.
Do not interpret the plugin minimum_version (22.11) as runtime certification for that release.

| Interface | Evidence and strategy |
|---|---|
| Toolbar hook | Present in 22.11 and 26.05 catalogue/detail.pl and cat-toolbar.inc; called by Template Toolkit with NO arguments. Read CGI biblionumber, validate server-side. No JS fallback is needed on inspected releases. |
| intranet_js | No arguments in 22.11/23.11; 26.05 adds a page hash argument. Removed because the native toolbar suffices. |
| run.pl | Native gate requires plugins => method; tool therefore requires plugins.tool in addition to plugin policy. |
| haspermission | Takes userid and structured permission requirement; checks current database permissions and superlibrarian. Use editcatalogue => edit_catalogue, not broad wildcards. |
| REST plugins | api_namespace and api_routes supported in 22.11 and 26.05; routes mounted under /api/v1/contrib/{namespace}. |
| CSRF | Koha::Token generate_csrf/check_csrf use session_id. Mutating operations use cud- prefixed op and POST for newer core CSRF conventions. |
| Account state | account_locked/is_expired/is_debarred available in inspected 22.11/26.05 Patron source. |
| Schema | Base get_qualified_table_name and store_data/retrieve_data are the existing plugin conventions; no invented schema registration API. |
| Bibliographic PUT | Absent in inspected 22.11.00 specification; present in 23.11.00, 24.05.00 and 26.05.x. |

23.11 source also confirms its template hooks and REST bibliography update format.
24.05 was sampled for bibliography PUT; the entire intermediate release matrix has not
been inspected or executed. Later releases are not automatically supported by a “+”
claim. Validate vendor patches and exact deployment versions on staging.

## Primary source links

- [22.11 catalogue controller](https://github.com/Koha-Community/Koha/blob/v22.11.00/catalogue/detail.pl)
- [22.11 toolbar template](https://github.com/Koha-Community/Koha/blob/v22.11.00/koha-tmpl/intranet-tmpl/prog/en/includes/cat-toolbar.inc)
- [26.05 toolbar controller](https://github.com/Koha-Community/Koha/blob/26.05.x/catalogue/detail.pl)
- [26.05 template hooks](https://github.com/Koha-Community/Koha/blob/26.05.x/Koha/Template/Plugin/KohaPlugins.pm)
- [22.11 authentication](https://github.com/Koha-Community/Koha/blob/v22.11.00/C4/Auth.pm)
- [22.11 plugin runner](https://github.com/Koha-Community/Koha/blob/v22.11.00/plugins/run.pl)
- [22.11 route registration](https://github.com/Koha-Community/Koha/blob/v22.11.00/Koha/REST/Plugin/PluginRoutes.pm)
- [26.05 REST authentication](https://github.com/Koha-Community/Koha/blob/26.05.x/Koha/REST/V1/Auth.pm)
- [22.11 CSRF wrapper](https://github.com/Koha-Community/Koha/blob/v22.11.00/Koha/Token.pm)
- [Official plugin base documentation](https://perldoc.koha-community.org/Koha/Plugins/Base.html)
- [Official API documentation](https://api.koha-community.org/)

Auditable GitHub file blob revisions inspected on 26.05.x:
catalogue/detail.pl **40c26046630b63a4f59c3316de14b361e818d1d9**;
cat-toolbar.inc **77a61e0a2d77d9e55d36baa2ca080035a60810ae**;
PluginRoutes.pm **bd79c79454efed0e08d4dfba96c18d05ef06dff1**;
REST/V1/Auth.pm **ade5c3f98101b7be477d0c780fd291752745a67e**;
biblios.yaml **94a5092c93db97b1d669d5a0567991096ffeec6f**.
These are file blobs, not release commit IDs.

The wiki plugin pages were inaccessible to the available web tool; the complete API
HTML exceeded its retrieval limit. Relevant official versioned source/specifications
and official plugin perldoc were used instead. BrowserOS tools were unavailable.
