#!/bin/sh
#
#set -x

# start a tinderbox chroot image
#
iam="$(whoami)"
if [[ ! "$iam" = "tinderbox" ]]; then
  echo " wrong user '$iam' !"
  exit 1
fi

orig=/tmp/tb/bin/runme.sh
copy=/tmp/runme.sh

# be more verbose if image names are given (== likely interactive mode)
#
verbose=0
if [[ $# -gt 0 ]]; then
  verbose=1
fi

# delay subsequent start to lower I/O impact
#
sleep=0

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
    [[ $verbose -eq 1 ]] && echo " found LOCK: $mnt"
    continue
  fi
  
  # image must not be stopping
  #
  if [[ -f $mnt/tmp/STOP ]]; then
    [[ $verbose -eq 1 ]] && echo " found STOP: $mnt"
    continue
  fi

  # non-empty package list is required
  #
  pks=$mnt/tmp/packages
  if [[ -f $pks && ! -s $pks ]]; then
    [[ $verbose -eq 1 ]] && echo " package list is empty: $mnt"
    continue
  fi

  # ok, start it
  #
  sleep $sleep
  nohup nice sudo ~/tb/bin/chr.sh $mnt "cp $orig $copy && $copy" &

  # heuristic test of a reboot where the cache isn't filled
  #
  uptime --pretty | cut -f3 -d ' ' | grep -q "minutes"
  if [[ $? -eq 0 ]]; then
    sleep=60
  else
    sleep=5
  fi
done

# otherwise the prompt isn't visible (due to 'nohup ... &'  ?)
#
if [[ $sleep ]]; then
	sleep 1
fi

