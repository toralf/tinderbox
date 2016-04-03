#!/bin/sh
#
# set -x

# spread freshly changed ebuilds around those images
#

mailto="tinderbox@zwiebeltoralf.de"

# get package list filenames of all chroot images which
#   1. are symlinked to ~ of the tinderbox user and
#   2. don't have any special entries in the package file
#
pksList=()
for i in ~/amd64-*
do
  if [[ ! -e $i/tmp/LOCK ]]; then
    continue
  fi

  f=$i/tmp/packages

  if [[ ! -s $f ]]; then
    continue
  fi

  grep -q -e "STOP" -e "INFO" -e "%" -e "@" $f
  if [[ $? -eq 0 ]]; then
    continue
  fi

  pksList=( ${dirU[@]} $f )
done

# empty array ?
#
if [[ ${#pksList[@]} = 0 ]]; then
  exit
fi

# this host repo is synced every 3 hours, add 1 hour too to give upstream a chance to mirror out ./files
# put that package "on top" of the package list (== at the bottom of the file) of arbitrarily choosen images
# we strip away the version b/c we do just want to test the latest visible package if not already done
#
# to strip the package version we can use dirname here instead qatom
# b/c the output of 'git diff' looks like this:
#
# A       www-apache/passenger/passenger-5.0.24.ebuild
# M       www-apps/kibana-bin/kibana-bin-4.1.4.ebuild
# A       www-apps/kibana-bin/kibana-bin-4.4.0.ebuild
#

log=/tmp/$(basename $0).log

(cd /usr/portage/; git diff --name-status "@{ 4 hour ago }".."@{ 1 hour ago }") | grep -v '^D' | grep -e '\.ebuild$' |\
awk ' { print $2 } ' | xargs dirname 2>/dev/null | sort --unique | tee $log | sort --random-sort |\
while read p
do
  echo $p >> ${pksList[$RANDOM % ${#pksList[@]}]}
done

if [[ $1 = "-m" ]]; then
  cat $log | mail -s "info: $(wc -l <$log) ebuilds poped" $mailto
fi
