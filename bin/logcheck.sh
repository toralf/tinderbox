#!/bin/bash
# set -x

# act if stdout/err of job.sh is non-empty

set -u
export LANG=C.utf8

f=/tmp/${0##*/}.out

# if non-empty than it was already reported
if [[ ! -s $f ]]; then
  if [[ "$(wc -c ~/logs/*.log 2>/dev/null | tail -n 1 | awk ' { print $1 } ')" != "0" ]]; then
    ls -l ~/logs/
    echo
    head -v ~/logs/*.log | tee $f
    echo
    echo -e "\n\nto re-activate this test again, do:\n\n  tail -v ~/logs/*; rm -f $f;     truncate -s 0 ~/logs/*\n\n"
  fi
fi
