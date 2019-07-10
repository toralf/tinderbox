#!/bin/bash
#
# set -x

# replace an tinderbox image in ~/run with a newer one
#


function Finish() {
  rm -f $lck
  exit $1
}


function LookForAnImage()  {
  # wait time between 2 images
  #
  latest=$(cd ~/run; ls -t */var/tmp/tb/setup.sh 2>/dev/null | head -n 1 | cut -f1 -d'/' -s)
  if [[ -n "$latest" ]]; then
    let "h = ( $(date +%s) - $(stat -c%Y ~/run/$latest/var/tmp/tb/setup.sh) ) / 3600"
    if [[ $h -lt $hours ]]; then
      Finish 3
    fi
  else
    Finish 3
  fi

  # look for an image being old enough and having enough emerge operations completed
  #
  while read i
  do
    let "d = ( $(date +%s) - $(stat -c%Y ~/run/$i/var/tmp/tb/setup.sh) ) / 3600 / 24"
    if [[ $d -lt $days ]]; then
      break
    fi

    if [[ ! -f ~/run/$i/var/log/emerge.log ]]; then
      continue
    fi
    c=$(grep -c ' ::: completed emerge' ~/run/$i/var/log/emerge.log)
    if [[ $c -lt $compl ]]; then
      continue
    fi

    oldimg=$i
    return
  done < <(cd ~/run; ls -t */var/tmp/tb/setup.sh 2>/dev/null | cut -f1 -d'/' -s | tac)

  Finish 3
}


function StopOldImage() {
  cat << EOF >> ~/run/$oldimg/var/tmp/tb/backlog.1st
STOP EOL at $(date +%R), $c completed, $(wc -l < ~/run/$oldimg/var/tmp/tb/backlog) left
%/usr/bin/pfl
app-portage/pfl
EOF

  if [[ -f ~/run/$oldimg/var/tmp/tb/LOCK ]]; then
    echo " wait for stop ..."
    while [[ -f ~/run/$oldimg/var/tmp/tb/LOCK ]]; do
      sleep 1
    done
  fi
}


function SetupANewImage()  {
  i=0
  while :
  do
    let "i=$i+1"

    echo
    date
    echo "attempt $i ============================================================="
    echo
    sudo ${0%/*}/setup_img.sh $setupargs
    rc=$?

    if [[ $rc -eq 0 ]]; then
      break
    elif [[ $rc -eq 2 ]]; then
      continue
    else
      echo "rc=$rc, exiting ..."
      Finish 23
    fi
  done

  echo
  date
  echo "done, needed $i attempt(s)"
}


#######################################################################
#
#

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

compl=4500    # emerge operations
days=5        # min. runtime of an image
hours=16      # min. distance to the previous image, effectively this yields into n+1 hours
oldimg=""     # if not given selects one
setupargs=""  # passed to setup_img.sh

while getopts c:d:h:o:s: opt
do
  case $opt in
    c)  compl=$OPTARG         ;;
    d)  days=$OPTARG          ;;
    h)  hours=$OPTARG         ;;
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
    echo "replace $oldimg ..."
    StopOldImage
  else
    echo "error, not found: $oldimg ..."
    Finish 1
  fi
fi

echo
date
echo "setup a new image ..."
SetupANewImage

if [[ -n "$oldimg" ]]; then
  echo
  date
  echo "delete $oldimg ..."
  rm ~/run/$oldimg ~/logs/$oldimg.log
fi

Finish 0
