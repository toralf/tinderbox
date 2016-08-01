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
#   4. don't have any special entries in its package file
#
avail_pks=""
for i in ~/amd64-*
do
  if [[ ! -e $i/tmp/LOCK ]]; then
    continue
  fi

  if [[ -e $i/tmp/STOP ]]; then
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

# nothing found ?
#
if [[ -z "$avail_pks" ]]; then
  exit
fi

# - the host repo is synced every 3 hours, add 1 hour too for mirroring
# - strip away the package version do test the latest visible package
# - dirname works here b/c the output of 'git diff' looks like:
#
# A       www-apache/passenger/passenger-5.0.24.ebuild
# M       www-apps/kibana-bin/kibana-bin-4.1.4.ebuild
# A       www-apps/kibana-bin/kibana-bin-4.4.0.ebuild

tmp=$(mktemp /tmp/pksXXXXXX)

(cd /usr/portage/; git diff --name-status "@{ 4 hour ago }".."@{ 1 hour ago }") |\
grep -v '^D'              |\
grep '\.ebuild$'          |\
awk ' { print $2 } '      |\
xargs dirname 2>/dev/null |\
sort --unique > $tmp

# shuffle the new ebuilds around for each image
#
if [[ -s $tmp ]]; then
  for pks in $avail_pks
  do
    sort --random-sort < $tmp >> $pks
  done
fi

rm $tmp
