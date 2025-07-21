#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

set -euf
export LANG=C.utf8
export PATH='./usr/sbin:./usr/bin:./sbin:./bin:/usr/sbin:/usr/bin:/sbin:/bin'

img=$(basename $1)
child=$(jq -r '."child-pid"' /tmp/$img.json)

cd ~tinderbox/img/$img

nsenter -t $child -a -r \
  bash -c 'ps faux; exit'

echo
pid=1
echo -n "pid ($pid): "
read -r input
[[ -n $input ]] && pid=$input
echo

echo "get gdb bt for $img with child-pid $child for pid $pid"
nsenter -t $child -a -r \
  gdb -q -batch -ex 'set logging enabled off' -ex 'thread apply all bt' -ex 'detach' -ex 'quit' -p $pid
