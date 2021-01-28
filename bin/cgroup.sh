#!/bin/sh
# set -x

# set cgroup v1 limits

set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export LANG=C.utf8


# use cgroup v1 if available
if ! hash -r cgcreate || ! hash -r cgset || ! test -d /sys/fs/cgroup; then
  exit 0
fi

# default: 8 vCPU, 120 GB RAM and 140 GB RAM+swap
vcpu=$(echo "scale=0; ${1:-8} * 100000" | bc)
ram=${2:-120G}
vram=${3:-140G}

# make this script available for non-tinderbox consumers too
cp /opt/tb/bin/cgroup-release-agent.sh /usr/local/bin/
chmod 755 /usr/local/bin/cgroup-release-agent.sh

echo 1 > /sys/fs/cgroup/memory/memory.use_hierarchy
for i in cpu memory
do
  echo "/usr/local/bin/cgroup-release-agent.sh" > /sys/fs/cgroup/$i/release_agent
done

# prefer a generic name b/c "tinderbox" is just one consumer of CGroups
name=/local
cgcreate -g cpu,memory:$name

cgset -r cpu.cfs_quota_us=$vcpu             $name
cgset -r memory.limit_in_bytes=$ram         $name
cgset -r memory.memsw.limit_in_bytes=$vram  $name
