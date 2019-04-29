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
  oldimg=$(cd ~/run; ls -1t */tmp/setup.sh 2>/dev/null | head -n 1 | cut -f1 -d'/' -s)
  if [[ -d ~/run/$oldimg ]]; then
    let "hours = ( $(date +%s) - $(stat -c%Y ~/run/$oldimg/tmp/setup.sh) ) / 3600"
    if [[ $hours -lt $min_hours ]]; then
      Finish 3
    fi
  fi

  # look for an image being old enough and having emerged enough
  #
  oldimg=""
  while read i
  do
    let "days = ( $(date +%s) - $(stat -c%Y ~/run/$i/tmp/setup.sh) ) / 86400"
    if [[ $days -lt $min_days ]]; then
      continue
    fi

    compl=$(grep ' ::: completed emerge' ~/run/$i/var/log/emerge.log 2>/dev/null | wc -l)
    if [[ $compl -lt $min_compl ]]; then
      continue
    fi

    oldimg=$i
    break
  done < <( cd ~/run; ls -1t */tmp/setup.sh 2>/dev/null | cut -f1 -d'/' -s | tac )

  if [[ -z "$oldimg" ]]; then
    Finish 4
  fi
}


function StopOldImage() {
  if [[ -f ~/run/$oldimg/tmp/LOCK && ! -f ~/run/$oldimg/tmp/STOP ]]; then
    echo " schedule pfl and stop afterwards ..."
    cat << EOF >> ~/run/$oldimg/tmp/backlog.1st
STOP (EOL) $compl completed, $(wc -l < ~/run/$oldimg/tmp/backlog) left
%/usr/bin/pfl
app-portage/pfl
EOF

    while [[ -f ~/run/$oldimg/tmp/LOCK ]]; do
      sleep 1
    done
  fi
}


function SetupANewImage()  {
  i=0
  while :
  do
    let "i = $i + 1"

    echo
    echo "attempt $i ============================================================="
    echo
    date
    sudo $(dirname $0)/setup_img.sh $setupargs
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
lck=/tmp/$(basename $0).lck
if [[ -s $lck ]]; then
  kill -0 $(cat $lck) 2>/dev/null
  if [[ $? -eq 0 ]]; then
    exit 1    # be silent, no Finish() here !
  fi
fi
echo $$ > $lck

oldimg=$(basename $1 2>/dev/null)
if [[ -z "$oldimg" || ! -e ~/run/$oldimg ]]; then
  min_days=${1:-5}
  min_hours=${2:-17}
  min_compl=${3:-4500}
  shift "$(( $# < 3 ? $# : 3 ))"

  LookForAnImage
else
  shift
fi
setupargs="$@"


echo
date
echo " replacing image $oldimg ..."

StopOldImage
SetupANewImage

date
echo "delete $oldimg"
rm ~/run/$oldimg ~/logs/$oldimg.log

Finish 0
