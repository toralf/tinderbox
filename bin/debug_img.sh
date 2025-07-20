#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

img=$(basename $1)
child=$(jq -r '."child-pid"' /tmp/$img.json)

cd ~tinderbox/img/$img

echo " enter:    ps faux; exit"
nsenter -t $child -F -C -i -p -u -r bash

echo
echo -n "pid (1): "
read -r pid
echo

echo "get gdb trace for $img with child-pid $child for pid $pid"
nsenter -t $child -F -a -r \
  gdb -q -batch -ex "set logging enabled off" -ex "bt full" -ex "detach" -ex "quit" -p ${pid:-1}
