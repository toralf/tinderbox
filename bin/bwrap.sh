#!/bin/bash
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

  # use cgroup v1 if available
  if ! hash -r cgcreate || ! hash -r cgset || ! test -d /sys/fs/cgroup; then
    return 0
  fi

  cgcreate -g cpu,memory:$name

  # chain each image especially if it does not respect "-j 2"
  cgset -r cpu.cfs_quota_us=300000          $name
  cgset -r memory.limit_in_bytes=30G        $name
  cgset -r memory.memsw.limit_in_bytes=40G  $name

  for i in cpu memory
  do
    echo      1 > /sys/fs/cgroup/$i/$name/notify_on_release
    echo "$pid" > /sys/fs/cgroup/$i/$name/tasks
  done
}


function Cleanup()  {
  local rc=$?

  rmdir "$lock_dir"

  exit $rc
}


function Exit()  {
  echo "bailing out ..."
  trap - QUIT TERM EXIT
}


#############################################################################
#
# main
#
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

trap Exit INT QUIT TERM EXIT

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

mnt=""
entrypoint=""

while getopts h\?m:s: opt
do
  case $opt in
    h|\?) Help
          ;;
    m)    if [[ -z "${OPTARG##*/}" || "$OPTARG" =~ [[:space:]] || "$OPTARG" =~ [\\\(\)\`$] ]]; then
            echo "argument not accepted"
            exit 2
          fi

          if [[ ! -e "$OPTARG" || ! $(stat -c '%u' "$OPTARG") = "0" ]]; then
            echo "no valid mount point found"
            exit 2
          fi
          mnt=$OPTARG
          ;;
    s)    if [[ ! -s "$OPTARG" ]]; then
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

if [[ ! -d /run/tinderbox ]]; then
  echo "please create /run/tinderbox before as user root!"
  exit 5
fi

lock_dir="/run/tinderbox/${mnt##*/}.lock"
mkdir "$lock_dir"
trap Cleanup QUIT TERM EXIT

if [[ -n "$entrypoint" ]]; then
  if [[ -L "$mnt/entrypoint" ]]; then
    echo "symlinked $mnt/entrypoint forbidden"
    exit 4
  fi
  rm -f             "$mnt/entrypoint"
  cp "$entrypoint"  "$mnt/entrypoint"
  chmod 744         "$mnt/entrypoint"
fi

sandbox=(env -i
    PATH=/usr/sbin:/usr/bin:/sbin:/bin
    HOME=/root
    SHELL=/bin/bash
    TERM=linux
    /usr/bin/bwrap
        --bind "$mnt"                             /
        --bind ~tinderbox/tb/data                 /mnt/tb/data
        --bind ~tinderbox/distfiles               /var/cache/distfiles
        --ro-bind ~tinderbox/tb/sdata/ssmtp.conf  /etc/ssmtp/ssmtp.conf
        --ro-bind /var/db/repos                   /mnt/repos
        --tmpfs                                   /var/tmp/portage
        --tmpfs /dev/shm
        --dev /dev
        --proc /proc
        --mqueue /dev/mqueue
        --unshare-cgroup
        --unshare-ipc
        --unshare-pid
        --unshare-uts
        --hostname "$(sed -e 's,[+\.],_,g' <<< ${mnt##*/} | cut -c-57)"
        --chdir /var/tmp/tb
        --die-with-parent
        --setenv MAILTO "${MAILTO:-tinderbox}"
        /bin/bash -l
)

CgroupCreate local/${mnt##*/} $$

# prevent "Broken sem_open function (bug 496328)"
# https://github.com/containers/bubblewrap/issues/329
echo "chmod 1777 /dev/shm" > "$mnt/etc/profile.d/99_bwrap.sh"

if [[ -n "$entrypoint" ]]; then
  ("${sandbox[@]}" -c "/entrypoint")
else
  ("${sandbox[@]}")
fi
