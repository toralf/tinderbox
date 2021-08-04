#!/bin/bash
# set -x


# setup a new tinderbox image


# helper of ThrowUseFlags()
function IgnoreUseFlags()  {
  grep -v -w -f ~tinderbox/tb/data/IGNORE_USE_FLAGS || true
}


# helper of DryRunWithRandomizedUseFlags
function ThrowUseFlags() {
  local n=$1        # pass up to n-1
  local m=${2:-4}   # mask 1:m of them

  shuf -n $(($RANDOM % $n)) |\
  sort |\
  while read -r flag
  do
    if __dice 1 $m; then
      echo -n "-$flag "
    else
      echo -n "$flag "
    fi
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
  if __dice 1 39; then
    abi3264="y"
  fi

  profile=""
  while read -r line
  do
    if [[ -z $profile ]]; then
      profile=$line
    fi
    local p=$(tr '/-' '_' <<< $line)
    # basic: not running
    if ! ls -d /run/tinderbox/$p-*.lock &>/dev/null; then
      profile=$line
      # sufficiant: not in ~/run
      if ! ls ~tinderbox/run/$p-* &>/dev/null; then
        break
      fi
      # but the last one would make it otherwise
    fi
  done < <(GetProfiles | shuf)

  cflags_default="-pipe -march=native -fno-diagnostics-color"
  if __dice 1 13; then
    # try to debug:  mr-fox kernel: [361158.269973] conftest[14463]: segfault at 3496a3b0 ip 00007f1199e1c8da sp 00007fffaf7220c8 error 4 in libc-2.33.so[7f1199cef000+142000]
    cflags_default+=" -Og -g"
  else
    cflags_default+=" -O2"
  fi

  cflags=$cflags_default
  if __dice 1 13; then
    # 685160 colon-in-CFLAGS
    cflags+=" -falign-functions=32:25:16"
  fi

  musl="n"
  science="n"
  testfeature="n"
  if __dice 1 39; then
    testfeature="y"
  fi
  useflagfile=""
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

  case $profile in
    17.1/hardened)                stage3=$(grep "^20.*Z/stage3-amd64-hardened-openrc-20.*\.tar\." $latest) ;;
    17.1/no-multilib/hardened)    stage3=$(grep "^20.*Z/stage3-amd64-hardened-nomultilib-openrc-20.*\.tar\." $latest) ;;
    17.1/no-multilib/systemd)     stage3=$(grep "^20.*Z/stage3-amd64-nomultilib-systemd-20.*\.tar\." $latest) ;;
    17.1/no-multilib)             stage3=$(grep "^20.*Z/stage3-amd64-nomultilib-openrc-20.*\.tar\." $latest) ;;
    17.0/musl/hardened)           stage3=$(grep "^20.*Z/stage3-amd64-musl-hardened-20.*\.tar\." $latest) ;;
    17.0/musl)                    stage3=$(grep "^20.*Z/stage3-amd64-musl-20.*\.tar\." $latest) ;;
    17.1*/systemd)                stage3=$(grep "^20.*Z/stage3-amd64-systemd-20.*\.tar\." $latest) ;;
    17.1/no-multi*/hard*/selinux) stage3=$(grep "^20.*Z/stage3-amd64-hardened-nomultilib-selinux-openrc-20.*\.tar\." $latest) ;;
    17.1/hardened/selinux)        stage3=$(grep "^20.*Z/stage3-amd64-hardened-selinux-openrc-20.*\.tar\." $latest) ;;
    *)                            stage3=$(grep "^20.*Z/stage3-amd64-openrc-20.*\.tar\." $latest) ;;
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
    local wgeturl="$mirror/releases/amd64/autobuilds"
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
function InitRepositories()  {
  cd $mnt
  mkdir -p ./etc/portage/repos.conf/

  # ::gentoo
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
auto-sync = no
priority  = 99

EOF

  # ::local
  mkdir -p       ./$repodir/local/{metadata,profiles}
  echo 'local' > ./$repodir/local/profiles/repo_name
  cat << EOF  > ./$repodir/local/metadata/layout.conf
[local]
masters = gentoo

EOF

  # ::gentoo
  date
  echo " cloning ::gentoo"
  cd ./$repodir
  # "git clone" of a local repo is much slower than cp
  local refdir=~tinderbox/img/$(ls -t ~tinderbox/run | head -n 1)/var/db/repos/gentoo
  if [[ ! -d $refdir ]]; then
    refdir=/var/db/repos/gentoo
  fi
  cp -ar --reflink=auto $refdir ./

  # ::musl
  if [[ $musl = "y" ]]; then
    cat << EOF >> ./etc/portage/repos.conf/all.conf
[musl]
location  = $repodir/musl
priority  = 40
sync-uri  = https://github.com/gentoo/musl.git
sync-type = git

EOF
    date
    echo " cloning ::musl"
    git clone --quiet https://github.com/gentoo/musl.git
  fi

  # ::science
  if [[ $science = "y" ]]; then
    cat << EOF >> ./etc/portage/repos.conf/all.conf
[science]
location  = $repodir/science
priority  = 50
sync-uri  = https://github.com/gentoo/sci.git
sync-type = git

EOF
    date
    echo " cloning ::science"
    git clone --quiet https://github.com/gentoo/sci.git
  fi

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

FEATURES="cgroup xattr -collision-protect -news -splitdebug"
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

if __dice 1 39; then
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

  # setup or dep calculation issues or just broken at all
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

  # max $jobs parallel jobs
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
  else
    cpconf ~tinderbox/tb/data/package.*.??openrc
  fi

  cpconf ~tinderbox/tb/data/package.*.??{common,setup}

  if [[ $abi3264 = "y" ]]; then
    cpconf ~tinderbox/tb/data/package.*.??abi32+64
  fi

  cpconf ~tinderbox/tb/data/package.*.??test-$testfeature

  # give Firefox, Thunderbird et al. a better chance
  if __dice 1 13; then
    cpconf ~tinderbox/tb/data/package.use.30misc
  fi

  # packages either having a -bin variant or shall only rarely been build
  for p in $(grep -v -e '#' -e'^$' ~tinderbox/tb/data/BIN_OR_SKIP)
  do
    if ! __dice 1 13; then
      echo "$p" >> ./etc/portage/package.mask/91bin-or-skip
    fi
  done

  echo "*/*  $(cpuid2cpuflags)" > ./etc/portage/package.use/99cpuflags
  cat ~tinderbox/tb/data/package.use.mask >> /etc/portage/profile/package.use.mask

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

  # requested by Whissi (an alternative mysql engine)
  if __dice 1 13; then
    echo "dev-db/percona-server" >> $bl.1st
  fi

  cat << EOF > $bl.1st
@world
@system
%rm -f /etc/portage/package.use/??setup*
@world
@system
%sed -i -e 's,EMERGE_DEFAULT_OPTS=",EMERGE_DEFAULT_OPTS="--deep ,g' /etc/portage/make.conf
sys-apps/portage
app-portage/gentoolkit
%emerge -uU =\$(portageq best_visible / gcc) dev-libs/mpc dev-libs/mpfr
sys-kernel/gentoo-kernel-bin
%SwitchGCC

EOF
}


function CreateSetupScript()  {
  cd $mnt

  cat << EOF > ./var/tmp/tb/setup.sh || exit 1
#!/bin/bash
# set -x

export LANG=C.utf8
set -euf

# include the \n at copying (sys-libs/readline de-activates that behaviour with v8.x)
echo "set enable-bracketed-paste off" >> /etc/inputrc

date
echo "#setup locale + timezone" | tee /var/tmp/tb/task

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

if grep -q LIBTOOL /etc/portage/make.conf; then
  date
  echo "#setup slibtool" | tee /var/tmp/tb/task
  echo "*/* -audit -cups" >> /etc/portage/package.use/slibtool
  emerge -u sys-devel/slibtool
fi

date
echo "#setup portage helpers" | tee /var/tmp/tb/task
emerge -u app-text/ansifilter app-portage/portage-utils

date
echo "#setup mailer" | tee /var/tmp/tb/task
# emerge ssmtp separately before mailx b/c mailx would pull in per default another MTA than ssmtp
emerge -u mail-mta/ssmtp
rm /etc/ssmtp/._cfg0000_ssmtp.conf    # the destination does already exist (bind-mounted by bwrap.sh)
emerge -u mail-client/mailx

date
echo "#setup libxcrypt" | tee /var/tmp/tb/task
emerge -u virtual/libcrypt

date
echo "#setup harfbuzz/freetype" | tee /var/tmp/tb/task
USE="-X" emerge -u media-libs/freetype

eselect profile set --force default/linux/amd64/$profile

# switch on the test feature now
if [[ $testfeature = "y" ]]; then
  sed -i -e 's,FEATURES=",FEATURES="test ,g' /etc/portage/make.conf
fi

# sort -u is needed if a package is in more than one repo
qsearch --all --nocolor --name-only --quiet | sort -u | shuf > /var/tmp/tb/backlog

date
echo "#setup done" | tee /var/tmp/tb/task

EOF

  chmod u+x ./var/tmp/tb/setup.sh
}


function RunSetupScript() {
  date
  echo " run setup script ..."

  cd ~tinderbox/
  echo '/var/tmp/tb/setup.sh &> /var/tmp/tb/setup.sh.log' > $mnt/var/tmp/tb/setup_wrapper.sh

  if nice -n 1 ${0%/*}/bwrap.sh -m "$mnt" -s $mnt/var/tmp/tb/setup_wrapper.sh; then
    echo -e " OK"
    return 0
  fi

  echo -e "$(date)\n $FUNCNAME was NOT ok\n"
  tail -v -n 100 $mnt/var/tmp/tb/setup.sh.log
  echo
  return 1
}


function DryRun() {
  cd $mnt

  chgrp portage ./etc/portage/package.use/*
  chmod g+w,a+r ./etc/portage/package.use/*

  if nice -n 1 sudo ${0%/*}/bwrap.sh -m "$mnt" -s $mnt/var/tmp/tb/dryrun_wrapper.sh &> $drylog; then
    echo " OK"
    return 0
  fi

  echo " NOT ok"
  return 1
}


function FormatUseFlags() {
  xargs --no-run-if-empty -s 73 | sed -e "s,^,*/*  ,g"
}


# varying USE flags till dry run of @world would succeed
function DryRunWithRandomizedUseFlags() {
  cd $mnt

  echo "#setup dryrun $attempt" | tee ./var/tmp/tb/task

  grep -v -e '^$' -e '^#' $repodir/gentoo/profiles/desc/l10n.desc |\
  cut -f1 -d' ' -s |\
  shuf -n $(($RANDOM % 20)) |\
  sort |\
  xargs |\
  xargs -I {} --no-run-if-empty echo "*/*  L10N: {}" > ./etc/portage/package.use/22thrown_l10n

  grep -v -e '^$' -e '^#' -e 'internal use only' $repodir/gentoo/profiles/use.desc |\
  cut -f1 -d' ' -s |\
  IgnoreUseFlags |\
  ThrowUseFlags 150 |\
  FormatUseFlags > ./etc/portage/package.use/24thrown_global_use_flags

  grep -Hl 'flag name="' $repodir/gentoo/*/*/metadata.xml |\
  shuf -n $(($RANDOM % 2000)) |\
  sort |\
  while read -r file
  do
    pkg=$(cut -f6-7 -d'/' <<< $file)
    grep -h 'flag name="' $file |\
    grep -v -i -F -e 'UNSUPPORTED' -e 'UNSTABLE' -e '(requires' |\
    cut -f2 -d'"' -s |\
    IgnoreUseFlags |\
    ThrowUseFlags 10 |\
    xargs |\
    xargs -I {} --no-run-if-empty printf "%-40s %s\n" "$pkg" "{}"
  done > ./etc/portage/package.use/26thrown_package_use_flags

  if DryRun; then
    return 0
  fi

  local fautocirc=./etc/portage/package.use/91setup-auto-solve-circ-dep

  grep -h -A 10 "It might be possible to break this cycle" $drylog |\
  grep -F ' (Change USE: ' |\
  grep -v -F  -e '_' -e 'sys-devel/gcc' -e 'sys-libs/glibc' \
              -e '+' -e 'This change might require ' |\
  sed -e "s,^- ,,g" -e "s, (Change USE:,,g" |\
  tr -d ')' |\
  sort -u |\
  while read -r p u
  do
    q=$(qatom $p | cut -f1-2 -d' ' | tr ' ' '/')
    printf "%-30s %s\n" $q "$u"
  done |\
  sort -u > $fautocirc

  if [[ -s $fautocirc ]]; then
    echo "#setup dryrun $attempt #circ dep" | tee ./var/tmp/tb/task
    tail -v $fautocirc
    if DryRun; then
      return 0
    fi
  fi

  local fautoflag=./etc/portage/package.use/28necessary-use-flag-change

  grep -h -A 100 'The following USE changes are necessary to proceed:' $drylog |\
  grep "^>=" |\
  sort -u |\
  grep -v -F -e '_' -e 'sys-devel/gcc' -e 'sys-libs/glibc' > $fautoflag

  if [[ -s $fautoflag ]]; then
    echo "#setup dryrun $attempt #flag change" | tee ./var/tmp/tb/task
    tail -v $fautoflag
    if DryRun; then
      return 0
    fi
  fi

  rm $fautocirc $fautoflag
  return 1
}


function ThrowImageUseFlags(){
  cd $mnt

  echo 'emerge --update --changed-use --newuse --deep @world --pretend' > ./var/tmp/tb/dryrun_wrapper.sh
  if [[ -e $useflagfile ]]; then
    date
    echo "dryrun with given USE flag file ==========================================================="
    echo
    cp $useflagfile ./etc/portage/package.use/28given_use_flags
    local drylog=./var/tmp/tb/logs/dryrun.log
    DryRun
    return $?
  else
    local attempt=1
    while [[ $attempt -lt 1000 ]]
    do
      if [[ -f ./var/tmp/tb/STOP ]]; then
        echo -e "\n found STOP file"
        rm ./var/tmp/tb/STOP
        return 1
      fi
      echo
      date
      echo "==========================================================="
      local drylog=./var/tmp/tb/logs/dryrun.$(printf "%03i" $attempt).log
      if DryRunWithRandomizedUseFlags; then
        return 0
      fi
      ((attempt++))
    done
    echo -e "\n max attempts reached"
    return 1
  fi
}


function startImage() {
  echo -e "\n$(date)\n  setup done"
  cd ~tinderbox/run
  ln -s ../img/$name
  echo
  su - tinderbox -c "${0%/*}/start_img.sh $name"
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

if [[ $# -gt 0 ]]; then
  echo "   args: '${@}'"
  echo
fi

repodir=/var/db/repos
tbdistdir=~tinderbox/distfiles
gentoo_mirrors=$(grep "^GENTOO_MIRRORS=" /etc/portage/make.conf | cut -f2 -d'"' -s)

InitOptions

while getopts M:S:a:c:f:j:m:p:s:t:u: opt
do
  case $opt in
    M)  musl="$OPTARG"        ;;
    S)  science="$OPTARG"     ;;
    a)  abi3264="$OPTARG"     ;;
    c)  cflags="$OPTARG"      ;;
    f)  mnt="$OPTARG"
        name=$(basename $mnt)
        ThrowImageUseFlags
        exit $?
        ;;
    j)  jobs="$OPTARG"        ;;
    p)  profile="$OPTARG"
        cflags=$cflags_default
        abi3264="n"
        testfeature="n"
        ;;
    s)  mnt="$OPTARG"
        name=$(basename $mnt)
        startImage
        exit $?
        ;;
    t)  testfeature="$OPTARG" ;;
    u)  useflagfile="$OPTARG" ;;
    *)  echo " '$opt' with '$OPTARG' not implemented"
        exit 1
        ;;
  esac
done

CheckOptions
UnpackStage3
InitRepositories
CompileMakeConf
CompilePortageFiles
CompileMiscFiles
CreateHighPrioBacklog
CreateSetupScript
RunSetupScript
ThrowImageUseFlags
startImage
