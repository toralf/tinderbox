#!/bin/sh
#
#set -x

# pick up latest ebuilds and put them on top of each applicable package list
#

mailto="tinderbox@zwiebeltoralf.de"

# collect all package list filenames if the image ...
#   1. is symlinked to ~
#   2. is running (no LOCK)
#   3. has a non-empty package list
#   4. doesn't have any special entries in its package list
#
avail_pks=""
for i in ~/run/amd64-*
do
  if [[ ! -e $i/tmp/LOCK ]]; then
    continue
  fi

  pks=$i/tmp/packages
  if [[ ! -s $pks ]]; then
    continue
  fi

  # consider '#' too here
  # eg. it is set if we clone an image to replay the emerge order
  # or if the setup is not fully done
  # or if the previously added package/s aren't processed yet
  #
  grep -q -E "^(STOP|INFO|%|@|#)" $pks
  if [[ $? -eq 0 ]]; then
    continue
  fi

  avail_pks="$avail_pks $pks"
done

if [[ -z "$avail_pks" ]]; then
  echo "no image ready"
  exit
fi

# get package names of all new or changed ebuilds
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
