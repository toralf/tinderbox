#!/bin/bash
#
# set -x

# bubblewrap into an image interactively - or - run a command
# https://forums.gentoo.org/viewtopic.php?p=8452922

function cgroup() {
  # avoid oom-killer eg. while emerging dev-perl/GD
  #
  local sysfsdir="/sys/fs/cgroup/memory/tinderbox-${mnt##*/}"
  if [[ ! -d "$sysfsdir" ]]; then
    mkdir -p "$sysfsdir"
  fi

  echo "$$" > "$sysfsdir/tasks"

  echo "12 * 2^30" | bc > $sysfsdir/memory.limit_in_bytes
  echo "16 * 2^30" | bc > $sysfsdir/memory.memsw.limit_in_bytes

  # restrict blast radius if -j1 for make processes is ignored
  #
  local sysfsdir="/sys/fs/cgroup/cpu/tinderbox-${mnt##*/}"
  if [[ ! -d "$sysfsdir" ]]; then
    mkdir -p "$sysfsdir"
  fi

  echo "$$" > "$sysfsdir/tasks"

  echo "100000" > $sysfsdir/cpu.cfs_quota_us
  echo "100000" > $sysfsdir/cpu.cfs_period_us
}


function Exit()  {
  rm "$lock"
  exit ${1:-1}
}


#############################################################################
#                                                                           #
# main                                                                      #
#                                                                           #
#############################################################################
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8
export GREP_COLOR="never"
export GREP_COLORS="never"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo " wrong opt(s)!"
  exit 1
fi

mnt="$(ls -d ~tinderbox/img{1,2}/${1##*/} 2>/dev/null || true)"

if [[ -z "$mnt" || ! -d "$mnt" || -L "$mnt" || $(stat -c '%u' "$mnt") -ne 0 ]]; then
  echo "no valid mount point found"
  exit 1
fi

if [[ "$mnt" =~ ".." || "$mnt" =~ "//" || "$mnt" =~ [[:space:]] || "$mnt" =~ '\' ]]; then
  echo "illegal character(s) in mount point"
  exit 1
fi

# 1st barrier to prevent running the same image twice
#
lock="$mnt/var/tmp/tb/LOCK"
if [[ -f "$lock" || -L "$lock" ]]; then
  echo "found lock file $lock"
  exit 1
fi

# 2nd barrier
#
pgrep -af "/usr/bin/bwrap .*$(echo ${mnt##*/} | sed "s,+,.,g")" && exit 1

touch "$lock"
chown tinderbox:tinderbox "$lock"

trap Exit QUIT TERM

rm -f "$mnt/entrypoint"

if [[ $# -eq 2 && -f $2 ]]; then
  cp "$2"   $mnt/entrypoint
  chmod 744 $mnt/entrypoint
fi

sandbox=(env -i
    PATH=/usr/sbin:/usr/bin:/sbin:/bin
    HOME=/root
    SHELL=/bin/bash
    TERM=linux
    /usr/bin/bwrap
    --bind $mnt                         /
    --bind /home/tinderbox/tb/data      /mnt/tb/data
    --bind /home/tinderbox/distfiles    /var/cache/distfiles
    --ro-bind /home/tinderbox/tb/sdata  /mnt/tb/sdata
    --ro-bind /var/db/repos             /mnt/repos
    --tmpfs                             /var/tmp/portage
    --tmpfs /dev/shm
    --dev /dev --proc /proc
    --mqueue /dev/mqueue
    --unshare-ipc --unshare-pid --unshare-uts
    --hostname "BWRAP-$(echo "${mnt##*/}" | sed -e 's,[+\.],_,g' | cut -c-57)"
    --chdir /
    --die-with-parent
     /bin/bash -l
)

cgroup

if [[ -x "$mnt/entrypoint" ]]; then
  (${sandbox[@]} -c "chmod 1777 /dev/shm && /entrypoint")
else
  (${sandbox[@]})
fi

Exit $?
