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

for mnt in ${@:-~/amd64-*}
do
  # $mnt must not be a broken symlink
  #
  if [[ -L $mnt && ! -e $mnt ]]; then
    [[ $verbose -eq 1 ]] && echo "broken symlink: $mnt"
    continue
  fi

  # $mnt must be a (chrootable) directory
  #
  if [[ ! -d $mnt ]]; then
    [[ $verbose -eq 1 ]] && echo "not a valid dir: $mnt"
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
done

# otherwise the prompt isn't visible (due to 'nohup ... &'  ?)
#
sleep 1
