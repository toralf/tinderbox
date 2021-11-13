#!/bin/bash
# set -x


# set overall cgroup v1 limits for tinderbox images, fuzzers et al.


set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export LANG=C.utf8

# use cgroup v1 if available
if ! hash -r cgcreate || ! hash -r cgset || ! test -d /sys/fs/cgroup; then
  exit 0
fi

# reserve 3 vCPUs, 18 GB RAM and 64 GB vRAM
vcpu=$(( 100000 * ($(nproc) - 3) ))
ram=110G
vram=320G

echo 1 > /sys/fs/cgroup/memory/memory.use_hierarchy

# cgroup v1 does not cleanup after itself
agent=/tmp/cgroup-release-agent.sh
cat << EOF > $agent
#!/bin/sh
cgdelete -g cpu,memory:\$1

EOF
chmod 755 $agent
for i in cpu memory
do
  echo $agent > /sys/fs/cgroup/$i/release_agent
done

# prefer a generic identifier both for Tor project and for Gentoo tinderbox
name=/local
cgcreate -g cpu,memory:$name

cgset -r cpu.cfs_quota_us=$vcpu             $name
cgset -r memory.limit_in_bytes=$ram         $name
cgset -r memory.memsw.limit_in_bytes=$vram  $name
