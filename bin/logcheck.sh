#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

set -eu
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

f=/tmp/$(basename $0).out
n=$(wc -l < <(cat ~tinderbox/logs/*.log 2>/dev/null) )
if [[ $n -gt 0 ]]; then
  if [[ ! -s $f ]]; then
    (
      ls -l ~tinderbox/logs/
      echo
      head -n 100 -v ~tinderbox/logs/*.log | tee $f
      echo
      echo -e "\n\nto re-activate this test again, do:\n\n  tail -v ~tinderbox/logs/*; rm -f $f;     truncate -s 0 ~tinderbox/logs/*\n\n"
    ) |
    mail -s "INFO: tinderbox logs" ${MAILTO:-tinderbox}
  fi
else
  # remove obsolete file
  if [[ -f $f ]]; then
    rm $f
  fi
fi
