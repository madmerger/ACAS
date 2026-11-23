# ACAS Windows ネイティブ版 (.NET 8 / WPF)

レガシー GnuCOBOL 版 ACAS を Windows ネイティブ UI (WPF) とローカル SQLite DB のスタンドアロンアプリへ移行したものです。画面・メニュー・メッセージ・帳票は日本語で表示します。

## 構成

| プロジェクト | 内容 |
|---|---|
| `Acas.Core` | 80×24 端末モデル、固定長レコード、SQLite ローカル DB、帳票スプール、各プログラムの移植、英日対応表 (`Resources/i18n.tsv`) |
| `Acas.App` | WPF アプリ (端末画面、帳票ビューア、同一性テストのケース再生) |
| `Acas.Verify` | 同一性テストのヘッドレス一括再生 (レガシー実測の画面・レコード・帳票と比較し JSON を出力) |
| `Acas.Tests` | xUnit 自動テスト |

## ビルドと実行

```
dotnet build Acas.sln -c Release
dotnet test Acas.sln -c Release
dotnet run --project Acas.App -c Release
dotnet run --project Acas.Verify -c Release -- <シナリオ台帳.json> <証跡ルート> [ケースID接頭辞...] [--out result.json]
```

## 同一性の考え方

- 内部では英語の「原文画面」と日本語の「表示画面」を同時に保持し、原文画面をレガシー実測の画面テキストと比較します。日本語表示は対応表に全文言が存在することで一致とみなします。
- レコードはレガシーと同じ固定長バイト列で保存し、バイト単位で比較します。
- 未移植の処理はソース内に `TODO` として明記しており、該当ケースは Verify で不一致になります。
