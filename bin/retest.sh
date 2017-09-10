#!/bin/sh
#
# set -x

# read from stdin package(s) and re-test them
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo "You must be the tinderbox user !"
  exit 1
fi

xargs -n1 |\
while read line
do
  # split away the version/revision
  #
  p=$(qatom "$line" | sed 's/[ ]*(null)[ ]*//g' | cut -f1-2 -d' ' -s | tr ' ' '/')
  if [[ -z "$p" ]]; then
    p=$line
  fi

  # remove all package entries made by job.sh
  #
  sed -i -e "/$(echo $p | sed -e 's,/,\\/,')/d"  \
    ~/tb/data/ALREADY_CATCHED                   \
    ~/run/*/etc/portage/package.mask/self       \
    ~/run/*/etc/portage/package.env/{cxx,nosandbox,notest} 2>/dev/null

  for image in ~/run/*
  do
    if [[ -f $image/tmp/STOP ]]; then
      continue
    fi

    backlog=$image/tmp/backlog

    # do not care about lines starting with a hash sign
    #
    grep -q -E -e "^(STOP|INFO|%|@)" $backlog
    if [[ $? -eq 0 ]]; then
      continue
    fi

    # re-schedule the package itself not a specific version of it
    #
    echo "$p" >> $backlog
  done
done

exit 0
