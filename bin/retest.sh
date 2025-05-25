#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# retest package(s), before remove all possible entries from mask files etc.

set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

result=/tmp/$(basename $0) # hold package(s) to be scheduled

# special atoms
grep -e '^%' <<<$* |
  sort -u >$result.special
if [[ -s $result.special ]]; then
  tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX)
  # run special entries shuffled after existing ones of .1st
  while read -r bl; do
    cp $bl $tmpfile
    shuf $result.special >>$tmpfile
    uniq $tmpfile >$bl
  done < <(find ~tinderbox/run/*/var/tmp/tb/ -maxdepth 1 -name "backlog.1st")
  rm $tmpfile
  echo " added $(wc -l <$result.special) special item(s)" >&2
fi
rm $result.special

# regular packages
grep -v -e '^%' <<<$* |
  xargs -r -n 1 |
  sort -u |
  while read -r atom; do
    if [[ $atom =~ ^@ || $atom =~ ^= ]]; then
      echo "$atom"
    else
      qatom -CF "%{CATEGORY}/%{PN}" $atom |
        grep -v '<unset>' |
        grep ".*-.*/.*"
    fi
  done |
  sort -u >$result.packages

if [[ -s $result.packages ]]; then
  # if there're only few packages then emerge them immediately
  if [[ $(wc -l <$result.packages) -le 3 ]]; then
    suffix="1st"
  else
    suffix="upd"
  fi
  echo -n " adding $(wc -l <$result.packages) package/s to $suffix ..." >&2

  # shuffle new packages, put them after the existing entries
  tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX)
  while read -r bl; do
    # grep out duplicates
    grep -v -F -x -f $bl $result.packages | shuf >$tmpfile
    cat $bl >>$tmpfile
    uniq $tmpfile >$bl
  done < <(find ~tinderbox/run/*/var/tmp/tb/ -maxdepth 1 -name "backlog.$suffix")
  rm $tmpfile
  echo

  # delete the package in each image specific file
  while read -r pkgname; do
    sed -i -e "/$(sed -e 's,/,\\/,' <<<$pkgname)\-[[:digit:]]/d" \
      ~tinderbox/tb/findings/ALREADY_CAUGHT \
      ~tinderbox/run/*/etc/portage/package.mask/self \
      ~tinderbox/run/*/etc/portage/package.env/{cflags_default,nosandbox,test-fail-continue} 2>/dev/null || true
  done <$result.packages
fi
rm $result.packages
