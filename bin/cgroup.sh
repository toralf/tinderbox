#!/bin/sh
set -x

# global upper limits for tinderboxes et.a l.

# set -euf

# hold lockdir names, the locking mechanism used by the tinderbox script bwrap.sh
mkdir /run/tinderbox

name=/local

cgcreate -g cpu,memory:$name

cgset -r cpu.cfs_quota_us=900000  $name
cgset -r cpu.cfs_period_us=100000 $name

cgset -r memory.use_hierarchy=1           $name
cgset -r memory.limit_in_bytes=120G       $name
cgset -r memory.memsw.limit_in_bytes=140G $name

echo "/opt/tb/bin/cgroup-release-agent.sh" > /sys/fs/cgroup/cpu/release_agent
echo "/opt/tb/bin/cgroup-release-agent.sh" > /sys/fs/cgroup/memory/release_agent

echo 1 > /sys/fs/cgroup/cpu/$name/notify_on_release
echo 1 > /sys/fs/cgroup/memory/$name/notify_on_release
