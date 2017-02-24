#!/bin/sh
#
#set -x

# start tinderbox chroot image/s
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " wrong user "
  exit 1
fi

# delay start of subsequent images to lower I/O impact
#
delay=1
if [[ $# -eq 0 ]]; then
  # test if this script was called from /etc/local.d/tinderbox.start
  #
  if [[ -f /tmp/tinderbox.start.log ]]; then
    if [[ ! -s /tmp/tinderbox.start.log ]]; then
      delay=30
    fi
  fi
fi

is_first=1
for mnt in ${@:-~/run/*}
do
  # hint: prepend $@ with ./ to specify non-common location/s
  #
  if [[ "$mnt" = "$(basename $mnt)" ]]; then
    mnt=~/run/$mnt
  fi

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
  if [[ $is_first -eq 1 ]]; then
    is_first=0
  else
    sleep $delay
  fi

  cp /opt/tb/bin/{job,pre-check,switch2libressl}.sh $mnt/tmp
  chmod a+w $mnt/tmp/pre-check.sh         # allowed to be adapted by the tinderbox user

  echo " $(date) starting $mnt"
  nohup nice sudo /opt/tb/bin/chr.sh $mnt "/bin/bash /tmp/job.sh" &> ~/logs/$(basename $mnt).log &
done

# avoid a non-visible prompt
#
echo
