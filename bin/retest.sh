#!/bin/bash
#
# set -x

# retest package(s)
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo "You must be the tinderbox user !"
  exit 1
fi

echo $* | xargs -n 1 |\
uniq |\ # no sort -u
while read line
do
  if [[ -z "$line" ]]; then
    continue
  fi

  # split away version/revision if possible
  #
  p=$(qatom "$line" | sed 's/[ ]*(null)[ ]*//g' | cut -f1-2 -d' ' -s | tr ' ' '/')
  if [[ -z "$p" ]]; then
    p=$line
  fi

  sed -i -e "/$(echo $p | sed -e 's,/,\\/,')/d" \
    ~/tb/data/ALREADY_CATCHED                   \
    ~/run/*/etc/portage/package.mask/self       \
    ~/run/*/etc/portage/package.env/{nosandbox,test-fail-continue} 2>/dev/null

  for i in $(ls ~/run 2>/dev/null)
  do
    # high prio but schedule it after existing entries -> put it on top of that file
    #
    bl=~/run/$i/var/tmp/tb/backlog.1st
    if [[ "$(head -n 1 $bl)" = "$p" ]]; then
      continue
    fi

    if [[ -s $bl ]]; then
      sed -i -e "1i $p" $bl
    else
      echo "$p" >> $bl
    fi
  done

done

exit 0
