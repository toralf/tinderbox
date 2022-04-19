#!/bin/bash
# set -x


# call this eg by:
# grep 'setup phase' ~/tb/data/ALREADY_CATCHED | sed -e 's,\[.*\] ,,g' | cut -f1 -d' ' | xargs retest.sh


set -eu
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

result=/tmp/$(basename $0).txt  # package/s to be scheduled in the backlog of each image

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
    ~tinderbox/tb/data/ALREADY_CATCHED \
    ~tinderbox/run/*/etc/portage/package.mask/self \
    ~tinderbox/run/*/etc/portage/package.env/{cflags_default,nosandbox,test-fail-continue} 2>/dev/null || true
done

if [[ -s $result ]]; then
  for bl in $(ls ~tinderbox/run/*/var/tmp/tb/backlog.1st 2>/dev/null)
  do
    tmp=$(mktemp /tmp/retest.sh_XXXXXX)
    # filter out dups, then put new entries after existing ones
    (grep -v -F -f $bl $result | shuf; cat $bl) > $tmp
    cp $tmp $bl
    rm $tmp
  done
fi
