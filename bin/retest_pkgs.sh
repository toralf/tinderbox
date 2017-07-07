#!/bin/sh
#
# set -x

# retest a package
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo "You must be the tinderbox user !"
  exit 1
fi

# stdin contains all packages
#
while read line
do
  # split away the version/revision
  #
  p=$(qatom "$line" | sed 's/[ ]*(null)[ ]*//g' | cut -f1-2 -d' ' -s | tr ' ' '/')
  if [[ -z "$p" ]]; then
    continue
  fi

  # remove all package specific entries made in job.sh
  #
  sed -i -e "/$(echo $p | sed -e 's,/,\\/,')/d"  \
    ~/tb/data/ALREADY_CATCHED                   \
    ~/run/*/etc/portage/package.mask/self       \
    ~/run/*/etc/portage/package.env/{cxx,nosandbox,notest,test-fail-continue} 2>/dev/null

  for i in ~/run/*
  do
    if [[ -f $i/tmp/STOP ]]; then
      continue
    fi

    pks=$i/tmp/packages

    # here we do not care about package lists having lines starting with a #
    #
    grep -q -E -e "^(STOP|INFO|%|@)" $pks
    if [[ $? -eq 0 ]]; then
      continue
    fi

    # re-schedule the package itself (not a specific version)
    #
    echo "$p" >> $pks
  done
done

exit 0
