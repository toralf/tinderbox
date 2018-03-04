#!/bin/sh
#
# set -x

# retest package(s)
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo "You must be the tinderbox user !"
  exit 1
fi

# split away version/revision if possible
#
echo $* | xargs -n 1 |\
while read line
do
  if [[ -z "$line" ]]; then
    continue
  fi

  p=$(qatom "$line" | sed 's/[ ]*(null)[ ]*//g' | cut -f1-2 -d' ' -s | tr ' ' '/')
  if [[ -z "$p" ]]; then
    p=$line
  fi

  sed -i -e "/$(echo $p | sed -e 's,/,\\/,')/d"  \
    ~/tb/data/ALREADY_CATCHED                   \
    ~/run/*/etc/portage/package.mask/self       \
    ~/run/*/etc/portage/package.env/{cxx,nosandbox,notest} 2>/dev/null

  for i in $(ls ~/run)
  do
    echo "$p" >> ~/run/$i/tmp/backlog.upd
  done

done

exit 0
