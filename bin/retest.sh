#!/bin/bash
# set -x


# call this eg by:
# grep 'setup phase' ~/tb/data/ALREADY_CATCHED | sed -e 's,\[.*\] ,,g' | cut -f1 -d' ' | xargs retest.sh


set -eu
export LANG=C.utf8

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

result=/tmp/$(basename $0).txt  # package/s to be scheduled in the backlog of each image
truncate -s 0 $result

# accept special *lines* w/o any check
if ! grep -e '^@' -e '^%' -e '^=' <<< ${@} >> $result; then
  :
fi

# work at the the remaining *items*
grep -v -e '^@' -e '^%' -e '^=' -e '#' <<< ${@} |\
xargs --no-run-if-empty -n 1 |\
sort -u |\
while read -r item
do
  echo "$item" >> $result
  # reset issue artefacts
  pkgname=$(qatom -F "%{CATEGORY}/%{PN}" "$item" 2>/dev/null | grep -v -F '<unset>' | grep ".*/.*")
  if [[ -n $pkgname ]]; then
    if ! sed -i -e "/$(sed -e 's,/,\\/,' <<< $pkgname)-[[:digit:]]/d" \
        ~tinderbox/tb/data/ALREADY_CATCHED \
        ~tinderbox/run/*/etc/portage/package.mask/self \
        ~tinderbox/run/*/etc/portage/package.env/{cflags_default,nosandbox,test-fail-continue} 2>/dev/null; then
      :   # ^^ not all of those files might exist
    fi
  fi
done

if [[ -s $result ]]; then
  for bl in $(ls ~tinderbox/run/*/var/tmp/tb/backlog.1st 2>/dev/null)
  do
    tmp=$(mktemp /tmp/bl_XXXXXX)
    # filter out dups, then put new entries after existing ones
    (sort -u $result | grep -v -F -f $bl | shuf; cat $bl) > $tmp
    cp $tmp $bl
    rm $tmp
  done
fi
