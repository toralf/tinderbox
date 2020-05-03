#!/bin/bash
#
# set -x

# replace an tinderbox image in ~/run with a newer one
#

function Finish() {
  rm -f $lck
  exit $1
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
  done < <(cd ~/run; ls -t */var/tmp/tb/setup.sh 2>/dev/null | cut -f1 -d'/' -s | tac)

  return 1
}


# look for an image being old enough and having enough emerge operations completed
#
function LookForAnOldEnoughImage()  {
  # wait time between 2 images
  #
  latest=$(cd ~/run; ls -t */var/tmp/tb/setup.sh 2>/dev/null | head -n 1 | cut -f1 -d'/' -s)
  if [[ -z "$latest" ]]; then
    return 1
  fi

  let "h = ( $(date +%s) - $(stat -c%Y ~/run/$latest/var/tmp/tb/setup.sh) ) / 3600"
  if [[ $h -lt $hours ]]; then
    return 1
  fi

  while read oldimg
  do
    [[ -f ~/run/$oldimg/var/tmp/tb/KEEP ]] && continue
    [[ $(GetLeft $oldimg)  -gt $left    ]] && continue
    [[ $(GetCompl $oldimg) -lt $compl   ]] && continue
    return 0  # matches all conditions
  done < <(cd ~/run; ls -t */var/tmp/tb/setup.sh 2>/dev/null | cut -f1 -d'/' -s | tac)

  return 1
}


function StopOldImage() {
  # prevent a restart-logic
  #
  echo -e "STOP\nSTOP\nSTOP\nSTOP\nSTOP\nSTOP\nSTOP\nSTOP scheduled at $(unset LC_TIME; date +%R), $(GetCompl $oldimg) completed, $(GetLeft $oldimg) left" |\
  tee -a ~/run/$oldimg/var/tmp/tb/STOP >> ~/run/$oldimg/var/tmp/tb/backlog.1st

  if [[ -f ~/run/$oldimg/var/tmp/tb/LOCK ]]; then
    echo " wait for stop ..."
    while [[ -f ~/run/$oldimg/var/tmp/tb/LOCK ]]; do
      sleep 1
    done
  else
    echo " image is not locked"
  fi
}


#######################################################################
#
#
set -uf

export LANG=C.utf8

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " You are not tinderbox !"
  exit 1
fi

# do not run this script in parallel
#
lck="/tmp/${0##*/}.lck"
if [[ -s "$lck" ]]; then
  kill -0 $(cat $lck) 2>/dev/null
  if [[ $? -eq 0 ]]; then
    exit 1    # be silent, no Finish() here !
  fi
fi
echo $$ > "$lck" || exit 1

compl=5500    # min. completed emerge operations
hours=6       # min. distance to the previous image, effectively this yields into n+1 hours
left=15000    # max. left entries in the backlog
oldimg=""     # optional: image to be replaced ("-" to skip this step)
setupargs=""  # args passed to call of setup_img.sh

while getopts c:h:l:r:s: opt
do
  case "$opt" in
    c)  compl="$OPTARG"         ;;
    h)  hours="$OPTARG"         ;;
    l)  left="$OPTARG"          ;;
    r)  oldimg="${OPTARG##*/}"  ;;
    s)  setupargs="$OPTARG"     ;;
    *)  echo " opt not implemented: '$opt'"; exit 1;;
  esac
done

if [[ -z "$oldimg" ]]; then
  LookForEmptyBacklogs
  if [[ $? -ne 0 ]]; then
    LookForAnOldEnoughImage || Finish 3
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

  sudo ${0%/*}/setup_img.sh "$setupargs"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    break
  elif [[ $rc -eq 3 ]]; then
    continue
  else
    Finish $rc
  fi
done

echo
date
echo " finished"
if [[ -e ~/run/$oldimg ]]
  rm -- ~/run/$oldimg ~/logs/$oldimg.log
fi
Finish 0
