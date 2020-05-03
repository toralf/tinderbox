#!/bin/bash
#
# set -x


# start tinderbox chroot image/s
#

set -euf
export LANG=C.utf8


if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " $0: wrong user $USER"
  exit 1
fi

for i in ${@:-$(ls ~/run 2>/dev/null)}
do
  echo -n "$(date +%X) "

  mnt="$(ls -d ~tinderbox/img{1,2}/${i##*/} 2>/dev/null || true)"

  if [[ ! -d "$mnt" ]]; then
    echo "not a valid mount point: '$mnt'"
    exit 1
  fi

  if [[ -f $mnt/var/tmp/tb/LOCK ]]; then
    echo " is running:  $mnt"
    continue
  fi

  if [[ -f $mnt/var/tmp/tb/STOP ]]; then
    echo " is stopping: $mnt"
    continue
  fi

  if [[ $(cat $mnt/var/tmp/tb/backlog* /var/tmp/tb/task 2>/dev/null | wc -l) -eq 0 ]]; then
    echo " all backlogs are empty: $mnt"
    continue
  fi

  cp /opt/tb/bin/job.sh $mnt/var/tmp/tb || continue
  chmod u+x $mnt/var/tmp/tb/job.sh

  echo " starting     $mnt"

  # nice makes reading of sysstat numbers easier
  #
  nice -n 1 sudo /opt/tb/bin/bwrap.sh "$mnt" "/var/tmp/tb/job.sh" &> ~/logs/${mnt##*/}.log &
done

# avoid an invisible prompt
#
echo
