#!/bin/bash
#
# set -x

# replace an older tinderbox image with a newer one
#


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


function GetCompl() {
  grep -c ' ::: completed emerge' ~/run/$1/var/log/emerge.log
}


function GetLeft()  {
  wc -l < ~/run/$1/var/tmp/tb/backlog
}


function LookForEmptyBacklogs()  {
  while read oldimg
  do
    n=$(wc -l < <(cat ~/run/$oldimg/var/tmp/tb/backlog{,.1st})) # ignore update, it is filled hourly
    [[ $? -eq 0 && $n -eq 0 ]] && return 0
  done < <(cd ~/run; ls -t */var/tmp/tb/name 2>/dev/null | cut -f1 -d'/' -s | tac)

  return 1
}


function list_images() {
  (
    ls ~tinderbox/run/
    ls /run/tinderbox/ | sed 's,.lock,,g'
  ) |\
  sort -u |\
  while read i
  do
    ls -d ~tinderbox/img{1,2}/${i} 2>/dev/null
  done |\
  sort -k 5 -t'/'
}


# look for an image satisfying the conditions
#
function LookForAnOldEnoughImage()  {
  local current_time=$(date +%s)
  local distance
  local newest=$(ls -t $(list_images | sed 's,$,/var/tmp/tb/name,g') 2>/dev/null | head -n 1)

  if [[ -n "$newest" ]]; then
    let "distance = ($current_time - $(stat -c%Y $newest)) / 3600"
    if [[ $distance -lt $condition_distance ]]; then
      return 1
    fi

    # hint: hereby the variable "oldimg" is set globally
    while read oldimg
    do
      [[ -f ~/run/$oldimg/var/tmp/tb/KEEP ]] && continue

      let "runtime = ($current_time - $(stat -c%Y ~/run/$oldimg/var/tmp/tb/name)) / 3600 / 24"
      if [[ $runtime -gt $condition_runtime ]]; then
        [[ $(GetLeft $oldimg) -lt $condition_backlog || $(GetCompl $oldimg) -gt $condition_completed ]] && return 0
      else
        [[ $(GetLeft $oldimg) -lt $condition_backlog && $(GetCompl $oldimg) -gt $condition_completed ]] && return 0
      fi
    done < <(cd ~/run; ls -t */var/tmp/tb/name 2>/dev/null | cut -f1 -d'/' -s | tac)  # from oldest to newest
  fi

  return 1
}


function StopOldImage() {
  # absorb external restart-logic
  #
  echo -e "STOP
STOP
STOP
STOP
STOP
STOP scheduled at $(unset LC_TIME; date +%R), $(GetCompl $oldimg) completed, $(GetLeft $oldimg) left
app-portage/pfl
" > ~/run/$oldimg/var/tmp/tb/backlog.1st

  local lock_dir=/run/tinderbox/$oldimg.lock
  if [[ -d $lock_dir ]]; then
    date
    echo " waiting for unlock ..."
    while [[ -d $lock_dir ]]; do
      sleep 1
    done
    date
    echo " unlocked."
  else
    echo " image is not locked"
  fi
}


#######################################################################
#
#
set -u

export LANG=C.utf8

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

condition_backlog=15000     # max. entries left in the backlog
condition_completed=6000    # min. amount of completed emerge operations
condition_distance=6        # min. distance in hours to the previous image
condition_runtime=13        # max. age in days for an image (where emerge efficiency drops down)
oldimg=""                   # optional: image name to be replaced ("-" to just spin up a new one)
setupargs=""                # args passed to call of setup_img.sh

while getopts b:c:d:o:r:s: opt
do
  case "$opt" in
    b)  condition_backlog="$OPTARG"   ;;
    c)  condition_completed="$OPTARG" ;;
    d)  condition_distance="$OPTARG"  ;;
    o)  oldimg="${OPTARG##*/}"        ;;
    s)  setupargs="$OPTARG"           ;;
    r)  condition_runtime="$OPTARG"   ;;
    *)  echo " opt not implemented: '$opt'"; exit 1;;
  esac
done

# do not run this script in parallel
#
lck="/tmp/${0##*/}.lck"
if [[ -s "$lck" ]]; then
  kill -0 $(cat $lck) 2>/dev/null
  if [[ $? -eq 0 ]]; then
    exit 1    # process is running
  fi
fi
echo $$ >> "$lck" || Finish 1

if [[ -z "$oldimg" ]]; then
  LookForEmptyBacklogs
  if [[ $? -ne 0 ]]; then
    LookForAnOldEnoughImage || Finish 0
  fi
fi

if [[ -n "$oldimg" && "$oldimg" != "-" ]]; then
  echo
  date
  if [[ -e ~/run/$oldimg ]]; then
    echo " replace $oldimg ..."
    StopOldImage
  else
    echo " error, not found: $oldimg ..."
    Finish 1
  fi
fi

while [[ : ]]
do
  echo
  date
  echo " setup a new image ..."

  sudo ${0%/*}/setup_img.sh $setupargs
  rc=$?
  if [[ $rc -eq 0 ]]; then
    if [[ -e ~/run/$oldimg ]]; then
      rm -- ~/run/$oldimg ~/logs/$oldimg.log
    fi
    Finish 0
  elif [[ $rc -eq 3 ]]; then
    continue
  else
    Finish $rc
  fi
done
