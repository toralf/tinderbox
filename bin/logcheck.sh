#!/bin/sh
#
# set -x

# check that logs are empty
#

# works together with a crontab entry like:
#
# # clean logs; pre-fill cache, start the tinderbox and the log watch dog
# #
# @reboot    rm -f /home/tinderbox/logs/*.log; rm -f /home/tinderbox/run/*/tmp/{LOCK,STOP}; /opt/tb/bin/whatsup.sh -otlp &>/dev/null; sleep 240; /opt/tb/bin/start_img.sh; /opt/tb/bin/logcheck.sh

mailto="tinderbox@zwiebeltoralf.de"

f=/tmp/$(basename $0).out

while :
do
  if [[ ! -f $f ]]; then
    if [[ -n "$(ls ~/logs/)" && "$(wc -c ~/logs/* 2>/dev/null | tail -n 1 | awk ' { print $1 } ')" != "0" ]]; then
      ls -l ~/logs/* >> $f
      head ~/logs/*  >> $f
      echo -e "\n\n\nto re-activate this test again, do:\n\n   truncate -s 0 ~/logs/*; rm -f $f\n" >> $f

      cat $f | mail -s "logs are non-empty" $mailto
    fi
  fi

  sleep 5
done
