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
echo >> $log
date >> $log

if grep -q "warning: " $log; then
  cat $log
fi
