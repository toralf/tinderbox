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

  # remove all mask entries as well as other entries
  #
  sed -i -e "/$(echo $p | sed -e 's,/,\\/,')/d"  \
    ~/tb/data/ALREADY_CATCHED                   \
    ~/run/*/etc/portage/package.mask/self       \
    ~/run/*/etc/portage/package.env/{cxx,nosandbox,test-fail-continue}

  for i in ~/run/*
  do
    if [[ -f $i/tmp/STOP ]]; then
      continue
    fi

    pks=$i/tmp/packages

    grep -q -E -e "^(STOP|INFO|%|@)" $pks
    if [[ $? -eq 0 ]]; then
      continue
    fi

    # schedule the package (not a particular version)
    #
    echo "$p" >> $pks
  done
done

exit 0
