# Changelog

All notable changes to Media Asset Management (MAM) for Koha are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). The release workflow publishes the section that matches the
tagged version as the GitHub release notes.

Companion application: [koha-mam](https://github.com/tahir242/koha-mam).

## [Unreleased]

### Changed

- Licensed under the GNU General Public License v3.0 or later (GPL-3.0-or-later), like Koha: `LICENSE`
  file and a license notice in every Perl module.

## [1.1.0] - 2026-10-26

**Go to MAM** needs MAM 1.1.0 or later (it must accept sign-ins without a record); record and item
sign-ins work with any MAM.

### Changed

- **Go to MAM** on the dashboard now signs the administrator in to the MAM (like **Attach Media**, but
  without a record) and opens it in a new tab. Before, it was a plain link that showed the MAM's
  "Sign in through Koha" page unless you had already used **Attach Media** in that browser session.
- Database schema 4: `biblio_id` of initiations and codes may be empty (dashboard sign-ins). Applied
  automatically on upgrade.
- Releases: `-beta` tags are published as the **Latest** release, so the repository page shows the `.kpz`.
  Only `-alpha`, `-rc` and `-dev` tags are pre-releases.
- Exchange response schema (`openapi.json`): `context.biblio_id` may be `null` (dashboard sign-ins).

### Fixed

- Item-level **Attach Media** was missing on the record page when Koha draws a plain **Edit** button
  instead of an Actions dropdown (Koha does this unless `LocalCoverImages` or `OPACLocalCoverImages` is on).
  The entry now appears as a button next to **Edit** in that case.

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
