#!/bin/bash
#
# set -x

# retest package(s)
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo "You must be the tinderbox user !"
  exit 1
fi

# list of package(s) to be retested
#
pks=/tmp/${0##*/}.txt
truncate -s 0 $pks

echo $* | xargs -n 1 |\
sort -u |\
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

  # delete package from various pattern files
  #
  sed -i -e "/$(echo $p | sed -e 's,/,\\/,')/d" \
    ~/tb/data/ALREADY_CATCHED                   \
    ~/run/*/etc/portage/package.mask/self       \
    ~/run/*/etc/portage/package.env/{nosandbox,test-fail-continue} 2>/dev/null

  echo $p >> $pks
done

if [[ -s $pks ]]; then
  for bl in $(ls ~/run/*/var/tmp/tb/backlog.1st 2>/dev/null)
  do
    (uniq $pks | shuf; cat $bl) > $bl.tmp
    # no "mv", that overwrites file permissions
    #
    cp $bl.tmp $bl
    rm $bl.tmp
  done
fi

exit 0
