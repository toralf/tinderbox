#!/bin/sh
#set -x

# global upper limits for all fuzzers, tinderboxes etc.

set -e

# needed by tinderbox
mkdir /run/tinderbox

cgdir="/sys/fs/cgroup/memory/local"
mkdir $cgdir
echo "120G" > $cgdir/memory.limit_in_bytes
echo "140G" > $cgdir/memory.memsw.limit_in_bytes

cgdir="/sys/fs/cgroup/cpu/local"
mkdir $cgdir
echo "900000" > $cgdir/cpu.cfs_quota_us
echo "100000" > $cgdir/cpu.cfs_period_us

