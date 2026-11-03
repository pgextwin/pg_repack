# pg_repack — Windows x64

[日本語](README_ja.md) | English

pgextwin publishes **unofficial Windows x64 binaries** of [pg_repack](https://github.com/reorg/pg_repack). reorganizes PostgreSQL tables and indexes with reduced locking compared with a traditional rewrite.

## Download

Choose your PostgreSQL major version from the [latest published Release](https://github.com/pgextwin/pg_repack/releases/latest), or [view earlier Releases](https://github.com/pgextwin/pg_repack/releases). PostgreSQL **14–18** packages are listed in the [pgextwin catalog](https://pgextwin.github.io/website/en/). PostgreSQL 14 community support ends November 12, 2026; existing downloads may remain available.

## Installation

1. Back up your environment and check the [upstream documentation](https://github.com/reorg/pg_repack).
2. Stop PostgreSQL before replacing files. Extract the ZIP matching your PostgreSQL major version, then copy the packaged lib/ and share/extension/ files into the corresponding PostgreSQL directories.
3. The ZIP also contains bin/pg_repack.exe. Copy it to the matching PostgreSQL bin/ directory; the command-line executable and server extension must use the same PostgreSQL major version. No shared preload is required. See upstream guidance for privileges and locking.
4. Start PostgreSQL with the required settings and run CREATE EXTENSION pg_repack; in the appropriate database.

Use the Release's SHA256SUMS.txt to verify downloaded files. Refer to the Release for SPDX SBOMs, vulnerability reports and any signed attestations. Test the extension before production use.

## License

The extension's behavior and limitations are documented by [upstream pg_repack](https://github.com/reorg/pg_repack). This is an independent, unofficial Windows package. Consult the included license notices.
