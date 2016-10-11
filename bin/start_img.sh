#!/bin/sh
#
#set -x

# start tinderbox chroot image/s
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " wrong user "
  exit 1
fi

# run a copy to allow editing of the origin
#
orig=/tmp/tb/bin/runme.sh
copy=/tmp/runme.sh

# delay start of subsequent images to lower I/O impact (but only after reboot)
#
uptime --pretty | cut -f3 -d ' ' | grep -q "minutes"
if [[ $? -eq 0 ]]; then
  delay=180
else
  delay=5
fi

sleep=0 # do not sleep before the 1st image
for mnt in ${@:-~/amd64-*}
do
  # $mnt must not be a broken symlink
  #
  if [[ -L $mnt && ! -e $mnt ]]; then
    echo "broken symlink: $mnt"
    continue
  fi

  # $mnt must be a directory
  #
  if [[ ! -d $mnt ]]; then
    echo "not a valid dir: $mnt"
    continue
  fi
  
  # image must not be locked
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
  if [[ -f $pks && ! -s $pks ]]; then
    echo " package list is empty: $mnt"
    continue
  fi

  # ok, start it
  #
  sleep $sleep
  nohup nice sudo ~/tb/bin/chr.sh $mnt "cp $orig $copy && $copy" &
  sleep=$delay
done

# avoid a non-visible prompt
#
if [[ $sleep ]]; then
  sleep 1
fi

