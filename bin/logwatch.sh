#!/bin/sh
#
#set -x

mailto="tinderbox@zwiebeltoralf.de"

if [[ -s ~/nohup.out ]]; then
  (ls -l ~/nohup.out; head -n 500 ~/nohup.out) | mail -s "nohup.out is non-empty" $mailto
  truncate -s 0 ~/nohup.out
fi

f=/tmp/watch.tinderbox.logs
if [[ ! -f $f ]]; then
  if [[ "$(wc -w ~/logs/* 2>/dev/null | tail -n 1)" != "0 total" ]]; then
    ls -l ~/logs/* > $f
    (cat $f; echo; echo "remove $f to re-activate this test again") | mail -s "logs are non-empty" $mailto
  fi
fi

