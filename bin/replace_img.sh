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

# bail out if the age of the latest image - if there's any - is younger than min_hours
#
img=$( cd ~/run; ls -1t */tmp/setup.sh 2>/dev/null | head -n 1 | cut -f1 -d'/' -s )
if [[ -d ~/run/$img ]]; then
  let "hours = ( $(date +%s) - $(stat -c%Y ~/run/$img/tmp/setup.sh) ) / 3600"
  if [[ $hours -lt $min_hours ]]; then
    Finish 3
  fi
fi

# bail out if no image matches the criteria
#
img=""
while read i
do
  let "days = ( $(date +%s) - $(stat -c%Y ~/run/$i/tmp/setup.sh) ) / 86400"
  if [[ $days -lt $min_days ]]; then
    continue
  fi

  compl=$( grep ' ::: completed emerge' ~/run/$i/var/log/emerge.log 2>/dev/null | wc -l )
  if [[ $compl -lt $min_compl ]]; then
    continue
  fi

  img=$i
  break
done < <( cd ~/run; ls -1t */tmp/setup.sh 2>/dev/null | cut -f1 -d'/' -s | tac )

if [[ -z "$img" ]]; then
  Finish 4
fi

echo
date
echo " replace-able image is $img"

if [[ -f ~/run/$img/tmp/LOCK ]]; then
  echo " will schedule pfl and stop afterwards ..."
  cat << EOF >> ~/run/$img/tmp/backlog.1st
STOP (EOL) $compl completed emerge operations
%/usr/bin/pfl
app-portage/pfl
EOF

  while :
  do
    if [[ ! -f ~/run/$img/tmp/LOCK ]]; then
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
echo "delete $img"
rm ~/run/$img ~/logs/$img.log

echo
date
echo "done, needed $i attempt(s)"

Finish 0
