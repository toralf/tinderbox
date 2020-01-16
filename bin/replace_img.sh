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
  while read i
  do
    if [[ -f ~/run/$i/var/tmp/tb/KEEP ]]; then
      continue
    fi

    if [[ ! -f ~/run/$i/var/log/emerge.log ]]; then
      continue
    fi

    let "d = ( $(date +%s) - $(stat -c%Y ~/run/$i/var/tmp/tb/setup.sh) ) / 3600 / 24"
    if [[ $d -lt $days ]]; then
      break
    fi

    c=$(GetCompl $i)
    if [[ $c -lt $compl ]]; then
      continue
    fi

    l=$(GetLeft $i)
    if [[ $l -gt $left ]]; then
      continue
    fi

    oldimg=$i
    return
  done < <(cd ~/run; ls -t */var/tmp/tb/setup.sh 2>/dev/null | cut -f1 -d'/' -s | tac)

  Finish 3
}


function StopOldImage() {
  if [[ -z "$c" || -z "$l" ]]; then
    c=$(GetCompl $oldimg)
    l=$(GetLeft $oldimg)
  fi

  cat << EOF >> ~/run/$oldimg/var/tmp/tb/backlog.1st
STOP scheduled at $(LC_TIME=de_DE.utf8 date +%R), $c completed, $l left
EOF

  if [[ -f ~/run/$oldimg/var/tmp/tb/LOCK ]]; then
    echo " wait for stop ..."
    while [[ -f ~/run/$oldimg/var/tmp/tb/LOCK ]]; do
      sleep 1
    done
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

compl=4600    # emerge operations
days=5        # min. runtime of an image
hours=17      # min. distance to the previous image, effectively this yields into n+1 hours
left=17000    # left entries in the backlog
oldimg=""     # if not given selects one
setupargs=""  # passed to setup_img.sh

while getopts c:d:h:l:o:s: opt
do
  case $opt in
    c)  compl=$OPTARG         ;;
    d)  days=$OPTARG          ;;
    h)  hours=$OPTARG         ;;
    l)  left=$OPTARG          ;;
    o)  oldimg=${OPTARG##*/}  ;;
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
nice sudo ${0%/*}/setup_img.sh $setupargs || Finish $?

if [[ -n "$oldimg" ]]; then
  echo
  date
  echo " delete $oldimg ..."
  rm ~/run/$oldimg ~/logs/$oldimg.log
fi

echo
Finish 0
