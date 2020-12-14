#!/bin/bash
# set -x

set -euf

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

mailto="tor-relay@zwiebeltoralf.de"


if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

log="/tmp/${0##*/}.log"

date > $log || exit 1
eix-sync &>> $log

# these repos are not used at the tinderbox host itself so eix-sync won't sync them
for repo in musl science
do
  date >> $log
  (cd /var/db/repos/$repo && git pull) &>> $log
done

# needed by job.sh
for repo in $(ls /var/db/repos/)
do
  if [[ -d /var/db/repos/$repo/.git ]]; then
    cd /var/db/repos/$repo
    git show -s --format="%ct" HEAD > timestamp.git
  fi
done

echo  >> $log
date  >> $log

if grep -q "warning: There are too many unreachable loose objects; run 'git prune' to remove them." $log; then
  for repo in $(ls /var/db/repos/)
  do
    cd /var/db/repos/$repo && git prune &>> $log
  done
fi
