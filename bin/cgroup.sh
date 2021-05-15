#!/bin/sh
# set -x


# set overall cgroup v1 limits for all tinderboxes and other fuzzers (==consumers)


set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export LANG=C.utf8

if [[ ! -d /run/tinderbox ]]; then
  mkdir /run/tinderbox
fi

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

# prefer a generic name for all consumers
name=/local
cgcreate -g cpu,memory:$name

# default: reserve 3 cores (SMT gives +60%)
vcpu=${1:-$(echo "($(nproc) - 3 * 1.6)  * 100000.0" | bc | sed -e 's,\..*,,g')}
ram=${2:-120G}
vram=${3:-150G}
cgset -r cpu.cfs_quota_us=$vcpu             $name
cgset -r memory.limit_in_bytes=$ram         $name
cgset -r memory.memsw.limit_in_bytes=$vram  $name
