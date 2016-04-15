#!/bin/sh
#
# set -x

# pick up latest ebuilds and put them on top of randomly choosen package lists
#

mailto="tinderbox@zwiebeltoralf.de"

# put all package list (f)ilenames of all chroot (i)mages into an (a)rray
# where the image
#   1. is symlinked to ~
#   2. is running
#   3. has a non-empty package list
#   4. don't have any special entries in its package file
#
a=()
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

  a=( ${a[@]} $f )
done

# nothing found ?
#
if [[ ${#a[@]} = 0 ]]; then
  exit
fi

# the host repo is synced every 3 hours, add an a hour more
# to give the ./files directory a chance to be mirrored out
# we strip away the package version b/c we do just want to test
# the latest visible package

# to strip the package version we can use dirname here instead qatom
# b/c the output of 'git diff' looks like:
#
# A       www-apache/passenger/passenger-5.0.24.ebuild
# M       www-apps/kibana-bin/kibana-bin-4.1.4.ebuild
# A       www-apps/kibana-bin/kibana-bin-4.4.0.ebuild

(cd /usr/portage/; git diff --name-status "@{ 4 hour ago }".."@{ 1 hour ago }") |\
grep -v '^D' | grep '\.ebuild$' | awk ' { print $2 } ' |\
xargs dirname 2>/dev/null | sort --unique --random-sort |\
while read p
do
  echo $p >> ${a[$RANDOM % ${#a[@]}]}
done
