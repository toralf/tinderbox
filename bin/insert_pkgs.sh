#!/bin/sh
#
# set -x

# spread freshly changed ebuilds around those images
#

# get package list filenames of those images symlinked to $HOME and having no special tasks to do
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

# to strip the package version we can use dirname here instead qatom
# b/c the output of 'git diff' looks like this:
#
# A       www-apache/passenger/passenger-5.0.24.ebuild
# M       www-apps/kibana-bin/kibana-bin-4.1.4.ebuild
# A       www-apps/kibana-bin/kibana-bin-4.4.0.ebuild
#

# the host repo is synced every 4 hours, wait 2 more hours to mirror out all files
#
(cd /usr/portage/; git diff --name-status "@{ 6 hour ago }".."@{ 2 hour ago }") | grep -v '^D' | grep -e '\.ebuild$' -e '\.patch$' |\
awk ' { print $2 } ' | xargs dirname 2>/dev/null | sort --unique --random-sort |\
while read p
do
  # put it at 2 arbitrily choosen images "on top" of the package list == at the bottom of the file
  #
  echo $p >> ${pksList[$RANDOM % ${#pksList[@]}]}
done
