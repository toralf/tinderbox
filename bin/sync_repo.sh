#!/bin/bash
#
#set -x


export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

mailto=tor-relay@zwiebeltoralf.de

log=/tmp/${0##*/}.log

date       > $log
eix-sync &>> $log
rc1=$?
# musl is not a repo used at the tinderbox host therefore eix-sync won't care for it
#
cd /var/db/repos/musl/ && git pull &>> $log
rc2=$?
date      >> $log

# update the timestamp file for each repos, used later in job.sh to decide inn each image whether to sync or not
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
  cd $( portageq get_repo_path / gentoo   ) && git prune &>> $log
  cd $( portageq get_repo_path / libressl ) && git prune &>> $log
  cd /var/db/repos/musl/                    && git prune &>> $log
fi

