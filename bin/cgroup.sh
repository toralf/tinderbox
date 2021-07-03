#!/bin/sh
# set -x


# set overall cgroup v1 limits for tinderbox images, fuzzers et al.


set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export LANG=C.utf8

# use cgroup v1 if available
if ! hash -r cgcreate || ! hash -r cgset || ! test -d /sys/fs/cgroup; then
  exit 0
fi

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

# prefer a generic identifier
name=/local
cgcreate -g cpu,memory:$name

# reserve 3.5 vCPUs, 18 GB RAM and 64 GB vRAM for others
vcpu=${1:-$(($(nproc) * 100000 - 350000))}
ram=${2:-110G}
vram=${3:-320G}
cgset -r cpu.cfs_quota_us=$vcpu             $name
cgset -r memory.limit_in_bytes=$ram         $name
cgset -r memory.memsw.limit_in_bytes=$vram  $name
