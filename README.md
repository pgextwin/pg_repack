# pg_repack Windows binaries

[日本語](README_ja.md) | **English**

This repository provides **unofficial Windows x64 binaries** of [pg_repack](https://github.com/reorg/pg_repack).

The Windows packages are built from the official upstream source and validated against ordinary PostgreSQL Windows installations.

## Upstream

- repository: `reorg/pg_repack`
- ref: `ver_1.5.3`
- version: 1.5.3
- pg_repack license: BSD-style; see `COPYRIGHT`

Supported and validated PostgreSQL versions:

| PostgreSQL | Tested minor | Architecture |
|---:|---:|---|
| 14 | 14.24 | Windows x64 |
| 15 | 15.19 | Windows x64 |
| 16 | 16.15 | Windows x64 |
| 17 | 17.11 | Windows x64 |
| 18 | 18.6 | Windows x64 |

PostgreSQL lifecycle metadata is maintained centrally in **pgextwin/build**. PostgreSQL 14 remains eligible only while it is within the configured community maintenance window.

## Download

The current pgextwin package-set release is:

~~~text
v1.5.3-windows.1
~~~

Assets use explicit PostgreSQL-major names:

~~~text
pg_repack-ver_1.5.3-pg14-windows-x64.zip
...
pg_repack-ver_1.5.3-pg18-windows-x64.zip
~~~

Each ZIP contains:

~~~text
bin/
  pg_repack.exe
lib/
  pg_repack.dll
share/
  extension/
    pg_repack.control
    pg_repack--1.5.3.sql
COPYRIGHT
POSTGRESQL-COPYRIGHT
UPSTREAM-README.rst
PACKAGE-INFO.txt
~~~

## Installation

1. Choose the ZIP matching the PostgreSQL **major version**.
2. Stop PostgreSQL before replacing extension binaries.
3. Copy `bin/pg_repack.exe` to PostgreSQL's `bin` directory.
4. Copy `lib/pg_repack.dll` to PostgreSQL's `lib` directory.
5. Copy `share/extension/*` to PostgreSQL's `share/extension` directory.
6. Restart PostgreSQL if it was stopped.
7. In each database where pg_repack will be used, run:

~~~sql
CREATE EXTENSION pg_repack;
~~~

`shared_preload_libraries` is not required for pg_repack.

The client executable uses the PostgreSQL installation's runtime libraries, so keep `pg_repack.exe` with the matching PostgreSQL installation and do not mix binaries across PostgreSQL major versions.

See [docs/windows_ja.md](docs/windows_ja.md) and the upstream documentation before using pg_repack on production tables.

## Windows build strategy

pg_repack contains both a PostgreSQL server extension and a frontend client executable, so the Windows build has two parts.

### Server DLL

The build compiles the exact pinned upstream server source with MSVC x64 and uses upstream `lib/exports.txt` to create the Windows DLL export definition.

pg_repack 1.5.3 predates PostgreSQL 18's extended module-magic API. For PostgreSQL 18, pgextwin applies in the disposable build workspace the same compatibility change later adopted upstream in commit `82120316e840773e4521314917a97c26b4b5f520`, using `PG_MODULE_MAGIC_EXT`.

### Client executable

The upstream pgut frontend helper historically includes PostgreSQL's generic `c.h`. On Windows, pgextwin changes that include in the disposable build workspace to `postgres_fe.h` so PostgreSQL's frontend Win32 mappings are selected.

Modern EDB PostgreSQL installations do not ship every internal static frontend support archive needed to link pg_repack.exe. When those archives are absent, pgextwin:

1. reads the exact installed PostgreSQL major/minor from `pg_config.exe`,
2. checks out the matching official `postgres/postgres` release tag,
3. uses PostgreSQL's supported Meson/MSVC Windows build path,
4. builds only the required `libpgport` and `libpgcommon` frontend support archives,
5. links those archives into `pg_repack.exe`.

No opaque precompiled compatibility library is stored in this repository.

Because PostgreSQL frontend support code is statically included in the client executable, release ZIPs include `POSTGRESQL-COPYRIGHT` in addition to pg_repack's `COPYRIGHT`.

## Functional CI

A successful compile is not sufficient. Every supported PostgreSQL major must pass:

1. exact upstream pg_repack `COPYRIGHT` verification,
2. MSVC x64 build of `pg_repack.dll` and `pg_repack.exe`,
3. installation into the matching PostgreSQL Windows distribution,
4. `CREATE EXTENSION pg_repack`,
5. creation of a real table with a primary key and dead/updated tuples,
6. execution of the built `pg_repack.exe` against that table,
7. verification that the row count is preserved,
8. verification that the relation filenode changes after repacking,
9. verification that `repack.version()` reports pg_repack 1.5.3,
10. package creation and artifact upload.

Pull requests and pushes to `main` validate only. A branch named `release/<tag>` publishes a GitHub Release only after the full matrix succeeds.

## Updating pg_repack

When upstream publishes a new release:

1. update the pinned upstream ref/version in `config/extension.json`,
2. review whether the PostgreSQL 18 module-magic compatibility edit is still needed,
3. review the frontend Windows compatibility path,
4. rerun the complete maintained PostgreSQL matrix,
5. update the documentation,
6. publish a new Windows release only after all functional tests pass.

## Licensing

pg_repack's upstream redistribution terms are preserved in `COPYRIGHT`.

`POSTGRESQL-COPYRIGHT` is included because the Windows client executable statically links PostgreSQL frontend support code. It is copied from the exact PostgreSQL source release used for that package's validation/build provenance.

These binaries are unofficial pgextwin builds and are not official binary releases from the pg_repack or PostgreSQL projects.
