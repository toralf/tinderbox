#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# set overall cgroup v1 limits for fuzzers, tinderbox et al.

set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

export CGROUP_LOGLEVEL=ERROR

# must exist before any cgroup entry is created
echo 1 >/sys/fs/cgroup/memory/memory.use_hierarchy

# cgroup v1 does not cleanup after itself so create and use a shell script for that
# place it in a system wide read + executeable location for every consumer
agent="/tmp/cgroup-release-agent.sh"
rm -f $agent
cat <<EOF >$agent
#!/bin/bash

set +e
export CGROUP_LOGLEVEL=ERROR

cgdelete memory:/\$1
cgdelete cpu:/\$1

exit 0

EOF

chmod u+x $agent

for i in cpu memory; do
  echo $agent >/sys/fs/cgroup/$i/release_agent
done

# put all local stuff (fuzzers, tinderbox) under this item
name=/local
cgcreate -g cpu,memory:$name

# reserve resources for the host system
vcpu=$((100000 * ($(nproc) - 4)))
ram=$((128 - 24))G
vram=$((128 + 256 - 64))G # swap is 256 GiB
cgset -r cpu.cfs_quota_us=$vcpu $name
cgset -r memory.limit_in_bytes=$ram $name
cgset -r memory.memsw.limit_in_bytes=$vram $name
