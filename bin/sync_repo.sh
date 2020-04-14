#!/bin/bash
#
#set -x


export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

mailto="tor-relay@zwiebeltoralf.de"

log=/tmp/${0##*/}.log

date > $log
eix-sync &>> $log
rc1=$?

# musl repo is not configured at the tinderbox host so eix-sync can't care for it
#
cd /var/db/repos/musl/ && git pull &>> $log
rc2=$?
date >> $log

# set the timestamp here b/c not in each image might git already be emerged
#
for repo in gentoo libressl musl
do
  cd /var/db/repos/$repo && git show -s --format="%ct" HEAD > timestamp.git
done

if [[ $rc1 -ne 0 || $rc2 -ne 0 || -n "$(grep 'git pull error' $log)" ]]; then
  mail -s "${0##*/}: rc=$rc" $mailto < $log
  exit 1
fi

echo  >> $log
date  >> $log

grep -q "warning: There are too many unreachable loose objects; run 'git prune' to remove them." $log
if [[ $? -eq 0 ]]; then
  for repo in gentoo libressl musl
  do
    cd /var/db/repos/$repo && git prune &>> $log
  done
fi

