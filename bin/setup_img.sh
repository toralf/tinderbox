#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# setup a new tinderbox image

function Exit() {
  local rc=${1:-$?}

  trap - INT QUIT TERM EXIT
  if [[ $rc -eq 0 ]]; then
    echo -e "\n$(date)\n  setup done for $name"
  else
    echo -e "\n$(date)\n  setup failed for $name"
  fi
  echo -e "\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
  exit $rc
}

# $1:$2, eg. 3:5
function dice() {
  [[ $((RANDOM % $2)) -lt $1 ]]
}

# helper of InitOptions()
function DiceAProfile() {
  eselect profile list |
    grep -F -e ' (stable)' -e ' (dev)' |
    grep -v -F -e '/musl' -e '/selinux' -e '/x32' |
    awk '{ print $2 }' |
    cut -f 4- -d '/' -s |
    shuf -n 1
}

# helper of main()
function InitOptions() {
  abi3264="n"
  cflags_default="-O2 -pipe -march=native -fno-diagnostics-color"
  cflags=$cflags_default
  jobs="5"
  keyword="~amd64"
  profile=$(DiceAProfile)
  testfeature="n"
  useflagsfrom=""

  # no games
  if [[ $profile =~ "/musl" ]]; then
    return
  fi

  if [[ $profile =~ "/systemd" ]]; then
    if dice 1 2; then
      profile=$(sed -e 's,17.1,23.0,' -e 's,/merged-usr,,' <<<$profile)
    fi
  fi

  if zgrep "^CONFIG_IA32_EMULATION=y" /proc/config.gz; then
    if [[ ! $profile =~ "/no-multilib" ]]; then
      if dice 1 80; then
        # this sets "*/* ABI_X86: 32 64"
        abi3264="y"
      fi
    fi
  fi

  # force bug 685160 (colon in CFLAGS)
  if dice 1 80; then
    cflags+=" -falign-functions=32:25:16"
  fi

  if zgrep "^CONFIG_COMPAT_32BIT_TIME=y" /proc/config.gz; then
    if dice 1 80; then
      testfeature="y"
    fi
  fi
}

# helper of CheckOptions()
function checkBool() {
  local var=$1
  local val=$(eval echo \$${var})

  if [[ $val != "y" && $val != "n" ]]; then
    echo " wrong boolean for \$$var: >>$val<<"
    return 1
  fi
}

# helper of main()
function CheckOptions() {
  checkBool "abi3264" || return 1
  checkBool "testfeature" || return 1

  if [[ -z $profile ]]; then
    echo " empty profile"
    return 1
  fi

  if grep -q "/$" <<<$profile; then
    echo " trailing slash in profile >>$profile<<"
    return 1
  fi

  if [[ ! -d $reposdir/gentoo/profiles/default/linux/amd64/$profile ]]; then
    echo " wrong profile: >>$profile<<"
    return 1
  fi

  if [[ $abi3264 == "y" ]]; then
    if [[ $profile =~ "/no-multilib" ]]; then
      echo " ABI_X86 mismatch: >>$profile<<"
      return 1
    fi
  fi

  if [[ ! $jobs =~ ^[0-9]+$ ]]; then
    echo " jobs is wrong: >>$jobs<<"
    return 1
  fi

  if [[ -n $useflagsfrom && ! $useflagsfrom == "null" && ! -d ~tinderbox/img/$(basename $useflagsfrom)/etc/portage/package.use/ ]]; then
    echo " useflagsfrom is wrong: >>$useflagsfrom<<"
    return 1
  fi
}

# helper of UnpackStage3()
function CreateImageName() {
  name="$(tr '/\-' '_' <<<$profile)"
  [[ $keyword == 'amd64' ]] && name+="_stable"
  [[ $abi3264 == "y" ]] && name+="_abi32+64"
  [[ $testfeature == "y" ]] && name+="_test"
  name+="-$(date +%Y%m%d-%H%M%S | tr -d '\n')"
}

# download, verify and unpack the stage3 file
function UnpackStage3() {
  local latest=$tbhome/distfiles/latest-stage3.txt

  echo -en "\n$(date) get latest-stage3.txt from"
  for mirror in $gentoo_mirrors; do
    echo -n " $mirror"
    if wget --connect-timeout=10 --quiet $mirror/releases/amd64/autobuilds/latest-stage3.txt --output-document=$latest; then
      echo " done"
      break
    else
      echo -n " failed "
    fi
  done
  if [[ ! -s $latest ]]; then
    echo " empty: $latest"
    return 1
  fi

  echo -e "\n$(date) get stage3 prefix for profile $profile"
  local prefix="stage3-amd64"
  prefix+=$(sed -e 's,^..\..,,' -e 's,/plasma,,' -e 's,/gnome,,' -e 's,-,,g' <<<$profile)
  prefix=$(sed -e 's,nomultilib/hardened,hardened-nomultilib,' <<<$prefix)
  if [[ $profile =~ "/desktop" ]]; then
    if [[ $profile =~ "23.0/" ]]; then
      prefix=$(sed -e 's,/desktop,,' <<<$prefix)
    elif dice 1 2; then
      # build up from a plain instead from a desktop stage3
      prefix=$(sed -e 's,/desktop,,' <<<$prefix)
    fi
  fi
  prefix=$(tr '/' '-' <<<$prefix)
  if [[ $profile =~ "/systemd" ]]; then
    if [[ $profile =~ "23.0/" ]]; then
      prefix+="-mergedusr"
    fi
  else
    if [[ ! $profile =~ "/musl" ]]; then
      prefix+="-openrc"
    fi
  fi
  if [[ $profile =~ "/clang" ]]; then
    prefix=$(sed -e 's,amd64,amd64-llvm,' -e 's,-clang,,' <<<$prefix)
  fi

  echo -e "\n$(date) get stage3 file name for prefix $prefix"
  local stage3
  if ! stage3=$(grep -o "^20.*T.*Z/$prefix-20.*T.*Z\.tar\.\w*" $latest); then
    echo " failed"
    return 1
  fi

  echo -e "\n$(date) updating signing keys ..."
  local keys="13EBBDBEDE7A12775DFDB1BABB572E0E2D182910 D99EAC7379A850BCE47DA5F29E6438C817072058"
  if ! gpg --keyserver hkps://keys.gentoo.org --recv-keys $keys; then
    echo " notice: failed, but will continue"
  fi

  local local_stage3=$tbhome/distfiles/$(basename $stage3)
  if [[ ! -s $local_stage3 || ! -s $local_stage3.asc ]]; then
    rm -f $local_stage3{,.asc}
    for mirror in $gentoo_mirrors; do
      echo -e "\n$(date) downloading $stage3{,.asc} from mirror $mirror ..."
      if wget --connect-timeout=10 --quiet $mirror/releases/amd64/autobuilds/$stage3{,.asc} --directory-prefix=$tbhome/distfiles; then
        echo -e "$(date) finished"
        break
      fi
    done
  fi
  if [[ ! -s $local_stage3 || ! -s $local_stage3.asc ]]; then
    echo -e "\n$(date) missing stage3 file"
    ls -l $tbhome/distfiles/$stage3{,.asc}
    return 1
  fi
  echo -e "\n$(date) using $local_stage3"

  echo -e "\n$(date) verifying stage3 files ..."
  if ! gpg --quiet --verify $local_stage3.asc; then
    mv -f $local_stage3{,.asc} /tmp
    echo " FAILED"
    return 1
  fi

  CreateImageName
  echo -e "\n$(date)\n +++ new image:    $name    +++\n"
  if ! mkdir ~tinderbox/img/$name; then
    return 1
  fi

  cd ~tinderbox/img/$name
  echo -e "\n$(date) untar'ing stage3 ..."
  if ! tar -xpf $local_stage3 --same-owner --xattrs; then
    echo " failed, moving files to /tmp"
    mv $local_stage3{,.asc} /tmp
    return 1
  fi
}

# prefer git over rsync
function InitRepository() {
  mkdir -p ./etc/portage/repos.conf/

  cat <<EOF >./etc/portage/repos.conf/all.conf
[DEFAULT]
main-repo = gentoo
auto-sync = yes

[gentoo]
location  = $reposdir/gentoo
sync-uri  = https://github.com/gentoo-mirror/gentoo.git
sync-type = git

EOF

  local curr_path=$PWD
  cd .$reposdir
  cp -ar --reflink=auto $reposdir/gentoo ./ # way faster and cheaper than "emaint sync --auto"
  cd ./gentoo
  rm -f ./.git/refs/heads/stable.lock ./.git/gc.log.lock # race with git operations at the host
  git config diff.renamelimit 0
  git config gc.auto 0
  git config pull.ff only
  git pull -q
  cd $curr_path
}

# create tinderbox related directories + files
function CompileTinderboxFiles() {
  mkdir -p ./mnt/tb/data ./var/tmp/tb/{,issues,logs} ./var/cache/distfiles
  echo $EPOCHSECONDS >./var/tmp/tb/setup.timestamp
  echo $name >./var/tmp/tb/name
  chmod a+wx ./var/tmp/tb/
}

# compile make.conf
function CompileMakeConf() {
  cat <<EOF >./etc/portage/make.conf
LC_MESSAGES=C
PORTAGE_TMPFS="/dev/shm"

CFLAGS="$cflags"
CXXFLAGS="\${CFLAGS}"

FCFLAGS="$cflags"
FFLAGS="\${FCFLAGS}"

# simply enables QA check for LDFLAGS being respected by build system.
LDFLAGS="\$LDFLAGS -Wl,--defsym=__gentoo_check_ldflags__=0"

ACCEPT_KEYWORDS="$keyword"

# just tinderbox'ing, no re-distribution nor any "usage" of software
ACCEPT_LICENSE="*"

# no manual interaction
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"

NOCOLOR="true"

FEATURES="xattr -news"
EMERGE_DEFAULT_OPTS="--verbose --verbose-conflicts --nospinner --quiet-build --tree --color=n --ask=n"

CLEAN_DELAY=0
PKGSYSTEM_ENABLE_FSYNC=0

PORT_LOGDIR="/var/log/portage"

PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="tinderbox@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

#PORTAGE_LOG_FILTER_FILE_CMD="bash -c 'ansifilter --ignore-clear; exec cat'"

GENTOO_MIRRORS="$gentoo_mirrors"

EOF

  if [[ $profile =~ "/musl" ]]; then
    echo 'RUSTFLAGS="-C target-feature=-crt-static"' >>./etc/portage/make.conf
  fi

  # requested by mgorny in 822354 (this is unrelated to FEATURES="test")
  if dice 1 2; then
    echo 'ALLOW_TEST="network"' >>./etc/portage/make.conf
  fi

  # rarely b/c it yields to much different error messages for the same issue
  if dice 1 40; then
    # shellcheck disable=SC2016
    echo 'GNUMAKEFLAGS="$GNUMAKEFLAGS --shuffle"' >>./etc/portage/make.conf
  fi
}

# helper of CompilePortageFiles()
function cpconf() {
  for f in $*; do
    # shellcheck disable=SC2034
    read -r dummy suffix filename <<<$(tr '.' ' ' <<<$(basename $f))
    # eg.: package.unmask.??common   ->   package.unmask/??common
    cp $f ./etc/portage/package.$suffix/$filename
    chmod a+r ./etc/portage/package.$suffix/$filename
  done
}

# create portage related directories + files
function CompilePortageFiles() {
  cp -ar $tbhome/tb/patches ./etc/portage

  for d in env package.{,env,unmask} patches; do
    if [[ ! -d ./etc/portage/$d ]]; then
      mkdir ./etc/portage/$d
    fi
  done

  touch ./etc/portage/package.mask/self # holds failed packages

  # https://bugs.gentoo.org/903631
  mkdir -p ./etc/portage/env/app-arch/
  echo 'EXTRA_ECONF="DEFAULT_ARCHIVE=/dev/null/BAD_TAR_INVOCATION"' >./etc/portage/env/app-arch/tar

  # setup or dep calculation issues or just broken at all
  echo 'FEATURES="-test"' >./etc/portage/env/notest

  # continue an expected failed test of a package while preserving the dependency tree
  echo 'FEATURES="test-fail-continue"' >./etc/portage/env/test-fail-continue

  # retry w/o sandbox'ing
  echo 'FEATURES="-sandbox -usersandbox"' >./etc/portage/env/nosandbox

  # retry with sane defaults
  cat <<EOF >./etc/portage/env/cflags_default
CFLAGS="$cflags_default"
CXXFLAGS="\${CFLAGS}"

FCFLAGS="\${CFLAGS}"
FFLAGS="\${CFLAGS}"

EOF

  # persist build dir - only /var/tmp/portage is cleaned in job.sh, this content will stay forever
  mkdir ./var/tmp/notmpfs
  echo 'PORTAGE_TMPDIR=/var/tmp/notmpfs' >./etc/portage/env/notmpfs

  # prepare to have "j1" as a fallback for an important package failing too often in parallel build
  for j in 1 $jobs; do
    cat <<EOF >./etc/portage/env/j$j
EGO_BUILD_FLAGS="-p $j"
GO19CONCURRENTCOMPILATION=0
GOMAXPROCS=$j

MAKEOPTS="\$MAKEOPTS -j$j"

OMP_DYNAMIC=FALSE
OMP_NESTED=FALSE
OMP_NUM_THREADS=$j

RUST_TEST_THREADS=$j
RUST_TEST_TASKS=$j

EOF

  done
  echo "*/*         j${jobs}" >>./etc/portage/package.env/00jobs

  if [[ $keyword == '~amd64' ]]; then
    cpconf $tbhome/tb/conf/package.*.??unstable
  else
    cpconf $tbhome/tb/conf/package.*.??stable
  fi

  if [[ $profile =~ '/systemd' ]]; then
    cpconf $tbhome/tb/conf/package.*.??systemd
  else
    cpconf $tbhome/tb/conf/package.*.??openrc
  fi

  cpconf $tbhome/tb/conf/package.*.??common

  if [[ -s $tbhome/tb/conf/bashrc ]]; then
    cp $tbhome/tb/conf/bashrc ./etc/portage/
  fi

  if [[ $abi3264 == "y" ]]; then
    cpconf $tbhome/tb/conf/package.*.??abi32+64
  fi

  cpconf $tbhome/tb/conf/package.*.??test-$testfeature

  if [[ $profile =~ "/musl" ]]; then
    cpconf $tbhome/tb/conf/package.*.??musl
  fi

  # lines with a comment like "DICE: topic x X" will be kept with m/N chance (default: 1/2)
  grep -hEo '# DICE: .*' ./etc/portage/package.*/* |
    cut -f 3- -d ' ' |
    sort -u -r |
    while read -r topic m N; do
      if dice ${m:-1} ${N:-2}; then
        # keep start of the line, but remove comment + spaces before
        sed -i -e "s, *# DICE: $topic *$,," -e "s, *# DICE: $topic .*,," ./etc/portage/package.*/*
      else
        # delete the whole line
        sed -i -e "/# DICE: $topic *$/d" -e "/# DICE: $topic .*/d" ./etc/portage/package.*/*
      fi
    done

  echo "*/*  $(cpuid2cpuflags)" >./etc/portage/package.use/99cpuflags

  for f in "$tbhome"/tb/conf/profile.*; do
    local target=./etc/portage/profile/$(basename $f | sed -e 's,profile.,,')
    cp "$f" $target
    chmod a+r $target
  done

  chmod 777 ./etc/portage/package.*/ # e.g. to add "notest" packages
  truncate -s 0 ./var/tmp/tb/task
}

function CompileMiscFiles() {
  cat <<EOF >./etc/resolv.conf
domain localdomain
nameserver 127.0.0.1
EOF

  local image_hostname=$(tr -c 'a-z0-9\-' '-' <<<${name,,})
  cut -c -63 <<<$image_hostname >./etc/conf.d/hostname
  local host_hostname=$(hostname)

  cat <<EOF >./etc/hosts
127.0.0.1 localhost $host_hostname $host_hostname.localdomain $image_hostname $image_hostname.localdomain
::1       localhost $host_hostname $host_hostname.localdomain $image_hostname $image_hostname.localdomain

EOF

  # avoid question of vim if run in that image
  cat <<EOF >./root/.vimrc
autocmd BufEnter *.txt set textwidth=0
cnoreabbrev X x
let g:session_autosave = 'no'
let g:tex_flavor = 'latex'
set softtabstop=2
set shiftwidth=2
set expandtab

EOF

  # include the \n in paste content (sys-libs/readline de-activated that with v8)
  echo -e "\$include /etc/inputrc\nset enable-bracketed-paste off" >./root/.inputrc
}

# what                      filled once by        updated by
#
# /var/tmp/tb/backlog     : setup_img.sh
# /var/tmp/tb/backlog.1st : setup_img.sh          job.sh, retest.sh
# /var/tmp/tb/backlog.upd :                       job.sh, retest.sh
function CreateBacklogs() {
  local bl=./var/tmp/tb/backlog

  truncate -s 0 $bl{,.1st,.upd}

  if [[ $profile =~ "/clang" ]]; then
    cat <<EOF >>$bl.1st
@world
sys-devel/clang
sys-devel/llvm
EOF

  else
    cat <<EOF >>$bl.1st
@world
%USE='-mpi -opencl' emerge --deep=0 -uU =\$(portageq best_visible / sys-devel/gcc)

EOF
  fi
}

function CreateSetupScript() {
  if [[ ! $profile =~ "/clang" ]]; then
    if dice 1 2; then
      echo -e "\n$(date) use host kernel ..."
      local kv=$(realpath /usr/src/linux)
      rsync -aq $kv ./usr/src
      (
        cd ./usr/src
        ln -s $(basename $kv) linux
      )
      echo 'sys-kernel/vanilla-sources-9999' >./etc/portage/profile/package.provided
    fi
  fi

  cat <<EOF >./var/tmp/tb/setup.sh || return 1
#!/bin/bash
# set -x

export LANG=C.utf8
set -euf

# use same user and group id as at the host to avoid confusion
date
echo "#setup user" | tee /var/tmp/tb/task
groupadd -g $(id -g tinderbox) tinderbox
useradd  -g $(id -g tinderbox) -u $(id -u tinderbox) -G \$(id -g portage) tinderbox

if [[ ! $profile =~ "/musl" ]]; then
  date
  echo "#setup locale" | tee /var/tmp/tb/task
  echo "en_US ISO-8859-1" >>/etc/locale.gen
  if [[ $testfeature == "y" ]]; then
    echo "en_US.UTF-8 UTF-8" >>/etc/locale.gen
  fi
  locale-gen
fi

date
echo "#setup timezone" | tee /var/tmp/tb/task
if [[ $profile =~ "/systemd" ]]; then
  cd /etc
  ln -sf ../usr/share/zoneinfo/UTC /etc/localtime
  cd -
else
  echo "UTC" >/etc/timezone
  emerge --config sys-libs/timezone-data
fi

date
echo "#setup env" | tee /var/tmp/tb/task
env-update
set +u; source /etc/profile; set -u

if [[ $profile =~ "/systemd" ]]; then
  date
  echo "#setup id" | tee /var/tmp/tb/task
  systemd-machine-id-setup
fi

date
echo "#setup git" | tee /var/tmp/tb/task
USE="-cgi -mediawiki -mediawiki-experimental -perl -webdav" emerge -u dev-vcs/git

date
echo "#setup sync tree" | tee /var/tmp/tb/task
emaint sync --auto >/dev/null

date
echo "#setup portage" | tee /var/tmp/tb/task
emerge -u sys-apps/portage

date
echo "#setup ansifilter" | tee /var/tmp/tb/task
USE="-gui" emerge -u app-text/ansifilter
sed -i -e 's,#PORTAGE_LOG_FILTER_FILE_CMD,PORTAGE_LOG_FILTER_FILE_CMD,' /etc/portage/make.conf

# emerge MTA before MUA b/c virtual/mta does not defaults to sSMTP
date
echo "#setup Mail" | tee /var/tmp/tb/task
if emerge -u mail-mta/ssmtp; then
  rm /etc/ssmtp/._cfg0000_ssmtp.conf    # use the already bind mounted file instead
else
  if [[ ! $profile =~ "/clang" ]]; then
    exit 1
  fi
fi
USE="-kerberos" emerge -u mail-client/s-nail

if [[ ! -e /usr/src/linux ]]; then
  date
  echo "#setup kernel" | tee /var/tmp/tb/task
  emerge -u sys-kernel/gentoo-kernel-bin
fi

date
echo "#setup xz, q, bugz" | tee /var/tmp/tb/task
emerge -u app-arch/xz-utils app-portage/portage-utils www-client/pybugz

date
echo "#setup pfl" | tee /var/tmp/tb/task
USE="-network-cron" emerge -u app-portage/pfl

date
echo "#setup profile, make.conf, backlog" | tee /var/tmp/tb/task
eselect profile set --force default/linux/amd64/$profile

if [[ $testfeature == "y" ]]; then
  sed -i -e 's,FEATURES=",FEATURES="test ,' /etc/portage/make.conf
fi

# sort -u is needed if a package is in several repositories
qsearch --all --nocolor --name-only --quiet | grep -v -F -f /mnt/tb/data/IGNORE_PACKAGES | sort -u | shuf >/var/tmp/tb/backlog

date
echo "#setup done" | tee /var/tmp/tb/task

EOF

  chmod u+x ./var/tmp/tb/setup.sh
}

function RunSetupScript() {
  echo
  date
  echo " run setup script ..."

  echo '/var/tmp/tb/setup.sh &>/var/tmp/tb/setup.sh.log' >./var/tmp/tb/setup_wrapper.sh
  if nice -n 3 $(dirname $0)/bwrap.sh -m $name -e ~tinderbox/img/$name/var/tmp/tb/setup_wrapper.sh; then
    if grep -m 1 ' Invalid atom ' ./var/tmp/tb/setup.sh.log; then
      echo -e "$(date)\n  OK - but ^^\n"
      return 1
    fi
    echo -e "$(date)\n  OK\n"
  else
    echo -e "$(date)\n  FAILED\n"
    tail -n 100 ./var/tmp/tb/setup.sh.log
    echo
    return 1
  fi
}

function RunDryrunWrapper() {
  local message=$1

  echo "$message" | tee ./var/tmp/tb/task
  nice -n 3 $(dirname $0)/bwrap.sh -m $name -e ~tinderbox/img/$name/var/tmp/tb/dryrun_wrapper.sh &>$drylog
  local rc=$?

  if grep -q 'WARNING: One or more updates/rebuilds have been skipped due to a dependency conflict:' $drylog; then
    ((++rc))
  fi

  if [[ $rc -eq 0 ]]; then
    echo " OK"
  else
    echo " NOT ok"
  fi

  return $rc
}

function FixPossibleUseFlagIssues() {
  local attempt=$1

  if RunDryrunWrapper "#setup dryrun $attempt"; then
    return 0
  fi

  for i in {1..9}; do
    # kick off particular packages from package specific use flag file
    local pkg=$(
      grep -m 1 -A 1 'The ebuild selected to satisfy .* has unmet requirements.' $drylog |
        awk '/^- / { print $2 }' |
        cut -f 1 -d ':' -s |
        xargs -r qatom -F "%{CATEGORY}/%{PN}"
    )
    if [[ -n $pkg ]]; then
      local f=./etc/portage/package.use/24thrown_package_use_flags
      if grep -q "$pkg " $f; then
        sed -i -e "/$(sed -e 's,/,\\/,' <<<$pkg) /d" $f
        if RunDryrunWrapper "#setup dryrun $attempt-$i # solved unmet requirements"; then
          return 0
        fi
      fi
    fi

    # try to solve a dep cycle if an *un*setting of a USE flag is advised
    local fautocirc=./etc/portage/package.use/27-$attempt-$i-a-circ-dep
    grep -A 20 "It might be possible to break this cycle" $drylog |
      grep -F ' (Change USE: ' |
      grep -v -F -e '+' -e 'This change might require ' |
      sed -e "s,^- ,>=," -e "s, (Change USE:,," -e 's,),,' |
      sort -u |
      grep -v ".*-.*/.* .*_.*" |
      while read -r p u; do
        printf "%-36s %s\n" $p "$u"
      done |
      sort -u >$fautocirc

    if [[ -s $fautocirc ]]; then
      if RunDryrunWrapper "#setup dryrun $attempt-$i # solved circ dep"; then
        return 0
      fi
    else
      rm $fautocirc
    fi

    # follow advices
    local fautoflag=./etc/portage/package.use/27-$attempt-$i-b-necessary-use-flag
    grep -A 300 'The following USE changes are necessary to proceed:' $drylog |
      grep "^>=" |
      grep -v -e '>=.* .*_' |
      while read -r p u; do
        printf "%-36s %s\n" $p "$u"
      done |
      sort -u >$fautoflag

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

# helper of ThrowFlags
function ShuffleUseFlags() {
  local n=$1      # pass up to n-1
  local m=$2      # mask 1:m of them
  local o=${3:-0} # minimum for n

  shuf -n $((RANDOM % n + o)) |
    sort |
    while read -r flag; do
      if dice 1 $m; then
        echo -n "-"
      fi
      echo -n "$flag "
    done
}

# varying USE flags till dry run of @world would succeed
function ThrowFlags() {
  local attempt=$1

  echo "#setup throw flags ..."

  grep -v -e '^$' -e '^#' .$reposdir/gentoo/profiles/desc/l10n.desc |
    cut -f 1 -d ' ' -s |
    shuf -n $((RANDOM % 20)) |
    sort |
    xargs |
    xargs -I {} -r echo "*/*  L10N: {}" >./etc/portage/package.use/22thrown_l10n

  grep -v -e '^$' -e '^#' -e 'internal use only' .$reposdir/gentoo/profiles/use.desc |
    cut -f 1 -d ' ' -s |
    grep -v -w -f $tbhome/tb/data/IGNORE_USE_FLAGS |
    ShuffleUseFlags 250 4 50 |
    xargs -s 73 |
    sed -e "s,^,*/*  ," >./etc/portage/package.use/23thrown_global_use_flags

  grep -Hl 'flag name="' .$reposdir/gentoo/*/*/metadata.xml |
    shuf -n $((RANDOM % 1800 + 200)) |
    sort |
    while read -r file; do
      pkg=$(cut -f6-7 -d'/' <<<$file)
      grep 'flag name="' $file |
        grep -v -i -F -e 'UNSUPPORTED' -e 'UNSTABLE' -e '(requires' |
        cut -f 2 -d '"' -s |
        grep -v -w -f $tbhome/tb/data/IGNORE_USE_FLAGS |
        ShuffleUseFlags 30 3 |
        xargs |
        xargs -I {} -r printf "%-36s %s\n" "$pkg" "{}"
    done >./etc/portage/package.use/24thrown_package_use_flags
}

function CompileUseFlagFiles() {
  cat <<EOF >./var/tmp/tb/dryrun_wrapper.sh
set -euf

if ! portageq best_visible / sys-devel/gcc; then
  echo "no visible gcc ?!"
  exit 1
fi

if [[ $profile =~ "/clang" ]]; then
  emerge --deep=0 -uU sys-devel/llvm sys-devel/clang --pretend
else
  USE="-mpi -opencl" emerge --deep=0 -uU =\$(portageq best_visible / sys-devel/gcc) --pretend
fi
emerge --newuse -uU @world --pretend

EOF

  if [[ -n $useflagsfrom ]]; then
    echo
    date
    echo " +++  1 dryrun with USE flags from $useflagsfrom  +++"

    local drylog=./var/tmp/tb/logs/dryrun.log
    if [[ ! $useflagsfrom == "null" ]]; then
      cp ~tinderbox/img/$(basename $useflagsfrom)/etc/portage/package.use/* ./etc/portage/package.use/
    fi
    FixPossibleUseFlagIssues 0
    return $?
  fi

  local attempt=0
  while [[ $((++attempt)) -le 300 ]]; do
    echo
    date
    echo "==========================================================="
    for i in EOL STOP; do
      if [[ -f ./var/tmp/tb/$i ]]; then
        echo -e "\n found $i file"
        return 1
      fi
    done

    local drylog=./var/tmp/tb/logs/dryrun.$(printf "%03i" $attempt).log
    ThrowFlags $attempt
    if FixPossibleUseFlagIssues $attempt; then
      return 0
    fi
  done
  echo -e "\n max attempts reached"
  return 1
}

function Finalize() {
  cd $tbhome/run
  ln -s ../img/$name
  wc -l -w ../img/$name/etc/portage/package.use/2*
}

#############################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

trap Exit INT QUIT TERM EXIT
echo -e "\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo -e "\n$(date)\n $0 start"

tbhome=~tinderbox
reposdir=/var/db/repos
gentoo_mirrors=$(
  source /etc/portage/make.conf
  xargs -n 1 <<<$GENTOO_MIRRORS | grep '^http' | shuf | xargs
)

InitOptions

while getopts a:j:k:p:t:u: opt; do
  case $opt in
  a) abi3264="$OPTARG" ;;      # y
  j) jobs="$OPTARG" ;;         # 4
  k) keyword="$OPTARG" ;;      # amd64
  p) profile="$OPTARG" ;;      # 23.0/desktop/systemd
  t) testfeature="$OPTARG" ;;  # y
  u) useflagsfrom="$OPTARG" ;; # ~/img/23.0_desktop_systemd-20230624-014416
  *)
    echo "unknown parameter '$opt'"
    exit 1
    ;;
  esac
done

CheckOptions
UnpackStage3
InitRepository
CompileTinderboxFiles
CompileMakeConf
CompilePortageFiles
CompileMiscFiles
CreateBacklogs
CreateSetupScript
RunSetupScript
sed -i -e 's,EMERGE_DEFAULT_OPTS=",EMERGE_DEFAULT_OPTS="--deep ,' ./etc/portage/make.conf
CompileUseFlagFiles
Finalize
