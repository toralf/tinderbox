#!/bin/bash
# set -x

# replace an image with a new one


function Finish() {
  local rc=${1:-$?}
  local pid=$$

  if [[ $rc -ne 0 ]]; then
    echo
    date
    echo " pid $pid exited with rc=$rc"
  fi

  trap - INT QUIT TERM EXIT
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


function StopOldImage() {
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
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

source $(dirname $0)/lib.sh

desired_count=14            # number of images to be run
while getopts n:u: opt
do
  case "$opt" in
    n)  desired_count="$OPTARG" ;;
    u)  echo "user decision" >> ~tinderbox/img/$(basename $OPTARG)/var/tmp/tb/REPLACE_ME  ;;
    *)  echo " opt not implemented: '$opt'"; exit 1 ;;
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

while :
do
  # mark old stopped images
  while read -r oldimg
  do
    if ! __is_running $oldimg; then
      hours=$(( (EPOCHSECONDS-$(stat -c %Y ~tinderbox/img/$oldimg/var/tmp/tb/task))/3600 ))
      if [[ $hours -ge 36 ]]; then
        echo -e "last task $hours hour/s ago" >> ~tinderbox/img/$oldimg/var/tmp/tb/REPLACE_ME
      fi
    fi
  done < <(ImagesInRunShuffled)

  # remove stopped dead images
  while read -r oldimg
  do
    if ! __is_running $oldimg; then
      if [[ -f ~tinderbox/run/$oldimg/var/tmp/tb/REPLACE_ME ]]; then
        rm ~tinderbox/run/$oldimg ~tinderbox/logs/$oldimg.log
      fi
    fi
  done < <(ImagesInRunShuffled)

  # setup a new image as long as a free slot is available
  if FreeSlotAvailable; then
    if setupNewImage; then
      continue
    else
      echo
      date
      echo " setup failed"
      Finish 1
    fi
  fi

  # stop and replace dead images accidently (re-)started
  while read -r oldimg
  do
    if __is_running $oldimg; then
      if [[ -f ~tinderbox/run/$oldimg/var/tmp/tb/REPLACE_ME ]]; then
        if StopOldImage; then
          rm ~tinderbox/run/$oldimg ~tinderbox/logs/$oldimg.log
          continue 2
        fi
      fi
    fi
  done < <(ImagesInRunShuffled)

  break
done

Finish 0
