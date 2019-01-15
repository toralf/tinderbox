#!/bin/bash
#
# set -x

# check if stdout/err of job.sh was made
#

mailto="tinderbox@zwiebeltoralf.de"

f=/tmp/$(basename $0).out

while :
do
  if [[ ! -f $f ]]; then
    if [[ -n "$(ls ~/logs/)" ]]; then
      if [[ "$(wc -c ~/logs/* 2>/dev/null | tail -n 1 | awk ' { print $1 } ')" != "0" ]]; then
        (
          ls -l ~/logs/*
          echo
          head ~/logs/*
          echo
          ls -l ~/run/*/tmp/mail.log

          echo -e "\nto re-activate this test again, do:\n\n   truncate -s 0 ~/logs/*; rm -f $f\n"
        ) >> $f

        cat $f | mail -s "logs are non-empty" $mailto
      fi
    fi
  fi

  sleep 5
done
