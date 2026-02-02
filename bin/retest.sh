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

# %command
if grep '%' <<<$* >$result.command; then
  tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX)
  # run special entries shuffled after existing ones of .1st
  while read -r bl; do
    cp $bl $tmpfile
    cat $result.command >>$tmpfile
    uniq $tmpfile >$bl
  done < <(find ~tinderbox/run/*/var/tmp/tb/ -maxdepth 1 -name "backlog.1st")
  rm $tmpfile
  echo " added $(wc -l <$result.command) %command" >&2

# regular packages
else
  xargs -r -n 1 <<<$* |
    while read -r atom; do
      if [[ $atom =~ ^@ || $atom =~ ^= ]]; then
        echo "$atom"
      else
        if ! qatom -CF "%{CATEGORY}/%{PN}" $atom |
          grep -v '<unset>' |
          grep ".*-.*/.*"; then
          echo " skipping: '$atom'" >&2
        fi
      fi
    done >$result.packages

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
fi

rm $result.command
