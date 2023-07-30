#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# call this eg by:
# retest.sh $(tail -n 20 ~/tb/data/ALREADY_CAUGHT | cut -f 1 -d ' ')

set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

result=/tmp/$(basename $0) # package/s to be scheduled in the backlog of each image

# accept special atoms w/o qatom check
xargs -n 1 <<<$* |
  grep -v -e "^[@=+-_\./[[:alnum:]]]" |
  grep -e '^@' -e '^=' |
  sort -u >$result.special

# run special entries shuffled after existing ones of .1st
if [[ -s $result.special ]]; then
  tmp=$(mktemp /tmp/$(basename $0)_XXXXXX)
  while read -r bl; do
    cp $bl $tmp
    shuf $result.special >>$tmp
    uniq $tmp >$bl
  done < <(find ~tinderbox/run/*/var/tmp/tb/ -name "backlog.1st")
  rm $tmp $result.special

else
  # work at regular atoms
  xargs -n 1 <<<$* |
    grep -v -e "^[+-_\./[[:alnum:]]]" |
    sort -u |
    xargs -r qatom -F "%{CATEGORY}/%{PN}" 2>/dev/null |
    grep -v -F '<unset>' |
    grep ".*-.*/.*" |
    sort -u >$result

  # for few atoms re-test them immediately otherwise put them into the (lower prioritized) .upd backlog
  if [[ -s $result ]]; then
    if [[ $(wc -l <$result) -le 3 ]]; then
      suffix="1st"
    else
      suffix="upd"
    fi

    # shuffle new atoms and put them after existing ones
    tmp=$(mktemp /tmp/$(basename $0)_XXXXXX)

    while read -r bl; do
      # grep out dups
      grep -v -F -f $bl $result | shuf >$tmp
      cat $bl >>$tmp
      uniq $tmp >$bl
    done < <(find ~tinderbox/run/*/var/tmp/tb/ -name "backlog.$suffix")
    rm $tmp

    # delete atom entry in image specific files
    while read -r pkgname; do
      sed -i -e "/$(sed -e 's,/,\\/,' <<<$pkgname)\-[[:digit:]]/d" \
        ~tinderbox/tb/data/ALREADY_CAUGHT \
        ~tinderbox/run/*/etc/portage/package.mask/self \
        ~tinderbox/run/*/etc/portage/package.env/{cflags_default,nosandbox,test-fail-continue} 2>/dev/null || true
    done <$result
  fi
  rm $result
fi
