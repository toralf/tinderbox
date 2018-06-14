#!/bin/sh
#
# set -x

# check that logs and nohup.out are empty
#

mailto="tinderbox@zwiebeltoralf.de"

f=/tmp/$(basename $0).out

while :
do
  if [[ ! -f $f ]]; then
    if [[ -s ~/nohup.out ]]; then
      (ls -l ~/nohup.out; head -n 500 ~/nohup.out) | mail -s "nohup.out is NOT empty" $mailto
      truncate -s 0 ~/nohup.out
    fi

    if [[ -n "$(ls ~/logs/)" && "$(wc -c ~/logs/* 2>/dev/null | tail -n 1 | awk ' { print $1 } ')" != "0" ]]; then
      ls -l ~/logs/* >> $f
      head ~/logs/*  >> $f
      echo -e "\n\n\nto re-activate this test again, do:\n\n   truncate -s 0 logs/*; rm -f $f\n" >> $f

      cat $f | mail -s "logs are non-empty" $mailto
    fi
  fi

  sleep 15
done
