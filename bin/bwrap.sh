#!/bin/bash
#
# set -x


# bubblewrap into an image interactively - or - run an entrypoint script
# https://forums.gentoo.org/viewtopic.php?p=8452922


function Cgroup() {
  if [[ ! -d "$cgroup_tinderbox_dir" ]]; then
    mkdir "$cgroup_tinderbox_dir"

    # avoid oom-killer eg. at emerging dev-perl/GD
    echo "16G" > $cgroup_tinderbox_dir/memory.limit_in_bytes
    echo "24G" > $cgroup_tinderbox_dir/memory.memsw.limit_in_bytes

    # restrict blast radius if -j1 for make is ignored
    echo "1000000" > $cgroup_tinderbox_dir/cpu.cfs_quota_us
    echo "1000000" > $cgroup_tinderbox_dir/cpu.cfs_period_us
  fi

  if [[ ! -d "$cgroup_image_dir" ]]; then
    mkdir "$cgroup_image_dir"
  fi
  if [[ -f "$cgroup_image_dir/cgroup.procs" && $(wc -l < "$cgroup_image_dir/cgroup.procs") -gt 0 ]]; then
    echo " cgroup has pid(s)"
    exit 1
  fi
  echo "$$" > "$cgroup_image_dir/cgroup.procs"
}


function CleanupAndExit()  {
  rm "$lock" "$cgroup_image_dir/cgroup.procs"
  rmdir "$cgroup_image_dir"
  exit $?
}


function Exit()  {
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

if [[ -d /home/tinderbox/img1/"${1##*/}" ]]; then
  mnt=/home/tinderbox/img1/"${1##*/}"

elif [[ -d /home/tinderbox/img2/"${1##*/}" ]]; then
  mnt=/home/tinderbox/img2/"${1##*/}"

else
  echo "no valid mount point found for $1"
  exit 2
fi

if [[ ! -d "$mnt" || -L "$mnt" || $(stat -c '%u' "$mnt") -ne 0 || ! "$mnt" = "$(realpath $mnt)" || ! "$mnt" =~ "/home/tinderbox/img" ]]; then
  echo "mount point not accepted"
  exit 2
fi

# 1st barrier to prevent to run emerge at the same image twice
lock="$mnt.lock"
if [[ -f "$lock" || -L "$lock" ]]; then
  echo "found lock $lock"
  exit 3
fi
touch "$lock"
if [[ -L "$lock" ]]; then
  echo "found symlinked lock $lock"
  exit 3
fi

# 2nd barrier
pgrep -af "^/usr/bin/bwrap --bind /home/tinderbox/img[12]/$(echo ${mnt##*/} | sed 's,+,.,g')" && exit 3

# 3rd barrier
cgroup_tinderbox_dir="/sys/fs/cgroup/tinderbox"
cgroup_image_dir="$cgroup_tinderbox_dir/${mnt##*/}"
Cgroup

# if now an error occurred then it is safe to remove the lock
trap CleanupAndExit QUIT TERM

rm -f "$mnt/entrypoint"
if [[ $# -eq 2 ]]; then
  if [[ -f "$2" ]]; then
    touch     "$mnt/entrypoint"
    chmod 744 "$mnt/entrypoint"
    cp "$2"   "$mnt/entrypoint"
  else
    echo "no valid entry point script given: $2"
    exit 4
  fi
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
    --hostname "BWRAP-$(echo "${mnt##*/}" | sed -e 's,[+\.],_,g' | cut -c-57)"
    --chdir /
    --die-with-parent
     /bin/bash -l
)

set +e  # be relax wrt job.sh exit code

if [[ -x "$mnt/entrypoint" ]]; then
  ("${sandbox[@]}" -c "chmod 1777 /dev/shm && /entrypoint")
else
  ("${sandbox[@]}")
fi

CleanupAndExit
