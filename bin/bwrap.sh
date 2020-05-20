#!/bin/bash
#
# set -x


# bubblewrap into an image interactively - or - run an entrypoint script


# a cleanup hook is not mandatory b/c we do reboot often
function Cgroup() {
  for i in memory cpu
  do
    d="/sys/fs/cgroup/$i/tinderbox"
    [[ ! -d "$d" ]] && mkdir "$d"
  done

  # upper limit for all images
  local cgdir="/sys/fs/cgroup/memory/tinderbox"
  echo "112G" > "$cgdir/memory.limit_in_bytes"
  echo "140G" > "$cgdir/memory.memsw.limit_in_bytes"
  echo "$$"   > "$cgdir/tasks"

  # force an oom-killer before the kernel does it, eg. for dev-perl/GD or spidermonkey
  local cgdir="/sys/fs/cgroup/memory/tinderbox/${mnt##*/}"
  [[ ! -d "$cgdir" ]] && mkdir "$cgdir"
  echo "12G" > "$cgdir/memory.limit_in_bytes"
  echo "20G" > "$cgdir/memory.memsw.limit_in_bytes"
  echo "$$"  > "$cgdir/tasks"

  # restrict blast radius if -j1 is ignored (use period = 0.1 sec)
  local cgdir="/sys/fs/cgroup/cpu/tinderbox/${mnt##*/}"
  [[ ! -d "$cgdir" ]] && mkdir "$cgdir"
  echo "100000" > "$cgdir/cpu.cfs_quota_us"
  echo "100000" > "$cgdir/cpu.cfs_period_us"
  echo "$$"     > "$cgdir/tasks"
}


function CleanupAndExit()  {
  rmdir "$lock_dir" && exit $1 || exit $?
}


function Exit()  {
  echo "bail out ..."
  exit 1
}


#############################################################################
#                                                                           #
# main                                                                      #
#                                                                           #
#############################################################################
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

trap Exit QUIT TERM

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo " wrong # of args"
  exit 1
fi

if [[ "$1" =~ ".." || "$1" =~ "//" || "$1" =~ [[:space:]] || "$1" =~ '\' || "${1##*/}" = "" ]]; then
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

# a basic lock mechanism
if [[ ! -d /run/tinderbox ]]; then
  mkdir /run/tinderbox
fi

# a file operation might be racy, only mkdir is an atomic kernel file system operation
lock_dir="/run/tinderbox/${mnt##*/}.lock"
mkdir "$lock_dir"

trap CleanupAndExit QUIT TERM

Cgroup

if [[ -L "$mnt/entrypoint" ]]; then
  echo "found symlinked $mnt/entrypoint"
  CleanupAndExit 4
fi
rm -f "$mnt/entrypoint"
if [[ $# -eq 2 ]]; then
  if [[ ! -f "$2" ]]; then
    echo "no valid entry point script given: $2"
    CleanupAndExit 4
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
    --unshare-ipc
    --unshare-pid
    --unshare-uts
    --unshare-cgroup
    --unshare-user-try
    --hostname "BWRAP-$(echo "${mnt##*/}" | sed -e 's,[+\.],_,g' | cut -c-57)"
    --chdir /var/tmp/tb
    --die-with-parent
     /bin/bash -l
)

set +e

if [[ -x "$mnt/entrypoint" ]]; then
  ("${sandbox[@]}" -c "chmod 1777 /dev/shm && /entrypoint")
else
  ("${sandbox[@]}")
fi

CleanupAndExit $?
