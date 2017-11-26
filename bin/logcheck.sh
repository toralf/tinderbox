#!/bin/sh
#
# set -x

# check for non-empty image log files
#

mailto="tinderbox@zwiebeltoralf.de"

f=/tmp/$(basename $0).out

while :
do
  if [[ ! -f $f ]]; then
    if [[ -s ~/nohup.out ]]; then
      (ls -l ~/nohup.out; head -n 500 ~/nohup.out) | mail -s "nohup.out is non-empty" $mailto
      truncate -s 0 ~/nohup.out
    fi

    if [[ -n "$(ls ~/logs/)" && "$(wc -c ~/logs/* 2>/dev/null | tail -n 1 | awk ' { print $1 } ')" != "0" ]]; then
      ls -l ~/logs/* >> $f
      head ~/logs/*  >> $f
      echo -e "\nto re-activate this test again, do:  truncate -s 0 logs/*; rm -f $f" >> $f

      cat $f | mail -s "logs are non-empty" $mailto
    fi
  fi
  sleep 60
done
