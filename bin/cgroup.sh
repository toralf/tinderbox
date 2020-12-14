#!/bin/sh
# set -x

# global upper limits for tinderboxes, fuzzer et. al.
# the /run directory and the Cgroup settings are used by various scripts
# so maybe call this script eg. by a crontab @reboot line

set -euf

if [[ ! -d /run/tinderbox ]]; then
  mkdir /run/tinderbox
fi

echo "/opt/tb/bin/cgroup-release-agent.sh" > /sys/fs/cgroup/cpu/release_agent
echo "/opt/tb/bin/cgroup-release-agent.sh" > /sys/fs/cgroup/memory/release_agent

name=/local

cgcreate -g cpu,memory:$name

cgset -r cpu.use_hierarchy=1      $name
cgset -r cpu.cfs_quota_us=900000  $name
cgset -r cpu.cfs_period_us=100000 $name
cgset -r cpu.notify_on_release=1  $name

cgset -r memory.use_hierarchy=1           $name
cgset -r memory.limit_in_bytes=120G       $name
cgset -r memory.memsw.limit_in_bytes=140G $name
cgset -r memory.notify_on_release=1       $name
