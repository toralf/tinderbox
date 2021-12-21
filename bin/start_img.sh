#!/bin/bash
# set -x


# start tinderbox chroot image/s


#############################################################################
#
# main
#
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8


if [[ ! "$(whoami)" = "tinderbox" ]]; then
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

  if [[ $(cat $mnt/var/tmp/tb/backlog{,,1st,.upd} /var/tmp/tb/task 2>/dev/null | wc -l) -eq 0 ]]; then
    echo " all backlogs are empty: $mnt"
    continue
  fi

  if __is_running "$mnt" ; then
    echo " image is locked:  $mnt"
    continue
  fi

  echo " starting: $mnt"

  # nice makes sysstat graphs better readable
  nice -n 3 sudo $(dirname $0)/bwrap.sh -m "$(basename $mnt)" -e "$(dirname $0)/job.sh" &> ~tinderbox/logs/$(basename $mnt).log &
done

# avoid an invisible prompt
echo
