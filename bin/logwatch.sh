#!/bin/sh
#
#set -x

mailto="tinderbox@zwiebeltoralf.de"

if [[ -s ~/nohup.out ]]; then
  (ls -l ~/nohup.out; head -n 500 ~/nohup.out) | timeout 120 mail -s "nohup.out is non-empty" $mailto
  truncate -s 0 ~/nohup.out
fi

f=/tmp/watch.tinderbox.logs
if [[ ! -f $f ]]; then
  if [[ "$(wc -w ~/logs/* 2>/dev/null | tail -n 1)" != "0 total" ]]; then
    head ~/logs/* > $f
    echo -e "\nto re-activate this test again, do:  rm $f" >> $f
    cat $f | timeout 120 mail -s "logs are non-empty" $mailto
  fi
fi

