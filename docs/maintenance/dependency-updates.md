# 依存関係・ランタイムの定期保守

- Dependabot は毎週 Maven (`/java`)、pip (`/tools/oracle`)、GitHub Actions
  (`/`) の更新 PR を作成する。各 ecosystem の minor/patch をまとめ、major は
  個別にする。上限は各 5 PR、ラベルは `dependencies`、コミット接頭辞は `deps(...)`。
  Java の複数モジュールも対象。iPad は外部 SPM/CocoaPods/Carthage 依存がないため
  Swift 用設定は不要。将来追加した場合は設定も追加する。
- セキュリティ更新は通常の Dependabot alerts / security updates を利用する。
  リポジトリ設定で両機能を有効にすること（このファイルだけでは有効化されない）。
  自動マージは設定しない。**すべての PR は Akira がレビューし、マージする。**
- `security-scan.yml` は毎週月曜 03:23 UTC、手動実行、および main 宛 PR / main push の
  `java/`、`ipad/`、`tools/oracle/`、`.github/` 変更時に実行する。
  OSV-Scanner v2.3.3 の公式再利用 workflow を SHA 固定で使用し、全体を再帰走査する。
  対応する依存ファイルがまだない main では走査ジョブをスキップする。
  検出時は PR を含めジョブを失敗させ、SARIF を Security → Code scanning と artifact に出力する。
  Code scanning の利用設定が必要。fork PR では GitHub のトークン権限制限により
  SARIF アップロードが拒否されることがある。権限回避のための pull_request_target は使わない。
- OSV は対応する manifest/lockfile の既知脆弱性検査であり、COBOL や Swift ソースの
  SAST ではない。Maven の推移依存まで保証するものではないため、通常のビルド・テストも継続する。
- ランタイム検査は標準ライブラリだけで動く。
  Java workflow の JDK と POM の `maven.compiler.release` / `java.version`、
  oracle workflow の Python、iPad workflow / project.yml の Xcode と iOS deployment target を
  endoflife.date と比較する。JDK は Temurin のサポート期間を使う。
  EOL は失敗、新しい Java LTS（Python / Apple は新しいサポート中の系列）は警告。
  リリース予定の系列は除外する。`latest-stable` は追従設定として表示する。
  Apple の最低 deployment target は CI の実行 OS ではないため、警告・失敗は更新検討の材料とする。
  API 障害・未登録系列・未対応のバージョン式は警告として続行するため、警告を放置しない。
  未マージのスタックのディレクトリが main に存在しない場合は SKIP する。

ローカル確認:

```sh
actionlint .github/workflows/security-scan.yml
check-jsonschema --builtin-schema vendor.dependabot .github/dependabot.yml
python3 -m unittest discover -s .github/scripts -p 'test_*.py'
python3 .github/scripts/check-runtimes.py --root .
osv-scanner scan source --recursive .
```
