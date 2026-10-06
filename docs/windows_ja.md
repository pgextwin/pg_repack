# pg_repack Windows x64 バイナリ利用ガイド

## 1. 対象

pgextwinのpg_repack packageはWindows x64向けです。

PostgreSQL 14〜18について、それぞれ専用ZIPを作成しています。必ず実行対象PostgreSQLの**メジャーバージョンと一致するZIP**を使用してください。

例:

~~~text
pg_repack-ver_1.5.3-pg17-windows-x64.zip
~~~

このZIPはPostgreSQL 17用です。

## 2. ファイル配置

PostgreSQLを停止してからZIPを展開し、次のように配置します。

~~~text
ZIP\bin\pg_repack.exe
  -> <PostgreSQL>\bin\pg_repack.exe

ZIP\lib\pg_repack.dll
  -> <PostgreSQL>\lib\pg_repack.dll

ZIP\share\extension\pg_repack.control
ZIP\share\extension\pg_repack--1.5.3.sql
  -> <PostgreSQL>\share\extension\
~~~

同梱される `COPYRIGHT` と `POSTGRESQL-COPYRIGHT` はライセンス表示です。削除せずpackageと一緒に保管してください。

## 3. Extension作成

PostgreSQLを起動し、pg_repackを利用するデータベースで実行します。

~~~sql
CREATE EXTENSION pg_repack;
~~~

確認:

~~~sql
SELECT repack.version();
~~~

1.5.3 packageでは次の形式の出力を確認できます。

~~~text
pg_repack 1.5.3
~~~

pg_repackでは `shared_preload_libraries` の設定は不要です。

## 4. pg_repack.exeの確認

PostgreSQLの `bin` から次を実行します。

~~~powershell
.\pg_repack.exe --version
~~~

実際の再編成では、対象DBへの接続条件、対象table、lock timeout、並列index buildなどの指定が関係します。コマンドラインオプションはupstream pg_repackドキュメントを確認してください。

典型的な形式は次のようになります。

~~~powershell
.\pg_repack.exe -h 127.0.0.1 -p 5432 -U postgres -d mydb --table public.mytable
~~~

本番データで実行する前に、バックアップ、空き容量、対象テーブルのprimary key/unique key条件、長時間transaction、DDL競合、接続権限を必ず確認してください。

## 5. PostgreSQL majorを混在させない

pg_repack packageにはserver extension DLLとfrontend executableの両方があります。

~~~text
pg_repack.dll
pg_repack.exe
~~~

これらはCIで指定PostgreSQL majorに対して個別にbuild/testしています。PG17向けDLLとPG18向けEXEのような混在はサポートしません。

アップグレード時は、新しいPostgreSQL major用ZIPから両方を入れ替えてください。

## 6. Windows buildの特徴

server側はupstream sourceをMSVC x64でcompileし、upstream `lib/exports.txt` を元にDLL exportを設定します。

PostgreSQL 18では、pg_repack 1.5.3に対してupstreamが後に採用したmodule-magic互換修正をbuild workspace内で適用します。

frontend側のpg_repack.exeでは、Windows frontend用header処理を適用します。

さらに、PostgreSQL installationに `libpgport` / `libpgcommon` が存在しない場合、CIは対象minorと同じPostgreSQL公式sourceを取得し、公式Meson/MSVC経路で必要なfrontend support archiveだけをbuildして静的linkします。

そのためZIPには:

~~~text
POSTGRESQL-COPYRIGHT
~~~

も含まれます。

## 7. CIでの実動作確認

各PostgreSQL majorについて、単なるDLL loadだけではなく次まで自動確認します。

1. `CREATE EXTENSION pg_repack`
2. primary key付きtableへ20,000行投入
3. UPDATEとDELETEを実行
4. row countとrelation filenodeを記録
5. buildした `pg_repack.exe` を実行
6. row countが維持されることを確認
7. relation filenodeが変化することを確認
8. `repack.version()` を確認

このテストはWindows packageがclient/server一式として実際に機能することを確認するためのものです。

## 8. 正規の仕様情報

pgextwinはWindows binaryのbuild・検証・配布を担当します。

pg_repackの以下の仕様はupstreamドキュメントを優先してください。

- コマンドラインオプション
- 対象table/indexの要件
- lock/transactionの挙動
- privilege要件
- tablespace
- parallel index build
- failure時のcleanup
- versionごとの仕様変更

本番利用前には必ずupstream README/documentationも確認してください。
