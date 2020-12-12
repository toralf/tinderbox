#!/bin/bash
# set -x


# setup a new tinderbox image


# helper of ThrowUseFlags()
#
function DropUseFlags()  {
  egrep -v -e '32|64|FreeBSD|^armv|bindist|bootstrap|broadcom|build|cdinstall|compile-locales|consolekit|d3d9|debug|doc|elibc|elogind|forced-sandbox|gallium|gcj|ghcbootstrap|hardened|hostname|ithreads|kill|libav|libreoffice|libressl|linguas|livecd|lto|make-symlinks|malloc|minimal|mips|monolithic|multilib|musl|nvidia|oci8|opencl|openmp|openssl|passwdqc|pax_kernel|perftools|prefix|tools|selinux|split-usr|ssp|static|symlink|system|systemd|test|uclibc|udev|user-session|vaapi|valgrind|vdpau|video_cards_|vim-syntax|vulkan|webkit|zink'
}


function PrintUseFlags() {
  xargs -s 73 | sed -e '/^$/d' | sed -e "s,^,*/*  ,g"
}


function ThrowUseFlags() {
  n=$1  # pass: about 1 of n
  m=5   # mask: about 20%

  shuf | sort |\
  while read flag
  do
    [[ $(($RANDOM % $n)) -eq 0 ]] || continue
    [[ $(($RANDOM % $m)) -eq 0 ]] && echo -n "-"
    echo -n "$flag "
  done
}


# helper of SetOptions()
#
function GetProfiles() {
  eselect profile list |\
  awk ' { print $2 } ' |\
  grep -e "^default/linux/amd64/17\.1" |\
  grep -v -e '/x32' -e '/selinux' -e '/uclibc' -e 'musl' |\
  cut -f4- -d'/' -s
}


function ThrowCflags()  {
  # 685160 colon-in-CFLAGS
  [[ $(($RANDOM % 2)) -eq 0 ]] && cflags="$cflags -falign-functions=32:25:16"
}


# helper of main()
# the variables here are mostly globals
#
function SetOptions() {
  cflags_default="-O2 -pipe -march=native -fno-diagnostics-color"
  cflags=""

  # an "y" yields to ABI_X86: 32 64
  multiabi="n"
  if [[ $(($RANDOM % 16)) -eq 0 ]]; then
    multiabi="y"
  fi

  # prefer a non-running profile
  # however if no one passes the break criteria, then the last entry would make it eventually
  while read profile
  do
    if [[ "$multiabi" = "y" ]]; then
      if [[ $profile =~ "/no-multilib" ]]; then
        continue
      fi
    fi

    local p=$(echo $profile | tr '/' '_')
    if [[ -z "$(ls -d ~tinderbox/run/$p-* /run/tinderbox/$p-*.lock 2>/dev/null)" ]]; then
      break
    fi
  done < <(GetProfiles | shuf)

  ThrowCflags
  features="xattr cgroup -news -collision-protect"

  # check the default USE flag set of choosen profile
  defaultuseflags="n"
  if [[ $(($RANDOM % 16)) -eq 0 ]]; then
    defaultuseflags="y"
  fi

  testfeature="n"
  # run at most 1 image
  if [[ -z "$(ls -d ~tinderbox/run/*test* 2>/dev/null)" ]]; then
    if [[ $(($RANDOM % 16)) -eq 0 ]]; then
      testfeature="y"
    fi
  fi

  libressl="n"
  # parity OpenSSL : LibreSSL = 1:1
  if [[ $(($RANDOM % 2)) -eq 0 ]]; then
    libressl="y"
  fi

  science="n"
  if [[ $(($RANDOM % 16)) -eq 0 ]]; then
    # run at most 1 image
    if [[ -z "$(ls -d ~tinderbox/run/*science* 2>/dev/null)" ]]; then
      science="y"
      testfeature="n"
    fi
  fi

  musl="n"
  # no random throwing, Musl is not yet ready for regular scheduling
  if [[ $musl = "y" ]]; then
    cflags="$cflags_default"
    defaultuseflags="y"
    libressl="n"
    profile="17.0/musl"
    multiabi="n"
    testfeature="n"
  fi
}


# helper of CheckOptions()
#
function checkBool()  {
  var=$1
  val=$(eval echo \$${var})

  if [[ "$val" != "y" && "$val" != "n" ]]; then
    echo " wrong value for variable \$$var: >>$val<<"
    exit 1
  fi
}


# helper of main()
#
function CheckOptions() {
  checkBool "defaultuseflags"
  checkBool "libressl"
  checkBool "multiabi"
  checkBool "musl"
  checkBool "science"
  checkBool "testfeature"

  if [[ -z "$profile" ]]; then
    echo " profile empty!"
    exit 1
  fi

  if [[ ! -d $repodir/gentoo/profiles/default/linux/amd64/$profile ]]; then
    echo " profile unknown: >>$profile<<"
    exit 1
  fi

}


# helper of UnpackStage3()
function CreateImageName()  {
  # profile[-flavour]-day-time
  name="$(echo $profile | tr '/' '_')-"
  [[ "$libressl" = "y" ]]     && name="${name}_libressl"
  [[ "$multiabi" = "y" ]]     && name="${name}_abi32+64"
  [[ "$science" = "y" ]]      && name="${name}_science"
  [[ "$testfeature" = "y" ]]  && name="${name}_test"
  name="$(echo $name | sed -e 's/-[_-]/-/g' -e 's/-$//')"
  name="${name}-$(date +%Y%m%d-%H%M%S)"
}


# helper of UnpackStage3()
#
function CreateImageDir() {
  local l=$(readlink ~tinderbox/img)
  if [[ ! -d ~tinderbox/"$l" ]]; then
    echo "unexpected readlink result '$l'"
    exit 1
  fi

  cd ~tinderbox/$l || exit 1

  mkdir $name || exit 1

  # relative path (eg ./img1) from ~tinderbox
  #
  mnt=$l/$name

  echo " new image: $mnt"
  echo
}


# download, verify and unpack the stage3 file
#
function UnpackStage3()  {
  latest="$tbdistdir/latest-stage3.txt"

  for mirror in $gentoo_mirrors
  do
    wget --connect-timeout=10 --quiet $mirror/releases/amd64/autobuilds/latest-stage3.txt --output-document=$latest && break
  done

  if [[ ! -s $latest ]]; then
    echo " empty: $latest"
    exit 1
  fi

  wgeturl="$mirror/releases/amd64/autobuilds"

  case $profile in
    */no-multilib/hardened)
      stage3=$(grep "/stage3-amd64-hardened+nomultilib-20.*\.tar\." $latest)
      ;;

    */musl/hardened)
      stage3=$(grep "/stage3-amd64-musl-hardened-20.*\.tar\." $latest)
      ;;

    */hardened)
      stage3=$(grep "/stage3-amd64-hardened-20.*\.tar\." $latest)
      ;;

    */no-multilib)
      stage3=$(grep "/stage3-amd64-nomultilib-20.*\.tar\." $latest)
      ;;

    */systemd)
      stage3=$(grep "/stage3-amd64-systemd-20.*\.tar\." $latest)
      ;;

    */musl)
      stage3=$(grep "/stage3-amd64-musl-vanilla-20.*\.tar\." $latest)
      ;;

    *)
      stage3=$(grep "/stage3-amd64-20.*\.tar\." $latest)
      ;;
  esac
  stage3=$(echo $stage3 | cut -f1 -d' ' -s)

  if [[ -z "$stage3" || "$stage3" =~ [[:space:]] ]]; then
    echo " can't get stage3 filename for profile '$profile' in $latest"
    exit 1
  fi

  f=$tbdistdir/${stage3##*/}
  if [[ ! -s $f || ! -f $f.DIGESTS.asc ]]; then
    date
    echo " downloading $f ..."
    wget --connect-timeout=10 --quiet --no-clobber $wgeturl/$stage3{,.DIGESTS.asc} --directory-prefix=$tbdistdir || exit 1
  fi

  date
  echo " getting signing key ..."
  # use the Gentoo key server, but be relaxed if it doesn't answer
  gpg --keyserver hkps://keys.gentoo.org --recv-keys 534E4209AB49EEE1C19D96162C44695DB9F6043D || true

  date
  echo " verifying $f ..."
  gpg --quiet --verify $f.DIGESTS.asc || exit 1
  echo

  CreateImageName
  CreateImageDir

  date
  cd $name
  echo " untar'ing $f ..."
  tar -xpf $f --same-owner --xattrs || exit 1
  echo
}


# configure image specific repositories (either being bind mounted or local)
#
function addRepoConf()  {
  local reponame=$1
  local priority=$2
  local location=${3:-$repodir/$reponame}

  cat << EOF > ./etc/portage/repos.conf/$reponame.conf
[$reponame]
location = $location
priority = $priority

EOF
}


function CompileRepoFiles()  {
  mkdir -p ./etc/portage/repos.conf/

  cat << EOF > ./etc/portage/repos.conf/default.conf
[DEFAULT]
main-repo = gentoo
auto-sync = no

EOF
  # the "local" repository for this particular image
  mkdir -p                  ./$repodir/local/{metadata,profiles}
  echo 'masters = gentoo' > ./$repodir/local/metadata/layout.conf
  echo 'local'            > ./$repodir/local/profiles/repo_name

  addRepoConf "gentoo" "10"
  [[ "$libressl" = "y" ]] && addRepoConf "libressl" "20"
  [[ "$musl" = "y" ]]     && addRepoConf "musl"     "30"
  [[ "$science" = "y" ]]  && addRepoConf "science"  "40"
  addRepoConf "tinderbox" "90" "/mnt/tb/data/portage"
  addRepoConf "local" "99"
}


# compile make.conf
#
function CompileMakeConf()  {
  cat << EOF > ./etc/portage/make.conf
LC_MESSAGES=C
NOCOLOR="true"
GCC_COLORS=""
PORTAGE_TMPFS="/dev/shm"

CFLAGS="$cflags_default $cflags"
CXXFLAGS="\${CFLAGS}"

FCFLAGS="$cflags_default"
FFLAGS="\${FCFLAGS}"

LDFLAGS="\${LDFLAGS} -Wl,--defsym=__gentoo_check_ldflags__=0"
$([[ ! $profile =~ "/hardened" ]] && echo 'PAX_MARKINGS="none"')

ACCEPT_KEYWORDS="~amd64"

# no re-distribution nor any "usage", just QA
ACCEPT_LICENSE="*"

# just tinderboxing, no manual interaction
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"

FEATURES="$features"
EMERGE_DEFAULT_OPTS="--with-bdeps=y --verbose-conflicts --nospinner --tree --quiet-build --autounmask-keep-masks=y --complete-graph=y --verbose --color=n --autounmask=n"

CLEAN_DELAY=0
NOCOLOR=true

PORT_LOGDIR="/var/log/portage"
PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="root@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

PORTAGE_GPG_DIR="/var/lib/gentoo/gkeys/keyrings/gentoo/release"
PORTAGE_GPG_KEY="F45B2CE82473685B6F6DCAAD23217DA79B888F45"

GENTOO_MIRRORS="$gentoo_mirrors"

EOF

  # the "tinderbox" user have to be in group "portage"
  chgrp portage ./etc/portage/make.conf
  chmod g+w ./etc/portage/make.conf
}


# helper of CompilePortageFiles()
#
function cpconf() {
  for f in $*
  do
    # eg.: .../package.unmask.??common -> package.unmask/??common
    read -r a b c <<<$(echo ${f##*/} | tr '.' ' ')
    cp $f ./etc/portage/"$a.$b/$c"
  done
}


# create portage + tinderbox directories + files and symlinks
#
function CompilePortageFiles()  {
  mkdir -p ./mnt/{repos,tb/data,tb/sdata} ./var/tmp/{portage,tb,tb/logs} ./var/cache/distfiles

  chgrp portage ./var/tmp/tb
  chmod ug+rwx  ./var/tmp/tb

  for d in package.{accept_keywords,env,mask,unmask,use} env
  do
    if [[ ! -d ./etc/portage/$d ]]; then
      mkdir       ./etc/portage/$d
    fi
    chmod 775     ./etc/portage/$d
    chgrp portage ./etc/portage/$d
  done

  (cd ./etc/portage; ln -s ../../mnt/tb/data/patches)

  touch       ./etc/portage/package.mask/self     # holds failed packages of this image
  chmod a+rw  ./etc/portage/package.mask/self

  echo 'FEATURES="test"'                          > ./etc/portage/env/test
  echo 'FEATURES="-test"'                         > ./etc/portage/env/notest

  # to preserve the same dep tree: re-try a failed package with "test" again but ignore now the test results
  #
  echo 'FEATURES="test-fail-continue"'            > ./etc/portage/env/test-fail-continue

  # re-try w/o sandbox'ing
  #
  echo 'FEATURES="-sandbox -usersandbox"'         > ./etc/portage/env/nosandbox

  # save CPU cycles with a cron job like:
  # @hourly  sort -u ~tinderbox/run/*/etc/portage/package.env/cflags_default 2>/dev/null > /tmp/cflagsknown2fail; for i in ~/run/*/etc/portage/package.env/; do cp /tmp/cflagsknown2fail $i; done
  cat <<EOF                                       > ./etc/portage/env/cflags_default
CFLAGS="$cflags_default"
CXXFLAGS="\${CFLAGS}"

FCFLAGS="\${CFLAGS}"
FFLAGS="\${CFLAGS}"

EOF

  # no parallel build, prefer 1 thread in N running images over up to N running threads in 1 image
  #
  cat << EOF                                      > ./etc/portage/env/noconcurrent
EGO_BUILD_FLAGS="-p 1"
GO19CONCURRENTCOMPILATION=0
GOMAXPROCS="1"
MAKEOPTS="-j1"
NINJAFLAGS="-j1"
OMP_DYNAMIC=FALSE
OMP_NESTED=FALSE
OMP_NUM_THREADS=1
RUSTFLAGS="-C codegen-units=1$([[ $musl = "y" ]] && echo " -C target-feature=-crt-static")"
RUST_TEST_THREADS=1
RUST_TEST_TASKS=1

EOF

  echo '*/*  noconcurrent' > ./etc/portage/package.env/00noconcurrent

  if [[ $profile =~ '/systemd' ]]; then
    cpconf ~tinderbox/tb/data/package.*.??systemd
  fi

  cpconf ~tinderbox/tb/data/package.*.??common

  if [[ "$libressl" = "y" ]]; then
    cpconf ~tinderbox/tb/data/package.env.??libressl  # *.use.* will be copied after GCC update
  fi

  if [[ "$multiabi" = "y" ]]; then
    cpconf ~tinderbox/tb/data/package.*.??abi32+64
  fi

  if [[ "$testfeature" = "y" ]]; then
    cpconf ~tinderbox/tb/data/package.*.*test
  else
    # overrule any IUSE=+test
    #
    echo "*/*  notest" > ./etc/portage/package.env/12notest
  fi

  echo "*/*  $(cpuid2cpuflags)" > ./etc/portage/package.use/99cpuflags

  # give FF and TB a chance
  if [[ $(($RANDOM % 8)) -eq 0 ]]; then
    cpconf ~tinderbox/tb/data/package.use.30misc
  fi

  touch ./var/tmp/tb/task

  chgrp portage ./etc/portage/package.*/* ./etc/portage/env/* ./var/tmp/tb/task
  chmod a+r,g+w ./etc/portage/package.*/* ./etc/portage/env/* ./var/tmp/tb/task
}


function CompileMiscFiles()  {
  # use local host DNS resolver
  #
  cat << EOF > ./etc/resolv.conf
domain localdomain
nameserver 127.0.0.1

EOF

  h=$(hostname)
  cat << EOF > ./etc/hosts
127.0.0.1 localhost $h.localdomain $h
::1       localhost $h.localdomain $h

EOF

  # avoid interactive question in vim
  #
  cat << EOF > ./root/.vimrc
set softtabstop=2
set shiftwidth=2
set expandtab
let g:session_autosave = 'no'
autocmd BufEnter *.txt set textwidth=0

EOF
}


# /var/tmp/tb/backlog.upd : update_backlog.sh writes to it
# /var/tmp/tb/backlog     : filled by setup_img.sh
# /var/tmp/tb/backlog.1st : filled by setup_img.sh, job.sh and retest.sh write to it
#
function CreateBacklog()  {
  bl=./var/tmp/tb/backlog

  truncate -s 0           $bl{,.1st,.upd}
  chmod 664               $bl{,.1st,.upd}
  chown tinderbox:portage $bl{,.1st,.upd}

  # requested by Whissi, this is an alternative mysql engine
  #
  if [[ $(($RANDOM % 16)) -eq 0 ]]; then
    echo "dev-db/percona-server" >> $bl.1st
  fi

  # update @world before working on the arbitrarily choosen package list
  # @system is just a fall back for @world failure or if it takes very long
  #
  # depclean must succeeded here during setup
  #
  cat << EOF >> $bl.1st
app-portage/pfl
%emerge --depclean --changed-use
@world
@system
EOF

  # switch to LibreSSL
  #
  if [[ "$libressl" = "y" ]]; then
    # --unmerge already schedules @preserved-rebuild but the final @preserved-rebuild should not fail, therefore "% ..."
    #
    cat << EOF >> $bl.1st
%emerge @preserved-rebuild
%emerge --unmerge dev-libs/openssl
%emerge --fetchonly dev-libs/libressl net-misc/openssh net-misc/wget
%chmod g+w     /etc/portage/package.use/??libressl
%chgrp portage /etc/portage/package.use/??libressl
%f=\$(echo /mnt/tb/data/package.use.??libressl); cp \$f /etc/portage/package.use/\${f##*.}
%emerge --fetchonly dev-libs/openssl
EOF
  fi

  # at least systemd and virtualbox need (even more compiled?) kernel sources and would fail in @preserved-rebuild otherwise
  #
  echo "%emerge -u sys-kernel/gentoo-sources" >> $bl.1st

  # upgrade GCC asap, and avoid to rebuild the existing one (b/c the old version will be unmerged soon)
  #
  #   %...      : bail out if it fails
  #   =         : do not upgrade the current (slotted) version b/c we remove them immediately afterwards
  # dev-libs/*  : avoid an rebuild of GCC later in @world due to an upgrade of any of these deps
  #
  echo "%emerge -uU =\$(portageq best_visible / sys-devel/gcc) dev-libs/mpc dev-libs/mpfr" >> $bl.1st

  if [[ $profile =~ "/systemd" ]]; then
    echo "%systemd-machine-id-setup" >> $bl.1st
  fi

  echo "%eselect python cleanup" >> $bl.1st
  echo "%eselect python update --if-unset" >> $bl.1st
}


# - configure locale, timezone etc.
# - install and configure tools used in job.sh
#     <package>                   <command>
#     app-portage/portage-utils   qatom
#     mail-*/*                    ssmtp, mail
# - switch to the desired profile
# - fill backlog
function CreateSetupScript()  {
  cat << EOF > ./var/tmp/tb/setup.sh || exit 1
#!/bin/sh
# set -x

set -euf

export GCC_COLORS=""

date
echo "#setup rsync" | tee /var/tmp/tb/task

                         rsync --archive --cvs-exclude /mnt/repos/gentoo   $repodir/
[[ $libressl = "y" ]] && rsync --archive --cvs-exclude /mnt/repos/libressl $repodir/
[[ $musl = "y" ]]     && rsync --archive --cvs-exclude /mnt/repos/musl     $repodir/
[[ $science = "y" ]]  && rsync --archive --cvs-exclude /mnt/repos/science  $repodir/

date
echo "#setup configure" | tee /var/tmp/tb/task

echo "$name" > /etc/conf.d/hostname
useradd -u $(id -u tinderbox) tinderbox

if [[ ! $musl = "y" ]]; then
  cat << EOF2 >> /etc/locale.gen
# by \$0 at \$(date)
#
en_US ISO-8859-1
en_US.UTF-8 UTF-8
de_DE ISO-8859-1
de_DE@euro ISO-8859-15
de_DE.UTF-8@euro UTF-8

EOF2

  locale-gen -j1
  eselect locale set en_US.UTF-8
fi

env-update
source /etc/profile

echo "Europe/Berlin" > /etc/timezone
emerge --config sys-libs/timezone-data

# date
# echo "#update stage3" | tee /var/tmp/tb/task
# emerge -u --deep --changed-use @system --keep-going=y --exclude sys-devel/gcc --exclude sys-libs/glibc || true
# locale-gen -j1
# eselect python update --if-unset

date
env-update
source /etc/profile

date
echo "#setup tools" | tee /var/tmp/tb/task

# emerge ssmtp before mailx b/c mailx would pull its ebuild default MTA rather than ssmtp
emerge -u mail-mta/ssmtp
emerge -u mail-client/mailx

# mandatory tools by job.sh
emerge -u app-portage/portage-utils

eselect profile set --force default/linux/amd64/$profile

if [[ $testfeature = "y" ]]; then
  echo "*/*  test" >> /etc/portage/package.env/11dotest
fi

date
echo "#setup backlog" | tee /var/tmp/tb/task
# sort -u is needed if the same package is in 2 or more repos
qsearch --all --nocolor --name-only --quiet | sort -u | shuf >> /var/tmp/tb/backlog
touch /var/tmp/tb/task

# create symlinks to appropriate credential files
(cd /etc/ssmtp && ln -sf ../../mnt/tb/sdata/ssmtp.conf)

EOF

  chmod u+x ./var/tmp/tb/setup.sh
}


# MTA et. al
#
function RunSetupScript() {
  date
  echo " run setup script ..."
  cd ~tinderbox/

  echo '/var/tmp/tb/setup.sh &> /var/tmp/tb/setup.sh.log' > $mnt/var/tmp/tb/setup_wrapper.sh
  nice -n 1 sudo ${0%/*}/bwrap.sh -m "$mnt" -s "$mnt/var/tmp/tb/setup_wrapper.sh"
  rc=$?

  if [[ $rc -ne 0 ]]; then
    echo -e "$(date)\n setup was NOT successful (rc=$rc) @ $mnt\n"
    tail -v -n 1000 $mnt/var/tmp/tb/setup.sh.log
    echo
    exit 3 # 3 triggers another dryrun in replace-image.sh
  fi

  echo
}


# the USE flags must do not yield to circular or other non-resolvable dependencies for the very first @world
function DryRun() {
  nice -n 1 sudo ${0%/*}/bwrap.sh -m "$mnt" -s $mnt/var/tmp/tb/dryrun_wrapper.sh
  local rc=$?

  if [[ $rc -eq 0 ]]; then
    grep -H -A 99 -e 'The following USE changes are necessary to proceed:'                \
                  -e 'One of the following packages is required to complete your request' \
                  $mnt/var/tmp/tb/dryrun.log
    if [[ $? -eq 0 ]]; then
      echo -e "\n$(date)\n dry run was NOT successful due to ^^^\n"
      return 11
    fi
  else
    echo -e "\n$(date)\n dry run was NOT successful (rc=$rc):\n"
    tail -v -n 200 $mnt/var/tmp/tb/dryrun.log
    echo
  fi

  return $rc
}


function DryRunLoops() {
  attempt=0
  max_attempts=30
  while [[ : ]]
  do
    echo

    ((attempt=attempt+1))
    date
    echo "dryrun $attempt#$max_attempts ==========================================================="
    echo
    echo "#setup dryrun $attempt#$max_attempts" > $mnt/var/tmp/tb/task

    grep -v -e '^$' -e '^#' $repodir/gentoo/profiles/desc/l10n.desc |\
    cut -f1 -d' ' -s |\
    shuf -n $(($RANDOM % 20)) |\
    sort |\
    xargs |\
    xargs -I {} --no-run-if-empty printf "%s %s\n" "*/*  L10N: -* {}" > $mnt/etc/portage/package.use/21thrown_l10n_from_profile

    grep -v -e '^$' -e '^#' $repodir/gentoo/profiles/use.desc |\
    cut -f1 -d' ' -s |\
    DropUseFlags |\
    ThrowUseFlags 10 |\
    PrintUseFlags > $mnt/etc/portage/package.use/22thrown_global_use_flags_from_profile

    grep -h 'flag name="' $repodir/gentoo/*/*/metadata.xml |\
    cut -f2 -d'"' -s |\
    sort -u |\
    DropUseFlags |\
    ThrowUseFlags 100 |\
    PrintUseFlags > $mnt/etc/portage/package.use/23thrown_global_use_flags_from_metadata

    grep -Hl 'flag name="' $repodir/gentoo/*/*/metadata.xml |\
    shuf -n $(($RANDOM % 400)) |\
    while read file
    do
      pkg=$(echo $file | cut -f6-7 -d'/')
      grep -h 'flag name="' $file |\
      cut -f2 -d'"' -s |\
      DropUseFlags |\
      ThrowUseFlags 10 |\
      xargs |\
      xargs -I {} --no-run-if-empty printf "%-50s %s\n" "$pkg" "{}"
    done |\
    sort > $mnt/etc/portage/package.use/24thrown_package_use_flags

    DryRun && break

    echo
    tail -v -n 2000 $mnt/etc/portage/package.use/2?thrown*

    if [[ $attempt -ge $max_attempts ]]; then
      echo -e "\n$(date)\ntoo much attempts, giving up\n"
      exit 2
    fi

  done
}


#############################################################################
#
# main
#
#############################################################################
set -u

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

date
echo " $0 started"
echo

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

if [[ $# -gt 0 ]]; then
  echo "   $# additional args are given: '${@}'"
  echo
fi

repodir=/var/db/repos
tbdistdir=~tinderbox/distfiles
gentoo_mirrors=$(grep "^GENTOO_MIRRORS=" /etc/portage/make.conf | cut -f2 -d'"' -s)

SetOptions

while getopts c:d:f:l:m:p:r:s:t: opt
do
  case $opt in
    c)  cflags="$OPTARG"
        ;;
    d)  mnt="$OPTARG"
        DryRunLoops
        exit 0
        ;;
    f)  features="$OPTARG"
        ;;
    l)  libressl="$OPTARG"
        ;;
    m)  multiabi="$OPTARG"
        ;;
    p)  profile="$OPTARG"
        ;;
    r)  defaultuseflags="$OPTARG"
        ;;
    s)  science="y"
        ;;
    t)  testfeature="$OPTARG"
        ;;
    *)  echo " '$opt' with '$OPTARG' not implemented"
        exit 1
        ;;
  esac
done

CheckOptions
UnpackStage3
CompileRepoFiles
CompileMakeConf
CompilePortageFiles
CompileMiscFiles
CreateBacklog
CreateSetupScript
RunSetupScript

echo 'emerge --update --deep --newuse --changed-use --backtrack=30 --pretend @world &> /var/tmp/tb/dryrun.log' > $mnt/var/tmp/tb/dryrun_wrapper.sh
if [[ "$defaultuseflags" = "y" ]]; then
  DryRun
else
  DryRunLoops
fi

echo -e "\n$(date)\n  setup OK"
cd ~tinderbox/run
ln -s ../$mnt

echo
su - tinderbox -c "${0%/*}/start_img.sh $name"

exit 0
