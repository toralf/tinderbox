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

if ls /tmp/$(basename $0)_* 2>/dev/null; then
  echo "another instance seems to run" >&2
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

# sam_ + flow
if [[ ${1-} == "reset" ]]; then
  # run this monthly or so to get rid of old stuff
  scope=""
  since=""
else
  scope="run"
  since="-cmin -65" # job runs hourly for <1min, so a 5 min overlap seems sufficient
fi

if [[ ${1-} == "reset" ]]; then
  truncate -s 0 $tmpfile
else
  cp ~tinderbox/img/needed.ELF.2.txt $tmpfile
fi
find ~tinderbox/${scope:-img}/*/var/db/pkg/ -mindepth 3 -maxdepth 4 -name "NEEDED.ELF.2" ${since-} 2>/dev/null |
  grep -v -F '/-MERGING-' |
  xargs -r cat 2>/dev/null |
  sort -u >>$tmpfile
cp $tmpfile ~tinderbox/img/needed.ELF.2.txt

if [[ ${1-} == "reset" ]]; then
  truncate -s 0 $tmpfile
else
  cp ~tinderbox/img/needed.txt $tmpfile
fi
find ~tinderbox/${scope:-img}/*/var/db/pkg/ -mindepth 3 -maxdepth 4 -name "NEEDED" ${since-} 2>/dev/null |
  grep -v -F '/-MERGING-' |
  xargs -r grep -H . 2>/dev/null |
  sed -e 's,^/home/tinderbox/.*/.*/var/db/pkg/,,' -e 's,/NEEDED:, ,' |
  sort -u >>$tmpfile
cp $tmpfile ~tinderbox/img/needed.txt

rm $tmpfile
