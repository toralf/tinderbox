#!/bin/sh
#
# set -x

# retest package(s)
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo "You must be the tinderbox user !"
  exit 1
fi

echo $* |\
xargs -n 1 |\
while read line
do
  # split away the version/revision if applicable
  #
  p=$(qatom "$line" | sed 's/[ ]*(null)[ ]*//g' | cut -f1-2 -d' ' -s | tr ' ' '/')
  if [[ -z "$p" ]]; then
    p=$line
  fi

  # remove all image specific package exceptions
  #
  sed -i -e "/$(echo $p | sed -e 's,/,\\/,')/d"  \
    ~/tb/data/ALREADY_CATCHED                   \
    ~/run/*/etc/portage/package.mask/self       \
    ~/run/*/etc/portage/package.env/{cxx,nosandbox,notest} 2>/dev/null

  # don't use backlog.upd b/c that content is shuffled around by update_backlog.sh
  #
  for i in ~/run/*
  do
    echo "$p" >> $i/tmp/backlog
  done
done

exit 0
