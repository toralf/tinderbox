#!/bin/bash
#
# set -x

# replace an tinderbox image with a new one
#
# works together with a crontab entry like:
#
# # spin up a new tinderbox image after N hours
# #
# 1 * * * * cd ~/img2; /opt/tb/bin/replace_img.sh 24


if [[ $# -ne 1 ]]; then
  echo "missing mandatory parameter1: <hours>, exiting..."
  exit 1
fi

n=$( pgrep -c $(basename $0) )
if [[ ${n} -ne 1 ]]; then
  echo "found ${n} running instances beside us, exiting..."
  pgrep -a $(basename $0)
  exit 1
fi

# get the newest image
#
nimg=$( ls -1td ~/run/* 2>/dev/null | head -n 1 | xargs -n 1 basename 2>/dev/null )
if [[ -z "${nimg}" ]]; then
  echo "no newest image found, exiting..."
  exit 2
fi

# bail out if its age is below $1 hours
#
let "age = $(date +%s) - $(stat -c%Y ~/run/${nimg})"
let "age = $age / 3600"
if [[ $age -lt $1 ]]; then
  exit 3
fi

# kick off the oldest image if its age is greater than N days
# otherwise stop
#
oimg=$( ls -1td ~/run/* 2>/dev/null | tail -n 1 | xargs -n 1 basename 2>/dev/null )
if [[ -e "${oimg}" ]]; then
  let "age = $(date +%s) - $(stat -c%Y ~/run/${oimg})"
  let "age = $age / 86400"
  if [[ $age -lt 11 ]]; then
    exit 4
  fi

  echo
  date
  /opt/tb/bin/stop_img.sh ${oimg}
  # wait till the old image is stopped
  #
  while :
  do
    if [[ ! -f ~/run/${oimg}/tmp/LOCK ]]; then
      break
    fi
    sleep 1
  done
  # delete the old image after a new one was setup
  #
fi

# spin up a new image, more than 1 attempt might be needed
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
    # retry hourly
    #
    sleep 3600
  fi
done
cat ${tmpfile}
rm -f ${tmpfile}

if [[ -e "${oimg}" ]]; then
  rm ~/run/${oimg} ~/logs/${oimg}.log
  date
  echo "deleted ${oimg}"
fi

echo
date
echo "done, needed ${i} attempt(s)"
