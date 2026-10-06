# pg_repack Windows バイナリ

[English](README.md) | **日本語**

このリポジトリでは、[pg_repack](https://github.com/reorg/pg_repack) 1.5.3 の **非公式 Windows x64 バイナリ**を提供します。

upstream は `reorg/pg_repack` の `ver_1.5.3` に固定し、通常のWindows版PostgreSQL環境を対象として PostgreSQL 14〜18 で実機能テストを行います。

## 対応PostgreSQL

| PostgreSQL | CIで検証したminor | 対象 |
|---:|---:|---|
| 14 | 14.24 | Windows x64 |
| 15 | 15.19 | Windows x64 |
| 16 | 16.15 | Windows x64 |
| 17 | 17.11 | Windows x64 |
| 18 | 18.6 | Windows x64 |

公開中のpgextwin Release tagは次のとおりです。

~~~text
v1.5.3-windows.1
~~~

## ZIPの内容

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

pg_repackは通常のExtension DLLだけでなく、実際にテーブル再編成を実行する `pg_repack.exe` も必要です。

## 導入

1. PostgreSQLの**メジャーバージョンに一致するZIP**を選びます。
2. PostgreSQLを停止します。
3. `bin/pg_repack.exe` をPostgreSQLの `bin` へコピーします。
4. `lib/pg_repack.dll` をPostgreSQLの `lib` へコピーします。
5. `share/extension/*` をPostgreSQLの `share/extension` へコピーします。
6. PostgreSQLを起動します。
7. 利用するデータベースで次を実行します。

~~~sql
CREATE EXTENSION pg_repack;
~~~

pg_repackでは `shared_preload_libraries` の設定は不要です。

`pg_repack.exe` は対象PostgreSQLのruntime libraryを利用するため、別メジャー向けのEXE/DLLを混在させないでください。

詳しい手順は [docs/windows_ja.md](docs/windows_ja.md) を参照してください。pg_repack本体のオプション、ロック動作、制約、運用上の注意事項はupstreamドキュメントを正規の情報源とします。

## Windows互換処理

### PostgreSQL 18

pg_repack 1.5.3はPostgreSQL 18で導入された拡張module-magic APIより前のreleaseです。

pgextwinではbuild用の一時checkoutに対して、upstreamが後にcommit `82120316e840773e4521314917a97c26b4b5f520` で採用したのと同等の `PG_MODULE_MAGIC_EXT` 対応を適用します。

### pg_repack.exe

Windows frontend側では、pgut helperのheaderをbuild workspace内だけで `postgres_fe.h` を使う形に調整し、PostgreSQLのfrontend向けWin32定義を利用します。

また、近年のEDB PostgreSQL Windowsインストールには、pg_repack.exeのlinkに必要な内部用 `libpgport` / `libpgcommon` が含まれない場合があります。その場合は:

1. `pg_config.exe` から実際のPostgreSQL major/minorを取得
2. 同じversionの公式 `postgres/postgres` release tagをcheckout
3. PostgreSQL公式のMeson/MSVC Windows build経路を利用
4. frontend support libraryだけをbuild
5. pg_repack.exeへ静的link

という手順をCI内で実行します。

不透明な事前build済み互換libraryはリポジトリに保存しません。

## CIの合格条件

PostgreSQL 14〜18の各majorで、実際に次を確認します。

- upstream COPYRIGHTの一致
- `pg_repack.dll` と `pg_repack.exe` のMSVC x64 build
- `CREATE EXTENSION pg_repack`
- primary key付き実テーブルの作成
- UPDATE/DELETE後のテーブルに対する `pg_repack.exe` 実行
- 実行前後でrow countが変わらないこと
- relation filenodeが変化し、物理再編成が行われたこと
- `repack.version()` が1.5.3を返すこと
- Windows ZIP packageの生成

## ライセンス

pg_repack本体の再配布条件は `COPYRIGHT` に保持します。

pg_repack.exeにはPostgreSQL frontend support codeを静的linkするため、そのpackageで使用したPostgreSQL公式sourceの `COPYRIGHT` も `POSTGRESQL-COPYRIGHT` として同梱します。

本バイナリはpgextwinによる非公式配布であり、pg_repack upstreamまたはPostgreSQLプロジェクトによる公式Windows binaryではありません。
