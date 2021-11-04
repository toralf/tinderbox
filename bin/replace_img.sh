#!/bin/bash
# set -x

# replace an image with a new one


function Finish() {
  local rc=${1:-$?}
  local pid=$$

  trap - INT QUIT TERM EXIT

  if [[ $rc -ne 0 ]]; then
    echo
    date
    echo " pid $pid exited with rc=$rc"
  fi

  rm $lockfile
  exit $rc
}


function GetCompletedEmergeOperations() {
  grep -c ' ::: completed emerge' ~/run/$1/var/log/emerge.log 2>/dev/null || echo "0"
}


function NumberOfPackagesInBacklog()  {
  wc -l 2>/dev/null < ~/run/$1/var/tmp/tb/backlog || echo "0"
}


function AnImageHasAnEmptyBacklog()  {
  while read -r i
  do
    local bl=~/run/$i/var/tmp/tb/backlog
    if [[ -f $bl ]]; then
      if [[ $(wc -l < $bl) -eq 0 ]]; then
        oldimg=$i
        return 0
      fi
    else
      echo "warn: $bl is missing !"
    fi
  done < <(cd ~/run; ls -dt * 2>/dev/null | tac)

  return 1
}


function WorldBrokenAndOld() {
  while read -r i
  do
    local file=~/run/$i/var/tmp/tb/@world.history
    if [[ -s $file ]]; then
      local line=$(tail -n 1 $file)
      if grep -q " NOT ok $" <<< $line; then
        local days=$(( ( $(date +%s) - $(getStartTime $i) ) / 86400 ))
        if [[ $days -ge 4 ]]; then
          oldimg=$i
          return 0
        fi
      fi
    fi
  done < <(cd ~/run; ls -dt * 2>/dev/null | tac)

  return 1
}


function MinDistanceIsReached()  {
  local newest=$(cd ~/run; ls -t */etc/conf.d/hostname 2>/dev/null | cut -f1 -d'/' -s | head -n 1)
  if [[ -z "$newest" ]]; then
    return 1
  fi

  local distance=$(( ( $(date +%s) - $(stat -c%Y ~/run/$newest/etc/conf.d/hostname) ) / 3600 ))
  [[ $distance -ge $condition_distance ]]
}


function MaxCountIsRunning()  {
  if ! pgrep -f $(dirname $0)/setup_img.sh 1>/dev/null; then
    [[ $(ls ~/run/ 2>/dev/null | wc -l) -ge $condition_count || $(ls /run/tinderbox 2>/dev/null | wc -l) -ge $condition_count ]]
  fi
}


function __ReachedMaxRuntime()  {
  local runtime=$(( ( $(date +%s) - $(stat -c%Y ~/run/$1/etc/conf.d/hostname) ) / 3600 / 24))
  [[ $runtime -ge $condition_runtime ]]
}


function __TooSmallBacklog()  {
  [[ $(NumberOfPackagesInBacklog $1) -le $condition_left ]]
}


function __EnoughCompletedEmergeOperations()  {
  [[ $(GetCompletedEmergeOperations $1) -ge $condition_completed ]]
}


function AnImageReachedEOL()  {
  while read -r i
  do
    if [[ $condition_runtime -gt -1 ]]; then
      if __ReachedMaxRuntime $i; then
        reason="reached max runtime"
        oldimg=$i
        return 0
      fi
    fi
    if [[ $condition_left -gt -1 ]]; then
      if __TooSmallBacklog $i; then
        reason="too small backlog"
        oldimg=$i
        return 0
      fi
    fi
    if [[ $condition_completed -gt -1 ]]; then
      if __EnoughCompletedEmergeOperations $i; then
        reason="enough completed"
        oldimg=$i
        return 0
      fi
    fi
  done < <(cd ~/run; ls -t */etc/conf.d/hostname 2>/dev/null | cut -f1 -d'/' -s | tac)

  return 1
}


function StopOldImage() {
  local msg="replace reason: $1"

  echo
  date
  echo " $msg for $oldimg"

  local lock_dir=/run/tinderbox/$oldimg.lock
  if [[ -d $lock_dir ]]; then
    date
    echo " waiting for image unlock ..."

    # do not just put a "STOP" into backlog.1st b/c job.sh might prepend additional task/s onto it
    # repeat STOP lines to neutralise an external triggered restart
    cat << EOF >> ~/run/$oldimg/var/tmp/tb/backlog.1st
STOP
STOP
STOP
STOP
STOP
STOP $msg
EOF
    echo "$msg" >> ~/run/$oldimg/var/tmp/tb/STOP
    while [[ -d $lock_dir ]]
    do
      sleep 1
    done
    echo "done"
  fi

  rm -- ~/run/$oldimg ~/logs/$oldimg.log
  oldimg=""
}


function setupANewImage() {
  echo
  date
  echo " setup a new image ..."
  sudo ${0%/*}/setup_img.sh $setupargs
}


#######################################################################
set -eu
export LANG=C.utf8

source $(dirname $0)/lib.sh

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

condition_completed=-1      # completed emerge operations
condition_distance=-1       # distance in hours to the previous image
condition_left=-1           # left entries in backlogs
condition_runtime=-1        # age in days for an image
condition_count=-1          # number of images to be run

oldimg=""                   # image to be replaced
setupargs=""                # argument(s) for setup_img.sh

while getopts c:d:l:n:o:r:s: opt
do
  case "$opt" in
    c)  condition_completed="$OPTARG"   ;;
    d)  condition_distance="$OPTARG"    ;;
    l)  condition_left="$OPTARG"        ;;
    n)  condition_count="$OPTARG"       ;;
    r)  condition_runtime="$OPTARG"     ;;

    o)  oldimg="${OPTARG##*/}"          ;;
    s)  setupargs="$OPTARG"             ;;
    *)  echo " opt not implemented: '$opt'"; exit 1;;
  esac
done

if [[ -n "$oldimg" ]]; then
  StopOldImage "user decision"
  exec nice -n 1 sudo ${0%/*}/setup_img.sh $setupargs
fi

# do not run in parallel (in automatic mode)
lockfile="/tmp/${0##*/}.lck"
if [[ -s "$lockfile" ]]; then
  if kill -0 $(cat $lockfile) 2>/dev/null; then
    exit 1    # a previous instance is (still) running
  else
    echo " found stale lockfile content:"
    cat $lockfile
  fi
fi
echo $$ > "$lockfile" || exit 1
trap Finish INT QUIT TERM EXIT


if [[ $condition_count -gt -1 ]]; then
  while ! MaxCountIsRunning
  do
    setupANewImage
  done
fi

while AnImageHasAnEmptyBacklog
do
  StopOldImage "empty backlogs"
  setupANewImage
done

while WorldBrokenAndOld
do
  StopOldImage "@world broken"
  setupANewImage
done

if [[ $condition_runtime -gt -1 || $condition_left -gt -1 || $condition_completed -gt -1 ]]; then
  while [[ $condition_distance -eq -1 ]] || MinDistanceIsReached
  do
    if AnImageReachedEOL; then
      StopOldImage "$reason"
      setupANewImage
    else
      break
    fi
  done
fi

Finish $?
