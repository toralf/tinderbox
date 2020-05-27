#!/bin/bash
#
# set -x

# setup a new tinderbox image

#############################################################################
#
# functions

# helper of ThrowUseFlags()
#
function DropUseFlags()  {
  egrep -v -e '32|64|^armv|bindist|bootstrap|build|cdinstall|compile-locales|consolekit|debug|elogind|forced-sandbox|gallium|gcj|ghcbootstrap|hardened|hostname|ithreads|kill|libav|libreoffice|libressl|libunwind|linguas|make-symlinks|malloc|minimal|monolithic|multilib|musl|nvidia|oci8|opencl|openmp|openssl|pax_kernel|perftools|prefix|tools|selinux|split-usr|ssp|static|symlink|system|systemd|test|uclibc|vaapi|valgrind|vdpau|vim-syntax|vulkan'
}


function PrintUseFlags() {
  xargs -s 73 | sed -e '/^$/d' | sed -e "s,^,*/*  ,g"
}


function ThrowUseFlags() {
  n=${1:-1}
  m=${2:-0}

  # throw up to n-1
  #
  shuf -n $(($RANDOM % $n)) | sort |\
  while read flag
  do
    # mask about 1/m
    #
    if [[ $m -gt 0 && $(($RANDOM % $m)) -eq 0 ]]; then
      echo -n "-"
    fi
    echo -n "$flag "
  done
}


# helper of SetOptions()
#
function GetProfiles() {
  eselect profile list |\
  awk ' { print $2 } ' |\
  grep -e "^default/linux/amd64/17\.1" -e "^default/linux/amd64/17\../musl" |\
  grep -v -e '/x32' -e '/selinux' -e '/uclibc' |\
  cut -f4- -d'/' -s
}


function ThrowCflags()  {
  # 685160 colon-in-CFLAGS
  if [[ $(($RANDOM % 2)) -eq 0 ]]; then
    cflags="$cflags -falign-functions=32:25:16"
  fi

  # 713576 by ago, but much noise (jer, ulm)
  if [[ $(($RANDOM % 2)) -eq 0 ]]; then
    cflags="$cflags -Wformat -Werror=format-security"
  fi
}


# helper of main()
# options can be overwritten by command line parameter
#
function SetOptions() {
  autostart="y"
  useflags="ThrowUseFlags"
  cflags_default="-O2 -pipe -march=native"
  cflags=""

  # throw a profile and prefer a non-running one, nevertheless the last entry will make it eventually
  #
  while read profile
  do
    ls -d ~tinderbox/run/$(echo $profile | tr '/' '_')-* &>/dev/null || break
  done < <(GetProfiles | grep -v "musl" | shuf)

  ThrowCflags
  features="xattr cgroup -news -collision-protect"

  # check unstable
  #
  keyword="unstable"

  # parity OpenSSL : LibreSSL = 1:1
  #
  libressl="n"
  if [[ "$keyword" = "unstable" ]]; then
    if [[ $(($RANDOM % 2)) -eq 0 ]]; then
      libressl="y"
    fi
  fi

  # an "y" yields to ABI_X86: 32 64
  #
  multilib="n"
  if [[ ! $profile =~ "/no-multilib" ]]; then
    if [[ $(($RANDOM % 8)) -eq 0 ]]; then
      multilib="y"
    fi
  fi

  # sets FEATURES=test eventually
  #
  testfeature="n"
  if [[ "$keyword" = "unstable" ]]; then
    # run at most 1 image
    #
    if [[ -z "$(ls -d ~tinderbox/run/*test* 2>/dev/null)" ]]; then
      if [[ $(($RANDOM % 32)) -eq 0 ]]; then
        testfeature="y"
      fi
    fi
  fi

  # throw languages
  #
  l10n="$(grep -v -e '^$' -e '^#' $repo_gentoo/profiles/desc/l10n.desc | cut -f1 -d' ' -s | shuf -n $(($RANDOM % 10)) | sort | xargs)"

  musl="n"  # handled in CheckOptions()
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
  if [[ -z "$profile" ]]; then
    echo " profile empty!"
    exit 1
  fi

  if [[ ! -d $repo_gentoo/profiles/default/linux/amd64/$profile ]]; then
    echo " profile unknown: >>$profile<<"
    exit 1
  fi

  if [[ "$keyword" != "stable" && "$keyword" != "unstable" ]]; then
    echo " wrong value for \$keyword: >>$keyword<<"
    exit 1
  fi

  if [[ "$keyword" = "stable" ]]; then
    libressl="n"
    testfeature="n"
  fi

  if [[ $profile =~ "/musl" || $musl = "y" ]]; then
    musl="y"

    useflags=""
    cflags="-O2 -pipe -march=native"
    keyword="unstable"
    libressl="n"
    multilib="n"
    testfeature="n"
    l10n=""
  fi

  checkBool "autostart"
  checkBool "libressl"
  checkBool "multilib"
  checkBool "testfeature"
  checkBool "musl"
}


# helper of UnpackStage3()
#
function ComputeImageName()  {
  name="$(echo $profile | tr '/' '_')-"

  if [[ "$keyword" = "stable" ]]; then
    name="${name}_stable"
  fi

  if [[ "$libressl" = "y" ]]; then
    name="${name}_libressl"
  fi

  if [[ "$multilib" = "y" ]]; then
    name="${name}_abi32+64"
  fi

  if [[ "$testfeature" = "y" ]]; then
    name="${name}_test"
  fi

  name="$(echo $name | sed -e 's/-[_-]/-/g' -e 's/-$//')"
}


function CreateImageDir() {
  local l=$(readlink ~tinderbox/img)
  if [[ ! -d ~tinderbox/"$l" ]]; then
    echo "unexpected readlink result '$l'"
    exit 1
  fi

  cd ~tinderbox/$l || exit 1

  name="${name}-$(date +%Y%m%d-%H%M%S)"
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
    wget --quiet $mirror/releases/amd64/autobuilds/latest-stage3.txt --output-document=$latest && break
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
    wget --quiet --no-clobber $wgeturl/$stage3{,.DIGESTS.asc} --directory-prefix=$tbdistdir || exit 1
  fi

  # do this once before:    gpg --recv-keys 534E4209AB49EEE1C19D96162C44695DB9F6043D
  #
  date
  echo " verifying $f ..."
  gpg --quiet --verify $f.DIGESTS.asc || exit 1
  echo

  CreateImageDir

  date
  cd $name
  echo " untar'ing $f ..."
  tar -xpf $f --same-owner --xattrs || exit 1
  echo
}


# configure image specific repositories (either being bind mounted or local)
#
function CompileRepoFiles()  {
  mkdir -p ./etc/portage/repos.conf/

  cat << EOF > ./etc/portage/repos.conf/gentoo.conf
[gentoo]
location = $repo_gentoo

EOF

  cat << EOF > ./etc/portage/repos.conf/tinderbox.conf
[tinderbox]
location = /mnt/tb/data/portage

EOF

  mkdir -p                  ./$repo_local/{metadata,profiles}
  echo 'masters = gentoo' > ./$repo_local/metadata/layout.conf
  echo 'local'            > ./$repo_local/profiles/repo_name

  cat << EOF > ./etc/portage/repos.conf/local.conf
[local]
location = $repo_local

EOF

  cat << EOF > ./etc/portage/repos.conf/default.conf
[DEFAULT]
main-repo = gentoo
auto-sync = no

[gentoo]
priority = 10

[tinderbox]
priority = 90

[local]
priority = 99

EOF

  if [[ "$libressl" = "y" ]]; then
    cat << EOF > ./etc/portage/repos.conf/libressl.conf
[libressl]
location = $repo_libressl

EOF

  cat << EOF >> ./etc/portage/repos.conf/default.conf
[libressl]
priority = 20

EOF

  fi

  if [[ "$musl" = "y" ]]; then
    cat << EOF > ./etc/portage/repos.conf/musl.conf
[musl]
location = $repo_musl

EOF
  cat << EOF >> ./etc/portage/repos.conf/default.conf
[musl]
priority = 30

EOF
  fi
}


# compile make.conf
#
function CompileMakeConf()  {
  cat << EOF > ./etc/portage/make.conf
LC_MESSAGES=C

CFLAGS="$cflags_default $cflags"
CXXFLAGS="\${CFLAGS}"

FCFLAGS="$cflags_default"
FFLAGS="\${FCFLAGS}"

LDFLAGS="\${LDFLAGS} -Wl,--defsym=__gentoo_check_ldflags__=0"
$([[ ! $profile =~ "/hardened" ]] && echo 'PAX_MARKINGS="none"')

ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE"
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
    # eg.: .../package.unmask.00stable -> package.unmask/00stable
    #
    to=$(sed 's,.00,/00,' <<< ${f##*/})
    cp $f ./etc/portage/$to
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

  touch       ./etc/portage/package.mask/self     # contains failed packages of this image
  chmod a+rw  ./etc/portage/package.mask/self

  echo 'FEATURES="test"'                          > ./etc/portage/env/test
  echo 'FEATURES="-test"'                         > ./etc/portage/env/notest

  # to preserve the same dep tree re-try a failed package with +test again but ignore the test result in the 2nd run
  #
  echo 'FEATURES="test-fail-continue"'            > ./etc/portage/env/test-fail-continue

  # re-try failing packages w/o sandbox'ing
  #
  echo 'FEATURES="-sandbox -usersandbox"'         > ./etc/portage/env/nosandbox

  # re-try failing packages w/o CFLAGS quirk
  #
  cat <<EOF                                       > ./etc/portage/env/cflags_default
CFLAGS="-O2 -pipe -march=native"
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
    cpconf ~tinderbox/tb/data/package.*.00systemd
  fi

  cpconf ~tinderbox/tb/data/package.*.00common
  cpconf ~tinderbox/tb/data/package.*.00$keyword

  if [[ "$libressl" = "y" ]]; then
    cpconf ~tinderbox/tb/data/package.env.00libressl
  fi

  if [[ "$multilib" = "y" ]]; then
    cpconf ~tinderbox/tb/data/package.*.00abi32+64
  fi

  if [[ "$testfeature" = "y" ]]; then
    cpconf ~tinderbox/tb/data/package.*.00*test
  else
    # overwrite IUSE=+test as set in few ebuilds
    #
    echo "*/*  notest" > ./etc/portage/package.env/00notest
  fi

  echo "*/*  $(cpuid2cpuflags)" > ./etc/portage/package.use/00cpuflags
  echo "ssp -cdinstall -oci8 -pax_kernel -valgrind -symlink" | PrintUseFlags > ./etc/portage/package.use/00fixed
  if [[ -n "$l10n" ]]; then
    echo "*/*  L10N: -* $l10n" > ./etc/portage/package.use/00thrown_l10n
  fi
  if [[ $multilib = "y" ]]; then
    echo '*/*  ABI_X86: -* 32 64' > ./etc/portage/package.use/00abi_x86
  fi

  touch ./var/tmp/tb/task

  chgrp portage ./etc/portage/package.*/* ./etc/portage/env/* ./var/tmp/tb/task
  chmod a+r,g+w ./etc/portage/package.*/* ./etc/portage/env/* ./var/tmp/tb/task
}


function CompileMiscFiles()  {
  echo $name > ./var/tmp/tb/name

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
  # this is the last time where depclean is run w/o "-p" (and must succeeded)
  #
  cat << EOF >> $bl.1st
%emerge --depclean
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
%chmod g+w     /etc/portage/package.use/00libressl
%chgrp portage /etc/portage/package.use/00libressl
%cp /mnt/tb/data/package.use.00libressl /etc/portage/package.use/00libressl
%emerge --fetchonly dev-libs/openssl
EOF
  fi

  # at least systemd and virtualbox need (even more compiled?) kernel sources and would fail in @preserved-rebuild otherwise
  #
  echo "%emerge -u sys-kernel/gentoo-sources" >> $bl.1st

  if [[ $keyword = "unstable" ]]; then
    # upgrade GCC asap, and avoid to rebuild the existing one (b/c the old version will be unmerged soon)
    #
    #   %...      : bail out if it fails
    #   =         : do not upgrade the current (slotted) version b/c we remove them immediately afterwards
    # dev-libs/*  : avoid an rebuild of GCC later in @world due to an upgrade of any of these deps
    #
    echo "%emerge -u --changed-use =\$(portageq best_visible / sys-devel/gcc) dev-libs/mpc dev-libs/mpfr" >> $bl.1st
  else
    # rarely but possible to have a newer GCC version in the tree than the stage3 has
    #
    echo "sys-devel/gcc" >> $bl.1st
  fi

  if [[ $profile =~ "/systemd" ]]; then
    echo "%systemd-machine-id-setup" >> $bl.1st
  fi

  echo "%eselect python cleanup" >> $bl.1st
  echo "%eselect python update --if-unset" >> $bl.1st
}


# - configure locale, timezone etc.
# - install and configure tools called in job.sh using a basic profile
#     <package>                   <command/s>
#     mail-*                      ssmtp, mail
#     app-arch/sharutils          uudecode
#     app-portage/gentoolkit      equery, eshowkw
#     www-client/pybugz           bugz
# - dry run of @world using the desired profile
#
function CreateSetupScript()  {
  cat << EOF > ./var/tmp/tb/setup.sh || exit 1
#!/bin/sh
#
# set -x

set -e

export GCC_COLORS=""

date
echo "#setup rsync" | tee /var/tmp/tb/task

rsync   --archive --cvs-exclude /mnt/repos/gentoo   /var/db/repos/
if [[ $libressl = "y" ]]; then
  rsync --archive --cvs-exclude /mnt/repos/libressl /var/db/repos/
fi
if [[ $musl = "y" ]]; then
  rsync --archive --cvs-exclude /mnt/repos/musl     /var/db/repos/
fi

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

if [[ 1 -eq 1 ]]; then
  date
  echo "#setup update stable image" | tee /var/tmp/tb/task

  emerge -u --deep --changed-use @system --keep-going=y --exclude sys-devel/gcc --exclude sys-libs/glibc
  locale-gen -j1
  eselect python update --if-unset

  env-update
  source /etc/profile
fi

if [[ $keyword = "unstable" ]]; then
  echo 'ACCEPT_KEYWORDS="~amd64"' >> /etc/portage/make.conf
fi

# emerge ssmtp before mailx b/c mailx would pull its ebuild default MTA rather than ssmtp
date
echo "#setup tools" | tee /var/tmp/tb/task
emerge -u mail-mta/ssmtp
emerge -u mail-client/mailx

# mandatory tools by job.sh
emerge -u app-arch/sharutils app-portage/gentoolkit www-client/pybugz

if [[ $(($RANDOM % 3)) -eq 0 ]]; then
  date
  echo "#setup glibc[-crypt] libxcrypt" | tee /var/tmp/tb/task

  echo '=virtual/libcrypt-2*'         >> /etc/portage/package.unmask/00libxcrypt
  cat <<EOF2                          >> /etc/portage/package.use/00libxcrypt
sys-libs/glibc      -crypt
sys-libs/libxcrypt  compat static-libs system
virtual/libcrypt    static-libs
EOF2

  echo 'sys-libs/glibc     -crypt'    >> /etc/portage/make.profile/package.use.force
  echo 'sys-libs/libxcrypt -system'   >> /etc/portage/make.profile/package.use.mask
fi

# glibc-2.31 + python-3 dep issue
#
emerge -1u virtual/libcrypt

eselect profile set --force default/linux/amd64/$profile

if [[ $testfeature = "y" ]]; then
  echo "*/*  test" >> /etc/portage/package.env/000test  # intentionally 3 zeros to be ordered lexicographically before "00notest"
fi

# unlikely that the backlog is emptied but if then ...
echo "%/usr/bin/pfl || true
app-portage/pfl" > /var/tmp/tb/backlog

# fill the backlog with all package valid for this profile
# hint: sort -u is needed if more than one non-empty repository is configured
#
qsearch --all --nocolor --name-only --quiet | sort -u | shuf >> /var/tmp/tb/backlog

# symlink credential files of mail-mta/ssmtp and www-client/pybugz
#
(cd /root && ln -s ../mnt/tb/sdata/.bugzrc)
(cd /etc/ssmtp && ln -sf ../../mnt/tb/sdata/ssmtp.conf)

date
echo "#setup done" | tee /var/tmp/tb/task

EOF

  chmod u+x ./var/tmp/tb/setup.sh
}


# MTA, bugz et. al
#
function RunSetupScript() {
  date
  echo " run setup script ..."
  cd ~tinderbox/

  echo '/var/tmp/tb/setup.sh &> /var/tmp/tb/setup.sh.log' > $mnt/var/tmp/tb/setup_wrapper.sh
  nice -n 1 sudo ${0%/*}/bwrap.sh "$mnt" "$mnt/var/tmp/tb/setup_wrapper.sh"
  rc=$?

  if [[ $rc -ne 0 ]]; then
    date
    echo " setup was NOT successful (rc=$rc) @ $mnt"
    echo
    tail -v -n 1000 $mnt/var/tmp/tb/setup.sh.log
    echo
    exit 2
  fi

  echo
}


# check that the USE flags do not yield to circular or other non-resolvable dependencies
#
function DryrunHelper() {
  echo
  tail -v -n 1000 $mnt/etc/portage/package.use/00thrown*
  echo

  echo "#setup dryrun" | tee $mnt/var/tmp/tb/task
  echo 'emerge --update --deep --changed-use --backtrack=30 --pretend @world &> /var/tmp/tb/dryrun.log' > $mnt/var/tmp/tb/dryrun_wrapper.sh
  nice -n 1 sudo ${0%/*}/bwrap.sh "$mnt" "$mnt/var/tmp/tb/dryrun_wrapper.sh"
  local rc=$?

  if [[ $rc -eq 0 ]]; then
    grep -H -A 32 -e 'The following USE changes are necessary to proceed:'                \
                  -e 'One of the following packages is required to complete your request' \
                  $mnt/var/tmp/tb/dryrun.log && rc=2
  fi

  echo
  date
  if [[ $rc -ne 0 ]]; then
    echo " ... was NOT successful (rc=$rc):"
    echo
    tail -v -n 1000 $mnt/var/tmp/tb/dryrun.log
    echo
  else
    echo " ... succeeded"
  fi

  return $rc
}


function Dryrun() {
  if [[ "$useflags" = "ThrowUseFlags" ]]; then
    i=0
    while :; do
      ((i=i+1))
      echo
      date
      echo "i=$i==========================================================="
      echo

      grep -h 'flag name="' $repo_gentoo/*/*/metadata.xml |\
      cut -f2 -d'"' -s | sort -u |\
      DropUseFlags |\
      ThrowUseFlags 80 5 |\
      PrintUseFlags > $mnt/etc/portage/package.use/00thrown_from_metadata

      grep -v -e '^$' -e '^#' $repo_gentoo/profiles/use.desc |\
      cut -f1 -d' ' -s |\
      DropUseFlags |\
      ThrowUseFlags 20 5 |\
      PrintUseFlags > $mnt/etc/portage/package.use/00thrown_from_profile

      DryrunHelper && break

      # hold on in the hope that the portage tree is healed afterwards ...
      #
      if [[ $(($i % 20)) -eq 0 ]]; then
        echo -e "\n\n too much attempts, giving up\n\n"
        exit 2
      fi

    done
  else
    echo ${useflags} | PrintUseFlags > $mnt/etc/portage/package.use/00given_at_setup
    DryrunHelper || exit 3
  fi

  echo
  date
  echo "  setup OK"
}


#############################################################################
#
# main
#
#############################################################################
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

date
echo " $0 started"
echo

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

if [[ -n "$1" ]]; then
  echo "   $# additional args are given: '${@}'"
  echo
fi

repo_gentoo=/var/db/repos/gentoo
repo_libressl=/var/db/repos/libressl
repo_musl=/var/db/repos/musl
repo_local=/var/db/repos/local

tbdistdir=~tinderbox/distfiles
gentoo_mirrors=$(grep "^GENTOO_MIRRORS=" /etc/portage/make.conf | cut -f2 -d'"' -s | xargs -n 1 | shuf | xargs)

SetOptions

while getopts a:c:f:k:l:m:p:t:u: opt
do
  case $opt in
    a)  autostart="$OPTARG"
        ;;
    c)  cflags="$OPTARG"
        ;;
    f)  features="$OPTARG"
        ;;
    k)  keyword="$OPTARG"
        ;;
    l)  libressl="$OPTARG"
        ;;
    m)  multilib="$OPTARG"
        ;;
    p)  profile="$OPTARG"
        ;;
    t)  testfeature="$OPTARG"
        ;;
    u)  useflags="$OPTARG"
        ;;
    *)  echo " '$opt' with '$OPTARG' not implemented"
        exit 1
        ;;
  esac
done

CheckOptions
ComputeImageName
UnpackStage3
CompileRepoFiles
CompileMakeConf
CompilePortageFiles
CompileMiscFiles
CreateBacklog
CreateSetupScript
RunSetupScript
Dryrun

cd ~tinderbox/run
ln -s ../$mnt

if [[ "$autostart" = "y" ]]; then
  echo
  su - tinderbox -c "${0%/*}/start_img.sh $name"
fi

exit 0
