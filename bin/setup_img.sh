#!/bin/bash
# set -x


# setup a new tinderbox image


# $1:$2, eg. 1:5
function dice() {
  [[ $(( $RANDOM%$2)) -lt $1 ]]
}


# helper of ThrowUseFlags()
function IgnoreUseFlags()  {
  grep -v -w -f $tbhome/tb/data/IGNORE_USE_FLAGS || true
}


# helper of ThrowUseFlags
function ThrowUseFlags() {
  local n=$1        # pass up to n-1
  local m=${2:-4}   # mask 1:m of them

  shuf -n $(( $RANDOM%$n)) |\
  sort |\
  while read -r flag
  do
    if dice 1 $m; then
      echo -n "-$flag "
    else
      echo -n "$flag "
    fi
  done
}


# helper of InitOptions()
function GetProfiles() {
  (
    eselect profile list |\
    grep -F 'default/linux/amd64/17.1' |\
    grep -v -F -e ' (exp)' -e '/x32' -e '/selinux' -e '/uclibc' -e '/musl' -e '/developer'

    # by sam
    eselect profile list |\
    grep -e 'default/linux/amd64/17.0/musl' |\
    grep -v -F -e '/selinux'
  ) |\
  awk ' { print $2 } ' |\
  cut -f4- -d'/' -s |\
  sort -u
}


# helper of main()
function InitOptions() {
  # 1 process in each of M running images is more efficient than *up to* n processes in N images
  # (given 1 x M = n x N) and it is much easier to catch the error message
  # but: the compile times are awefully with -j1
  jobs=4

  profile=$(GetProfiles | shuf -n 1)

  # a "y" activates "*/* ABI_X86: 32 64"
  abi3264="n"
  if [[ ! $profile =~ "/no-multilib" ]]; then
    if dice 1 40; then
      abi3264="y"
    fi
  fi

  cflags_default="-pipe -march=native -fno-diagnostics-color"
  # try to debug:  mr-fox kernel: [361158.269973] conftest[14463]: segfault at 3496a3b0 ip 00007f1199e1c8da sp 00007fffaf7220c8 error 4 in libc-2.33.so[7f1199cef000+142000]
  if dice 1 80; then
    cflags_default+=" -Og -g"
  else
    cflags_default+=" -O2"
  fi

  cflags=$cflags_default
  if dice 1 40; then
    # 685160 colon-in-CFLAGS
    cflags+=" -falign-functions=32:25:16"
  fi

  # stable image ?
  keyword="~amd64"
  if dice 1 80; then
    keyword="amd64"
  fi

  testfeature="n"
  if dice 1 80; then
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
  checkBool "testfeature"

  if [[ -z $profile ]]; then
    echo " profile empty!"
    return 1
  fi

  if [[ ! -d $reposdir/gentoo/profiles/default/linux/amd64/$profile ]]; then
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

  if [[ $profile =~ "musl" ]]; then
    abi3264="n"
    keyword="~amd64"
    testfeature="n"
  fi
}


# helper of UnpackStage3()
function CreateImageName()  {
  name="$(tr '/\-' '_' <<< $profile)"
  name+="-j${jobs}"
  [[ $keyword = '~amd64' ]] || name+="_stable"
  [[ $abi3264 = "n" ]]      || name+="_abi32+64"
  [[ $testfeature = "n" ]]  || name+="_test"
  [[ $cflags =~ O2 ]]       || name+="_debug"
  name+="-$(date +%Y%m%d-%H%M%S)"
}


# download, verify and unpack the stage3 file
function UnpackStage3()  {
  local latest=$tbhome/distfiles/latest-stage3.txt

  for mirror in $gentoo_mirrors
  do
    if wget --connect-timeout=10 --quiet $mirror/releases/amd64/autobuilds/latest-stage3.txt --output-document=$latest; then
      date
      echo "using mirror: $mirror"
      echo
      break
    fi
  done
  if [[ ! -s $latest ]]; then
    echo " empty: $latest"
    return 1
  fi

  local stage3=""
  case $profile in
    17.1/no-multilib/systemd)   stage3=$(grep "^20.*Z/stage3-amd64-nomultilib-systemd-20.*\.tar\." $latest) ;;
    17.1/no-multilib/hardened)  stage3=$(grep "^20.*Z/stage3-amd64-hardened-nomultilib-openrc-20.*\.tar\." $latest) ;;
    17.1/no-multilib)           stage3=$(grep "^20.*Z/stage3-amd64-nomultilib-openrc-20.*\.tar\." $latest) ;;
    17.1/hardened)              stage3=$(grep "^20.*Z/stage3-amd64-hardened-openrc-20.*\.tar\." $latest) ;;
    17.1/desktop*/systemd)      stage3=$(grep "^20.*Z/stage3-amd64-desktop-systemd-20.*\.tar\." $latest) ;;
    17.1/desktop*)              stage3=$(grep "^20.*Z/stage3-amd64-desktop-openrc-20.*\.tar\." $latest) ;;
    17.1*/systemd)              stage3=$(grep "^20.*Z/stage3-amd64-systemd-20.*\.tar\." $latest) ;;
    17.1*)                      stage3=$(grep "^20.*Z/stage3-amd64-openrc-20.*\.tar\." $latest) ;;
    17.0/musl/hardened)         stage3=$(grep "^20.*Z/stage3-amd64-musl-hardened-20.*\.tar\." $latest) ;;
    17.0/musl)                  stage3=$(grep "^20.*Z/stage3-amd64-musl-20.*\.tar\." $latest) ;;
  esac

  stage3=$(cut -f1 -d' ' -s <<< $stage3)
  if [[ -z $stage3 || $stage3 =~ [[:space:]] ]]; then
    echo " can't get stage3 filename for profile '$profile' in $latest"
    return 1
  fi

  local f=$tbhome/distfiles/$(basename $stage3)
  if [[ ! -s $f || ! -f $f.DIGESTS.asc ]]; then
    date
    echo " downloading $f ..."
    local wgeturl="$mirror/releases/amd64/autobuilds"
    wget --connect-timeout=10 --quiet --no-clobber $wgeturl/$stage3{,.DIGESTS.asc} --directory-prefix=$tbhome/distfiles || return 1
  fi

  date
  echo " updating signing key ..."
  # use the Gentoo key server, but be relaxed if it doesn't answer
  gpg --keyserver hkps://keys.gentoo.org --recv-keys 534E4209AB49EEE1C19D96162C44695DB9F6043D || true
  date
  echo " verifying $f ..."
  gpg --quiet --verify $f.DIGESTS.asc || return 1
  echo

  CreateImageName

  mkdir ~tinderbox/img/$name || return 1
  cd ~tinderbox/img/$name
  echo " new image: $name"
  echo

  date
  echo " untar'ing $f ..."
  tar -xpf $f --same-owner --xattrs || return 1
  echo
}


# configure only a ::gentoo repository
function InitRepository()  {
  mkdir -p ./etc/portage/repos.conf/

  cat << EOF >> ./etc/portage/repos.conf/all.conf
[DEFAULT]
main-repo = gentoo
auto-sync = yes

[gentoo]
location  = $reposdir/gentoo
sync-uri  = https://github.com/gentoo-mirror/gentoo.git
sync-type = git

EOF

  date
  # "git clone" is at a local machine much slower than a "cp --reflink"
  local refdir=$(ls -t $tbhome/img/*${reposdir}/gentoo/metadata/timestamp.chk 2>/dev/null | head -n 1 | sed -e 's,metadata/timestamp.chk,,')
  if [[ ! -d $refdir ]]; then
    # fallback is the host
    refdir=$reposdir/gentoo
  fi
  echo " cloning ::gentoo from $refdir"
  cd .$reposdir
  cp -ar --reflink=auto $refdir ./
  rm -f ./gentoo/.git/refs/heads/stable.lock ./gentoo/.git/gc.log.lock
  cd - 1>/dev/null

  echo
}


# compile make.conf
function CompileMakeConf()  {
  cat << EOF > ./etc/portage/make.conf
LC_MESSAGES=C
PORTAGE_TMPFS="/dev/shm"

CFLAGS="$cflags"
CXXFLAGS="\${CFLAGS}"

FCFLAGS="$cflags_default"
FFLAGS="\${FCFLAGS}"

# simply enables QA check for LDFLAGS being respected by build system.
LDFLAGS="\${LDFLAGS} -Wl,--defsym=__gentoo_check_ldflags__=0"

RUSTFLAGS="-Ctarget-cpu=native -v"
$([[ $profile =~ "musl" ]] && echo 'RUSTFLAGS=" -C target-feature=-crt-static"')

$([[ $profile =~ "/hardened" ]] || echo 'PAX_MARKINGS="none"')

ACCEPT_KEYWORDS="$keyword"

# just tinderbox, no re-distribution nor any "usage"
ACCEPT_LICENSE="*"

# no manual interaction
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"

NOCOLOR="true"
PORTAGE_LOG_FILTER_FILE_CMD="bash -c 'ansifilter --ignore-clear; exec cat'"

FEATURES="cgroup protect-owned xattr -collision-protect -news"
EMERGE_DEFAULT_OPTS="--verbose --verbose-conflicts --nospinner --quiet-build --tree --color=n --ask=n"

CLEAN_DELAY=0
PKGSYSTEM_ENABLE_FSYNC=0

PORT_LOGDIR="/var/log/portage"

PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="root@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

GENTOO_MIRRORS="$gentoo_mirrors"

EOF

  # requested by sam
  if [[ $keyword = '~amd64' ]]; then
    if dice 1 80; then
      echo 'LIBTOOL="rdlibtool"'            >> ./etc/portage/make.conf
      echo 'MAKEFLAGS="LIBTOOL=${LIBTOOL}"' >> ./etc/portage/make.conf
    fi
  fi

  # requested by mgorny in 822354
  # Hint: this is unrelated to "test"
  if dice 1 2; then
    echo 'ALLOW_TEST="network"' >> ./etc/portage/make.conf
  fi

  chgrp portage ./etc/portage/make.conf
  chmod g+w     ./etc/portage/make.conf
}


# helper of CompilePortageFiles()
function cpconf() {
  for f in $*
  do
    read -r dummy suffix filename <<<$(tr '.' ' ' <<< $(basename $f))
    # eg.:  .../package.unmask.??common   ->   package.unmask/??common
    cp $f ./etc/portage/package.$suffix/$filename
  done
}


# create portage and tinderbox related directories + files
function CompilePortageFiles()  {
  mkdir -p ./mnt/tb/data ./var/tmp/{portage,tb,tb/logs} ./var/cache/distfiles

  chgrp portage ./var/tmp/tb/{,logs}
  chmod ug+rwx  ./var/tmp/tb/{,logs}

  echo $EPOCHSECONDS > ./var/tmp/tb/setup.timestamp
  echo $name > ./var/tmp/tb/name

  for d in profile package.{accept_keywords,env,mask,unmask,use} env
  do
    if [[ ! -d ./etc/portage/$d ]]; then
      mkdir ./etc/portage/$d
    fi
    chgrp portage ./etc/portage/$d
    chmod g+w     ./etc/portage/$d
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
  for j in 1 $jobs
  do
    cat << EOF > ./etc/portage/env/j$j
EGO_BUILD_FLAGS="-p $j"
GO19CONCURRENTCOMPILATION=0

MAKEOPTS="-j$j"

OMP_DYNAMIC=FALSE
OMP_NESTED=FALSE
OMP_NUM_THREADS=$j

RUST_TEST_THREADS=$j
RUST_TEST_TASKS=$j

EOF

  done
  echo "*/*         j${jobs}" >> ./etc/portage/package.env/00j${jobs}

  if [[ $keyword = '~amd64' ]]; then
    cpconf $tbhome/tb/data/package.*.??unstable
  else
    cpconf $tbhome/tb/data/package.*.??stable
  fi

  if [[ $profile =~ '/systemd' ]]; then
    cpconf $tbhome/tb/data/package.*.??systemd
  else
    cpconf $tbhome/tb/data/package.*.??openrc
  fi

  cpconf $tbhome/tb/data/package.*.??common

  if [[ $abi3264 = "y" ]]; then
    cpconf $tbhome/tb/data/package.*.??abi32+64
  fi

  cpconf $tbhome/tb/data/package.*.??test-$testfeature

  echo "*/*  $(cpuid2cpuflags)" > ./etc/portage/package.use/99cpuflags

  for f in $tbhome/tb/data/{package.,}use.mask
  do
    cp $f ./etc/portage/profile/$(basename $f)
  done

  touch ./var/tmp/tb/task

  chgrp portage ./etc/portage/package.*/* ./etc/portage/env/* ./var/tmp/tb/task
  chmod a+r,g+w ./etc/portage/package.*/* ./etc/portage/env/* ./var/tmp/tb/task
}


function CompileMiscFiles()  {
  # use local host DNS resolver
  cat << EOF > ./etc/resolv.conf
domain localdomain
nameserver 127.0.0.1
EOF

  local image_hostname=$(echo $name | tr -d '\n' | tr '[:upper:]' '[:lower:]' | tr -c '[^a-z0-9\-]' '-' | cut -c-63)
  echo $image_hostname > ./etc/conf.d/hostname

  local host_hostname=$(hostname)

  cat << EOF > ./etc/hosts
127.0.0.1 localhost $host_hostname $host_hostname.localdomain $image_hostname $image_hostname.localdomain
::1       localhost $host_hostname $host_hostname.localdomain $image_hostname $image_hostname.localdomain

EOF

  # avoid interactive question of vim
  cat << EOF > ./root/.vimrc
set softtabstop=2
set shiftwidth=2
set expandtab
let g:session_autosave = 'no'
autocmd BufEnter *.txt set textwidth=0
cnoreabbrev X x

EOF

  # include the \n in pasting (sys-libs/readline de-activates that behaviour with v8.x)
  echo "set enable-bracketed-paste off" >> ./root/.inputrc
}


# what                      filled once by        updated by
#
# /var/tmp/tb/backlog     : setup_img.sh
# /var/tmp/tb/backlog.1st : setup_img.sh          job.sh, retest.sh
# /var/tmp/tb/backlog.upd :                       job.sh
function CreateBacklogs()  {
  local bl=./var/tmp/tb/backlog

  touch                   $bl{,.1st,.upd}
  chown tinderbox:portage $bl{,.1st,.upd}
  chmod 664               $bl{,.1st,.upd}

  # requested by Whissi (an non-default virtual/mysql engine)
  if dice 1 10; then
    echo "dev-db/percona-server" >> $bl.1st
  fi

  if [[ $name =~ "_debug" ]]; then
    echo "sys-process/minicoredumper" >> $bl.1st
  fi

  cat << EOF >> $bl.1st
app-portage/pfl
@world
%sed -i -e \\'s,--verbose,--deep --verbose,g\\' /etc/portage/make.conf
%emerge -u --changed-use sys-devel/gcc
sys-kernel/gentoo-kernel-bin
# run %emerge to provide "qatom" which is needed in getNextTask() of job.sh
%emerge -u app-portage/portage-utils

EOF
}


function CreateSetupScript()  {
  cat << EOF > ./var/tmp/tb/setup.sh || return 1
#!/bin/bash
# set -x

export LANG=C.utf8
set -euf

if [[ ! $profile =~ "musl" ]]; then
  date
  echo "#setup locale" | tee /var/tmp/tb/task
  echo -e "en_US       ISO-8859-1"  >> /etc/locale.gen
  echo -e "en_US.UTF-8 UTF-8"       >> /etc/locale.gen      # especially for "test" needed
  locale-gen
fi

date
echo "#setup timezone" | tee /var/tmp/tb/task
echo "Europe/Berlin" > /etc/timezone
emerge --config sys-libs/timezone-data
env-update
set +u; source /etc/profile; set -u

if [[ $profile =~ "/systemd" ]]; then
  systemd-machine-id-setup
fi

groupadd -g $(id -g tinderbox)                       tinderbox
useradd  -g $(id -g tinderbox) -u $(id -u tinderbox) tinderbox

date
echo "#setup git" | tee /var/tmp/tb/task
USE="-cgi -mediawiki -mediawiki-experimental -webdav" emerge -u dev-vcs/git
git config --global gc.auto 0   # could invalidate COW effect
emaint sync --auto 1>/dev/null

date
echo "#setup portage" | tee /var/tmp/tb/task
emerge -u app-text/ansifilter
# have the latest portage version in place for dryrun
emerge -u sys-apps/portage

if grep -q '^LIBTOOL="rdlibtool"' /etc/portage/make.conf; then
  date
  echo "#setup slibtool" | tee /var/tmp/tb/task
  emerge -u sys-devel/slibtool
fi

date
echo "#setup MTA and MUA" | tee /var/tmp/tb/task
# emerge sSMTP before a mail client b/c virtual/mta specifies per default another MTA
emerge -u mail-mta/ssmtp
rm /etc/ssmtp/._cfg0000_ssmtp.conf    # /etc/ssmtp/ssmtp.conf is already bind-mounted in bwrap.sh
emerge -u mail-client/s-nail

eselect profile set --force default/linux/amd64/$profile

if [[ $testfeature = "y" ]]; then
  sed -i -e 's,FEATURES=",FEATURES="test ,g' /etc/portage/make.conf
fi

if [[ $name =~ "debug" ]]; then
  sed -i -e 's,FEATURES=",FEATURES="splitdebug compressdebug ,g' /etc/portage/make.conf
fi

# sort -u is needed if a package is in several repositories
qsearch --all --nocolor --name-only --quiet | grep -v -F -f /mnt/tb/data/IGNORE_PACKAGES | sort -u | shuf > /var/tmp/tb/backlog

date
echo "#setup done" | tee /var/tmp/tb/task

EOF

  chmod u+x ./var/tmp/tb/setup.sh
}


function RunSetupScript() {
  date
  echo " run setup script ..."

  echo '/var/tmp/tb/setup.sh &> /var/tmp/tb/setup.sh.log' > ./var/tmp/tb/setup_wrapper.sh
  if nice -n 1 $(dirname $0)/bwrap.sh -m $name -e ~tinderbox/img/$name/var/tmp/tb/setup_wrapper.sh; then
    echo -e " OK"
    return 0
  else
    echo -e "$(date)\n $FUNCNAME was NOT ok\n"
    tail -v -n 100 ./var/tmp/tb/setup.sh.log
    echo
    return 1
  fi
}


function RunDryrunWrapper() {
  local message=$1

  echo "$message" | tee ./var/tmp/tb/task
  nice -n 1 sudo $(dirname $0)/bwrap.sh -m $name -e ~tinderbox/img/$name/var/tmp/tb/dryrun_wrapper.sh &> $drylog
  local rc=$?
  chmod a+r $drylog

  [[ $rc -eq 0 ]] && echo " OK" || echo " NOT ok"
  return $rc
}


function FixPossibleUseFlagIssues() {
  if RunDryrunWrapper "#setup dryrun $attempt"; then
    return 0
  fi

  for i in {1..9}
  do
    # kick off particular packages
    local pkg=$(
      grep -A 1 'The ebuild selected to satisfy .* has unmet requirements.' $drylog |\
      awk ' /^- / { print $2 } ' |\
      cut -f1 -d':' -s |\
      xargs --no-run-if-empty qatom -F "%{CATEGORY}/%{PN}" |\
      sed -e 's,/,\\/,'
    )
    if [[ -n $pkg ]]; then
      local f=./etc/portage/package.use/24thrown_package_use_flags
      local before=$(wc -l < $f)
      sed -i -e "/$pkg /d" $f
      local after=$(wc -l < $f)
      if [[ $before != $after ]]; then
        if RunDryrunWrapper "#setup dryrun $attempt-$i # solved unmet requirements"; then
          return 0
        fi
      fi
    fi

    # try to solve a dep cycle
    local fautocirc=./etc/portage/package.use/27-$attempt-$i-a-circ-dep
    grep -A 10 "It might be possible to break this cycle" $drylog |\
    grep -F ' (Change USE: ' |\
    grep -v -F -e '+' -e 'This change might require ' |\
    sed -e "s,^- ,,g" -e "s, (Change USE:,,g" |\
    tr -d ')' |\
    sort -u |\
    grep -v ".*-.*/.* .*_.*" |\
    while read -r p u
    do
      q=$(qatom -F "%{CATEGORY}/%{PN}" $p)
      printf "%-30s %s\n" $q "$u"
    done |\
    sort -u > $fautocirc

    if [[ -s $fautocirc ]]; then
      if RunDryrunWrapper "#setup dryrun $attempt-$i # solved circ dep"; then
        return 0
      fi
    else
      rm $fautocirc
    fi

    # follow advices
    local fautoflag=./etc/portage/package.use/27-$attempt-$i-b-necessary-use-flag
    grep -A 100 'The following USE changes are necessary to proceed:' $drylog |\
    grep "^>=" |\
    grep -v -e '>=.* .*_' |\
    sort -u > $fautoflag

    if [[ -s $fautoflag ]]; then
      if RunDryrunWrapper "#setup dryrun $attempt-$i # solved flag change"; then
        return 0
      fi
    else
      rm $fautoflag
    fi

    # if no change in this round was made then give up
    if [[ -z $pkg && ! -s $fautocirc && ! -s $fautoflag ]]; then
      break
    fi
  done

  rm -f ./etc/portage/package.use/27-*-*
  return 1
}


# varying USE flags till dry run of @world would succeed
function ThrowImageUseFlags() {
  echo "#setup dryrun $attempt # throw flags ..."

  grep -v -e '^$' -e '^#' $reposdir/gentoo/profiles/desc/l10n.desc |\
  cut -f1 -d' ' -s |\
  shuf -n $(( $RANDOM%20 )) |\
  sort |\
  xargs |\
  xargs -I {} --no-run-if-empty echo "*/*  L10N: {}" > ./etc/portage/package.use/22thrown_l10n

  grep -v -e '^$' -e '^#' -e 'internal use only' $reposdir/gentoo/profiles/use.desc |\
  cut -f1 -d' ' -s |\
  IgnoreUseFlags |\
  ThrowUseFlags 250 |\
  xargs -s 73 |\
  sed -e "s,^,*/*  ,g" > ./etc/portage/package.use/23thrown_global_use_flags

  grep -Hl 'flag name="' $reposdir/gentoo/*/*/metadata.xml |\
  shuf -n $(( $RANDOM%3000)) |\
  sort |\
  while read -r file
  do
    pkg=$(cut -f6-7 -d'/' <<< $file)
    grep 'flag name="' $file |\
    grep -v -i -F -e 'UNSUPPORTED' -e 'UNSTABLE' -e '(requires' |\
    cut -f2 -d'"' -s |\
    IgnoreUseFlags |\
    ThrowUseFlags 15 3 |\
    xargs |\
    xargs -I {} --no-run-if-empty printf "%-40s %s\n" "$pkg" "{}"
  done > ./etc/portage/package.use/24thrown_package_use_flags
}


function CompileUseFlagFiles() {
  local attempt=0
  echo 'emerge --update --changed-use --newuse --deep @world --pretend' > ./var/tmp/tb/dryrun_wrapper.sh
  if [[ -e $useflagfile ]]; then
    date
    echo "dryrun with given USE flag file ==========================================================="
    echo
    cp $useflagfile ./etc/portage/package.use/28given_use_flags
    local drylog=./var/tmp/tb/logs/dryrun.log
    FixPossibleUseFlagIssues $attempt
    return $?
  else
    while [[ $(( ++attempt )) -le 200 ]]
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
      ThrowImageUseFlags
      if FixPossibleUseFlagIssues $attempt; then
        return 0
      fi
    done
    echo -e "\n max attempts reached"
    return 1
  fi
}


function StartImage() {
  cd $tbhome/run
  ln -s ../img/$name
  wc -l -w $name/etc/portage/package.use/2*
  su - tinderbox -c "$(dirname $0)/start_img.sh $name"
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

if [[ $# -gt 0 ]]; then
  echo "   args: '${@}'"
  echo
fi

tbhome=~tinderbox
reposdir=/var/db/repos
gentoo_mirrors=$(grep "^GENTOO_MIRRORS=" /etc/portage/make.conf | cut -f2 -d'"' -s | xargs -n 1 | shuf)

InitOptions

while getopts a:c:j:k:p:t:u: opt
do
  case $opt in
    a)  abi3264="$OPTARG"     ;;
    c)  cflags="$OPTARG"      ;;
    j)  jobs="$OPTARG"        ;;
    k)  keyword="$OPTARG"     ;;
    p)  profile="$OPTARG"     ;;
    t)  testfeature="$OPTARG" ;;
    u)  useflagfile="$OPTARG" ;;
    *)  echo " '$opt' with '$OPTARG' not implemented"
        exit 2
        ;;
  esac
done

CheckOptions
UnpackStage3
InitRepository
CompilePortageFiles
CompileMakeConf
CompileMiscFiles
CreateBacklogs
CreateSetupScript
RunSetupScript
CompileUseFlagFiles
chgrp portage ./etc/portage/package.use/*
chmod g+w,a+r ./etc/portage/package.use/*
echo -e "\n$(date)\n  setup done\n"
StartImage
