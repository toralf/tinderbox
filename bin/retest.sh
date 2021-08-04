#!/bin/bash
# set -x


set -eu
export LANG=C.utf8

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

source $(dirname $0)/lib.sh

result=/tmp/${0##*/}.txt  # package/s for the appropriate backlog
truncate -s 0 $result

xargs -n 1 <<< ${@} |\
sort -u |\
grep -v "^$" |\
while read -r word
do
  echo "$word" >> $result

  # delete a package in global and image specific files
  pkgname=$(qatom "$word" 2>/dev/null | cut -f1-2 -d' ' -s | grep -v -F '<unset>' | tr ' ' '/')
  if [[ -n "$pkgname" ]]; then
    sed -i -e "/$(sed -e 's,/,\\/,' <<< $pkgname)/d"  \
        ~/tb/data/ALREADY_CATCHED                     \
        ~/run/*/etc/portage/package.mask/self         \
        ~/run/*/etc/portage/package.env/{cflags_default,nosandbox,test-fail-continue} \
        2>/dev/null || true
  fi
done

if [[ -s $result ]]; then
  for i in $(__list_images)
  do
    bl=$i/var/tmp/tb/backlog.1st
    if [[ -s $bl ]]; then
      # filter out dups, schedule new entries after existing entries
      (sort -u $result | grep -v -F -f $bl | shuf; cat $bl) > $bl.tmp
    else
      shuf $result > $bl.tmp
    fi
    mv $bl.tmp $bl
  done
fi
