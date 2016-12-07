#!/bin/sh
#
#set -x

# pick up latest ebuilds and put them on top of individual package lists
#

mailto="tinderbox@zwiebeltoralf.de"

# collect all package list filenames if the image ...
#   1. is symlinked to ~
#   2. is running (no LOCK)
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

  # do not consider '#' - that's just a comment marker
  #
  grep -q -E "^(STOP|INFO|%|@)" $pks
  if [[ $? -eq 0 ]]; then
    continue
  fi

  avail_pks="$avail_pks $pks"
done

if [[ -z "$avail_pks" ]]; then
  echo "no image ready"
  exit
fi

# put package names of new or changed ebuilds into tmp
#
tmp=$(mktemp /tmp/pksXXXXXX)

# the host repo is synced every 3 hours, add 1 hour for mirroring
# kick off (D)eleted ebuilds and get the package name only
#
# A       www-apache/passenger/passenger-5.0.24.ebuild
# M       www-apps/kibana-bin/kibana-bin-4.1.4.ebuild
# A       www-apps/kibana-bin/kibana-bin-4.4.0.ebuild
#
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
info="# $(wc -l < $tmp) packages at $(date)"
if [[ -s $tmp ]]; then
  for pks in $avail_pks
  do
    echo "$info"              >> $pks
    sort --random-sort < $tmp >> $pks
  done
fi

echo "$info"
rm $tmp
