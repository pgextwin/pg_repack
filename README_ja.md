# pg_repack — Windows x64 バイナリ

[English](README.md) | 日本語

[pg_repack](https://github.com/reorg/pg_repack)の**非公式Windows x64バイナリ**です。テーブルやインデックスの再編成を行うツールです。

## ダウンロードと対応環境

[最新の公開Release](https://github.com/pgextwin/pg_repack/releases/latest)から、利用中のPostgreSQLメジャーバージョンに一致するZIPを選んでください。[過去のReleases](https://github.com/pgextwin/pg_repack/releases)も確認できます。PostgreSQL **14〜18**向けの配布状況は[pgextwinカタログ](https://pgextwin.github.io/website/ja/)に掲載しています。PostgreSQL 14のコミュニティサポートは2026年11月12日に終了します。

## インストール

1. バックアップを取得し、[上流ドキュメント](https://github.com/reorg/pg_repack)で必要条件を確認します。
2. ファイルを置き換える前にPostgreSQLを停止します。対応するZIPのlib/とshare/extension/以下のファイルを、PostgreSQLの同名ディレクトリに配置します。
3. ZIPにはbin/pg_repack.exeも含まれます。対応するPostgreSQLのbin/へコピーしてください。EXEと拡張機能のDLLは同じPostgreSQLメジャーバージョン向けのものを使用します。事前ロードは不要です。実行権限やロックの扱いは上流の説明を確認してください。
4. 必要な設定を反映してPostgreSQLを起動し、利用するデータベースでCREATE EXTENSION pg_repack;を実行します。

ReleaseのSHA256SUMS.txtでダウンロードしたファイルを照合してください。SPDX形式のSBOM、脆弱性レポート、署名付き証明の有無はReleaseで確認できます。本番導入前に検証環境で動作を確認してください。

## ライセンス

機能、設定、制限事項は[上流のpg_repack](https://github.com/reorg/pg_repack)を参照してください。本配布は非公式のWindowsバイナリです。ライセンスは同梱の表示に従います。
