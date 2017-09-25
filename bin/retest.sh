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

  # don't put this into backlog.upd b/c it could be delayed by a huge repository update
  #
  for i in ~/run/*
  do
    echo "$p" >> $i/tmp/backlog
  done
done

exit 0
