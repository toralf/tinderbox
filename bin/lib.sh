# /run/ lock dir is used by bwrap and cgroup
function __is_running() {
  [[ -d /run/tinderbox/$(basename $1).lock ]]
}


function __getStartTime() {
  cat ~tinderbox/img/$(basename $1)/var/tmp/tb/setup.timestamp
}

