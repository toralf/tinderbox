#!/bin/bash
# set -x

# act if stdout/err of job.sh is non-empty

set -eu
export LANG=C.utf8

mailto="tinderbox@zwiebeltoralf.de"

f=/tmp/${0##*/}.out

while [[ : ]]
do
  if [[ ! -f $f ]]; then
    if [[ "$(wc -c ~/logs/*.log 2>/dev/null | tail -n 1 | awk ' { print $1 } ')" != "0" ]]; then
      (
        ls -l ~/logs/
        echo
        head -v ~/logs/*.log
        echo
        ls -l ~/run/*/var/tmp/tb/mail.log
        echo
        head -v ~/run/*/var/tmp/tb/mail.log
        echo -e "\nto re-activate this test again, do:\n\n   tail -v ~/logs/*; truncate -s 0 ~/logs/*; rm -f $f\n"
      ) |\
      tee $f | mail -s "logs are non-empty" $mailto || true
    fi
  fi

  sleep 1
done
