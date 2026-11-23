# Vendored license texts

## COPYRIGHT.postgresql

The PostgreSQL license notice (the `COPYRIGHT` file of the PostgreSQL
source tree), vendored into this packaging repository so that the
PostgreSQL License half of this package's license evidence lives in the
packaging repository itself.

- Source: `postgres/postgres` repository, file `COPYRIGHT`, commit
  `6b3806732b7c5df06bdd0ed150e8a07b4ad62315` ("Stamp 14.24.",
  2026-08-10).
- Bytes: 1,198 bytes, SHA-256
  `3d6af92ff8a4c2cdf69afb1cf44edea727922f5cd0cf8b5f72b11cdecac8fdfd`.
  The same bytes are carried by the other pins the Catalog previously
  recorded for this package and by the `REL_19_0` tag.

`pg_repack.exe` statically links PostgreSQL frontend support code
(`libpgport` / `libpgcommon`). The shipped ZIP already carries this same
notice as `POSTGRESQL-COPYRIGHT`, produced at build time from the
official PostgreSQL source checkout (see `windows/ci/build.ps1` and
`windows/ci/package.ps1`); that mechanism is unchanged. This vendored
copy exists so the Catalog's per-version license evidence for the
PostgreSQL License can pin a file in this repository instead of a file
in `postgres/postgres`, whose pins the Catalog fleet verifier cannot
re-pin for a new Release.

This file is intentionally not listed in `config/extension.json`
`license.files`: those entries must byte-match a file in the upstream
`reorg/pg_repack` tree, which carries no PostgreSQL license text.
