#!/bin/sh
#
# set -x

# replace an tinderbox image with a new one
#

# get the oldest image (symlink) name
#
i=$( ls -1td ~/run/* 2>/dev/null | tail -n 1 | xargs -n 1 basename 2>/dev/null )

if [[ ! -e ~/run/${i} ]]; then
  exit 1
fi

/opt/tb/bin/stop_img.sh ${i}

# wait till it is stopped
#
while :
do
  if [[ ! -f ~/run/${i}/tmp/LOCK ]]; then
    break
  fi
  sleep 10
done

rm ~/run/${i} ~/log/${i}.log

while :
do
  /opt/tb/bin/setup_img.sh && break
done
