#!/bin/bash
#
# set -x


# start tinderbox chroot image/s
#


set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8
export GREP_COLOR="never"
export GREP_COLORS="never"

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

for i in ${@:-$(ls ~/run 2>/dev/null)}
do
  echo -n "$(date +%X) "

  mnt="$(ls -d ~tinderbox/img{1,2}/${i##*/} 2>/dev/null || true)"

  if [[ -z "$mnt" || ! -d "$mnt" || -L "$mnt" || $(stat -c '%u' "$mnt") -ne 0 ]]; then
    echo "no valid mount point found"
    continue
  fi

  if [[ "$mnt" =~ ".." || "$mnt" =~ "//" || "$mnt" =~ [[:space:]] || "$mnt" =~ '\' ]]; then
    echo "illegal character(s) in mount point"
    continue
  fi

  if [[ -f $mnt/var/tmp/tb/LOCK ]]; then
    echo " is running:  $mnt"
    continue
  fi

  if [[ -f $mnt/var/tmp/tb/STOP ]]; then
    echo " is stopping: $mnt"
    continue
  fi

  if [[ $(cat $mnt/var/tmp/tb/backlog{,,1st,.upd} /var/tmp/tb/task 2>/dev/null | wc -l) -eq 0 ]]; then
    echo " all backlogs are empty: $mnt"
    continue
  fi

  echo " starting     $mnt"

  # nice makes reading of sysstat numbers easier
  #
  nice -n 1 sudo /opt/tb/bin/bwrap.sh "$mnt" "/opt/tb/bin/job.sh" &> ~/logs/${mnt##*/}.log &
done

# avoid an invisible prompt
#
echo
