#!/bin/bash
# set -x


# call this eg by:
# grep 'setup phase' ~/tb/data/ALREADY_CAUGHT | sed -e 's,\[.*\] ,,g' | cut -f1 -d' ' | xargs retest.sh


set -eu
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

result=/tmp/$(basename $0).txt  # package/s to be scheduled in the backlog of each image

first=0
if [[ "$1" = "1st" ]]; then
  first=1
  shift
fi

# accept special *lines* w/o any check
grep -e '^@' -e '^%' -e '^=' <<< ${@} |\
sort -u > $result

# work at regular atoms
grep -v -e '^@' -e '^%' -e '^=' -e '#' <<< ${@} |\
sort -u |\
xargs qatom -F "%{CATEGORY}/%{PN}" 2>/dev/null |\
grep -v -F '<unset>' |\
grep ".*/.*" |\
sort -u |\
tee -a $result |\
while read -r pkgname
do
  sed -i -e "/$(sed -e 's,/,\\/,' <<< $pkgname)\-[[:digit:]]/d" \
    ~tinderbox/tb/data/ALREADY_CAUGHT \
    ~tinderbox/run/*/etc/portage/package.mask/self \
    ~tinderbox/run/*/etc/portage/package.env/{cflags_default,nosandbox,test-fail-continue} 2>/dev/null || true
done

if [[ -s $result ]]; then
  tmp=$(mktemp /tmp/retest.sh_XXXXXX)
  if [[ $first -eq 1 ]]; then
    for bl in $(ls ~tinderbox/run/*/var/tmp/tb/backlog.1st 2>/dev/null)
    do
      # put new entries shuffled after existing ones, filter out dups before
      (grep -v -F -f $bl $result | shuf; cat $bl) > $tmp
      cp $tmp $bl
    done
  else
    for bl in $(ls ~tinderbox/run/*/var/tmp/tb/backlog.upd 2>/dev/null)
    do
      # mix existing and new entries and resolve dups
      cat $bl $result | sort -u | shuf > $tmp
      cp $tmp $bl
    done
  fi
  rm $tmp
fi
