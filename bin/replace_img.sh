#!/bin/bash
#
# set -x

# replace the oldest tinderbox image with a new one
#

if [[ $# -ne 2 ]]; then
  echo "help: '$0 <hour/s> day/s', exiting..."
  exit 1
fi

n=$( pgrep -c $(basename $0) )
if [[ $n -ne 1 ]]; then
  echo "found $n running instances (including me:$$), exiting..."
  pgrep -a $(basename $0)
  exit 1
fi

# bail out if the age of the youngest image is below $1 hours
#
yimg=$( cd ~/run; ls -1 | xargs -n 1 readlink 2>/dev/null | xargs -I {} echo {}/tmp/setup.sh 2>/dev/null | xargs ls -1t | cut -f3 -d'/' | head -n 1 )
if [[ -z "$yimg" ]]; then
  echo "no newest image found, exiting..."
  exit 2
fi

let "age = $(date +%s) - $(stat -c%Y ~/run/$yimg/tmp/setup.sh)"
let "age = $age / 3600"
if [[ $age -lt $1 ]]; then
  exit 2
fi

# kick off the oldest image if its age is greater than N days
#
oimg=$( cd ~/run; ls -1 | xargs -n 1 readlink 2>/dev/null | xargs -I {} echo {}/tmp/setup.sh 2>/dev/null | xargs ls -1t | cut -f3 -d'/' | tail -n 1 )
if [[ -z "$oimg" ]]; then
  echo "no oldest image found, exiting..."
  exit 3
fi

let "age = $(date +%s) - $(stat -c%Y ~/run/$oimg/tmp/setup.sh)"
let "age = $age / 86400"
if [[ $age -lt $2 ]]; then
  exit 3
fi

# wait till the old image is stopped but delete it after a new one was setup
#
echo
date
/opt/tb/bin/stop_img.sh $oimg
while :
do
  if [[ ! -f ~/run/$oimg/tmp/LOCK ]]; then
    break
  fi
  sleep 1
done

# spin up a new image, more than 1 attempt might be needed
# after x attempts (maybe due to a broken tree) retry just hourly
#
i=0
while :
do
  let "i = $i + 1"

  echo
  echo "i=$i============================================================="
  echo
  date
  sudo /opt/tb/bin/setup_img.sh

  if [[ $? -eq 0 ]]; then
    break
  fi
done

# delete artefacts of the old image
#
rm ~/run/$oimg ~/logs/$oimg.log
date
echo "deleted $oimg"

echo
date
echo "done, needed $i attempt(s)"
