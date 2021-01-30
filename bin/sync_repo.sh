#!/bin/bash
# set -x

set -euf

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8


if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

log="/tmp/${0##*/}.log"

date > $log || exit 1
eix-sync &>> $log

# sync repos which are not configured at the tinderbox host
for repo in libressl musl science
do
  date >> $log
  cd /var/db/repos/$repo 2>/dev/null || continue
  git pull &>> $log
done

# needed by job.sh to decide whether to sync with local image or not
for repo in $(ls /var/db/repos/)
do
  if [[ -d /var/db/repos/$repo/.git ]]; then
    cd /var/db/repos/$repo
    git show -s --format="%ct" HEAD > timestamp.git
  fi
done

echo >> $log
date >> $log

if grep -q "warning: " $log; then
  cat $log
fi

