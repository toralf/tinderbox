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

# be verbose if image names are given
#
verbose=0
if [[ $# -gt 0 ]]; then
  verbose=1
fi

# delayed start after boot to lower the I/O impact
#
sleep=0
uptime --pretty | cut -f3 -d ' ' | grep -q "minutes"
if [[ $? -eq 0 ]]; then
  min=$(uptime --pretty | cut -f2 -d ' ')
  if [[ $min -lt 10 ]]; then
    sleep=120
    rm -f amd64-*/tmp/{LOCK,STOP} # cleanup
  fi
fi

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
  nohup nice sudo ~/tb/bin/chr.sh $mnt "cp $orig $copy && $copy" &

  sleep $sleep
done

# otherwise the prompt isn't visible (due to 'nohup ... &'  ?)
#
sleep 1

