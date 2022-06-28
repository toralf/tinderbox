function __getStartTime() {
  local b=$(basename $1)

  cat ~tinderbox/img/$b/var/tmp/tb/setup.timestamp
}


function __is_cgrouped() {
  local b=$(basename $1)

  [[ -d /sys/fs/cgroup/cpu/local/$b/ ]]
}


function __is_locked() {
  local b=$(basename $1)

  [[ -d /run/tinderbox/$b.lock/ ]]
}


function __is_running() {
  __is_cgrouped $1 || __is_locked $1
}
