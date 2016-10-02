#!/bin/sh
#
#set -x

# pick up latest ebuilds and put them on top of individual package lists
#

mailto="tinderbox@zwiebeltoralf.de"

# collect all package list filenames if the image ...
#   1. is symlinked to ~
#   2. is running
#   3. has a non-empty package list
#   4. doesn't have any special entries in its package list
#
avail_pks=""
for i in ~/amd64-*
do
  if [[ ! -e $i/tmp/LOCK ]]; then
    continue
  fi

  pks=$i/tmp/packages
  if [[ ! -s $pks ]]; then
    continue
  fi

  grep -q -E "^(STOP|INFO|%|@)" $pks
  if [[ $? -eq 0 ]]; then
    continue
  fi

  avail_pks="$avail_pks $pks"
done

# bail out ?
#
if [[ -z "$avail_pks" ]]; then
  exit
fi

# the host repo is synced every 3 hours, add 1 hour too for mirroring
# kick off (D)eleted ebuilds and strip away the package version
#
# A       www-apache/passenger/passenger-5.0.24.ebuild
# M       www-apps/kibana-bin/kibana-bin-4.1.4.ebuild
# A       www-apps/kibana-bin/kibana-bin-4.4.0.ebuild

tmp=$(mktemp /tmp/pksXXXXXX)

(
  cd /usr/portage/
  git diff --name-status "@{ 4 hour ago }".."@{ 1 hour ago }"
) |\
grep -v '^D'          |\
grep '\.ebuild$'      |\
awk ' { print $2 } '  |\
cut -f1-2 -d'/'       |\
sort --unique > $tmp

# shuffle the ebuilds around in a different way for each image
#
if [[ -s $tmp ]]; then
  for pks in $avail_pks
  do
    sort --random-sort < $tmp >> $pks
  done
fi

rm $tmp
