#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

img=$(basename $1)
pid=$(jq -r '."child-pid"' /tmp/$img.json)

echo "get gdb trace for $img with pid $pid"

# these parameters should match the --unshare-... of bwrap.sh
nsenter -t $pid -F -C -i -p -u \
  gdb -q -batch -ex "set logging enabled off" -ex "bt full" -ex "detach" -ex "quit" -p 1

