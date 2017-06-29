#!/bin/sh
#
#set -x

mailto="tinderbox@zwiebeltoralf.de"

f=/tmp/$(basename $0).out

while :; do
  if [[ ! -f $f ]]; then
    if [[ -s ~/nohup.out ]]; then
      (ls -l ~/nohup.out; head -n 500 ~/nohup.out) | mail -s "nohup.out is non-empty" $mailto
      truncate -s 0 ~/nohup.out
    fi

    if [[ -n "$(ls -l ~/logs/)" && "$(wc -c ~/logs/* 2>/dev/null | tail -n 1 | cut -f1 -d' ')" != "0" ]]; then
      ls -l ~/logs/* >> $f
      head ~/logs/*  >> $f
      echo -e "\nto re-activate this test again, do:  rm $f" >> $f

      cat $f | mail -s "logs are non-empty" $mailto
    fi
  fi
  sleep 60
done
