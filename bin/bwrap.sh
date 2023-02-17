#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# wrap (bubblewrap or chroot) into an image to run a script in it -or- work interactively within it


function CgroupCreate() {
  local name=local/$1
  local pid=$2

  if ! cgcreate -g cpu,memory:$name; then
    return 1
  fi

  # the value of -jX of the image name gives the number of parallel build processes
  local j=$(grep -Eo '\-j[0-9]+' <<< $name | cut -c3-)

  # the slice is 10us
  local cpu=$(( 100000*j + 10000 ))
  cgset -r cpu.cfs_quota_us=$cpu $name

  local mem=$(( 4*j + 10 ))
  cgset -r memory.limit_in_bytes=${mem}G $name

  # Hint: /var/tmp/portage is a tmpfs therefore this memory settings has (implicitly) a quota for that directory too
  cgset -r memory.memsw.limit_in_bytes=70G $name

  for i in cpu memory
  do
    echo 1 > /sys/fs/cgroup/$i/$name/notify_on_release
    if ! echo "$pid" > /sys/fs/cgroup/$i/$name/tasks; then
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

  if [[ -d $lock_dir ]]; then
    rmdir "$lock_dir"
  fi
  exit $rc
}


function ChrootMountAll() {
  (
    set -e

    mount -o size=16G -t tmpfs  tmpfs $mnt/run
    mount             -t proc   proc  $mnt/proc
    mount --rbind               /sys  $mnt/sys
    mount --make-rslave               $mnt/sys

    mount --rbind               /dev  $mnt/dev
    mount --make-rslave               $mnt/dev

    mount -o bind     ~tinderbox/tb/data              $mnt/mnt/tb/data
    mount -o bind,ro  ~tinderbox/tb/sdata/ssmtp.conf  $mnt/etc/ssmtp/ssmtp.conf
    mount -o bind     ~tinderbox/distfiles            $mnt/var/cache/distfiles

    mount -o size=16G -t tmpfs  tmpfs   $mnt/tmp
    mount -o size=16G -t tmpfs  tmpfs   $mnt/var/tmp/portage
  )

  return $?
}


function ChrootUmountAll() {
  (
    set +e

    umount -l $mnt/var/tmp/portage $mnt/tmp
    umount -l $mnt/var/cache/distfiles $mnt/etc/ssmtp/ssmtp.conf $mnt/mnt/tb/data
    umount -l $mnt/dev{/pts,/shm,/mqueue,}
    umount -l $mnt/{sys,proc,run}
  )
}


function Chroot() {
  local rc

  if ChrootMountAll; then
    if [[ -n "$entrypoint" ]]; then
      (/usr/bin/chroot $mnt /bin/bash -l -c "su - root -c /entrypoint")
      rc=$?
    else
      (/usr/bin/chroot $mnt /bin/bash -l -c "su - root")
      rc=$?
    fi
  else
    rc=13
  fi

  if ! ChrootUmountAll; then
    (( rc++ ))
  fi

  return $rc
}


function Bwrap() {
  if [[ $mnt =~ "merged_usr" || $mnt =~ "23.0" ]]; then
    local path="/usr/sbin:/usr/bin"
  else
    local path="/sbin:/bin:/usr/sbin:/usr/bin"
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
        --hostname "$(cat $mnt/etc/conf.d/hostname)"
        --die-with-parent
        --chdir /var/tmp/tb
        --unshare-cgroup
        --unshare-ipc
        --unshare-pid
        --unshare-uts
        --bind "$mnt"                             /
        --dev                                     /dev
        --mqueue                                  /dev/mqueue
        --perms 1777 --tmpfs                      /dev/shm
        --ro-bind ~tinderbox/tb/sdata/ssmtp.conf  /etc/ssmtp/ssmtp.conf
        --bind ~tinderbox/tb/data                 /mnt/tb/data
        --proc                                    /proc
        --ro-bind ~tinderbox/.bugzrc              /root/.bugzrc
        --tmpfs                                   /run
        --ro-bind /sys                            /sys
        --size $((1*2**30)) --perms 1777 --tmpfs  /tmp
        --bind ~tinderbox/distfiles               /var/cache/distfiles
        --size $((32*2**30)) --perms 1777 --tmpfs /var/tmp/portage
        /bin/bash -l
  )

  if [[ -n "$entrypoint" ]]; then
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
  echo " you must be root"
  exit 1
fi

wrapper="Bwrap"
entrypoint=""
mnt=""

while getopts ce:m: opt
do
  case $opt in
    c)  wrapper="Chroot"
        ;;
    e)  if [[ ! -s "$OPTARG" ]]; then
          echo "no valid entrypoint script given: $OPTARG"
          exit 1
        fi
        entrypoint=$OPTARG
        ;;
    m)  if [[ -z "$OPTARG" || -z "${OPTARG##*/}" || "$OPTARG" =~ [[:space:]] || "$OPTARG" =~ [\\\(\)\`$] ]]; then
          echo "argument not accepted"
          exit 1
        fi
        mnt=~tinderbox/img/${OPTARG##*/}
        ;;
    *)  echo "unknown parameter '$opt'"; exit 1;;
  esac
done

if [[ -z "$mnt" ]]; then
  echo "no mnt given!"
  exit 1
fi

if [[ ! -e "$mnt" ]]; then
  echo "no valid mount point given"
  exit 1
fi

if [[ $(stat -c '%u' "$mnt") != "0" ]]; then
  echo "wrong ownership of mount point"
  exit 1
fi

# this is usually the 2nd barrier but would be the 1st if no cgroup is in place
lock_dir="/run/tinderbox/${mnt##*/}.lock"
if [[ -d $lock_dir ]]; then
  echo "lock dir found: $lock_dir"
  exit 1
fi
mkdir -p "$lock_dir"

if ! CgroupCreate ${mnt##*/} $$; then
  CgroupDelete ${mnt##*/}
  Exit 1
fi

trap Exit INT QUIT TERM EXIT

if [[ -n "$entrypoint" ]]; then
  rm -f                           "$mnt/entrypoint"
  cp "$entrypoint"                "$mnt/entrypoint"
  chmod 744                       "$mnt/entrypoint"

  rm -f                     "$mnt/lib.sh"
  cp "$(dirname $0)/lib.sh" "$mnt/lib.sh"
  chmod 644                 "$mnt/lib.sh"
fi

$wrapper
