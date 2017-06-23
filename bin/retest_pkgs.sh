#!/bin/sh
#
# set -x

# retest a package
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo "You must be the tinderbox user !"
  exit 1
fi

while read line
do
  # split away the version/revision
  #
  p=$(qatom "$line" | sed 's/[ ]*(null)[ ]*//g' | cut -f1-2 -d' ' | tr ' ' '/')

  # remove all mask entries as well as other entries
  #
  sed -i -e "/$(echo $p | sed -e 's,/,\\/,')/d"  \
    ~/tb/data/ALREADY_CATCHED                   \
    ~/run/*/etc/portage/package.mask/self       \
    ~/run/*/etc/portage/package.env/{cxx,nosandbox,test-fail-continue}

  # schedule the package (not a particular version)
  #
  for pks in ~/run/*/tmp/packages
  do
    grep -q -E -e "^(STOP|INFO|%|@)" $pks
    if [[ $? -ne 0 ]]; then
      echo "$p" >> $pks
    fi
  done
done

exit 0
