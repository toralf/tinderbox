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


function shufImages() {
  (set +f; cd ~tinderbox/run; ls -d * 2>/dev/null | shuf)
}


function GetCompletedEmergeOperations() {
  grep -c ' ::: completed emerge' ~tinderbox/run/$1/var/log/emerge.log 2>/dev/null || echo "0"
}


function HasAnEmptyBacklog() {
  oldimg=""
  while read -r i
  do
    local bl=~tinderbox/run/$i/var/tmp/tb/backlog
    if [[ -f $bl ]]; then
      if [[ $(wc -l < $bl) -eq 0 ]]; then
        reason="empty backlogs"
        oldimg=$i
        return 0
      fi
    fi
  done < <(shufImages)

  return 1
}


function Broken() {
  oldimg=""
  while read -r i
  do
    local starttime=$(getStartTime $i 2>/dev/null)
    if [[ -z $starttime ]]; then
      reason="setup broken"
      oldimg=$i
      return 0
    fi

    local runtime=$(( ($(date +%s)-$starttime) / 3600 / 24 ))

    s="@world"
    if tail -n 1 ~tinderbox/run/$i/var/tmp/tb/$s.history 2>/dev/null | grep -q " NOT ok $"; then
      if [[ $runtime -ge 1 ]]; then
        reason="$s broken"
        oldimg=$i
        return 0
      fi
    fi

    s="@preserved-rebuild"
    if tail -n 1 ~tinderbox/run/$i/var/tmp/tb/$s.history 2>/dev/null | grep -q " NOT ok $"; then
      if [[ $runtime -ge 2 ]]; then
        reason="$s broken"
        oldimg=$i
        return 0
      fi
    fi
    if tail -n 1 ~tinderbox/run/$i/var/tmp/tb/$s.history 2>/dev/null | grep -q " DetectRebuildLoop"; then
      reason="$s DetectRebuildLoop"
      oldimg=$i
      return 0
    fi
  done < <(shufImages)

  return 1
}


function MinDistanceIsReached() {
  local newest=$(set +f; cat ~tinderbox/run/*/var/tmp/tb/setup.timestamp | sort -u -n | tail -n 1)
  if [[ -z "$newest" ]]; then
    return 1
  fi

  local distance=$(( ( $(date +%s) - $newest ) / 3600 ))
  [[ $distance -ge $condition_distance ]]
}


function FreeSlotAvailable() {
  if [[ ! $condition_count -gt -1 ]]; then
    return 1
  fi

  if pgrep -f $(dirname $0)/setup_img.sh 1>/dev/null; then
    return 1
  fi

  [[ $(ls /run/tinderbox 2>/dev/null | wc -l) -lt $condition_count && $(shufImages | wc -l) -lt $condition_count ]]
}


function ReplaceAnImage() {
  oldimg=""
  while read -r i
  do
    if [[ $condition_runtime -gt -1 ]]; then
      local runtime=$(( ( $(date +%s) - $(getStartTime $i) ) / 3600 / 24))
      if [[ $runtime -ge $condition_runtime ]]; then
        reason="runtime $runtime days (>$condition_runtime)"
        oldimg=$i
        return 0
      fi
    fi
    if [[ $condition_completed -gt -1 ]]; then
      local completed=$(GetCompletedEmergeOperations $i)
      if [[ $completed -ge $condition_completed ]]; then
        reason="$completed emerges completed (> $condition_completed)"
        oldimg=$i
        return 0
      fi
    fi
  done < <(shufImages)

  return 1
}


function StopOldImage() {
  local lock_dir=/run/tinderbox/$oldimg.lock

  if [[ -d $lock_dir ]]; then
    local msg="replaced b/c: $reason"

    echo " stopping: $oldimg"
    date
    echo -e "\n waiting for image unlock ...\n"
    date
    echo " $msg"

    # do not just put a "STOP" into backlog.1st b/c job.sh might prepend additional task/s onto it
    # repeat STOP lines to neutralise an external triggered restart
    cat << EOF >> ~tinderbox/run/$oldimg/var/tmp/tb/backlog.1st
STOP
STOP
STOP
STOP
STOP
STOP $msg
EOF
    echo "$msg" >> ~tinderbox/run/$oldimg/var/tmp/tb/STOP
    local i=7200
    while [[ -d $lock_dir ]]
    do
      if ! ((--i)); then
        echo "give up on $oldimg"
        sed '/^STOP/d' ~tinderbox/run/$oldimg/var/tmp/tb/backlog.1st
        rm ~tinderbox/run/$oldimg/var/tmp/tb/STOP
        return 1
      fi
      sleep 1
    done
    echo "done"
  else
    echo "not runnning"
  fi
  echo

  rm -- ~tinderbox/run/$oldimg ~tinderbox/logs/$oldimg.log
}


function setupANewImage() {
  echo
  date
  echo " setup a new image ..."
  sudo $(dirname $0)/setup_img.sh $setupargs
}


#######################################################################
set -euf
export LANG=C.utf8

source $(dirname $0)/lib.sh

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

condition_completed=-1      # completed emerge operations
condition_count=-1          # number of images to be run
condition_distance=-1       # distance in hours to the previous image
condition_runtime=-1        # age in days for an image

oldimg=""                   # image to be replaced
setupargs=""                # argument(s) for setup_img.sh

while getopts c:d:n:o:r:s: opt
do
  case "$opt" in
    c)  condition_completed="$OPTARG"   ;;
    n)  condition_count="$OPTARG"       ;;
    d)  condition_distance="$OPTARG"    ;;
    r)  condition_runtime="$OPTARG"     ;;

    o)  oldimg=$(basename "$OPTARG")
        reason="user decision"
        if StopOldImage; then
          exec nice -n 1 sudo $(dirname $0)/setup_img.sh $setupargs
        fi
        ;;
    s)  setupargs="$OPTARG"             ;;
    *)  echo " opt not implemented: '$opt'"; exit 1;;
  esac
done

# do not run in parallel from here
lockfile="/tmp/$(basename $0).lck"
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

while FreeSlotAvailable
do
  setupANewImage
done

while HasAnEmptyBacklog
do
  if StopOldImage; then
    setupANewImage
  fi
done

while Broken
do
  if StopOldImage; then
    setupANewImage
  fi
done

while ReplaceAnImage
do
  if [[ $condition_distance -gt -1 ]]; then
    if ! MinDistanceIsReached; then
      break
    fi
  fi

  if StopOldImage; then
    setupANewImage
  fi
done

Finish 0
