#!/bin/bash
# set -x

# replace an older tinderbox image with a newer one


function Finish() {
  local rc=$1
  local pid=$$

  if [[ $rc -ne 0 ]]; then
    echo
    date
    echo " finished $pid with rc=$rc"
  fi

  sed -i -e "/^${pid}$/d" $lck
  if [[ ! -s $lck ]]; then
    rm $lck
  fi

  exit $rc
}


function GetCompleted() {
  grep -c ' ::: completed emerge' ~/run/$1/var/log/emerge.log || true
}


function GetLeft()  {
  wc -l < ~/run/$1/var/tmp/tb/backlog
}


function LookForEmptyBacklogs()  {
  while read oldimg
  do
    if [[ $(wc -l < <(cat ~/run/$oldimg/var/tmp/tb/backlog{,.1st} 2>/dev/null)) = "0" ]]; then
      return 0
    fi
  done < <(cd ~/run; ls -dt * 2>/dev/null | tac)

  return 1
}


function list_images() {
  (
    ls ~tinderbox/run/
    ls /run/tinderbox/ | sed 's,.lock,,g'
  )  2>/dev/null |\
  sort -u |\
  while read i
  do
    ls -d ~tinderbox/img{1,2}/${i} 2>/dev/null
  done |\
  sort -k 5 -t'/'
}


# look for an image satisfying the conditions
function LookForAnOldEnoughImage()  {
  local newest=$(cd ~/run; ls -t */etc/conf.d/hostname 2>/dev/null | cut -f1 -d'/' -s | head -n 1)
  if [[ -z "$newest" ]]; then
    return 1
  fi

  local current_time=$(date +%s)

  # min distance between 2 subsequent images
  if [[ $condition_distance -gt -1 ]]; then
    local distance
    let "distance = ($current_time - $(stat -c%Y $newest/etc/conf.d/hostname)) / 3600" || true
    if [[ $distance -lt $condition_distance ]]; then
      return 1
    fi
  fi

  # hint: $oldimg is set here as a side effect, but only used if "0" is returned
  while read oldimg
  do
    local runtime
    let "runtime = ($current_time - $(stat -c%Y ~/run/$oldimg/etc/conf.d/hostname)) / 3600 / 24" || true

    if [[ $condition_maxruntime -gt -1 ]]; then
      if [[ $runtime -ge $condition_maxruntime ]]; then
        return 0
      fi
    fi

    local left=$(GetLeft $oldimg)
    local completed=$(GetCompleted $oldimg)
    if [[ $condition_left -gt -1 && $condition_completed -gt -1 ]]; then
      if [[ $left -le $condition_left && $completed -ge $condition_completed ]]; then
        return 0
      fi
    elif [[ $condition_left -gt -1 ]]; then
      if [[ $left -le $condition_left ]]; then
        return 0
      fi
    elif [[ $condition_completed -gt -1 ]]; then
      if [[ $completed -ge $condition_completed ]]; then
        return 0
      fi
    fi
  done < <(cd ~/run; ls -t */etc/conf.d/hostname 2>/dev/null | cut -f1 -d'/' -s | tac)  # from oldest to newest

  return 1
}


function StopOldImage() {
  # kick off current entries and neutralize external restart-logic for a while
  cat << EOF > ~/run/$oldimg/var/tmp/tb/backlog.1st
STOP
STOP
STOP
STOP
STOP
STOP $(GetCompleted $oldimg) completed, $(GetLeft $oldimg) left
EOF

  local lock_dir=/run/tinderbox/$oldimg.lock
  if [[ -d $lock_dir ]]; then
    date
    echo " waiting for unlock ..."
    while [[ -d $lock_dir ]]
    do
      sleep 1
    done
    date
    echo " unlocked."
  else
    echo " image is not locked"
  fi
}


#######################################################################
set -eu
export LANG=C.utf8

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

condition_completed=-1      # completed emerge operations
condition_distance=-1       # distance in hours to the previous image
condition_left=-1           # left entries in backlogs
condition_maxruntime=-1     # age in days for an image

oldimg=""                   # optional: image name to be replaced ("-" to add a new one)
setupargs=""                # argument(s) for setup_img.sh

while getopts c:d:l:m:o:s: opt
do
  case "$opt" in
    c)  condition_completed="$OPTARG"   ;;
    d)  condition_distance="$OPTARG"    ;;
    l)  condition_left="$OPTARG"        ;;
    m)  condition_maxruntime="$OPTARG"  ;;

    o)  oldimg="${OPTARG##*/}"          ;;
    s)  setupargs="$OPTARG"             ;;
    *)  echo " opt not implemented: '$opt'"; exit 1;;
  esac
done

# do not run this script in parallel
lck="/tmp/${0##*/}.lck"
if [[ -s "$lck" ]]; then
  if kill -0 $(cat $lck) 2>/dev/null; then
    exit 1    # process is running
  fi
fi
echo $$ >> "$lck" || Finish 1

if [[ -z "$oldimg" ]]; then
  if ! LookForEmptyBacklogs; then
    if ! LookForAnOldEnoughImage; then
      Finish 0
    fi
  fi
elif [[ ! -e ~/run/$oldimg ]]; then
  echo " error, old image not found: $oldimg"
  Finish 1
fi

if [[ -e ~/run/$oldimg ]]; then
  echo
  date
  if [[ -e ~/run/$oldimg ]]; then
    echo " finishing $oldimg ..."
    StopOldImage
  fi
fi

echo
date
echo " setup a new image ..."

if sudo ${0%/*}/setup_img.sh $setupargs; then
  if [[ -e ~/run/$oldimg ]]; then
    rm -- ~/run/$oldimg ~/logs/$oldimg.log
  fi
  Finish 0
else
  Finish $?
fi

