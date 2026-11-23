# iPad 版 ACAS 移植ガイド

レガシー GnuCOBOL プログラムを `ACASCore` (Swift Package) へ 1 プログラム = 1 Swift ファイルで移植する。
手本: `Programs/GL/General.swift` (general.cbl)、`Programs/GL/GL000.swift` (gl000.cbl)、`Programs/System/ACASMenu.swift` (ACAS.cbl)。

## 絶対条件
- 画面位置 (行・桁)、入力項目の順序・桁数・属性、メニューキー、エラーコード、計算 (桁・丸め・符号)、
  ファイル更新内容 (固定長レコードのバイト列) をレガシーと同一にする。レガシーのバグ・癖もそのまま再現する (直さない)。
- 仕様の正はレガシーソースと証跡 (`runs/<ケース>/NN-screen.txt`, `record-diff.json`)。期待値ではなく実測に合わせる。
- 画面に出す文字列を Swift に直書きしない。必ず文言キー経由 (`s.t("gl000.title")`)。

## 構成
```
ipad/ACASCore/Sources/ACASCore/
  Runtime/    Terminal(80x24) Console(DISPLAY/ACCEPT) Cobol/Pic(数値・編集) Record/Layout(固定長レコード)
              FileStore(SQLite: 索引/相対/行順) L10n Session Replay
  Programs/System|GL|SL|PL|Stock|IRS/   各プログラム + <X>Programs.swift (register)
ipad/ACAS/Resources/Localization/fragments/<sub>.en.strings / <sub>.ja.strings   文言 (サブシステム別)
ipad/ACAS/Resources/Seeds/*.json   ベースライン (証跡 baselines/ の論理レコード)
ipad/ACAS/Resources/Cases/cases.json   453 ケース
```

## COBOL → Swift 対応
| COBOL | Swift |
|---|---|
| `display X at LLCC with foreground-color n [erase eos/eol] [highlight]` | `c.display(X, at: LLCC, color: n, eraseEOS: true)` |
| `accept F at LLCC with update/auto/upper/secure` (pic x(n)) | `F = try c.accept(at: LLCC, size: n, initial: F, options: [.update, .auto])` (update 無しなら initial は不要) |
| 数値項目の accept (pic 9(n)) | `kind: .numeric`。戻り値は文字列 → `Cobol.moveNumeric` / `Cobol.numval` |
| `cob-crt-status` | `c.crtStatus` (Enter 0, Fn 1000+n, PgUp 2001, PgDn 2002, Up 2003, Down 2004, Esc 2005) |
| SCREEN SECTION の `display/accept screen` | `ScreenField` の配列 + `c.displayFields` / `c.acceptScreen` |
| `call "xxx" using ws-calling-data system-record to-day` | `try s.call("xxx")`。共有領域は `s.sys` `s.defaultRecord` `s.sysRecord4` `s.toDay` `s.termCode` `s.caller` `s.called` |
| `exit program` / `goback` | `return` |
| `stop run` | `throw StopRun()` |
| 索引ファイル | `IndexedFile(s.store, path: s.ledgers + "ledger.dat", layout:, keyOffset:, keyLength:)`、`open()` `read(key:)` `start(notLessThan:)` `readNext()` `write` `rewrite` `delete`、`status` = "00"/"10"/"22"/"23"/"35" |
| 相対ファイル (system.dat 等) | `RelativeFile` / `s.systemFile` / `Common.loadSystemRecords(s)` `Common.rewriteSystemRecords(s)` |
| 行順ファイル・帳票 (prt-1 等) | `s.printLine(path, line)` / `s.store.readRaw` `writeRaw` `appendRaw` |
| レコード定義 (copybook) | `Layout("name", [("field-name", .x(n) / .n9 / .comp3 / .comp / .native / .filler)])`。項目名は copybook の名前を小文字で |
| `pic zz9.99-` 等の編集 | `Pic.edit("zz9.99-", value:, scale:)` |
| `compute ... rounded` | `Cobol.rescaleRounded`。それ以外の MOVE/COMPUTE は切り捨て `Cobol.rescale` + 桁あふれ `Cobol.truncate` |
| `accept from date/time` | `s.today` `s.time` `s.timeHHMMSS` (テストでは固定時刻を注入) |
| maps04 (日付変換) | `Maps04.toBinary("dd/mm/ccyy")` `Maps04.toDate(bin)` `Common.convDate` `Common.toUK` |

数値は必ず「スケール付き整数 (Int64)」で扱う。Double を使わない。
GnuCOBOL のファイル名は `ACAS_LEDGERS` 配下 → `s.ledgers + "xxx.dat"`、IRS は `s.irsDir + ...`。
(ベースラインに存在するファイル名は `Seeds/*.json` の `files` キーを参照)

## 文言 (英日対応表)
- `fragments/<sub>.en.strings` = レガシー画面の英語原文 (一字一句そのまま)。`fragments/<sub>.ja.strings` = 日本語。この 2 ファイルが英日対応表。
- キーは `<プログラム>.<内容>` の snake_case (`gl030.add_new_accounts`)。エラーは `gl030.gl031` のようにコードを含め、日本語にもコード (GL031 等) を残す。
- 日本語のセル幅 (全角 = 2) は英語原文以下にする。`s.t(key)` が英語幅まで空白詰めするので、入力欄 `[ ]` の位置はずれない。
  角括弧など位置が意味を持つ文字は英語と同じ桁に置く。
- 帳票の見出し・明細ラベルも同様に文言キー化する (キー接頭辞 `report.` は幅チェック対象外だが、桁位置は保つ)。
- 追加後は `python3 ipad/scripts/merge_strings.py` を実行 (Localizable.strings を再生成。キー不一致・幅超過はエラー)。
  `en.lproj/ja.lproj/Localizable.strings` は生成物なので直接編集しない。

## 検証 (必須)
```
cd ipad/ACASCore
ACAS_EVIDENCE=<証跡zipを展開したディレクトリ> ACAS_CASES='^GL-' ACAS_VERBOSE=1 ACAS_RESULTS=/tmp/gl.json swift test 2>&1 | grep -E "error:|REPLAY|^==|L[0-9]+ (legacy|ipad)"
```
- 英語モードで全画面 (日時は正規化) とレコード差分 (追加/変更/削除後のバイト列) をレガシー証跡と文字単位で比較する。
- `ACAS_LANG=ja` でも同じケースが最後まで進むこと (expect 文言は見ない)。
- 担当ケースが全て「一致」になるまで直す。一致させられないケースは理由を報告する (隠さない)。
