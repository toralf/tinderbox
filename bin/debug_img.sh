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
  nsenter -t $child -a -r \
    bash
else
  # if $2 is "" or a pid then create a gdb bt,  with a "0" just the namespace process table is dumped
  out=/tmp/$(basename $0).log
  truncate -s 0 $out

  nsenter -t $child -a -r \
    bash -c 'COLUMNS=10000 ps faux; exit' 2>&1 |
    tee -a $out

  echo
  pid=${2:-0}
  if [[ $pid -gt 0 ]]; then
    echo -n "pid ($pid, 0=abort): "
    read -r input
    [[ -n $input ]] && pid=$input
    echo

    if [[ -n $pid && $pid -gt 0 ]]; then
      echo -e "\n\n  + + + gdb bt for $img with child-pid $child for pid $pid + + +\n\n" | tee -a $out
      nsenter -t $child -a -r \
        gdb -q -batch \
        -ex 'set logging enabled off' -ex 'set pagination off' -ex 'thread apply all bt' -ex 'detach' -ex 'quit' \
        -p $pid 2>&1 |
        tee -a $out
    fi
  fi

  echo -e "\n\n  + + +  helper:  curl -F'file=@$out' https://0x0.st  + + +\n\n"
fi
