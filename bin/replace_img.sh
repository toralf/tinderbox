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


function FoundABrokenImage() {
  oldimg=""
  while read -r i
  do
    local starttime
    if ! starttime=$(getStartTime $i 2>/dev/null); then
      reason="setup broken"
      oldimg=$i
      return 0
    fi

    s="@world"
    if tail -n 1 ~tinderbox/run/$i/var/tmp/tb/$s.history 2>/dev/null | grep -q " NOT ok $"; then
      if [[ $(wc -l < ~tinderbox/run/$i/var/tmp/tb/backlog.1st) -eq 0 ]]; then
        reason="$s broken"
        oldimg=$i
        return 0
      fi
    fi

    s="@preserved-rebuild"
    if tail -n 1 ~tinderbox/run/$i/var/tmp/tb/$s.history 2>/dev/null | grep -q " DetectRebuildLoop"; then
      reason="$s DetectRebuildLoop"
      oldimg=$i
      return 0
    fi
    if tail -n 1 ~tinderbox/run/$i/var/tmp/tb/$s.history 2>/dev/null | grep -q " NOT ok $"; then
      local runtime=$(( ($(date +%s) - starttime) / 3600 / 24 ))
      if [[ $runtime -ge 2 ]]; then
        reason="$s broken"
        oldimg=$i
        return 0
      fi
    fi
  done < <(shufImages)

  return 1
}


function FreeSlotAvailable() {
  if [[ $desired_count -eq -1 ]]; then
    return 1
  fi

  if pgrep -f $(dirname $0)/setup_img.sh 1>/dev/null; then
    return 1
  fi

  [[ $(ls /run/tinderbox 2>/dev/null | wc -l) -lt $desired_count && $(shufImages | wc -l) -lt $desired_count ]]
}


function StopOldImage() {
  local lock_dir=/run/tinderbox/$oldimg.lock

  if [[ -d $lock_dir ]]; then
    local completed=$(grep -c ' ::: completed emerge' ~tinderbox/run/$i/var/log/emerge.log 2>/dev/null || echo "0")
    local msg="replaced b/c: $reason ($completed emerges completed)"

    echo " stopping: $oldimg"
    date
    echo -e "\n waiting for image unlock ...\n"
    date
    echo " $msg"

    # do not just put a "STOP" into backlog.1st b/c job.sh might prepend additional task/s onto it
    # repeat STOP lines to neutralise any externally triggered restart
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


function setupNewImage() {
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

desired_count=-1            # number of images to be run
oldimg=""                   # image to be replaced
setupargs=""                # argument(s) for setup_img.sh

while getopts n:o:s: opt
do
  case "$opt" in
    n)  desired_count="$OPTARG"       ;;
    o)  oldimg=$(basename "$OPTARG")    ;;
    s)  setupargs="$OPTARG"             ;;
    *)  echo " opt not implemented: '$opt'"; exit 1;;
  esac
done

if [[ -n $oldimg ]]; then
  reason="user decision"
  if StopOldImage; then
    exec nice -n 1 sudo $(dirname $0)/setup_img.sh $setupargs
  fi
fi

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
  echo "less than $desired_count images running"
  setupNewImage
done

while HasAnEmptyBacklog
do
  if StopOldImage; then
    setupNewImage
  fi
done

while FoundABrokenImage
do
  if StopOldImage; then
    setupNewImage
  fi
done

Finish 0
