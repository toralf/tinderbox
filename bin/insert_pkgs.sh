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
for i in ~/run/*
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

# get package names from new/changed ebuilds
#
tmp=$(mktemp /tmp/pksXXXXXX)

(
  cd /usr/portage/
  # the host repo is synced every 3 hours via a cron job, which ideally calls us
  #
  git diff --diff-filter=ACMR --name-status "@{ 3 hour ago }".."@{ 0 hour ago }"
) | grep -F '.ebuild' | cut -f2- | xargs -n 1 | cut -f1-2 -d'/' | sort --unique > $tmp

# prepend the package names onto the package list files at each available each image
#
info="# $(wc -l < $tmp) packages at $(date)"
if [[ -s $tmp ]]; then
  for pks in $avail_pks
  do
    echo "$info"              >> $pks
    # shuffle the package names around in a different way for each image
    #
    sort --random-sort < $tmp >> $pks
  done
fi

echo "$info"
rm $tmp
