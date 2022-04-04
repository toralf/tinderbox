#!/bin/bash
# set -x


# stop tinderbox image/s


#############################################################################
#
# main
#
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

source $(dirname $0)/lib.sh

for i in ${@:-$(ls ~tinderbox/run 2>/dev/null)}
do
  echo -n "$(date +%X) "
  mnt=~tinderbox/img/$(basename $i)

  if [[ ! -d $mnt ]]; then
    echo "no valid mount point found for $mnt"
    continue
  fi

  if [[ -f $mnt/var/tmp/tb/STOP ]]; then
    echo " has STOP file: $mnt"
    continue
  fi

  if ! __is_running "$mnt" ; then
    echo " is not running: $mnt"
    continue
  fi

  echo "stopping $mnt"

  touch $mnt/var/tmp/tb/STOP
done
