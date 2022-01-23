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


function HasReplaceMe() {
  oldimg=""
  while read -r i
  do
    if [[ -f ~tinderbox/run/$i/var/tmp/tb/REPLACE_ME ]]; then
      reason="$(cat ~tinderbox/run/$i/var/tmp/tb/REPLACE_ME)"
      oldimg=$i
      return 0
    fi
  done < <(shufImages)

  return 1
}


function FreeSlotAvailable() {
  if [[ $desired_count -eq -1 ]]; then
    return 1
  fi

  r=$(ls /run/tinderbox 2>/dev/null | wc -l)
  s=$(pgrep -c -f $(dirname $0)/setup_img.sh)

  [[ $(( r+s )) -lt $desired_count && $(shufImages | wc -l) -lt $desired_count ]]
}


function StopOldImage() {
  local lock_dir=/run/tinderbox/$oldimg.lock
  local msg="replaced b/c: $reason"

  rm ~tinderbox/run/$oldimg
  if [[ -d $lock_dir ]]; then
    echo " stopping: $msg" | tee -a ~tinderbox/img/$oldimg/var/tmp/tb/STOP
    date

    echo -e "\n waiting for image unlock ...\n"
    date
    local i=1800
    while [[ -d $lock_dir ]]
    do
      if ! (( --i )); then
        echo "give up waiting for $oldimg"
        return 1
      fi
      sleep 1
    done
    echo "done"
  else
    echo "$oldimg $msg"
  fi
  rm ~tinderbox/logs/$oldimg.log
  echo
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

if [[ "$(whoami)" != "tinderbox" ]]; then
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

# this is allowed to be run in parallel however that is racy for about 1-2 minutes
if [[ -n $oldimg ]]; then
  reason="user decision"
  echo "$reason" >> /var/tmp/tb/REPLACE_ME
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

# unlink a stopped image
while read -r i
do
  if ! __is_running $i; then
    hours=$(( (EPOCHSECONDS-$(stat -c %Y ~tinderbox/run/$i/var/tmp/tb/task))/3600 ))
    if [[ $hours -ge 36 ]]; then
      echo -e "\n$i last task $hours hour/s ago - removed from ~tinderbox/run\n"
      rm ~tinderbox/run/$i
      imglog=~tinderbox/logs/$i.log
      if [[ -s $imglog ]]; then
        tail -v -n 100 $imglog
      fi
      rm $imglog
    fi
  fi
done < <(shufImages)

while :
do
  if FreeSlotAvailable; then
    setupNewImage

  elif HasReplaceMe; then
    if StopOldImage; then
      continue
    fi

  else
    break
  fi
done

Finish 0
