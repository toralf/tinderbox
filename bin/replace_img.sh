#!/bin/bash
#
# set -x

# replace the oldest tinderbox image with a new one
#

function Finish() {
  rm -f $lck
  exit $1
}


#######################################################################
#
if [[ $# -gt 3 ]]; then
  echo "call: '$0 [day(s) [hour(s) ]]'"
  exit 1
fi
days=${1:-5}
hours=${2:-12}

# be silent here
#
lck=/tmp/$( basename $0 ).lck
if [[ -f $lck ]]; then
  exit 2
fi
echo $$ >> $lck

# bail out if the age of the youngest image is below $1 hours
#
yimg=$( cd ~/run; ls | xargs --no-run-if-empty readlink | xargs --no-run-if-empty -I {} echo {}/tmp/setup.sh | xargs --no-run-if-empty ls -1t | cut -f3 -d'/' | head -n 1 )
if [[ -z "$yimg" ]]; then
  echo "no newest image found, exiting ..."
  Finish 3
fi

let "age = $(date +%s) - $(stat -c%Y ~/run/$yimg/tmp/setup.sh)"
let "age = $age / 3600"
if [[ $age -lt $hours ]]; then
  Finish 3
fi

# kick off the oldest image if its age is greater than N days
#
oimg=$( cd ~/run; ls | xargs --no-run-if-empty readlink | xargs --no-run-if-empty -I {} echo {}/tmp/setup.sh | xargs --no-run-if-empty ls -1t | cut -f3 -d'/' | tail -n 1 )
if [[ -z "$oimg" ]]; then
  echo "no oldest image found, exiting ..."
  Finish 3
fi

let "age = $(date +%s) - $(stat -c%Y ~/run/$oimg/tmp/setup.sh)"
let "age = $age / 86400"
if [[ $age -lt $days ]]; then
  Finish 3
fi

echo
date
echo " old image is $oimg"

if [[ -f ~/run/$oimg/tmp/LOCK ]]; then
  echo " will schedule pfl and stop afterwards ..."
  cat << EOF >> ~/run/$oimg/tmp/backlog.1st
STOP
%/usr/bin/pfl
app-portage/pfl
EOF

  while :
  do
    if [[ ! -f ~/run/$oimg/tmp/LOCK ]]; then
      break
    fi
    sleep 1
  done
fi

# setup up a new image
#
i=0
while :
do
  let "i = $i + 1"

  echo
  echo "attempt $i ============================================================="
  echo
  date
  sudo $(dirname $0)/setup_img.sh
  rc=$?

  if [[ $rc -eq 0 ]]; then
    break
  elif [[ $rc -eq 2 ]]; then
    continue
  else
    echo "rc=$rc, exiting ..."
    Finish 4
  fi
done

# delete old image and its log file after a new image was setup
#
date
echo "delete $oimg"
rm ~/run/$oimg ~/logs/$oimg.log

echo
date
echo "done, needed $i attempt(s)"

Finish 0
