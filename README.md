# ACAS

ACAS (Applewood Computers Accounting System) is a COBOL-based accounting
application with ledger, stock, sales, and purchasing workflows represented in
this source distribution. The menu also references payroll and point-of-sale
modules, but those modules are not included in the open-source distribution.

## Source layout

- `ACAS.cbl` — main program and menu
- `common/` — shared COBOL modules
- `copybooks/` — reusable data and file definitions
- `comp-all.sh` — build helper for the application programs

The project is preserved as a source distribution; review the existing shell
scripts and copybooks before compiling or running individual modules.
