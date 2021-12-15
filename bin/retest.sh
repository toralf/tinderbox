#!/bin/bash
# set -x


set -eu
export LANG=C.utf8

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

source $(dirname $0)/lib.sh

result=/tmp/$(basename $0).txt  # package/s for the appropriate backlog
truncate -s 0 $result

grep    -e '^@' -e '^%' -e '^='        <<< ${@} >> $result || true
grep -v -e '^@' -e '^%' -e '^=' -e '#' <<< ${@} |\
xargs --no-run-if-empty -n 1 |\
sort -u |\
while read -r atom
do
  echo "$atom" >> $result
  # delete from global and image specific files
  pkgname=$(qatom -F "%{CATEGORY}/%{PN}" "$atom" 2>/dev/null | grep -v -F '<unset>' | sed -e 's,/,\\/,g')
  if [[ -n "$pkgname" ]]; then
    if ! sed -i -e "/$pkgname/d" \
        ~tinderbox/tb/data/ALREADY_CATCHED \
        ~tinderbox/run/*/etc/portage/package.mask/self \
        ~tinderbox/run/*/etc/portage/package.env/{cflags_default,nosandbox,test-fail-continue} 2>/dev/null; then
      # ^^ those files might not exist currently
      :
    fi
  fi
done

if [[ -s $result ]]; then
  for i in $(__list_images)
  do
    bl=$i/var/tmp/tb/backlog.1st
    # filter out dups, then put new entries after existing ones
    (sort -u $result | grep -v -F -f $bl | shuf; cat $bl) > $bl.tmp
    mv $bl.tmp $bl
  done
fi
