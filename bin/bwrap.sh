#!/bin/bash
#
# set -x


# bubblewrap (better chroot) into an image interactively - or - run an entrypoint script


function Help() {
  echo
  echo "  call: $(basename $0) -m mountpoint [-s <entrypoint script>]"
  echo
}


function CgroupCreate() {
  local name=$1
  local pid=$2

  # restrict blast radius if -j1 is ignored + force an oom-killer before the kernel chosoes a process to kill
  cgcreate -g cpu,memory:$name

  cgset -r cpu.use_hierarchy=1      $name
  cgset -r cpu.cfs_quota_us=150000  $name
  cgset -r cpu.cfs_period_us=100000 $name
  cgset -r cpu.notify_on_release=1  $name

  cgset -r memory.use_hierarchy=1           $name
  cgset -r memory.limit_in_bytes=20G        $name
  cgset -r memory.memsw.limit_in_bytes=30G  $name
  cgset -r memory.notify_on_release=1       $name

  echo "$pid" > /sys/fs/cgroup/cpu/$name/tasks
  echo "$pid" > /sys/fs/cgroup/memory/$name/tasks
}


function Cleanup()  {
  local rc=$?

  rmdir "$lock_dir"

  exit $rc
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

mnt=""
entrypoint=""
while getopts h\?m:s: opt
do
  case $opt in
    h|\?)
        Help
        ;;
    m)
        if [[ -z "${OPTARG##*/}" || "$OPTARG" =~ [[:space:]] || "$OPTARG" =~ [\\\(\)\`$] ]]; then
          echo "argument not accepted"
          exit 2
        fi

        for i in 1 2
        do
          mnt=/home/tinderbox/img${i}/${OPTARG##*/}
          if [[ -d "$mnt" ]]; then
            break
          fi
        done

        if [[ -z "$mnt" || -L "$mnt" || ! $(stat -c '%u' "$mnt") = "0" || ! "$mnt" = "$(realpath -e $mnt)" ]]; then
          echo "mount point not accepted"
          exit 2
        fi

        ;;
    s)
        if [[ ! -s "$OPTARG" ]]; then
          echo "no valid entry point script given: $OPTARG"
          exit 3
        fi

        entrypoint="$OPTARG"
        ;;
  esac
done

if [[ -z "$mnt" ]]; then
  echo "no mnt given!"
  exit 4
fi

# a basic lock mechanism: only mkdir is an atomic kernel file system operation
lock_dir="/run/tinderbox/${mnt##*/}.lock"
mkdir "$lock_dir"

trap Cleanup EXIT QUIT TERM

if [[ -n "$entrypoint" ]]; then
  if [[ -L "$mnt/entrypoint" ]]; then
    echo "found symlinked $mnt/entrypoint"
    exit 4
  fi

  if [[ -e "$mnt/entrypoint" ]]; then
    rm -f "$mnt/entrypoint"
  fi
  touch             "$mnt/entrypoint"
  chmod 744         "$mnt/entrypoint"
  cp "$entrypoint"  "$mnt/entrypoint"
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

CgroupCreate local/${mnt##*/} $$

# prevent "Broken sem_open function (bug 496328)"
echo "chmod 1777 /dev/shm" > "$mnt/etc/profile.d/99_bwrap.sh"

if [[ -n "$entrypoint" ]]; then
  ("${sandbox[@]}" -c "/entrypoint")
else
  ("${sandbox[@]}")
fi
