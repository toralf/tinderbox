#!/bin/bash
#
# set -x

export LANG=C.utf8

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

function LookForAnImage()  {
  # wait time between 2 images
  #
  latest=$(cd ~/run; ls -t */var/tmp/tb/setup.sh 2>/dev/null | head -n 1 | cut -f1 -d'/' -s)
  if [[ -z "$latest" ]]; then
    Finish 3
  fi

  let "h = ( $(date +%s) - $(stat -c%Y ~/run/$latest/var/tmp/tb/setup.sh) ) / 3600"
  if [[ $h -lt $hours ]]; then
    Finish 3
  fi

  # look for an image being old enough and having enough emerge operations completed
  #
  while read oldimg
  do
    n=$(wc -l < <(cat ~/run/$oldimg/var/tmp/tb/backlog*))
    if [[ $? -eq 0 && $n -eq 0 ]]; then
      return
    fi

    if [[ -f ~/run/$oldimg/var/tmp/tb/KEEP ]]; then
      continue
    fi

    c=$(GetCompl $oldimg)
    if [[ $c -lt $compl ]]; then
      continue
    fi

    l=$(GetLeft $oldimg)
    if [[ $l -gt $left ]]; then
      continue
    fi

    return
  done < <(cd ~/run; ls -t */var/tmp/tb/setup.sh 2>/dev/null | cut -f1 -d'/' -s | tac)

  Finish 3
}


function StopOldImage() {
  if [[ -z "$c" || -z "$l" ]]; then
    c=$(GetCompl $oldimg)
    l=$(GetLeft $oldimg)
  fi

  # prevent any aside-restart-logic
  #
  echo -e "STOP\nSTOP\nSTOP scheduled at $(LC_TIME=de_DE.utf8 date +%R), $c completed, $l left" >> ~/run/$oldimg/var/tmp/tb/backlog.1st

  if [[ -f ~/run/$oldimg/var/tmp/tb/LOCK ]]; then
    echo " wait for stop ..."
    while [[ -f ~/run/$oldimg/var/tmp/tb/LOCK ]]; do
      sleep 1
    done
  else
    echo " image is already not locked"
  fi
}


#######################################################################
#
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " You are not tinderbox !"
  exit 1
fi

# do not run this script in parallel
#
lck=/tmp/${0##*/}.lck
if [[ -s $lck ]]; then
  kill -0 $(cat $lck) 2>/dev/null
  if [[ $? -eq 0 ]]; then
    exit 1    # be silent, no Finish() here !
  fi
fi
echo $$ > $lck

compl=4800    # completed emerge operations
hours=5       # min. distance to the previous image, effectively this yields into n+1 hours
left=16000    # left entries in the backlog
oldimg=""     # optional: image to be replaced
setupargs=""  # args passed thru to setup_img.sh

while getopts c:h:l:r:s: opt
do
  case $opt in
    c)  compl=$OPTARG         ;;
    h)  hours=$OPTARG         ;;
    l)  left=$OPTARG          ;;
    r)  oldimg=${OPTARG##*/}  ;;
    s)  setupargs="$OPTARG"   ;;
    *)  echo " not implemented !"; exit 1;;
  esac
done

if [[ -z "$oldimg" ]]; then
  LookForAnImage
fi

if [[ -n "$oldimg" ]]; then
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

echo
date
echo " setup a new image ..."
sudo ${0%/*}/setup_img.sh $setupargs || Finish $?

if [[ -n "$oldimg" ]]; then
  echo
  date
  echo " delete $oldimg ..."
  rm ~/run/$oldimg ~/logs/$oldimg.log
fi

echo
Finish 0
