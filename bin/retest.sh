#!/bin/bash
# set -x


# call this eg by:
# grep 'setup phase' ~/tb/data/ALREADY_CATCHED | sed -e 's,\[.*\] ,,g' | cut -f1 -d' ' -s | xargs -r qatom -F "%{CATEGORY}/%{PN}" | xargs retest.sh


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
  pkgname=$(qatom -F "%{CATEGORY}/%{PN}" "$item" 2>/dev/null | grep -v -F '<unset>' | sed -e 's,/,\\/,g')
  if [[ -n "$pkgname" ]]; then
    if ! sed -i -e "/$pkgname/d" \
        ~tinderbox/tb/data/ALREADY_CATCHED \
        ~tinderbox/run/*/etc/portage/package.mask/self \
        ~tinderbox/run/*/etc/portage/package.env/{cflags_default,nosandbox,test-fail-continue} 2>/dev/null; then
      # ^^ not all of those files might exist
      :
    fi
  fi
done

if [[ -s $result ]]; then
  for i in $(ls ~tinderbox/run 2>/dev/null)
  do
    bl=~tinderbox/run/$i/var/tmp/tb/backlog.1st
    # filter out dups, then put new entries after existing ones
    (sort -u $result | grep -v -F -f $bl | shuf; cat $bl) > $bl.tmp
    mv $bl.tmp $bl
  done
fi
