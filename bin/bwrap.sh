#!/bin/bash
#
# set -x


# bubblewrap into an image interactively - or - run an entrypoint script


function Cgroup() {
  # force an oom-killer before the kernel does it, eg. for dev-perl/GD or dev-lang/spidermonkey
  local cgdir="/sys/fs/cgroup/memory/local/${mnt##*/}"
  if [[ ! -d "$cgdir" ]]; then
    mkdir "$cgdir"
  fi

  echo "1"   > "$cgdir/memory.use_hierarchy"
  echo "20G" > "$cgdir/memory.limit_in_bytes"
  echo "30G" > "$cgdir/memory.memsw.limit_in_bytes"
  echo "$$"  > "$cgdir/tasks"

  # restrict blast radius if -j1 is ignored
  local cgdir="/sys/fs/cgroup/cpu/local/${mnt##*/}"
  if [[ ! -d "$cgdir" ]]; then
    mkdir "$cgdir"
  fi
  echo "150000" > "$cgdir/cpu.cfs_quota_us"
  echo "100000" > "$cgdir/cpu.cfs_period_us"
  echo "$$"     > "$cgdir/tasks"
}


function Cleanup()  {
  rc=${1:-$?}
  rmdir "$lock_dir" && exit $rc || exit $?
}


function Exit()  {
  echo "bailing out ..."
}


#############################################################################
#                                                                           #
# main                                                                      #
#                                                                           #
#############################################################################
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

trap Exit EXIT QUIT TERM

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo " wrong # of args"
  exit 1
fi

if [[ "$1" =~ [[:space:]] || "$1" =~ '\' || "${1##*/}" = "" ]]; then
  echo "arg1 not accepted: $1"
  exit 2
fi

if [[ -d "/home/tinderbox/img1/${1##*/}" ]]; then
  mnt="/home/tinderbox/img1/${1##*/}"

elif [[ -d "/home/tinderbox/img2/${1##*/}" ]]; then
  mnt="/home/tinderbox/img2/${1##*/}"

else
  echo "no valid mount point found for $1"
  exit 2
fi

if [[ ! -d "$mnt" || -L "$mnt" || $(stat -c '%u' "$mnt") -ne 0 || ! "$mnt" = "$(realpath $mnt)" || ! "$mnt" =~ "/home/tinderbox/img" ]]; then
  echo "mount point not accepted"
  exit 2
fi

# a basic lock mechanism: only mkdir is an atomic kernel file system operation
lock_dir="/run/tinderbox/${mnt##*/}.lock"
mkdir "$lock_dir"

trap Cleanup EXIT QUIT TERM

Cgroup

if [[ -L "$mnt/entrypoint" ]]; then
  echo "found symlinked $mnt/entrypoint"
  Cleanup 4
fi
rm -f "$mnt/entrypoint"
if [[ $# -eq 2 ]]; then
  if [[ ! -f "$2" ]]; then
    echo "no valid entry point script given: $2"
    Cleanup 4
  fi
  touch     "$mnt/entrypoint"
  chmod 744 "$mnt/entrypoint"
  cp "$2"   "$mnt/entrypoint"
fi

sandbox=(env -i
    PATH=/usr/sbin:/usr/bin:/sbin:/bin
    HOME=/root
    SHELL=/bin/bash
    TERM=linux
    /usr/bin/bwrap
    --bind "$mnt"                       /
    --bind /home/tinderbox/tb/data      /mnt/tb/data
    --bind /home/tinderbox/distfiles    /var/cache/distfiles
    --ro-bind /home/tinderbox/tb/sdata  /mnt/tb/sdata
    --ro-bind /var/db/repos             /mnt/repos
    --tmpfs                             /var/tmp/portage
    --tmpfs /dev/shm
    --dev /dev
    --proc /proc
    --mqueue /dev/mqueue
    --unshare-cgroup
    --unshare-ipc
    --unshare-pid
    --unshare-user-try
    --unshare-uts
    --hostname "BWRAP-$(echo "${mnt##*/}" | sed -e 's,[+\.],_,g' | cut -c-57)"
    --chdir /var/tmp/tb
    --die-with-parent
     /bin/bash -l
)

if [[ -x "$mnt/entrypoint" ]]; then
  ("${sandbox[@]}" -c "chmod 1777 /dev/shm && /entrypoint")
else
  ("${sandbox[@]}")
fi
