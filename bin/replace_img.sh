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
min_days=${1:-5}
min_hours=${2:-12}
min_compl=${3:-3500}
shift 3
setupargs="$@"

lck=/tmp/$( basename $0 ).lck
if [[ -f $lck ]]; then
  exit 1    # be silent and no Finish() here !
fi
echo $$ >> $lck   # the ">>" helps to catch an (unlikely) race

# bail out if the age of the youngest image is below min_hours
#
yimg=$( cd ~/run; ls | xargs --no-run-if-empty readlink | xargs --no-run-if-empty -I {} echo {}/tmp/setup.sh | xargs --no-run-if-empty ls -1t | cut -f3 -d'/' | head -n 1 )
if [[ -z "$yimg" ]]; then
  echo "no newest image found, exiting ..."
  Finish 2
fi

let "hours = ( $(date +%s) - $(stat -c%Y ~/run/$yimg/tmp/setup.sh) ) / 3600"
if [[ $hours -lt $min_hours ]]; then
  Finish 3
fi

# bail out if the age of the oldest image is below min_days
#
oimg=$( cd ~/run; ls | xargs --no-run-if-empty readlink | xargs --no-run-if-empty -I {} echo {}/tmp/setup.sh | xargs --no-run-if-empty ls -1t | cut -f3 -d'/' | tail -n 1 )
if [[ -z "$oimg" ]]; then
  echo "no oldest image found, exiting ..."
  Finish 4
fi

let "days = ( $(date +%s) - $(stat -c%Y ~/run/$oimg/tmp/setup.sh) ) / 86400"
if [[ $days -lt $min_days ]]; then
  Finish 5
fi

# bail out if less than x emerge operations were completed at oldest image
#
compl=$(grep ' ::: completed emerge' ~/run/$oimg/var/log/emerge.log 2>/dev/null | wc -l)
if [[ $compl -lt $min_compl ]]; then
  Finish 6
fi

echo
date
echo " old image is $oimg"

if [[ -f ~/run/$oimg/tmp/LOCK ]]; then
  echo " will schedule pfl and stop afterwards ..."
  cat << EOF >> ~/run/$oimg/tmp/backlog.1st
STOP (EOL) $compl completed emerge operations
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

# delete old image and its log file after a new image was setup
#
date
echo "delete $oimg"
rm ~/run/$oimg ~/logs/$oimg.log

echo
date
echo "done, needed $i attempt(s)"

Finish 0
