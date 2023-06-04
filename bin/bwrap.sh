#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# bubblewrap/chroot into an image to either run a script -or- to work interactively in it

function CgroupCreate() {
  local name=local/$1
  local pid=$2

  if ! cgcreate -g cpu,memory:$name; then
    return 1
  fi

  local jobs=$(
    set +f
    sed 's,^.*j,,' $mnt/etc/portage/package.env/00j*
  )

  # j+0.1 vCPU, slice is 10us
  local cpu=$((100000 * jobs + 10000))
  cgset -r cpu.cfs_quota_us=$cpu $name

  local mem=$((4 * jobs + 10))
  cgset -r memory.limit_in_bytes=${mem}G $name

  # this setting implies a quota for /var/tmp/portage too (because that dir is a tmpfs)
  cgset -r memory.memsw.limit_in_bytes=70G $name

  for i in cpu memory; do
    echo "1" >/sys/fs/cgroup/$i/$name/notify_on_release
    if ! echo "$pid" >/sys/fs/cgroup/$i/$name/tasks; then
      return 1
    fi
  done
}

function CgroupDelete() {
  local name=local/$1

  cgdelete -g cpu,memory:$name
}

# no "echo" here
function Exit() {
  local rc=${1:-$?}

  trap - INT QUIT TERM EXIT

  if [[ $wrapper == "Chroot" ]]; then
    ChrootUmountAll
  fi

  if [[ -d $lock_dir ]]; then
    rmdir -- $lock_dir
  fi

  exit $rc
}

function ChrootMountAll() {
  set -e

  mount -o size=16G -t tmpfs tmpfs $mnt/run
  mount -t proc proc $mnt/proc
  mount --rbind /sys $mnt/sys
  mount --make-rslave $mnt/sys

  mount --rbind /dev $mnt/dev
  mount --make-rslave $mnt/dev

  mount -o bind ~tinderbox/tb/data $mnt/mnt/tb/data
  mount -o bind,ro ~tinderbox/tb/sdata/ssmtp.conf $mnt/etc/ssmtp/ssmtp.conf
  mount -o bind ~tinderbox/distfiles $mnt/var/cache/distfiles

  mount -o size=16G -t tmpfs tmpfs $mnt/tmp
  mount -o size=16G -t tmpfs tmpfs $mnt/var/tmp/portage

  return $?
}

function ChrootUmountAll() {
  set +e

  umount -l $mnt/var/tmp/portage $mnt/tmp \
    $mnt/var/cache/distfiles $mnt/etc/ssmtp/ssmtp.conf $mnt/mnt/tb/data \
    $mnt/dev{/pts,/shm,/mqueue,} \
    $mnt/{sys,proc,run}
}

function Chroot() {
  if ChrootMountAll; then
    if [[ -n $entrypoint ]]; then
      /usr/bin/chroot $mnt /bin/bash -l -c "su - root -c /entrypoint"
    else
      /usr/bin/chroot $mnt /bin/bash -l -c "su - root"
    fi
  fi
  local rc=$?

  if ! ChrootUmountAll; then
    ((++rc))
  fi

  return $rc

}

function Bwrap() {
  local path="/usr/sbin:/usr/bin"
  if [[ ! $mnt =~ "merged_usr" && ! $mnt =~ "23.0" ]]; then
    path+="/sbin:/bin"
  fi

  local hostname="$(cat $mnt/etc/conf.d/hostname)"
  if [[ -z $hostname || $hostname =~ ' ' ]]; then
    hostname="wrong-hostname"
  fi

  local home_dir="/var/tmp/tb"
  if [[ ! -d $mnt/$home_dir ]]; then
    home_dir="/"
  fi

  local sandbox=(env -i
    /usr/bin/bwrap
    --clearenv
    --setenv HOME "/root"
    --setenv MAILTO "${MAILTO:-tinderbox}"
    --setenv PATH "$path"
    --setenv SHELL "/bin/bash"
    --setenv TERM "linux"
    --setenv USER "root"
    --hostname "$hostname"
    --die-with-parent
    --chdir "$home_dir"
    --unshare-cgroup
    --unshare-ipc
    --unshare-pid
    --unshare-uts
    --bind "$mnt" /
    --dev /dev
    --mqueue /dev/mqueue
    --perms 1777 --tmpfs /dev/shm
    --ro-bind ~tinderbox/tb/sdata/ssmtp.conf /etc/ssmtp/ssmtp.conf
    --bind ~tinderbox/tb/data /mnt/tb/data
    --proc /proc
    --ro-bind ~tinderbox/.bugzrc /root/.bugzrc
    --tmpfs /run
    --ro-bind /sys /sys
    --size $((2 ** 30)) --perms 1777 --tmpfs /tmp
    --bind ~tinderbox/distfiles /var/cache/distfiles
    --size $((2 ** 35)) --perms 1777 --tmpfs /var/tmp/portage
    /bin/bash -l
  )

  if [[ -n $entrypoint ]]; then
    ("${sandbox[@]}" -c "/entrypoint")
  else
    ("${sandbox[@]}")
  fi
  local rc=$?

  return $rc
}

#############################################################################
#
# main
#
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

entrypoint=""
mnt=""
wrapper="Bwrap"

while getopts ce:m: opt; do
  case $opt in
  c)
    wrapper="Chroot"
    ;;
  e)
    if [[ ! -s $OPTARG ]]; then
      echo "no valid entrypoint script given: $OPTARG" >&2
      exit 1
    fi
    entrypoint=$OPTARG
    ;;
  m)
    if [[ -z $OPTARG || -z ${OPTARG##*/} || $OPTARG =~ [[:space:]] || $OPTARG =~ [\\\(\)\`$] ]]; then
      echo "argument not accepted" >&2
      exit 1
    fi
    mnt=~tinderbox/img/${OPTARG##*/}
    ;;
  *)
    echo "unknown parameter '$opt'" >&2
    exit 1
    ;;
  esac
done

if [[ -z $mnt ]]; then
  echo "no mnt given!" >&2
  exit 1
fi

if [[ ! -e $mnt ]]; then
  echo "no valid mount point given" >&2
  exit 1
fi

if [[ $(stat -c '%u' "$mnt") != "0" ]]; then
  echo "wrong ownership of mount point" >&2
  exit 1
fi

if [[ ! -d /run/tinderbox/ ]]; then
  mkdir /run/tinderbox/
fi

# this is the 1st barrier (the 2nd is cgroup)
lock_dir="/run/tinderbox/${mnt##*/}.lock"
if ! mkdir "$lock_dir"; then
  echo "lock dir cannot be created: $lock_dir"
  exit 1
fi

trap Exit INT QUIT TERM EXIT

if ! CgroupCreate ${mnt##*/} $$; then
  CgroupDelete ${mnt##*/}
  exit 1
fi

if [[ -n $entrypoint ]]; then
  rm -f "$mnt/entrypoint"
  cp "$entrypoint" "$mnt/entrypoint"
  chmod 744 "$mnt/entrypoint"

  rm -f "$mnt/lib.sh"
  cp "$(dirname $0)/lib.sh" "$mnt/lib.sh"
  chmod 644 "$mnt/lib.sh"
fi

$wrapper
