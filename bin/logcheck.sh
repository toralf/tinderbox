#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

f=/tmp/$(basename $0).out
n=$(wc -l < <(cat ~tinderbox/logs/*.log 2>/dev/null))
if [[ $n -gt 0 ]]; then
  if [[ ! -s $f ]]; then
    {
      ls -l ~tinderbox/logs/
      echo
      head -n 100 -v ~tinderbox/logs/*.log | tee $f
      echo
      echo -e "\n\nto re-activate this test again, do:\n\n  truncate -s 0 ~tinderbox/logs/*\n\n"
    } |
      mail -s "INFO: tinderbox logs" tinderbox
  fi
else
  # remove marker file which avoids mail spam
  if [[ -f $f ]]; then
    rm $f
  fi
fi
