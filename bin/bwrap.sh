#!/bin/bash
#
# set -x


# bubblewrap into an image interactively - or - run an entrypoint script
# https://forums.gentoo.org/viewtopic.php?p=8452922


function Cgroup() {
  if [[ ! -d "$cgroup_tinderbox_dir" ]]; then
    mkdir "$cgroup_tinderbox_dir"

    echo "1" > $cgroup_tinderbox_dir/cgroup.clone_children

    # avoid oom-killer eg. at emerging dev-perl/GD
    echo "16G" > $cgroup_tinderbox_dir/memory.limit_in_bytes
    echo "24G" > $cgroup_tinderbox_dir/memory.memsw.limit_in_bytes

    # restrict blast radius if -j1 for make is ignored
    echo "100000" > $cgroup_tinderbox_dir/cpu.cfs_quota_us
    echo "100000" > $cgroup_tinderbox_dir/cpu.cfs_period_us
  fi

  if [[ -d "$cgroup_image_dir" ]]; then
    echo "found a cgroup $cgroup_image_dir"
    exit 3
  else
    mkdir "$cgroup_image_dir"
  fi

  echo "$$" > "$cgroup_image_dir/tasks"
}


function CleanupAndExit()  {
  rm "$cgroup_image_dir/tasks"
  rmdir "$cgroup_image_dir" && exit $1 || exit $?
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

cgroup_tinderbox_dir="/sys/fs/cgroup/tinderbox"
cgroup_image_dir="$cgroup_tinderbox_dir/${mnt##*/}"
Cgroup

trap CleanupAndExit QUIT TERM

if [[ -L "$mnt/entrypoint" ]]; then
  echo "found symlinked $mnt/entrypoint"
  CleanupAndExit 4
fi
rm -f     "$mnt/entrypoint"
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
    --hostname "BWRAP-$(echo "${mnt##*/}" | sed -e 's,[+\.],_,g' | cut -c-57)"
    --chdir /var/tmp/tb
    --die-with-parent
     /bin/bash -l
)

set +e  # be relax wrt job.sh exit code

if [[ -x "$mnt/entrypoint" ]]; then
  ("${sandbox[@]}" -c "chmod 1777 /dev/shm && /entrypoint")
else
  ("${sandbox[@]}")
fi

CleanupAndExit $?
