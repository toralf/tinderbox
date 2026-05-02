#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

set -euf
export LANG=C.utf8
export PATH='/usr/sbin:/usr/bin:/sbin:/bin:'

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

img=$(basename $1)
child=$(jq -r '."child-pid"' /tmp/$img.json)
[[ -n $child ]]
cd ~tinderbox/img/$img

if [[ $# -eq 1 ]]; then
  # interactive shell
  LC_ALL=$LANG nsenter -t $child -a -r \
    bash
else
  # if $2 is "" or a pid then create a gdb bt,  with a "0" just the namespace process table is dumped
  out=/tmp/$(basename $0).log
  truncate -s 0 $out

  LC_ALL=$LANG nsenter -t $child -a -r \
    bash -c 'COLUMNS=10000 ps faux; exit' 2>&1 |
    tee -a $out

  echo
  pid=${2:-0}
  if [[ $pid -gt 0 ]]; then
    echo -n "pid ($pid, 0=abort): "
    read -r input
    if [[ -n $input ]]; then
      pid=$input
    fi
    echo

    echo -e "\n\n  + + + gdb bt for $img with child-pid $child for pid $pid + + +\n\n" | tee -a $out
    LC_ALL=$LANG nsenter -t $child -a -r \
      gdb -q -batch \
      -ex 'set logging enabled off' -ex 'set pagination off' -ex 'thread apply all bt' -ex 'detach' -ex 'quit' \
      -p $pid 2>&1 |
      tee -a $out
  fi

  echo -e "\n\n  + + +  helper:  curl -F'file=@$out' https://paste.gentoo.zip  + + +\n\n"
fi
