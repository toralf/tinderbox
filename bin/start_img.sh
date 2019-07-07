#!/bin/bash
#
# set -x

# start tinderbox chroot image/s
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " $0: wrong user $USER"
  exit 1
fi

cd ~

for mnt in ${@:-$(ls ~/run 2>/dev/null)}
do
  # try to prepend ~/run if no path is given
  #
  if [[ ! -e $mnt && ! $mnt =~ '/' ]]; then
    mnt=~/run/$mnt
  fi

  if [[ ! -e $mnt ]]; then
    if [[ -L $mnt ]]; then
      echo "broken symlink: $mnt"
    else
      echo "vanished/invalid: $mnt"
    fi
    continue
  fi

  if [[ ! -d $mnt ]]; then
    echo "not a valid dir: $mnt"
    continue
  fi
  
  if [[ -f $mnt/tmp/LOCK ]]; then
    echo " image is not running: $mnt"
    continue
  fi

  if [[ -f $mnt/tmp/STOP ]]; then
    echo " image is not stopping: $mnt"
    continue
  fi

  if [[ $(cat $mnt/tmp/backlog* /tmp/task 2>/dev/null | wc -l) -eq 0 ]]; then
    echo " all backlogs are empty: $mnt"
    continue
  fi

  cp /opt/tb/bin/job.sh $mnt/tmp || continue

  echo " $(date) starting $mnt"
  nice sudo /opt/tb/bin/chr.sh $mnt "/bin/bash /tmp/job.sh" &> ~/logs/$(basename $mnt).log &

  # avoid spurious trouble with mount in chr.sh
  #
  sleep 1

done

# avoid a non-visible prompt
#
echo
