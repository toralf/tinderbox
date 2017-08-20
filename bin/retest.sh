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
while read i
do
  # split away the version/revision
  #
  p=$(qatom $(portageq best_visible / "$i") 2>/dev/null | sed 's/[ ]*(null)[ ]*//g' | cut -f1-2 -d' ' -s | tr ' ' '/')
  if [[ -z "$p" ]]; then
    continue
  fi

  # remove all package entries made by job.sh
  #
  sed -i -e "/$(echo $p | sed -e 's,/,\\/,')/d"  \
    ~/tb/data/ALREADY_CATCHED                   \
    ~/run/*/etc/portage/package.mask/self       \
    ~/run/*/etc/portage/package.env/{cxx,nosandbox,notest} 2>/dev/null

  for i in ~/run/*
  do
    if [[ -f $i/tmp/STOP ]]; then
      continue
    fi

    pks=$i/tmp/packages

    # do not care about lines starting with a hash sign
    #
    grep -q -E -e "^(STOP|INFO|%|@)" $pks
    if [[ $? -eq 0 ]]; then
      continue
    fi

    # re-schedule the package itself not a specific version of it
    #
    echo "$p" >> $pks
  done
done

exit 0
