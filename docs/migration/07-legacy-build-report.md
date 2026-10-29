# 07. レガシー（GnuCOBOL）ビルド確認レポート

> 作業コピー `/home/ubuntu/work/acas-legacy` での実行結果（原本リポジトリは無変更）。以下は実行時のレポート原文。


## Summary

- Source copied from `/home/ubuntu/repos/ACAS` to `/home/ubuntu/work/acas-legacy`, excluding `.git`. No writes were made to the original checkout.
- Compiler: GnuCOBOL `3.1.2.0`.
- Build scripts: all eight invocations exited with status `0`; the captured compiler logs contain no errors.
- Source inventory: **136 `.cbl` files** — **115 built OK**, **0 failed**, **21 not built by any script**.
- Produced artifacts: **114 `.so` modules**, **6 executables with no extension**, **0 `.exe` files**.

“Built OK” means a corresponding compiled module or executable was produced in the source directory. “Not built by any script” means no corresponding output was produced by the requested repository scripts; it is not a compile failure.

## Source fixes in the copy

1. `copybooks/wsfnctn.cob:10`: changed `Rrn binary-long` to `Rrn binary-long unsigned` for GnuCOBOL 3.1.2.
2. `incomplete_records_system/wsfnctn.cob`: checked for the same `Rrn` / `binary-long` declaration; neither occurs there, so it was left unchanged.
3. No other source fixes were needed or applied.

## Per-program status

Every filename below is a `.cbl` source, and the status applies to each filename in that group.

### Built OK (115)

- `.`: `ACAS.cbl`
- `common/`: `maps01.cbl`, `maps04.cbl`, `maps09.cbl`, `maps99.cbl`, `sys002.cbl`, `xl150.cbl`
- `general/`: `general.cbl`, `gl000.cbl`, `gl020.cbl`, `gl030.cbl`, `gl050.cbl`, `gl051.cbl`, `gl060.cbl`, `gl070.cbl`, `gl071.cbl`, `gl072.cbl`, `gl080.cbl`, `gl090.cbl`, `gl090a.cbl`, `gl090b.cbl`, `gl100.cbl`, `gl105.cbl`, `gl120.cbl`
- `incomplete_records_system/`: `irs.cbl`, `irs010.cbl`, `irs020.cbl`, `irs030.cbl`, `irs040.cbl`, `irs050.cbl`, `irs055.cbl`, `irs060.cbl`, `irs065.cbl`, `irs070.cbl`, `irs080.cbl`, `irs085.cbl`, `irs090.cbl`, `irsub1.cbl`, `irsub2.cbl`, `irsub3.cbl`, `irsub4.cbl`, `irsub5.cbl`, `irsubp.cbl`
- `purchase/`: `pl000.cbl`, `pl010.cbl`, `pl015.cbl`, `pl020.cbl`, `pl025.cbl`, `pl030.cbl`, `pl040.cbl`, `pl050.cbl`, `pl055.cbl`, `pl060.cbl`, `pl070.cbl`, `pl080.cbl`, `pl085.cbl`, `pl090.cbl`, `pl095.cbl`, `pl100.cbl`, `pl115.cbl`, `pl120.cbl`, `pl130.cbl`, `pl140.cbl`, `pl160.cbl`, `pl165.cbl`, `pl170.cbl`, `pl180.cbl`, `pl190.cbl`, `pl900.cbl`, `pl910.cbl`, `pl920.cbl`, `pl930.cbl`, `pl940.cbl`, `pl950.cbl`, `pl960.cbl`, `purchase.cbl`
- `sales/`: `sales.cbl`, `sl000.cbl`, `sl010.cbl`, `sl020.cbl`, `sl050.cbl`, `sl055.cbl`, `sl060.cbl`, `sl070.cbl`, `sl080.cbl`, `sl085.cbl`, `sl090.cbl`, `sl095.cbl`, `sl100.cbl`, `sl110.cbl`, `sl115.cbl`, `sl120.cbl`, `sl130.cbl`, `sl140.cbl`, `sl160.cbl`, `sl165.cbl`, `sl170.cbl`, `sl180.cbl`, `sl190.cbl`, `sl200.cbl`, `sl900.cbl`, `sl910.cbl`, `sl920.cbl`, `sl930.cbl`, `sl940.cbl`, `sl950.cbl`, `sl960.cbl`
- `stock/`: `st000.cbl`, `st010.cbl`, `st020.cbl`, `st030.cbl`, `st040.cbl`, `st050.cbl`, `st060.cbl`, `stock.cbl`

### Failed (0)

None. There is no first compiler error line to report.

### Not built by any script (21)

- `common/`: `acas011.cbl`, `irsub1.cbl`, `irsub3.cbl`, `irsub4.cbl`, `irsub5.cbl`, `maps51.cbl`, `mapser.cbl`, `mapserup.cbl`, `stockMT.cbl`
- `experimental-stuff/`: `send-some-mail.cbl`, `send-some-mail2.cbl`
- `incomplete_records_system/RW-programs/`: `irs010.cbl`, `irs020.cbl`, `irs040.cbl`, `irs050-rw.cbl`, `irs090.cbl`, `irs090Rep.cbl`
- `stock/`: `acasconvert1.cbl`
- `stock/RW-Programs/`: `st010.cbl`, `st010.original.cbl`, `st010Rep.cbl`

## Produced executables and modules

All paths are relative to `/home/ubuntu/work/acas-legacy`. The listed `.so` files are shared modules; the six names without suffix are executable programs. No `.exe` files were produced.

- Root: executable `ACAS`
- `common/` (`.so`): `maps01.so`, `maps04.so`, `maps09.so`, `maps99.so`, `sys002.so`, `xl150.so`
- `general/`: executable `general`; modules `general.so`, `gl000.so`, `gl020.so`, `gl030.so`, `gl050.so`, `gl051.so`, `gl060.so`, `gl070.so`, `gl071.so`, `gl072.so`, `gl080.so`, `gl090.so`, `gl090a.so`, `gl090b.so`, `gl100.so`, `gl105.so`, `gl120.so`
- `incomplete_records_system/`: executable `irs`; modules `irs.so`, `irs010.so`, `irs020.so`, `irs030.so`, `irs040.so`, `irs050.so`, `irs055.so`, `irs060.so`, `irs065.so`, `irs070.so`, `irs080.so`, `irs085.so`, `irs090.so`, `irsub1.so`, `irsub2.so`, `irsub3.so`, `irsub4.so`, `irsub5.so`, `irsubp.so`
- `purchase/`: executable `purchase`; modules `purchase.so`, `pl000.so`, `pl010.so`, `pl015.so`, `pl020.so`, `pl025.so`, `pl030.so`, `pl040.so`, `pl050.so`, `pl055.so`, `pl060.so`, `pl070.so`, `pl080.so`, `pl085.so`, `pl090.so`, `pl095.so`, `pl100.so`, `pl115.so`, `pl120.so`, `pl130.so`, `pl140.so`, `pl160.so`, `pl165.so`, `pl170.so`, `pl180.so`, `pl190.so`, `pl900.so`, `pl910.so`, `pl920.so`, `pl930.so`, `pl940.so`, `pl950.so`, `pl960.so`
- `sales/`: executable `sales`; modules `sales.so`, `sl000.so`, `sl010.so`, `sl020.so`, `sl050.so`, `sl055.so`, `sl060.so`, `sl070.so`, `sl080.so`, `sl085.so`, `sl090.so`, `sl095.so`, `sl100.so`, `sl110.so`, `sl115.so`, `sl120.so`, `sl130.so`, `sl140.so`, `sl160.so`, `sl165.so`, `sl170.so`, `sl180.so`, `sl190.so`, `sl200.so`, `sl900.so`, `sl910.so`, `sl920.so`, `sl930.so`, `sl940.so`, `sl950.so`, `sl960.so`
- `stock/`: executable `stock`; modules `stock.so`, `st000.so`, `st010.so`, `st020.so`, `st030.so`, `st040.so`, `st050.so`, `st060.so`

## Build logs and diagnostics

Full standard output and error were captured in `/home/ubuntu/work/acas-legacy/build-logs/`:

- `comp-all.log`
- `comp-irs.log`
- `incomplete_records_system-comp-irs.log`
- `common-comp-common.log`
- `general-comp-gl.log`
- `purchase-comp-purchase.log`
- `sales-comp-sales.log`
- `stock-comp-stock.log`
- Smoke logs: `acas-smoke.log` (initial attempt without ACAS environment variables) and `acas-smoke-env.log` (run with required variables)

Corresponding build script exit statuses are in the `.exit` files in the same directory; all are `0`. The logs contain warnings but no compiler errors:

- `xl150.cbl:110`: copybook library `../purchase` not found; the compiler ignored that library.
- `irs010.cbl:277`, `irs020.cbl:240`, `irs030.cbl:291`: `OCCURS` screen items are not implemented.
- Inline `PERFORM` without imperative statement warnings: `sales/sl930.cbl:948–960`, `sales/sl950.cbl:785–797`, and `stock/st060.cbl:341, 395, 564, 588, 610`.

## ACAS startup smoke check

The initial run with only `COB_LIBRARY_PATH` set displayed `SY009 Environment variables not yet set up : ABORTING`; it did not create data files. The second run set `ACAS_LEDGERS`, `ACAS_IRS`, and `ACAS_BIN` to scratch/copy paths as required by the program, and set `COB_LIBRARY_PATH` to the built module directories. Under `script` with `TERM=xterm`, ACAS displayed `ACAS (3.00.05)` and reached `ACAS System Setup Routine - Level 1`, prompting for the company name. No menus were driven. The program was still waiting at setup when the timeout terminated the interactive process.

First-run data file observed in `/home/ubuntu/work/acas-legacy/run`:

- `system.dat` — 0 bytes at capture time.

No other `.dat` files were found in the scratch run directory or elsewhere in the copied tree.
