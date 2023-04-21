#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# call this eg by:
# retest.sh $(tail -n 20 ~/tb/data/ALREADY_CAUGHT | cut -f 1 -d ' ')

set -eu
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

result=/tmp/$(basename $0) # package/s to be scheduled in the backlog of each image

# accept special atoms w/o any check
xargs -n 1 <<<$* |
  grep -e '^@' -e '^%' -e '^=' |
  sort -u >$result.special

# work at regular atoms
xargs -n 1 <<<$* |
  grep -v -e '^@' -e '^%' -e '^=' -e '#' |
  xargs -n 1 |
  sort -u |
  xargs qatom -F "%{CATEGORY}/%{PN}" 2>/dev/null |
  grep -v -F '<unset>' |
  grep ".*/.*" |
  sort -u >$result

if [[ -s $result ]]; then
  # emerge new atoms shuffled after existings
  tmp=$(mktemp /tmp/retest.sh_XXXXXX)
  for bl in $(ls ~tinderbox/run/*/var/tmp/tb/backlog.1st 2>/dev/null); do
    (
      # grep out dups
      grep -v -F -f $bl $result | shuf
      cat $bl
    ) >$tmp
    uniq $tmp >$bl
  done
  rm $tmp

  # reset atom in image specific files
  while read -r pkgname; do
    sed -i -e "/$(sed -e 's,/,\\/,' <<<$pkgname)\-[[:digit:]]/d" \
      ~tinderbox/tb/data/ALREADY_CAUGHT \
      ~tinderbox/run/*/etc/portage/package.mask/self \
      ~tinderbox/run/*/etc/portage/package.env/{cflags_default,nosandbox,test-fail-continue} 2>/dev/null || true
  done <$result
fi

if [[ -s $result.special ]]; then
  # emerge special entries before existings
  tmp=$(mktemp /tmp/retest.sh_XXXXXX)
  for bl in $(ls ~tinderbox/run/*/var/tmp/tb/backlog.1st 2>/dev/null); do
    cp $bl $tmp
    shuf $result.special >>$tmp
    uniq $tmp >$bl
  done
  rm $tmp
fi

rm $result{,.special}
