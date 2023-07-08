#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# setup a new tinderbox image

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

  # set "*/* ABI_X86: 32 64"
  if [[ ! $profile =~ "/no-multilib" ]]; then
    if dice 1 80; then
      abi3264="y"
    fi
  fi

  # force bug 685160 (colon in CFLAGS)
  if dice 1 80; then
    cflags+=" -falign-functions=32:25:16"
  fi

  # not very fruitful but do it now and then
  if dice 1 80; then
    testfeature="y"
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

  if [[ -n $useflagsfrom && ! -d ~tinderbox/img/$(basename $useflagsfrom)/etc/portage/package.use/ ]]; then
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
  name+="-$(date +%Y%m%d-%H%M%S)"
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
      # build up from plain instead from desktop stage
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

  echo -e "\n$(date) get stage3 file name for prefix $prefix"
  local stage3
  if ! stage3=$(grep -o "^20.*T.*Z/$prefix-20.*T.*Z\.tar\.\w*" $latest); then
    echo " failed"
    return 1
  fi

  local stage3_filename=$tbhome/distfiles/$(basename $stage3)
  if [[ ! -s $stage3_filename || ! -s $stage3_filename.asc ]]; then
    echo -e "\n$(date) downloading $stage3{,.asc} ..."
    for mirror in $gentoo_mirrors; do
      if wget --connect-timeout=10 --quiet --no-clobber $mirror/releases/amd64/autobuilds/$stage3{,.asc} --directory-prefix=$tbhome/distfiles; then
        echo -e "$(date) succeeded from mirror $mirror"
        break
      else
        echo -e "$(date) failed from mirror $mirror"
      fi
    done

    if [[ ! -s $stage3_filename || ! -s $stage3_filename.asc ]]; then
      echo -e "\n$(date) failed to download stage3"
      ls -l $tbhome/distfiles/$stage3{,.asc}
      return 1
    fi
  fi
  echo -e "\n$(date) using $stage3_filename"

  echo -e "\n$(date) updating signing keys ..."
  local keys="13EBBDBEDE7A12775DFDB1BABB572E0E2D182910 D99EAC7379A850BCE47DA5F29E6438C817072058"
  if ! gpg --keyserver hkps://keys.gentoo.org --recv-keys $keys; then
    echo " notice: failed, but will continue"
  fi

  echo -e "\n$(date) verifying stage3 files ..."
  if ! gpg --quiet --verify $stage3_filename.asc; then
    echo " failed, moving files to /tmp"
    mv $stage3_filename{,.asc} /tmp
    return 1
  fi

  CreateImageName
  echo -e "\n$(date)\n +++ new image:    $name    +++\n"
  if ! mkdir ~tinderbox/img/$name; then
    return 1
  fi

  cd ~tinderbox/img/$name
  echo -e "\n$(date) untar'ing stage3 ..."
  if ! tar -xpf $stage3_filename --same-owner --xattrs; then
    echo " failed, moving files to /tmp"
    mv $stage3_filename{,.asc} /tmp
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
  cp -ar --reflink=auto $reposdir/gentoo ./ # way faster and cheaper than "emaint sync --auto >/dev/null"
  cd ./gentoo
  rm -f ./.git/refs/heads/stable.lock ./.git/gc.log.lock # race with git operations at the host
  git config diff.renamelimit 0
  git config gc.auto 0
  git config pull.ff only
  cd $curr_path
}

# create tinderbox related directories + files
function CompileTinderboxFiles() {
  mkdir -p ./mnt/tb/data ./var/tmp/{portage,tb,tb/logs} ./var/cache/distfiles

  chgrp portage ./var/tmp/tb/{,logs}
  chmod ug+rwx ./var/tmp/tb/{,logs}

  echo $EPOCHSECONDS >./var/tmp/tb/setup.timestamp
  echo $name >./var/tmp/tb/name
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
PORTAGE_LOG_FILTER_FILE_CMD="bash -c 'ansifilter --ignore-clear; exec cat'"

FEATURES="xattr -news"
EMERGE_DEFAULT_OPTS="--verbose --verbose-conflicts --nospinner --quiet-build --tree --color=n --ask=n"

CLEAN_DELAY=0
PKGSYSTEM_ENABLE_FSYNC=0

PORT_LOGDIR="/var/log/portage"

PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="tinderbox@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

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

  chgrp portage ./etc/portage/make.conf
  chmod g+w ./etc/portage/make.conf
}

# helper of CompilePortageFiles()
function cpconf() {
  for f in $*; do
    # shellcheck disable=SC2034
    read -r dummy suffix filename <<<$(tr '.' ' ' <<<$(basename $f))
    # eg.: package.unmask.??common   ->   package.unmask/??common
    cp $f ./etc/portage/package.$suffix/$filename
  done
}

# create portage related directories + files
function CompilePortageFiles() {
  cp -ar $tbhome/tb/patches ./etc/portage

  for d in env package.{accept_keywords,env,mask,unmask,use} patches profile; do
    if [[ ! -d ./etc/portage/$d ]]; then
      mkdir ./etc/portage/$d
    fi
    chgrp portage ./etc/portage/$d
    chmod g+w ./etc/portage/$d
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
    cp $f ./etc/portage/profile/$(basename $f | sed -e 's,profile.,,')
  done

  touch ./var/tmp/tb/task

  chgrp portage ./etc/portage/package.*/* ./etc/portage/env/* ./var/tmp/tb/task
  chmod a+r,g+w ./etc/portage/package.*/* ./etc/portage/env/* ./var/tmp/tb/task
}

function CompileMiscFiles() {
  cat <<EOF >./etc/resolv.conf
domain localdomain
nameserver 127.0.0.1
EOF

  local image_hostname=$(echo $name | tr -d '\n' | tr '[:upper:]' '[:lower:]' | tr -c '^a-z0-9\-' '-' | cut -c-63)
  echo $image_hostname >./etc/conf.d/hostname

  local host_hostname=$(hostname)

  cat <<EOF >./etc/hosts
127.0.0.1 localhost $host_hostname $host_hostname.localdomain $image_hostname $image_hostname.localdomain
::1       localhost $host_hostname $host_hostname.localdomain $image_hostname $image_hostname.localdomain

EOF

  # avoid interactive question of vim
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
  echo "set enable-bracketed-paste off" >>./root/.inputrc
}

# what                      filled once by        updated by
#
# /var/tmp/tb/backlog     : setup_img.sh
# /var/tmp/tb/backlog.1st : setup_img.sh          job.sh, retest.sh
# /var/tmp/tb/backlog.upd :                       job.sh, retest.sh
function CreateBacklogs() {
  local bl=./var/tmp/tb/backlog

  truncate -s 0 $bl{,.1st,.upd}
  chown tinderbox:portage $bl{,.1st,.upd}
  chmod 664 $bl{,.1st,.upd}

  cat <<EOF >>$bl.1st
@world
sys-devel/gcc
%USE='-mpi -opencl' emerge --deep=0 -uU =\$(portageq best_visible / sys-devel/gcc)

EOF

}

function CreateSetupScript() {
  cat <<EOF >./var/tmp/tb/setup.sh || return 1
#!/bin/bash
# set -x

export LANG=C.utf8
set -euf

if [[ ! $profile =~ "/musl" ]]; then
  date
  echo "#setup locale" | tee /var/tmp/tb/task
  echo "en_US ISO-8859-1" >> /etc/locale.gen
  if [[ $testfeature = "y" ]]; then
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
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
  echo "UTC" > /etc/timezone
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
emerge -u app-text/ansifilter sys-apps/portage

date
echo "#setup Mail" | tee /var/tmp/tb/task
# emerge MTA before MUA b/c default of virtual/mta does not point to sSMTP
emerge -u mail-mta/ssmtp
rm /etc/ssmtp/._cfg0000_ssmtp.conf    # use the already bind mounted file instead
USE=-kerberos emerge -u mail-client/s-nail

date
echo "#setup user" | tee /var/tmp/tb/task
groupadd -g $(id -g tinderbox)                       tinderbox
useradd  -g $(id -g tinderbox) -u $(id -u tinderbox) tinderbox

date
echo "#setup kernel" | tee /var/tmp/tb/task
emerge -u sys-kernel/gentoo-kernel-bin

date
echo "#setup xz, q, bugz and pfl" | tee /var/tmp/tb/task
emerge -u app-arch/xz-utils app-portage/portage-utils www-client/pybugz app-portage/pfl

date
echo "#setup profile, make.conf, backlog" | tee /var/tmp/tb/task
eselect profile set --force default/linux/amd64/$profile

if [[ $testfeature = "y" ]]; then
  sed -i -e 's,FEATURES=",FEATURES="test ,' /etc/portage/make.conf
fi

# sort -u is needed if a package is in several repositories
qsearch --all --nocolor --name-only --quiet | grep -v -F -f /mnt/tb/data/IGNORE_PACKAGES | sort -u | shuf > /var/tmp/tb/backlog

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
    if grep ' Invalid atom ' ./var/tmp/tb/setup.sh.log; then
      return 1
    fi
    echo -e " OK"
  else
    echo -e "$(date)\n setup was NOT ok\n"
    tail -v -n 100 ./var/tmp/tb/setup.sh.log
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

  chmod a+r $drylog
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
        xargs --no-run-if-empty qatom -F "%{CATEGORY}/%{PN}"
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

  grep -v -e '^$' -e '^#' $reposdir/gentoo/profiles/desc/l10n.desc |
    cut -f1 -d' ' -s |
    shuf -n $((RANDOM % 20)) |
    sort |
    xargs |
    xargs -I {} --no-run-if-empty echo "*/*  L10N: {}" >./etc/portage/package.use/22thrown_l10n

  grep -v -e '^$' -e '^#' -e 'internal use only' $reposdir/gentoo/profiles/use.desc |
    cut -f1 -d' ' -s |
    grep -v -w -f $tbhome/tb/data/IGNORE_USE_FLAGS |
    ShuffleUseFlags 250 4 50 |
    xargs -s 73 |
    sed -e "s,^,*/*  ," >./etc/portage/package.use/23thrown_global_use_flags

  grep -Hl 'flag name="' $reposdir/gentoo/*/*/metadata.xml |
    shuf -n $((RANDOM % 1800 + 200)) |
    sort |
    while read -r file; do
      pkg=$(cut -f6-7 -d'/' <<<$file)
      grep 'flag name="' $file |
        grep -v -i -F -e 'UNSUPPORTED' -e 'UNSTABLE' -e '(requires' |
        cut -f2 -d'"' -s |
        grep -v -w -f $tbhome/tb/data/IGNORE_USE_FLAGS |
        ShuffleUseFlags 30 3 |
        xargs |
        xargs -I {} --no-run-if-empty printf "%-36s %s\n" "$pkg" "{}"
    done >./etc/portage/package.use/24thrown_package_use_flags
}

function CompileUseFlagFiles() {
  cat <<EOF >./var/tmp/tb/dryrun_wrapper.sh
set -euf

if ! portageq best_visible / sys-devel/gcc; then
  echo "no visible gcc"
  exit 13
fi
USE="-mpi -opencl" emerge --deep=0 -uU =\$(portageq best_visible / sys-devel/gcc) --pretend
emerge --update --changed-use --newuse @world --pretend

EOF

  if [[ -n $useflagsfrom ]]; then
    echo
    date
    echo " +++  1 dryrun with USE flags from $useflagsfrom  +++"

    local drylog=./var/tmp/tb/logs/dryrun.log
    cp ~tinderbox/img/$(basename $useflagsfrom)/etc/portage/package.use/* ./etc/portage/package.use/
    FixPossibleUseFlagIssues 0
    return $?
  fi

  local attempt=0
  while [[ $((++attempt)) -le 200 ]]; do
    echo
    date
    echo "==========================================================="
    if [[ -f ./var/tmp/tb/STOP ]]; then
      echo -e "\n found STOP file"
      rm ./var/tmp/tb/STOP
      return 1
    fi

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
  chgrp portage ./etc/portage/package.use/*
  chmod g+w,a+r ./etc/portage/package.use/*

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

echo -e "\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
echo -e "\n$(date)\n $0 start"

tbhome=~tinderbox
reposdir=/var/db/repos
gentoo_mirrors=$(grep "^GENTOO_MIRRORS=" /etc/portage/make.conf | cut -f2 -d'"' -s | xargs -n 1 | shuf | xargs)

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

echo -e "\n$(date)\n  setup done"
echo -e "\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
