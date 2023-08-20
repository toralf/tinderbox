#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)

# sam_
if sort -u ~tinderbox/img/*/var/tmp/sam.txt >$tmpfile 2>/dev/null; then
  cp $tmpfile ~tinderbox/img/sam.txt
fi

# xgqt
if sort -u ~tinderbox/img/*/var/tmp/xgqt.txt >$tmpfile 2>/dev/null; then
  sort -nr $tmpfile >~tinderbox/img/xgqt.txt
fi

# sam_ + flow, run "reset" from time to time to clean up, otherwise run this hourly (65 == 5 min overlap)
(
  if [[ ${1-} == "reset" ]]; then
    find ~tinderbox/img/*/var/db/pkg/ -mindepth 3 -maxdepth 4 -name "NEEDED.ELF.2" 2>/dev/null |
      grep -v -F '/-MERGING-' |
      xargs -r cat 2>/dev/null
  else
    cat ~tinderbox/img/needed.ELF.2.txt
    find ~tinderbox/run/*/var/db/pkg/ -mindepth 3 -maxdepth 4 -name "NEEDED.ELF.2" -cmin -65 2>/dev/null |
      grep -v -F '/-MERGING-' |
      xargs -r cat 2>/dev/null
  fi
) | sort -u >$tmpfile
cp $tmpfile ~tinderbox/img/needed.ELF.2.txt

(
  if [[ ${1-} == "reset" ]]; then
    find ~tinderbox/img/*/var/db/pkg/ -mindepth 3 -maxdepth 4 -name "NEEDED" 2>/dev/null |
      grep -v -F '/-MERGING-' |
      xargs -r grep -H . 2>/dev/null |
      sed -e 's,^/home/tinderbox/.*/.*/var/db/pkg/,,' -e 's,/NEEDED:, ,'
  else
    cat ~tinderbox/img/needed.txt
    find ~tinderbox/run/*/var/db/pkg/ -mindepth 3 -maxdepth 4 -name "NEEDED" -cmin -65 2>/dev/null |
      grep -v -F '/-MERGING-' |
      xargs -r grep -H . 2>/dev/null |
      sed -e 's,^/home/tinderbox/.*/.*/var/db/pkg/,,' -e 's,/NEEDED:, ,'
  fi
) | sort -u >$tmpfile
cp $tmpfile ~tinderbox/img/needed.txt

rm $tmpfile
