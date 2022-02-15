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


function ImagesInRunShuffled() {
  (set +f; cd ~tinderbox/run; ls -d * 2>/dev/null | shuf)
}


function FreeSlotAvailable() {
  r=$(ls /run/tinderbox 2>/dev/null | wc -l)
  s=$(pgrep -c -f $(dirname $0)/setup_img.sh)

  [[ $(( r+s )) -lt $desired_count && $(ImagesInRunShuffled | wc -l) -lt $desired_count ]]
}


function StopAndUnlinkOldImage() {
  local msg="kicked off b/c: $(cat ~tinderbox/img/$oldimg/var/tmp/tb/REPLACE_ME)"
  if __is_running $oldimg; then
    echo
    date
    echo " stopping: $oldimg"
    touch ~tinderbox/img/$oldimg/var/tmp/tb/STOP
    local i=1800
    while __is_locked $oldimg
    do
      if ! (( --i )); then
        echo "  give up to wait for $oldimg"
        return 1
      fi
      sleep 1
    done
    echo "done"
  else
    echo "$oldimg $msg"
  fi
}


function setupNewImage() {
  echo
  date
  echo " setup a new image ..."
  sudo $(dirname $0)/setup_img.sh
}


#######################################################################
set -euf
export LANG=C.utf8

source $(dirname $0)/lib.sh

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

desired_count=13            # number of images to be run

while getopts n:o:s: opt
do
  case "$opt" in
    n)  desired_count="$OPTARG" ;;
    o)  echo "user decision" >> ~tinderbox/img/$(basename $OPTARG)/var/tmp/tb/REPLACE_ME  ;;
    *)  echo " opt not implemented: '$opt'"; exit 1 ;;
  esac
done

if [[ $desired_count -lt 0 || $desired_count -gt 99 ]]; then
  echo "desired_count is wrong: $desired_count"
  exit 1
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

while :
do
  if FreeSlotAvailable; then
    if ! setupNewImage; then
      rc=$?
      echo " setup failed with rc=$rc, sleep 10 min ..."
      if ! sleep 600; then
        : # allowed to be killed
      fi
      continue
    fi
  fi

  while read -r oldimg
  do
    if ! __is_running $oldimg; then
      hours=$(( (EPOCHSECONDS-$(stat -c %Y ~tinderbox/img/$oldimg/var/tmp/tb/task))/3600 ))
      if [[ $hours -ge 36 ]]; then
        echo -e "last task $hours hour/s ago" >> ~tinderbox/img/$oldimg/var/tmp/tb/REPLACE_ME
      fi
    fi

    if [[ -f ~tinderbox/run/$oldimg/var/tmp/tb/REPLACE_ME ]]; then
      if StopAndUnlinkOldImage; then
        rm ~tinderbox/run/$oldimg ~tinderbox/logs/$oldimg.log
        continue 2
      fi
    fi
  done < <(ImagesInRunShuffled)

  break
done

Finish 0
