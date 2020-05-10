#!/bin/bash
#
# set -x


# stop tinderbox chroot image/s
#


function __is_running() {
  [[ -d "/sys/fs/cgroup/tinderbox/${1##*/}" ]]
  return $?
}


set -euf
export LANG=C.utf8

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

for i in ${@:-$(ls ~/run 2>/dev/null)}
do
  echo -n "$(date +%X) "

  mnt="$(ls -d ~tinderbox/img{1,2}/${i##*/} 2>/dev/null || true)"

  if [[ -z "$mnt" || ! -d "$mnt" || -L "$mnt" || $(stat -c '%u' "$mnt") -ne 0 ]]; then
    echo "no valid mount point found for $i"
    continue
  fi

  if [[ "$mnt" =~ ".." || "$mnt" =~ "//" || "$mnt" =~ [[:space:]] || "$mnt" =~ '\' ]]; then
    echo "illegal character(s) in mount point $mnt"
    continue
  fi


  if ! __is_running "$mnt" ; then
    echo " is not running: $mnt"
    continue
  fi

  if [[ -f $mnt/var/tmp/tb/STOP ]]; then
    echo " is stopping: $mnt"
    continue
  fi

  echo " stopping     $mnt"
  touch "$mnt/var/tmp/tb/STOP"
done
