#!/bin/sh
#
# set -x

# a helper to test again a (previously failed) package at a tinderbox image
#
# for that all mask entries as well as other entries have to be removed
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo "You must be the tinderbox user !"
  exit 1
fi

while read line
do
  # split away the version/revision
  #
  p=$(qatom "$line" | cut -f1-2 -d' ' | tr ' ' '/')

  sed -i -e "/$(echo $ | sed -e 's,/,\/,')/d"  \
    ~/tb/data/ALREADY_CATCHED                   \
    ~/run/*/etc/portage/package.mask/self       \
    ~/run/*/etc/portage/package.env/{cxx,nosandbox,test-fail-continue}
done

exit 0
