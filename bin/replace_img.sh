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
if [[ ${n} -ne 1 ]]; then
  echo "found ${n} running instances beside us, exiting..."
  pgrep -a $(basename $0)
  exit 1
fi

# bail out if the age of the youngest image is below $1 hours
#
yimg=$( ls -1td ~/run/* 2>/dev/null | head -n 1 | xargs -n 1 basename 2>/dev/null )
if [[ -z "${yimg}" ]]; then
  echo "no newest image found, exiting..."
  exit 2
fi

let "age = $(date +%s) - $(stat -c%Y ~/run/${yimg})"
let "age = $age / 3600"
if [[ $age -lt $1 ]]; then
  exit 2
fi

# kick off the oldest image if its age is greater than N days
#
oimg=$( ls -1td ~/run/* 2>/dev/null | tail -n 1 | xargs -n 1 basename 2>/dev/null )
if [[ -z "${oimg}" ]]; then
  echo "no oldest image found, exiting..."
  exit 3
fi

let "age = $(date +%s) - $(stat -c%Y ~/run/${oimg})"
let "age = $age / 86400"
if [[ $age -lt $2 ]]; then
  exit 3
fi

# wait till the old image is stopped but delete it after a new one was setup
#
echo
date
/opt/tb/bin/stop_img.sh ${oimg}
while :
do
  if [[ ! -f ~/run/${oimg}/tmp/LOCK ]]; then
    break
  fi
  sleep 1
done

# spin up a new image, more than 1 attempt might be needed
# after x attempts (maybe due to a broken tree) retry just hourly
#
i=0
tmpfile=$(mktemp /tmp/$(basename $0).XXXXXX)
while :
do
  let "i = ${i} + 1"

  sudo /opt/tb/bin/setup_img.sh &> ${tmpfile}
  rc=$?
  if [[ ${rc} -eq 0 ]]; then
    break
  else
    cat ${tmpfile} | mail -s "admin: $(basename $0) attempt ${i} rc=${rc}" tinderbox@zwiebeltoralf.de
  fi

  if [[ ${i} -gt 10 ]]; then
    sleep 3600
  fi
done
cat ${tmpfile}
rm -f ${tmpfile}

rm ~/run/${oimg} ~/logs/${oimg}.log
date
echo "deleted ${oimg}"

echo
date
echo "done, needed ${i} attempt(s)"
