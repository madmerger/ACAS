#!/bin/bash
# Verify cobol_layout.py record lengths against GnuCOBOL (FUNCTION LENGTH) for each copybook.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
WORK=${WORK:-$(mktemp -d)}
cd "$ROOT"
FILES="$*"
fail=0
for f in $FILES; do
  base=v$(echo "$f" | md5sum | cut -c1-10)
  src="$WORK/$base.cbl"
  names=$(python3 docs/migration/tools/cobol_layout.py "$f" | python3 -c "import json,sys;d=json.load(sys.stdin);[print(r['name'],r['length']) for rs in d.values() for r in rs]")
  {
    echo '       >>source free'
    echo ' identification division.'
    echo " program-id. v."
    echo ' data division.'
    echo ' working-storage section.'
    grep -v -i -E '^\s*fd\s' "$f" | grep -v -i '>>source'
    echo ' procedure division.'
    while read -r n l; do echo "     display \"$n \" function length($n)."; done <<< "$names"
    echo '     stop run.'
  } > "$src"
  ( cd "$WORK" && cobc -x -free -I "$ROOT/copybooks" -o "$base" "$src" 2>"$base.err" ) || { echo "COMPILE-FAIL $f: $(head -1 "$WORK/$base.err")"; fail=1; continue; }
  actual=$("$WORK/$base")
  while read -r n l; do
    a=$(echo "$actual" | awk -v n="$n" '$1==n{print $2+0}')
    if [ "$a" = "$l" ]; then echo "OK   $f $n $l"; else echo "DIFF $f $n parser=$l cobc=$a"; fail=1; fi
  done <<< "$names"
done
exit $fail
