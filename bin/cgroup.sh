#!/bin/sh
# set -x

# set cgroup v1 limits

set -euf

# prefer a generic name b/c not only tinderbox will use it
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

# make it available for non-tinderbox users too
cp /opt/tb/bin/cgroup-release-agent.sh /usr/local/bin/
chmod 755 /usr/local/bin/cgroup-release-agent.sh

for i in cpu memory
do
  echo "/usr/local/bin/cgroup-release-agent.sh" > /sys/fs/cgroup/$i/release_agent
done
