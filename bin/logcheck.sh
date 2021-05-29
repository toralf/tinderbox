#!/bin/bash
# set -x

# crontab example:
# * * * * * /opt/tb/bin/logcheck.sh

set -eu
export LANG=C.utf8

f=/tmp/${0##*/}.out

if [[ ! -s $f && "$(wc -c ~/logs/*.log 2>/dev/null | tail -n 1 | awk ' { print $1 } ')" != "0" ]]; then
  ls -l ~/logs/
  echo
  head -v ~/logs/*.log | tee $f
  echo
  echo -e "\n\nto re-activate this test again, do:\n\n  tail -v ~/logs/*; rm -f $f;     truncate -s 0 ~/logs/*\n\n"
fi
