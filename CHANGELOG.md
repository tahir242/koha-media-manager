# Changelog

All notable changes to Media Asset Management (MAM) for Koha are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). The release workflow publishes the section that matches the
tagged version as the GitHub release notes.

## [1.0.0] - 2026-10-24

First public release (beta).

### Added

- **Attach Media** button on the record details toolbar of the Koha staff interface.
- **Attach Media** entry in each item's **Actions** menu, on the record's holdings table and on the
  add/edit item page; items are identified by item number, so no barcode is needed.
- Secure single sign-on to the MAM application (code-v2): opaque single-use codes, browser binding,
  server-to-server exchange, permissions re-checked at every step.
- Record and item context in the sign-in, verified by Koha at initiation, completion and exchange.
- Permission policy: cataloguers (`catalogue` + `plugins → tool` + `editcatalogue → edit_catalogue`) and
  superlibrarians, mapped to MAM capabilities.
- Configuration page with validation, hashed client secret and a rotation overlap window.
- Dashboard with status, connection test and a paginated, filterable audit log with correlation IDs.
- Test-only **Allow HTTP** switch for isolated networks without TLS.
- Rate limits for sign-ins and exchanges; daily maintenance script with audit retention.
- Self-contained package builders for Windows (`.bat`, `.ps1`), Linux/macOS (`.sh`) and Python.
- GitHub Actions workflow that tests every push and publishes a release with the `.kpz` for every tag.
- User Manual and Developer Guide.
