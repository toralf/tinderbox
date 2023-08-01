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

# sam
#
if sort -u ~tinderbox/img/*/var/tmp/sam.txt >$tmpfile 2>/dev/null; then
  cp $tmpfile ~tinderbox/img/sam.txt
fi

# sam + flow
#

# every few months the next 2 lines should be commented out for 1 run to avoid growing those files infinitely
scope="run"
since="-cmin -65" # job runs hourly

cp ~tinderbox/img/needed.ELF.2.txt $tmpfile
find ~tinderbox/${scope:-img}/*/var/db/pkg/ -name NEEDED.ELF.2 ${since:-} -exec cat {} + >>$tmpfile
sort -u <$tmpfile >~tinderbox/img/needed.ELF.2.txt

cp ~tinderbox/img/needed.txt $tmpfile
find ~tinderbox/${scope:-img}/*/var/db/pkg/ -name NEEDED ${since:-} |
  while read -r file; do
    if pkg=$(sed -e 's,.*/var/db/pkg/,,' -e 's,/NEEDED,,' <<<$file); then # -MERGING race
      sed -e "s,^,$pkg ," $file
    fi
  done >>$tmpfile
sort -u <$tmpfile >~tinderbox/img/needed.txt

rm $tmpfile
