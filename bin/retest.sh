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
while read -r word
do
  echo "$word" >> $result

  # delete a package from global tinderbox file and from image specific files
  pkgname=$(qatom "$word" 2>/dev/null | cut -f1-2 -d' ' -s | grep -F -v '<unset>' | tr ' ' '/')
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
    touch /var/tmp/tb/SYNC  # force a repo sync

    bl=$i/var/tmp/tb/backlog.1st
    # put shuffled data (grep out dups before) ahead of high prio backlog
    (sort -u $result | grep -v -F -f $bl | shuf; cat $bl) > $bl.tmp
    mv $bl.tmp $bl
  done
fi
