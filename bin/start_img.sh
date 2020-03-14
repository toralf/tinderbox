#!/bin/bash
#
# set -x

export LANG=C.utf8

# start tinderbox chroot image/s
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " $0: wrong user $USER"
  exit 1
fi

for mnt in ${@:-$(ls ~/run 2>/dev/null)}
do
  echo -n "$(date +%X) "

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
  
  if [[ -f $mnt/var/tmp/tb/LOCK ]]; then
    echo " is running:  $mnt"
    continue
  fi

  if [[ -f $mnt/var/tmp/tb/STOP ]]; then
    echo " is stopping: $mnt"
    continue
  fi

  if [[ $(cat $mnt/var/tmp/tb/backlog* /var/tmp/tb/task 2>/dev/null | wc -l) -eq 0 ]]; then
    echo " all backlogs are empty: $mnt"
    continue
  fi

  cp /opt/tb/bin/job.sh $mnt/var/tmp/tb || continue

  echo " starting     $mnt"

  # nice -n 1 helps to analyze the SVG graphics of sysstat better
  #
  nice -n 1 sudo /opt/tb/bin/chr.sh $mnt "/bin/bash /var/tmp/tb/job.sh" &> ~/logs/${mnt##*/}.log &

  # avoid spurious trouble with mountall() in chr.sh
  #
  sleep 1
done

# avoid an invisible prompt
#
echo
