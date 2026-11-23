# Windows 版 ACAS

Windows 上で動作する WPF デスクトップアプリです。Web ビューを使用せず、固定長の業務データと帳票をローカルの SQLite に保持します。共通基盤では帳票の一覧・閲覧・保存・印刷を提供します。各業務画面と同一性検証は後続の変更で追加します。

## 開発時の実行

Windows で .NET 8 SDK を使用し、このディレクトリから実行します。

```powershell
dotnet build Acas.sln -c Release
dotnet test Acas.sln -c Release --no-build
dotnet run --project Acas.App -c Release --no-build
```

保存先はユーザーごとのローカルアプリケーションデータ内の `ACAS\acas.db` です。検証で通常の業務データと分離する場合は `-- --database <検証用データベースのパス>` を指定します。共有パス、ネットワークドライブ、リンクを経由するパスは使用できません。
