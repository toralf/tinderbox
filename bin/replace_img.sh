#!/bin/sh
#
# set -x

# replace an tinderbox image with a new one
#
# works together with a crontab entry like:
#
# # spin up a new tinderbox image after N hours
# #
# 1 * * * * cd ~/img2; /opt/tb/bin/replace_img.sh 20


n=$( pgrep -c $(basename $0) )
if [[ ${n} -ne 1 ]]; then
  echo "found ${n} running instances of us"
  pgrep -a $(basename $0)
  exit 1
fi

# if $1 is given, then wait till the newest image is older than $1 (in hours)
#
if [[ $# -ne 0 ]]; then
  while :
  do
    # get the newest image
    #
    i=$( ls -1td ~/run/* 2>/dev/null | head -n 1 | xargs -n 1 basename 2>/dev/null )
    if [[ -z "${i}" ]]; then
      echo "no newest image found"
      exit 2
    fi

    # get age in hours
    #
    let "age = $(date +%s) - $(stat -c%Y ~/run/${i})"
    let "age = $age / 3600"
    if [[ $age -ge $1 ]]; then
      break
    fi
    exit 3
  done
fi

# kick off the oldest image
#
i=$( ls -1td ~/run/* 2>/dev/null | tail -n 1 | xargs -n 1 basename 2>/dev/null )
if [[ -z "${i}" ]]; then
  echo "no oldest image found"
  exit 4
fi
date
echo "stopping ${i}"
/opt/tb/bin/stop_img.sh ${i}

# wait till it is stopped
#
while :
do
  if [[ ! -f ~/run/${i}/tmp/LOCK ]]; then
    break
  fi
  sleep 1
done
rm ~/run/${i} ~/logs/${i}.log
date
echo "deleted  ${i}"
echo

# spin up a new one
#
while :
do
  sudo /opt/tb/bin/setup_img.sh && break
done
