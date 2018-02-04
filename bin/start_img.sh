#!/bin/sh
#
# set -x

# start tinderbox chroot image/s
#
# typcial call:
#
# $> start_img.sh desktop-libressl_20170224-103028
#
if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " $0: wrong user $USER"
  exit 1
fi

# lower the I/O pressure b/c disk cache is empty after reboot
#
sleep=0
if [[ "$1" = "reboot" ]]; then
  sleep=120
  shift
fi

cd ~

for mnt in ${@:-$(ls ~/run)}
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
  
  # image must not be running
  #
  if [[ -f $mnt/tmp/LOCK ]]; then
    echo " found LOCK: $mnt"
    continue
  fi

  # image must not be stopping
  #
  if [[ -f $mnt/tmp/STOP ]]; then
    echo " found STOP: $mnt"
    continue
  fi

  # at least one non-empty backlog is required
  #
  if [[ $(cat $mnt/tmp/backlog* 2>/dev/null | wc -l) -eq 0 ]]; then
    echo " all backlogs are empty: $mnt"
    continue
  fi

  cp /opt/tb/bin/{job,pre-check}.sh $mnt/tmp || continue

  sleep $sleep
  echo " $(date) starting $mnt"
  nohup nice sudo /opt/tb/bin/chr.sh $mnt "/bin/bash /tmp/job.sh" &> ~/logs/$(basename $mnt).log &
  sleep 1

done

# avoid a non-visible prompt
#
echo
