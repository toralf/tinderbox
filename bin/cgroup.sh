#!/bin/sh
#set -x

# global upper limits for tinderboxes et.a l.

set -euf

# locking mechanism used by the tinderbox
mkdir /run/tinderbox

cgdir="/sys/fs/cgroup/memory/local"
if [[ ! -d "$cgdir" ]]; then
  mkdir "$cgdir"
fi
echo "1"    > $cgdir/memory.use_hierarchy
echo "120G" > $cgdir/memory.limit_in_bytes
echo "140G" > $cgdir/memory.memsw.limit_in_bytes

cgdir="/sys/fs/cgroup/cpu/local"
if [[ ! -d "$cgdir" ]]; then
  mkdir "$cgdir"
fi
echo "900000" > $cgdir/cpu.cfs_quota_us
echo "100000" > $cgdir/cpu.cfs_period_us
