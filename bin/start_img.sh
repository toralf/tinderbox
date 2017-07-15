#!/bin/sh
#
#set -x

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

# lower the I/O impact having an empty cache after reboot
#
sleep=0
if [[ "$1" = "reboot" ]]; then
  sleep=180
  shift
fi

cd ~

for mnt in ${@:-$(ls ~/run)}
do
  if [[ ! -d $mnt ]]; then
    tmp=$(ls -d /home/tinderbox/img?/$mnt 2>/dev/null)
    if [[ ! -d $tmp ]]; then
      echo "cannot guess the full path to the image $mnt"
      continue
    fi
    mnt=$tmp
  fi

  # $mnt must not be a broken symlink
  #
  if [[ -L $mnt && ! -e $mnt ]]; then
    echo "broken symlink: $mnt"
    continue
  fi

  # $mnt must be or point to a directory
  #
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

  # non-empty package list required
  #
  pks=$mnt/tmp/packages
  if [[ ! -s $pks ]]; then
    echo " package list is empty: $mnt"
    continue
  fi

  cp /opt/tb/bin/{job,pre-check,switch2libressl}.sh $mnt/tmp || continue

  sleep $sleep
  echo " $(date) starting $mnt"
  nohup nice sudo /opt/tb/bin/chr.sh $mnt "/bin/bash /tmp/job.sh" &> ~/logs/$(basename $mnt).log &
  sleep 1

done

# avoid a non-visible prompt
#
echo
