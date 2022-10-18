#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# set overall cgroup v1 limits for tinderbox images, fuzzers et al.


set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export LANG=C.utf8

# must exist before any cgroup entry is created
echo 1 > /sys/fs/cgroup/memory/memory.use_hierarchy

# cgroup v1 does not cleanup after itself so create and use a shell script for that
# place it in a system wide read + executeable location for every consumer
agent="/tmp/cgroup-release-agent.sh"
cat << EOF > $agent
#!/bin/sh

cgdelete -g cpu,memory:\$1

EOF

chown root:root $agent
chmod 755       $agent

for i in cpu memory
do
  echo $agent > /sys/fs/cgroup/$i/release_agent
done

# put all local stuff (fuzzers, tinderbox) under this item
name=/local
cgcreate -g cpu,memory:$name

# reserve ressources for the host system
vcpu=$(( 100000 * ($(nproc)-6) ))
ram=$(( 128-24 ))G
vram=$(( 384-64 ))G   # vram=ram+swap, swap is 0.25 TB
cgset -r cpu.cfs_quota_us=$vcpu             $name
cgset -r memory.limit_in_bytes=$ram         $name
cgset -r memory.memsw.limit_in_bytes=$vram  $name
