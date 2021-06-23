#!/bin/bash
# set -x


# setup a new tinderbox image


# helper of ThrowUseFlags()
function IgnoreUseFlags()  {
  grep -v -w -f ~tinderbox/tb/data/IGNORE_USE_FLAGS || true
}


# helper of DryRunWithRandomUseFlags
function ThrowUseFlags() {
  local n=$1  # pass up to n-1
  local m=5   # mask 1:5

  shuf -n $(($RANDOM % $n)) |\
  sort |\
  while read -r flag
  do
    if __dice 1 $m; then
      echo -n "-"
    fi
    echo -n "$flag "
  done
}


# helper of InitOptions()
function GetProfiles() {
  eselect profile list |\
  awk ' { print $2 } ' |\
  grep -F "default/linux/amd64/17.1" |\
  grep -v -F -e '/x32' -e '/selinux' -e '/uclibc' -e 'musl' |\
  cut -f4- -d'/' -s
}


# helper of main()
# almost are variables here are globals
function InitOptions() {
  # 1 process in N running images rules over *up to* N running processes in 1 image
  # furhermore -j1 makes it easier to manage resource management -but-
  # the compile times are awefully
  jobs=3

  # a "y" activates "*/* ABI_X86: 32 64"
  abi3264="n"
  if __dice 1 24; then
    abi3264="y"
  fi

  # prefer a non-running profile plus not symlinked to ~/run
  profile=""
  while read -r line
  do
    if [[ -z $profile ]]; then
      profile=$line
    fi
    local p=$(tr '/-' '_' <<< $line)
    if ! ls -d /run/tinderbox/$p-*.lock &>/dev/null; then
      profile=$line
      if ! ls ~tinderbox/run/$p-* &>/dev/null; then
        break
      fi
    fi
  done < <(GetProfiles | shuf)

  cflags_default="-pipe -march=native -fno-diagnostics-color"
  if __dice 1 12; then
    # catch sth like:  mr-fox kernel: [361158.269973] conftest[14463]: segfault at 3496a3b0 ip 00007f1199e1c8da sp 00007fffaf7220c8 error 4 in libc-2.33.so[7f1199cef000+142000]
    cflags_default+=" -Og -g"
  else
    cflags_default+=" -O2"
  fi
  local cflags_special=""
  if __dice 1 12; then
    # 685160 colon-in-CFLAGS
    cflags_special+=" -falign-functions=32:25:16"
  fi
  cflags="$cflags_default $cflags_special"

  musl="n"
  randomuseflags="y"
  science="n"

  testfeature="n"
  if __dice 1 24; then
    testfeature="y"
  fi
}


# helper of CheckOptions()
function checkBool()  {
  var=$1
  val=$(eval echo \$${var})

  if [[ $val != "y" && $val != "n" ]]; then
    echo " wrong value for variable \$$var: >>$val<<"
    return 1
  fi
}


# helper of main()
function CheckOptions() {
  checkBool "abi3264"
  checkBool "musl"
  checkBool "randomuseflags"
  checkBool "science"
  checkBool "testfeature"

  if [[ -z $profile ]]; then
    echo " profile empty!"
    return 1
  fi

  if [[ ! -d $repodir/gentoo/profiles/default/linux/amd64/$profile ]]; then
    echo " wrong profile: >>$profile<<"
    return 1
  fi

  if [[ $abi3264 = "y" ]]; then
    if [[ $profile =~ "/no-multilib" ]]; then
      echo " ABI_X86 mismatch: >>$profile<<"
      return 1
    fi
  fi

  if [[ ! $jobs =~ ^[0-9].*$ ]]; then
    echo " jobs is wrong: >>${jobs}<<"
    return 1
  fi
}


# helper of UnpackStage3()
function CreateImageName()  {
  name="$(tr '/\-' '_' <<< $profile)"
  name+="-j${jobs}"
  [[ $abi3264 = "n" ]]      || name+="_abi32+64"
  [[ $science = "n" ]]      || name+="_science"
  [[ $testfeature = "n" ]]  || name+="_test"
  [[ $cflags =~ O2 ]]       || name+="_debug"
  name+="-$(date +%Y%m%d-%H%M%S)"
}


# download, verify and unpack the stage3 file
function UnpackStage3()  {
  local latest="$tbdistdir/latest-stage3.txt"

  for mirror in $gentoo_mirrors
  do
    wget --connect-timeout=10 --quiet $mirror/releases/amd64/autobuilds/latest-stage3.txt --output-document=$latest && break
  done

  if [[ ! -s $latest ]]; then
    echo " empty: $latest"
    return 1
  fi

  local wgeturl="$mirror/releases/amd64/autobuilds"

  case $profile in
    */no-multilib/hardened)   stage3=$(grep "/stage3-amd64-hardened+nomultilib-20.*\.tar\." $latest);;
    */musl/hardened)          stage3=$(grep "/stage3-amd64-musl-hardened-20.*\.tar\." $latest);;
    */hardened)               stage3=$(grep "/stage3-amd64-hardened-20.*\.tar\." $latest);;
    */no-multilib)            stage3=$(grep "/stage3-amd64-nomultilib-20.*\.tar\." $latest);;
    */systemd)                stage3=$(grep "/stage3-amd64-systemd-20.*\.tar\." $latest);;
    */musl)                   stage3=$(grep "/stage3-amd64-musl-vanilla-20.*\.tar\." $latest);;
    *)                        stage3=$(grep "/stage3-amd64-20.*\.tar\." $latest);;
  esac
  local stage3=$(cut -f1 -d' ' -s <<< $stage3)

  if [[ -z $stage3 || $stage3 =~ [[:space:]] ]]; then
    echo " can't get stage3 filename for profile '$profile' in $latest"
    return 1
  fi

  local f=$tbdistdir/${stage3##*/}
  if [[ ! -s $f || ! -f $f.DIGESTS.asc ]]; then
    date
    echo " downloading $f ..."
    wget --connect-timeout=10 --quiet --no-clobber $wgeturl/$stage3{,.DIGESTS.asc} --directory-prefix=$tbdistdir || return 1
  fi

  date
  echo " getting signing key ..."
  # use the Gentoo key server, but be relaxed if it doesn't answer
  gpg --keyserver hkps://keys.gentoo.org --recv-keys 534E4209AB49EEE1C19D96162C44695DB9F6043D || true

  date
  echo " verifying $f ..."
  gpg --quiet --verify $f.DIGESTS.asc || return 1
  echo

  CreateImageName

  mnt=~tinderbox/img/$name
  mkdir $mnt || return 1
  echo " new image: $mnt"
  echo

  date
  cd $mnt
  echo " untar'ing $f ..."
  tar -xpf $f --same-owner --xattrs || return 1
  echo
}


# configure image repositories
function CompileRepoFiles()  {
  cd $mnt

  mkdir -p ./etc/portage/repos.conf/

  cat << EOF >> ./etc/portage/repos.conf/all.conf
[DEFAULT]
main-repo = gentoo
auto-sync = yes

[gentoo]
location  = $repodir/gentoo
priority  = 10
sync-uri  = https://github.com/gentoo-mirror/gentoo.git
sync-type = git

[local]
location  = $repodir/local
priority  = 99

EOF

  mkdir -p                  ./$repodir/local/{metadata,profiles}
  echo 'masters = gentoo' > ./$repodir/local/metadata/layout.conf
  echo 'local'            > ./$repodir/local/profiles/repo_name

  if [[ $musl = "y" ]]; then
    cat << EOF >> ./etc/portage/repos.conf/all.conf
[musl]
location  = $repodir/musl
priority  = 40
sync-uri  = https://github.com/gentoo/musl.git
sync-type = git

EOF
  fi

  if [[ $science = "y" ]]; then
    cat << EOF >> ./etc/portage/repos.conf/all.conf
[science]
location  = $repodir/science
priority  = 50
sync-uri  = https://github.com/gentoo/sci.git
sync-type = git

EOF
  fi

  date
  echo " clone repos ..."

  # rsync is much faster than git clone
  cd ./$repodir
  rsync --archive --quiet /var/db/repos/gentoo ./
  cd ./gentoo
  git pull --quiet 2>/dev/null
  cd ..
  [[ $musl    = "n" ]] || git clone --quiet https://github.com/gentoo/musl.git 2>/dev/null
  [[ $science = "n" ]] || git clone --quiet https://github.com/gentoo/sci.git  2>/dev/null
  echo
}


# compile make.conf
function CompileMakeConf()  {
  cd $mnt

  cat << EOF > ./etc/portage/make.conf
LC_MESSAGES=C
PORTAGE_TMPFS="/dev/shm"

CFLAGS="$cflags"
CXXFLAGS="\${CFLAGS}"

FCFLAGS="$cflags_default"
FFLAGS="\${FCFLAGS}"

LDFLAGS="\${LDFLAGS} -Wl,--defsym=__gentoo_check_ldflags__=0"
$([[ $profile =~ "/hardened" ]] || echo 'PAX_MARKINGS="none"')

# test unstable only
ACCEPT_KEYWORDS="~amd64"

# no re-distribution nor any "usage", just QA
ACCEPT_LICENSE="*"

# no manual interaction
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"

NOCOLOR="true"
PORTAGE_LOG_FILTER_FILE_CMD="bash -c 'ansifilter --ignore-clear; exec cat'"

FEATURES="cgroup splitdebug xattr -collision-protect -news"
EMERGE_DEFAULT_OPTS="--verbose --verbose-conflicts --nospinner --quiet-build --tree --color=n --ask=n --with-bdeps=y --verbose-conflicts"

ALLOW_TEST="network"

CLEAN_DELAY=0

PORT_LOGDIR="/var/log/portage"
PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="root@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

GENTOO_MIRRORS="$gentoo_mirrors"

EOF

if __dice 1 6; then
  cat <<EOF >> ./etc/portage/make.conf
LIBTOOL="rdlibtool"
MAKEFLAGS="LIBTOOL=\${LIBTOOL}"

EOF
fi

  # the "tinderbox" user must be a member of group "portage"
  chgrp portage ./etc/portage/make.conf
  chmod g+w ./etc/portage/make.conf
}


# helper of CompilePortageFiles()
function cpconf() {
  for f in $*
  do
    # eg.: .../package.unmask.??common -> package.unmask/??common
    read -r a b c <<<$(tr '.' ' ' <<< ${f##*/})
    cp $f ./etc/portage/"$a.$b/$c"
  done
}


# create portage and tinderbox related directories + files
function CompilePortageFiles()  {
  cd $mnt

  mkdir -p ./mnt/{repos,tb/data} ./var/tmp/{portage,tb,tb/logs} ./var/cache/distfiles

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

  touch       ./etc/portage/package.mask/self     # gets failed packages
  chmod a+rw  ./etc/portage/package.mask/self

  echo 'FEATURES="test"'                  > ./etc/portage/env/test
  echo 'FEATURES="-test"'                 > ./etc/portage/env/notest

  # continue an expected failed test of a package while preserving the dependency tree
  echo 'FEATURES="test-fail-continue"'    > ./etc/portage/env/test-fail-continue

  # retry w/o sandbox'ing
  echo 'FEATURES="-sandbox -usersandbox"' > ./etc/portage/env/nosandbox

  # retry with sane defaults
  cat <<EOF                               > ./etc/portage/env/cflags_default
CFLAGS="$cflags_default"
CXXFLAGS="\${CFLAGS}"

FCFLAGS="\${CFLAGS}"
FFLAGS="\${CFLAGS}"

EOF

  # no more parallelism than specified in $jops
  cat << EOF                              > ./etc/portage/env/jobs
EGO_BUILD_FLAGS="-p ${jobs}"
GO19CONCURRENTCOMPILATION=0

MAKEOPTS="-j${jobs}"

OMP_DYNAMIC=FALSE
OMP_NESTED=FALSE
OMP_NUM_THREADS=${jobs}

RUST_TEST_THREADS=${jobs}
RUST_TEST_TASKS=${jobs}

EOF
  if [[ $musl = "y" ]]; then
    echo 'RUSTFLAGS=" -C target-feature=-crt-static"' >> ./etc/portage/env/jobs
  fi

  echo '*/*  jobs' > ./etc/portage/package.env/00jobs

  if [[ $profile =~ '/systemd' ]]; then
    cpconf ~tinderbox/tb/data/package.*.??systemd
  fi

  cpconf ~tinderbox/tb/data/package.*.??common

  if [[ $abi3264 = "y" ]]; then
    cpconf ~tinderbox/tb/data/package.*.??abi32+64
  fi

  if [[ $testfeature = "y" ]]; then
    cpconf ~tinderbox/tb/data/package.*.*test
  else
    # overrule any IUSE=+test
    echo "*/*  notest" > ./etc/portage/package.env/12notest
  fi

  # give Firefox, Thunderbird et al. a chance
  if __dice 1 12; then
    cpconf ~tinderbox/tb/data/package.use.30misc
  fi

  for p in $(grep -v -e '#' -e'^$' ~tinderbox/tb/data/BIN_OR_SKIP)
  do
    if __dice 11 12; then
      echo "$p" >> ./etc/portage/package.mask/91bin-or-skip
    fi
  done

  echo "*/*  $(cpuid2cpuflags)" > ./etc/portage/package.use/99cpuflags

  # libxcrypt as requested by sam
  # https://gist.github.com/thesamesam/a36ff15235f5cbe5004972f80f254123#portage-changes
  # https://wiki.gentoo.org/wiki/Project:Toolchain/libcrypt_implementation
  if __dice 1 2; then
    cat << EOF >> ./etc/portage/package.use/81libxcrypt
# Disable libcrypt in glibc
sys-libs/glibc -crypt
# Provide libcrypt
sys-libs/libxcrypt system

EOF

    cat << EOF >> ./etc/portage/package.accept_keywords/81libxcrypt
# Allow the new libcrypt virtual which includes libxcrypt
>=virtual/libcrypt-2

EOF

    cat << EOF >> ./etc/portage/package.unmask/81libxcrypt
# Allow virtual which specifies libxcrypt
>=virtual/libcrypt-2

EOF

    mkdir -p ./etc/portage/profile

    cat << EOF >> ./etc/portage/profile/package.use.mask
# Allow libxcrypt to be the system provider of libcrypt, not glibc
sys-libs/libxcrypt -system

EOF

    cat << EOF >> ./etc/portage/profile/package.use.force
# Don't force glibc to provide libcrypt
sys-libs/glibc -crypt

EOF
fi

  touch ./var/tmp/tb/task

  chgrp portage ./etc/portage/package.*/* ./etc/portage/env/* ./var/tmp/tb/task
  chmod a+r,g+w ./etc/portage/package.*/* ./etc/portage/env/* ./var/tmp/tb/task
}


function CompileMiscFiles()  {
  cd $mnt

  # use local host DNS resolver
  cat << EOF > ./etc/resolv.conf
domain localdomain
nameserver 127.0.0.1

EOF

  local h=$(hostname)
  cat << EOF > ./etc/hosts
127.0.0.1 localhost $h.localdomain $h
::1       localhost $h.localdomain $h

EOF

  # avoid interactive question in vim
  cat << EOF > ./root/.vimrc
set softtabstop=2
set shiftwidth=2
set expandtab
let g:session_autosave = 'no'
autocmd BufEnter *.txt set textwidth=0
cnoreabbrev X x

EOF

  echo "$name" > ./etc/conf.d/hostname
}


# /var/tmp/tb/backlog     : filled  once by setup_img.sh
# /var/tmp/tb/backlog.1st : filled  once by setup_img.sh, job.sh or retest.sh updates it
# /var/tmp/tb/backlog.upd : updated      by job.sh
function CreateHighPrioBacklog()  {
  local bl=./var/tmp/tb/backlog

  cd $mnt

  touch                   $bl{,.1st,.upd}
  chmod 664               $bl{,.1st,.upd}
  chown tinderbox:portage $bl{,.1st,.upd}

  # requested by Whissi, its an alternative mysql engine
  if __dice 1 12; then
    echo "dev-db/percona-server" >> $bl.1st
  fi

  cat << EOF > $bl.1st
@world
%rm /etc/portage/package.use/90setup
@world
@world
@system
@system
%sed -i -e 's,EMERGE_DEFAULT_OPTS=",EMERGE_DEFAULT_OPTS="--deep ,g' /etc/portage/make.conf
sys-apps/portage
%eselect kernel set 1
sys-kernel/gentoo-kernel-bin
EOF

  # update GCC first
  # =          : do not rebuild the current GCC (slot)
  # dev-libs/* : avoid a rebuild of GCC later in @world caused by an update/rebuild of these packages
  echo "%emerge -uU =\$(portageq best_visible / gcc) dev-libs/mpc dev-libs/mpfr" >> $bl.1st
}


function CreateSetupScript()  {
  cd $mnt

  cat << EOF > ./var/tmp/tb/setup.sh || exit 1
#!/bin/sh
# set -x

export LANG=C.utf8
set -euf

date
echo "#setup locales + timezone" | tee /var/tmp/tb/task

if [[ ! $musl = "y" ]]; then
  cat << EOF2 >> /etc/locale.gen
# by \$0 at \$(date)
en_US ISO-8859-1
en_US.UTF-8 UTF-8
de_DE ISO-8859-1
de_DE@euro ISO-8859-15
de_DE.UTF-8@euro UTF-8

EOF2

  locale-gen -j${jobs}
  eselect locale set C.UTF-8
fi

echo "Europe/Berlin" > /etc/timezone
emerge --config sys-libs/timezone-data
env-update
set +u; source /etc/profile; set -u

if [[ $profile =~ "/systemd" ]]; then
  systemd-machine-id-setup
fi

date
echo "#setup git" | tee /var/tmp/tb/task
emerge -u dev-vcs/git
emaint sync --auto 1>/dev/null

echo "#setup portage helpers" | tee /var/tmp/tb/task
if grep -q LIBTOOL /etc/portage/make.conf; then
  echo "*/* -audit -cups" >> /etc/portage/package.use/slibtool
  emerge -u sys-devel/slibtool
fi
emerge -u app-text/ansifilter app-portage/portage-utils

date
echo "#setup mailer" | tee /var/tmp/tb/task
# emerge ssmtp separately before mailx b/c mailx would pull in per default another MTA than ssmtp
emerge -u mail-mta/ssmtp
rm /etc/ssmtp/._cfg0000_ssmtp.conf    # the destination already exists (bind-mounted by bwrap-sh)
emerge -u mail-client/mailx

if [[ -s /etc/portage/package.use/81libxcrypt ]]; then
  date
  echo "#setup libxcrypt" | tee /var/tmp/tb/task
  emerge -u virtual/libcrypt || emerge -u virtual/libcrypt dev-lang/perl || exit 1
fi

if grep -q 'sys-devel/gcc' /var/tmp/tb/setup.sh.log; then
  echo "%SwitchGCC" >> /var/tmp/tb/backlog.1st
fi

date
eselect profile set --force default/linux/amd64/$profile
if [[ $testfeature = "y" ]]; then
  echo "*/*  test" >> /etc/portage/package.env/11dotest
fi

date
echo "#setup backlog" | tee /var/tmp/tb/task
# sort -u is needed if a package is in more than one repo
qsearch --all --nocolor --name-only --quiet | sort -u -R > /var/tmp/tb/backlog

# copy+paste the \n too for middle mouse selections (sys-libs/readline de-activates that behaviour with v8.x)
echo "set enable-bracketed-paste off" >> /etc/inputrc

EOF

  chmod u+x ./var/tmp/tb/setup.sh
}


function RunSetupScript() {
  date
  echo " run setup script ..."

  cd ~tinderbox/
  echo '/var/tmp/tb/setup.sh &> /var/tmp/tb/setup.sh.log' > $mnt/var/tmp/tb/setup_wrapper.sh

  if ! nice -n 1 ${0%/*}/bwrap.sh -m "$mnt" -s $mnt/var/tmp/tb/setup_wrapper.sh; then
    echo -e "$(date)\n $FUNCNAME was NOT successful @ $mnt\n"
    tail -v -n 100 $mnt/var/tmp/tb/setup.sh.log
    echo
    return 1
  fi
}


function DryRun() {
  if ! nice -n 1 sudo ${0%/*}/bwrap.sh -m "$mnt" -s $mnt/var/tmp/tb/dryrun_wrapper.sh; then
    echo -e "$(date)\n $FUNCNAME was NOT successful\n"
    return 1
  fi
}


function FormatUseFlags() {
  xargs -s 73 | sed -e '/^$/d' | sed -e "s,^,*/*  ,g"
}


# varying USE flags till dry run of @world would succeed
function DryRunWithRandomUseFlags() {
  cd $mnt

  for attempt in $(seq -w 1 50)
  do
    echo
    date
    echo "dryrun $attempt ==========================================================="
    echo

    echo "#setup dryrun $attempt" > ./var/tmp/tb/task

    grep -v -e '^$' -e '^#' $repodir/gentoo/profiles/desc/l10n.desc |\
    cut -f1 -d' ' -s |\
    shuf -n $(($RANDOM % 15)) |\
    sort |\
    xargs |\
    xargs -I {} --no-run-if-empty printf "%s %s\n" "*/*  L10N: -* {}" > ./etc/portage/package.use/21thrown_l10n_from_profile

    grep -v -e '^$' -e '^#' $repodir/gentoo/profiles/use.desc |\
    cut -f1 -d' ' -s |\
    IgnoreUseFlags |\
    ThrowUseFlags 150 |\
    FormatUseFlags > ./etc/portage/package.use/22thrown_global_use_flags_from_profile

    grep -h 'flag name="' $repodir/gentoo/*/*/metadata.xml |\
    cut -f2 -d'"' -s |\
    sort -u |\
    IgnoreUseFlags |\
    ThrowUseFlags 150 |\
    FormatUseFlags > ./etc/portage/package.use/23thrown_global_use_flags_from_metadata

    grep -Hl 'flag name="' $repodir/gentoo/*/*/metadata.xml |\
    shuf -n $(($RANDOM % 900)) |\
    sort |\
    while read -r file
    do
      pkg=$(cut -f6-7 -d'/' <<< $file)
      grep -h 'flag name="' $file |\
      cut -f2 -d'"' -s |\
      IgnoreUseFlags |\
      ThrowUseFlags 12 |\
      xargs |\
      xargs -I {} --no-run-if-empty printf "%-50s %s\n" "$pkg" "{}"
    done > ./etc/portage/package.use/24thrown_package_use_flags

    chgrp portage ./etc/portage/package.use/2*
    chmod a+r,g+w ./etc/portage/package.use/2*

    # allows "tail -f ./dryrun.log"
    touch ./var/tmp/tb/logs/dryrun.$attempt.log
    (cd ./var/tmp/tb; ln -f ./logs/dryrun.$attempt.log dryrun.log)

    if DryRun &> ./var/tmp/tb/logs/dryrun.$attempt.log; then
      return
    fi
  done

  echo -e "\n$(date)\ndidn't make it after $attempt attempts, giving up\n"
  truncate -s 0 ./var/tmp/tb/task
  exit 2
}


#############################################################################
#
# main
#
set -eu
export LANG=C.utf8

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

date
echo " $0 started"
echo

source $(dirname $0)/lib.sh

echo "   $# args given: '${@}'"
echo

repodir=/var/db/repos
tbdistdir=~tinderbox/distfiles
gentoo_mirrors=$(grep "^GENTOO_MIRRORS=" /etc/portage/make.conf | cut -f2 -d'"' -s)

InitOptions

while getopts a:c:j:m:p:r:s:t: opt
do
  case $opt in
    a)  abi3264="$OPTARG"         ;;
    c)  cflags="$OPTARG"          ;;
    j)  jobs="$OPTARG"            ;;
    p)  profile="$OPTARG"         ;;
    r)  randomuseflags="$OPTARG"  ;;
    s)  science="$OPTARG"         ;;
    t)  testfeature="$OPTARG"     ;;
    m)  musl="$OPTARG"            ;;
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
CreateHighPrioBacklog
CreateSetupScript
RunSetupScript
echo
echo 'emerge --update --changed-use --pretend --deep @world' > $mnt/var/tmp/tb/dryrun_wrapper.sh
if [[ $randomuseflags = "y" ]]; then
  DryRunWithRandomUseFlags
else
  date
  echo "dryrun with default USE flags ==========================================================="
  echo
  DryRun
fi

echo -e "\n$(date)\n  setup OK"
cd ~tinderbox/run
ln -s ../img/$name
echo
su - tinderbox -c "${0%/*}/start_img.sh $name"
