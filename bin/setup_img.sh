#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# setup a new tinderbox image
# CompileUseFlagFiles() is the central part

function Exit() {
  local rc=${1:-$?}

  trap - INT QUIT TERM EXIT
  set +e
  if [[ $rc -eq 0 ]]; then
    echo -e "$(date)  setup done for $name"
  else
    echo -e "$(date)  setup failed for $name with rc=$rc"
  fi
  echo -e "\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
  mv $trace_file $tbhome/img/$name/var/tmp/tb/
  exit $rc
}

# $1:$2, e.g. 3:5
function dice() {
  [[ $((RANDOM % $2)) -lt $1 ]]
}

# helper of InitOptions()
function DiceAProfile() {
  eselect profile list |
    grep -F '/23.0' |
    grep -v -e '/prefix' -e '/selinux' -e '/split-usr' -e '/x32' |
    awk '{ print $2 }' |
    cut -f 4- -d '/' -s |
    if dice 7 8; then
      # weigth MUSL less
      grep -v '/musl'
    else
      grep '.'
    fi |
    if dice 3 4; then
      # weigth LLVM less
      grep -v '/llvm'
    else
      grep '.'
    fi |
    if dice 1 2; then
      # weigth desktop more
      grep '/desktop'
    else
      grep '.'
    fi |
    shuf -n 1
}

# helper of main()
function InitOptions() {
  echo "$(date) ${FUNCNAME[0]} ..."

  # const
  cflags_default="-O2 -pipe -march=native -fno-diagnostics-color"
  case $(nproc) in
  32) jobs="4" ;;
  96) jobs="8" ;;
  *) jobs=$(($(nproc) / 8)) ;;
  esac

  keyword="~amd64"

  # variable
  abi3264="n"
  cflags=$cflags_default
  name="n/a" # set in CreateImageName()
  start_it="n"
  testfeature="n"
  useconfigof=""

  profile=$(DiceAProfile)

  # musl is not matured enough for a chaos monkey
  if [[ $profile =~ "/musl" ]]; then
    return
  fi

  if dice 1 10; then
    cflags=$(sed -e 's,-O2,-O3,g' <<<$cflags)
  fi

  if [[ ! $profile =~ "/no-multilib" ]]; then
    if dice 1 40; then
      # this sets "*/* ABI_X86: 32 64" via package.use.40abi32+64
      abi3264="y"
    fi
  fi

  # force bug 685160 (colon in CFLAGS)
  if dice 1 80; then
    cflags+=" -falign-functions=32:25:16"
  fi

  if dice 1 20; then
    testfeature="y"
  fi
}

# helper of CheckOptions()
function checkBool() {
  local var=$1

  local val
  val=$(eval echo \$${var})
  if [[ $val != "y" && $val != "n" ]]; then
    echo " wrong boolean for \$$var: >>$val<<"
    return 1
  fi
}

# helper of main()
function CheckOptions() {
  checkBool "abi3264"
  checkBool "testfeature"

  if grep -q "/$" <<<$profile; then
    profile=$(sed -e 's,/$,,' <<<$profile)
  fi

  if [[ -z $profile ]]; then
    echo " empty profile"
    return 1
  fi

  if [[ ! -d $reposdir/gentoo/profiles/default/linux/amd64/$profile ]]; then
    echo " unknown profile: >>$profile<<"
    return 1
  fi

  if [[ $abi3264 == "y" && $profile =~ "/no-multilib" ]]; then
    echo " ABI_X86 mismatch: >>$abi3264<< >>$profile<<"
    return 1
  fi

  if [[ -n $useconfigof && $useconfigof != "me" && ! -d ~tinderbox/img/$(basename $useconfigof)/etc/portage/ ]]; then
    echo " useconfigof is wrong: >>$useconfigof<<"
    return 1
  fi
}

# helper of InitImageFromStage3()
function CreateImageName() {
  name="$(tr '/\-' '_' <<<$profile)"
  [[ $keyword == "amd64" ]] && name+="_stable"
  [[ $abi3264 == "y" ]] && name+="_abi32+64"
  [[ $testfeature == "y" ]] && name+="_test"
  name+="-$(date +%Y%m%d-%H%M%S)"
}

function getStage3List() {
  for mirror in $mirrors; do
    echo "$(date)   downloading $(basename $stage3_list) from $mirror"
    if wget --connect-timeout=10 --quiet $mirror/$mirror_path/$(basename $stage3_list) --output-document=$stage3_list.new; then
      if [[ -s $stage3_list.new ]]; then
        echo "$(date)   verify stage3 list file ..."
        if gpg --verify $stage3_list.new &>/dev/null; then
          mv $stage3_list.new $stage3_list
          return 0
        else
          echo "$(date)   gpg failed"
        fi
      else
        echo "$(date)   empty stage3 list"
      fi
    else
      echo "$(date)   wget failed"
    fi
  done

  return 1
}

function getStage3Filename() {
  echo "$(date)   get stage3 prefix for profile $profile"

  local prefix="stage3-amd64"
  prefix+=$(sed -e 's,^..\..,,' -e 's,/plasma,,' -e 's,/gnome,,' -e 's,-,,g' <<<$profile)
  if [[ $profile =~ "/desktop" ]]; then
    if dice 1 2; then
      # start from plain stage3
      prefix=$(sed -e 's,/desktop,,' <<<$prefix)
    fi
  fi
  prefix=$(tr '/' '-' <<<$prefix)
  if [[ ! $profile =~ "/musl" && ! $profile =~ "/systemd" ]]; then
    prefix+="-openrc"
  fi

  if [[ $profile =~ '23.0/no-multilib/hardened' ]]; then
    # there's no stage3, so start with a 23.0/hardened and switch later
    prefix=$(sed -e 's,nomultilib-,,' <<<$prefix)
  fi

  echo "$(date)   get stage3 file name for prefix $prefix"

  if [[ $stage3_list =~ "latest" ]]; then
    if ! stage3=$(grep -o "^20.*/$prefix-20.*T.*Z\.tar\.\w*" $stage3_list); then
      echo "$(date)   failed"
      return 1
    fi
  else
    if ! stage3=$(grep -o "$prefix-20.*T.*Z\.tar\.\w*" $stage3_list); then
      echo "$(date)   failed"
      return 1
    fi
  fi
}

function downloadStage3File() {
  local_stage3=$tbhome/distfiles/$(basename $stage3)

  if [[ -s $local_stage3 ]]; then
    return 0
  fi

  rm -f $local_stage3
  for mirror in $mirrors; do
    echo "$(date)   downloading $stage3 from $mirror ..."
    if wget --connect-timeout=10 --quiet $mirror/$mirror_path/$stage3 --directory-prefix=$tbhome/distfiles; then
      if [[ -s $local_stage3 ]]; then
        echo "$(date)   done"
        return 0
      else
        echo "$(date)   empty"
      fi
    fi
  done

  echo "$(date)   failed"
  return 1
}

function verifyStage3File() {
  if [[ ! -s $local_stage3.asc ]]; then
    rm -f $local_stage3.asc
    for mirror in $mirrors; do
      echo "$(date)   downloading $stage3.asc from $mirror ..."
      if wget --connect-timeout=10 --quiet $mirror/$mirror_path/$stage3.asc --directory-prefix=$tbhome/distfiles; then
        echo "$(date)   done"
        break
      fi
    done
  fi

  echo "$(date)   verify stage3 file ..."
  if ! gpg --verify $local_stage3.asc &>/dev/null; then
    echo "$(date)   failed"
    rm $local_stage3{,.asc}
    return 1
  fi
}

# download, verify and unpack the stage3 file
function InitImageFromStage3() {
  echo "$(date) ${FUNCNAME[0]} ..."

  local stage3
  local local_stage3
  local stage3_list="$tbhome/distfiles/latest-stage3.txt"

  eval $(grep -A 10 "^GENTOO_MIRRORS=" /etc/portage/make.conf | tr -d '\\\n')
  local mirrors=$GENTOO_MIRRORS
  local mirror_path="releases/amd64/autobuilds"

  getStage3List
  getStage3Filename
  downloadStage3File
  echo "$(date)   using $local_stage3"
  verifyStage3File

  CreateImageName
  echo "$(date)   name: $name"
  mkdir ~tinderbox/img/$name
  cd ~tinderbox/img/$name
  echo "$(date)   unpacking stage3 ..."
  if ! tar -xpf $local_stage3 --same-owner --xattrs; then
    echo "$(date)   failed"
    return 1
  fi
}

# prefer git over rsync
function InitRepository() {
  echo "$(date) ${FUNCNAME[0]} ..."

  mkdir -p ./etc/portage/repos.conf/

  cat <<EOF >./etc/portage/repos.conf/all.conf
[DEFAULT]
main-repo = gentoo
auto-sync = yes

[gentoo]
location  = $reposdir/gentoo
sync-uri  = https://github.com/gentoo-mirror/gentoo.git
sync-type = git
sync-git-verify-commit-signature = false

EOF

  local curr_path=$PWD

  cd .$reposdir
  if ! git clone -q --depth=1 https://github.com/gentoo-mirror/gentoo.git 2>&1; then
    # take the most up-to-date source
    local source=$(ls -td ~/img/*/$reposdir/gentoo $reposdir/gentoo/ | head -n 1)
    cp -ar --reflink=auto $source .
  fi

  cd ./gentoo
  git config diff.renamelimit 0
  git config gc.auto 0
  git config pull.ff only

  cd $curr_path
}

# create tinderbox related directories + files
function CompileTinderboxFiles() {
  echo "$(date) ${FUNCNAME[0]} ..."

  mkdir -p ./mnt/tb/data ./var/tmp/tb/{,issues,logs} ./var/cache/distfiles
  echo $EPOCHSECONDS >./var/tmp/tb/setup.timestamp
  echo $name >./var/tmp/tb/name
  chmod a+wx ./var/tmp/tb/
}

# compile make.conf
function CompileMakeConf() {
  echo "$(date) ${FUNCNAME[0]} ..."

  cat <<EOF >./etc/portage/make.conf
LC_MESSAGES=C

# set each explicitely to tweak (only) CFLAGS in job.sh e.g. for gcc-14
CFLAGS="$cflags"
CXXFLAGS="$cflags"
FCFLAGS="$cflags"
FFLAGS="$cflags"

# simply enables QA check for LDFLAGS being respected by build system.
LDFLAGS="\$LDFLAGS -Wl,--defsym=__gentoo_check_ldflags__=0"

ACCEPT_KEYWORDS="$keyword"

# just tinderbox'ing, no re-distribution nor any kind of "use"
ACCEPT_LICENSE="* -@EULA"

# no manual interaction
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"

NO_COLOR="true"

FEATURES="xattr -news"
EMERGE_DEFAULT_OPTS="--newuse --changed-use --verbose --verbose-conflicts --nospinner --quiet-build --tree --color=n --ask=n"

CLEAN_DELAY=0
PKGSYSTEM_ENABLE_FSYNC=0

PORT_LOGDIR="/var/log/portage"

PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="tinderbox@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

#PORTAGE_LOG_FILTER_FILE_CMD="bash -c 'ansifilter --ignore-clear; exec cat'"

GENTOO_MIRRORS="$GENTOO_MIRRORS"

EOF

  # requested by mgorny in 822354 (this is unrelated to FEATURES="test")
  if dice 1 2; then
    echo 'ALLOW_TEST="network"' >>./etc/portage/make.conf
  fi

  # it might give much more different error messages for the same issue
  if dice 1 20; then
    # shellcheck disable=SC2016
    echo 'GNUMAKEFLAGS="$GNUMAKEFLAGS --shuffle"' >>./etc/portage/make.conf
  fi

  if [[ $profile =~ "/musl" ]]; then
    echo 'RUSTFLAGS="-C target-feature=-crt-static"' >>./etc/portage/make.conf
  fi
}

# helper of CompilePortageFiles()
function cpconf() {
  # shellcheck disable=SC2045
  for f in $(ls $* 2>/dev/null); do
    # shellcheck disable=SC2034
    read -r package suffix filename <<<$(tr '.' ' ' <<<$(basename $f))
    # e.g.: package.unmask.??common   ->   package.unmask/??common
    cp $f ./etc/portage/package.$suffix/$filename
    chmod a+r ./etc/portage/package.$suffix/$filename
  done
}

# create portage related directories + files
function CompilePortageFiles() {
  echo "$(date) ${FUNCNAME[0]} ..."

  cp -r $tbhome/tb/patches ./etc/portage
  for d in env package.{env,unmask}; do
    [[ ! -d ./etc/portage/$d ]] && mkdir ./etc/portage/$d
  done

  touch ./etc/portage/package.mask/self # will hold failed packages

  # handle broken setup or particular package issue
  echo 'FEATURES="-test"' >./etc/portage/env/notest

  # continue after a (known) test phase failure rather than setting "notest"
  # for that package and therefore risk a changed dependency tree
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

  # if persistent build dir is needed
  mkdir ./var/tmp/notmpfs
  echo 'PORTAGE_TMPDIR=/var/tmp/notmpfs' >./etc/portage/env/notmpfs

  # "j1" is the fallback for packages failing in parallel build
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
  echo "*/*         j$jobs" >>./etc/portage/package.env/00jobs

  cat <<EOF >./etc/portage/env/clang
PORTAGE_USE_CLANG_HOOK=1
EOF

  cat <<EOF >./etc/portage/env/gcc
PORTAGE_USE_CLANG_HOOK=0
EOF

  if [[ $keyword == '~amd64' ]]; then
    cpconf $tbhome/tb/conf/package.*.??unstable
  else
    cpconf $tbhome/tb/conf/package.*.??stable
  fi

  if [[ $profile =~ "/llvm" ]]; then
    cpconf $tbhome/tb/conf/package.*.??llvm
    cp $tbhome/tb/conf/bashrc.clang ./etc/portage
  else
    cpconf $tbhome/tb/conf/package.*.??gcc
  fi

  if [[ $profile =~ '/musl' ]]; then
    cpconf $tbhome/tb/conf/package.*.??musl
  fi

  if [[ $profile =~ '/systemd' ]]; then
    cpconf $tbhome/tb/conf/package.*.??systemd
  else
    cpconf $tbhome/tb/conf/package.*.??openrc
  fi

  cpconf $tbhome/tb/conf/package.*.??common

  if [[ $abi3264 == "y" ]]; then
    cpconf $tbhome/tb/conf/package.*.??abi32+64
  fi

  cpconf $tbhome/tb/conf/package.*.??test-$testfeature

  # take lines tagged with "# DICE: <topic> <m> <N>" with an m/N chance (default: 1/2)
  grep -ho '# DICE: .*' ./etc/portage/package.*/* |
    cut -f 3- -d ' ' |
    sort -u -r |
    tr -d '][' |
    while read -r topic m N; do
      if ! dice ${m:-1} ${N:-2}; then
        sed -i -e "/# DICE: $topic /d" -e "/# DICE: \[$topic\] /d" ./etc/portage/package.*/*
      fi
    done

  echo "*/*  $(cpuid2cpuflags)" >./etc/portage/package.use/99cpuflags

  for f in "$tbhome"/tb/conf/profile.*; do
    local target=./etc/portage/profile/$(basename $f | sed -e 's,profile.,,')
    cp $f $target
    chmod a+r $target
  done

  chmod 777 ./etc/portage/package.*/ # e.g. to add "notest" packages
  truncate -s 0 ./var/tmp/tb/task
}

function CompileMiscFiles() {
  echo "$(date) ${FUNCNAME[0]} ..."

  cat <<EOF >./etc/resolv.conf
domain localdomain
nameserver 127.0.0.1
EOF

  local image_hostname=$(tr -d '\n' <<<${name,,} | tr -c 'a-z0-9\-' '-')
  cut -c -63 <<<$image_hostname >./etc/conf.d/hostname
  local host_hostname
  host_hostname=$(hostname)

  cat <<EOF >./etc/hosts
127.0.0.1 localhost $host_hostname $host_hostname.localdomain $image_hostname $image_hostname.localdomain
::1       localhost $host_hostname $host_hostname.localdomain $image_hostname $image_hostname.localdomain
EOF

  # avoid question of vim if run in that image
  cat <<EOF >./root/.vimrc
autocmd BufEnter *.txt set textwidth=0
cnoreabbrev X x
let g:session_autosave="no"
let g:tex_flavor="latex"
set softtabstop=2
set shiftwidth=2
set expandtab
EOF

  # include the \n in the pasted content (sys-libs/readline de-activated that with v8)
  echo -e "\$include /etc/inputrc\nset enable-bracketed-paste off" >./root/.inputrc
}

# file                      filled once by        updated by
#
# /var/tmp/tb/backlog     : setup_img.sh
# /var/tmp/tb/backlog.1st : setup_img.sh          job.sh, retest.sh
# /var/tmp/tb/backlog.upd :                       job.sh, retest.sh
function CreateBacklogs() {
  echo "$(date) ${FUNCNAME[0]} ..."

  local bl=./var/tmp/tb/backlog
  truncate -s 0 $bl{,.1st,.upd}

  if [[ $profile =~ "/llvm" ]]; then
    cat <<EOF >>$bl.1st
@world
%cd /etc/portage/ && ln -sf bashrc.clang bashrc && printf '%-37s%s\n' '*/*' 'clang' >/etc/portage/package.use/clang
%emerge -1 --selective=n --deep=0 -u =\$(portageq best_visible / sys-devel/clang) =\$(portageq best_visible / sys-devel/llvm)
EOF
  elif [[ $profile =~ '23.0/no-multilib/hardened' ]]; then
    # [11:06:37 pm] <@toralf> Would changing the profile and re-emerging @world with --emptytree do it?
    # [11:27:13 pm] <@dilfridge> switching from/to hardened, and switching from multilib to non-multilib, yes
    # [11:27:31 pm] <@dilfridge> switching from non-multilib to multilib, NO
    cat <<EOF >>$bl.1st
%emerge -e @world
%emerge -1 --selective=n --deep=0 -u =\$(portageq best_visible / sys-devel/gcc) sys-devel/binutils sys-libs/glibc
EOF
  else
    cat <<EOF >>$bl.1st
@world
%emerge -1 --selective=n --deep=0 -u =\$(portageq best_visible / sys-devel/gcc)
EOF
  fi
}

function CreateSetupScript() {
  echo "$(date) ${FUNCNAME[0]} ..."

  cat <<EOF >./var/tmp/tb/setup.sh
#!/bin/bash
set -x

export LANG=C.utf8
set -euf

date
cat /var/tmp/tb/name

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
echo "#setup sync" | tee /var/tmp/tb/task
emaint sync --auto >/dev/null || true

date
echo "#setup portage" | tee /var/tmp/tb/task
emerge -1u sys-apps/portage

date
echo "#setup ansifilter" | tee /var/tmp/tb/task
USE="-gui" emerge -u app-text/ansifilter
sed -i -e 's,#PORTAGE_LOG_FILTER_FILE_CMD,PORTAGE_LOG_FILTER_FILE_CMD,' /etc/portage/make.conf

# emerge MTA before MUA b/c virtual/mta does not default to sSMTP
date
echo "#setup Mail" | tee /var/tmp/tb/task
emerge -u mail-mta/ssmtp
rm /etc/ssmtp/._cfg0000_ssmtp.conf    # use the already bind mounted file instead
emerge -u mail-client/mailx

date
echo "#setup kernel" | tee /var/tmp/tb/task
emerge -u sys-kernel/gentoo-kernel-bin

date
echo "#setup tools" | tee /var/tmp/tb/task
emerge -u app-arch/xz-utils app-portage/portage-utils www-client/pybugz

date
echo "#setup pfl" | tee /var/tmp/tb/task
USE="-network-cron" emerge -u app-portage/pfl

# sam_
if [[ $((RANDOM % 40)) -eq 0 ]]; then
  date
  echo "#setup slibtool" | tee /var/tmp/tb/task
  emerge -u dev-build/slibtool
  cat <<EOF2 >>/etc/portage/make.conf

LIBTOOL="rdlibtool"
MAKEFLAGS="LIBTOOL=\\\${LIBTOOL}"

EOF2
fi

if ls -l /etc/**/._cfg0000_* 2>/dev/null 1>&2; then
  echo -e "\n ^^ unexpected config file changes\n" >&2
  exit 1
fi

date
echo "#setup profile" | tee /var/tmp/tb/task
eselect profile set --force default/linux/amd64/$profile

sed -i -e 's,EMERGE_DEFAULT_OPTS=",EMERGE_DEFAULT_OPTS="--deep ,' /etc/portage/make.conf

if [[ $testfeature == "y" ]]; then
  sed -i -e 's,FEATURES=",FEATURES="test ,' /etc/portage/make.conf
fi

date
echo "#setup backlog" | tee /var/tmp/tb/task
# "sort -u" is needed if a package is in several repositories
qsearch --all --nocolor --name-only --quiet | grep -v -f /mnt/tb/data/IGNORE_PACKAGES | sort -u | shuf >/var/tmp/tb/backlog

date
echo "#setup done" | tee /var/tmp/tb/task

EOF

  chmod u+x ./var/tmp/tb/setup.sh
}

function RunSetupScript() {
  echo "$(date) ${FUNCNAME[0]} ..."

  echo '/var/tmp/tb/setup.sh &>/var/tmp/tb/setup.sh.log' >./var/tmp/tb/setup_wrapper.sh
  chmod u+x ./var/tmp/tb/setup_wrapper.sh
  if nice -n 3 $(dirname $0)/bwrap.sh -m $name -e ~tinderbox/img/$name/var/tmp/tb/setup_wrapper.sh; then
    if grep -m 1 ' Invalid atom ' ./var/tmp/tb/setup.sh.log; then
      echo -e "$(date)   OK - but ^^"
      return 1
    fi
  else
    echo -e "$(date)   FAILED"
    tail -n 100 ./var/tmp/tb/setup.sh.log
    echo
    return 1
  fi
  if grep -h -F ' * IMPORTANT: config file ' ./var/tmp/tb/setup.sh.log | grep -v '/etc/ssmtp/ssmtp.conf'; then
    return 1
  fi
}

function RunDryrunWrapper() {
  echo "$1" | tee ./var/tmp/tb/task

  if nice -n 3 $(dirname $0)/bwrap.sh -m $name -e ~tinderbox/img/$name/var/tmp/tb/dryrun_wrapper.sh &>$drylog; then
    if grep -q 'WARNING: One or more updates/rebuilds have been skipped due to a dependency conflict:' $drylog; then
      return 1
    fi

    for i in net-libs/libmbim x11-libs/pango; do
      if grep -Eo "^\[ebuild .*(dev-lang/perl|$i|dev-perl/Locale-gettext)" $drylog |
        cut -f 2- -d ']' |
        awk '{ print $1 }' |
        xargs |
        grep -q -F "dev-perl/Locale-gettext $i dev-lang/perl"; then
        # for sam: check if this has less packages than the previous candidate
        local n=$(grep -Eo "^Total: .* packages" $drylog | tail -n 1 | awk '{ print $2 }')
        if [[ $n -lt 201 ]]; then
          echo -e "$(date) Perl dep issue for $i n=$n" | tee ~tinderbox/img/$name/var/tmp/tb/KEEP
          exit 42
        fi
        return 1
      fi
    done

    echo " OK"
    return 0

  elif [[ -s $drylog ]]; then
    return 1

  else
    echo -e "\n sth. fatal happened\n" >&2
    exit 1
  fi
}

function FixPossibleUseFlagIssues() {
  local attempt=$1

  if RunDryrunWrapper "#setup dryrun $attempt"; then
    return 0
  fi

  # try few (dozen) times to fix the current diced setup
  for i in $(seq -w 1 29); do

    for k in EOL STOP; do
      if [[ -f ./var/tmp/tb/$k ]]; then
        echo -e "\n found $k file"
        exit 1
      fi
    done

    # kick off one package from the package specific use flag file
    local pn=$(
      grep -m 1 -A 1 'The ebuild selected to satisfy .* has unmet requirements.' $drylog |
        awk '/^- / { print $2 }' |
        cut -f 1 -d ':' -s |
        xargs -r qatom -F "%{CATEGORY}/%{PN}" |
        grep -v -F '<unset>/'
    )

    if [[ -n $pn ]]; then
      local f=./etc/portage/package.use/24thrown_package_use_flags
      if grep -q "^${pn} " $f; then
        sed -i -e "/$(sed -e 's,/,\\/,' <<<$pn) /d" $f
        if RunDryrunWrapper "#setup dryrun $attempt-$i # unmet req: $pn"; then
          return 0
        fi
      fi
    fi

    local f_temp=./tmp/fix-use-flags
    local msg=""

    # work on lines like:   - sys-cluster/mpich-3.4.3 (Change USE: -valgrind)
    local f_circ_flag=./etc/portage/package.use/27-$attempt-$i-a-circ-dep
    local f_circ_test=./etc/portage/package.env/27-$attempt-$i-notest-a-circ-dep
    rm -f $f_temp
    grep -m 1 -A 20 "It might be possible to break this cycle" $drylog |
      grep '^- .* (Change USE: ' |
      sed -e "s,^- ,," -e "s, (Change USE:,," -e "s,)$,," |
      grep -v -e 'abi_x86_32' -e '_target' -e 'video_cards_' |
      while read -r p f; do
        local pn=$(qatom -F "%{CATEGORY}/%{PN}" $p)
        for flag in $f; do
          # allow only unsetting a flag
          if [[ $flag != "-*" ]]; then
            continue
          fi
          if [[ $flag == "-test" ]]; then
            if ! grep -q "^${pn}  .*notest" ./etc/portage/package.env/*; then
              printf "%-36s notest\n" $pn >>$f_circ_test
            fi
          elif ! grep -q "^${pn}  .*$flag" ./etc/portage/package.use/*; then
            printf "%-36s %s\n" $pn $flag >>$f_temp
          fi
        done
      done

    if [[ -s $f_temp || -s $f_circ_test ]]; then
      if [[ -s $f_temp ]]; then
        mv $f_temp $f_circ_flag
        msg+=" # circ dep: $(xargs <$f_circ_flag)"
      fi
      if [[ -s $f_circ_test ]]; then
        msg+=" # notest: $(xargs <$f_circ_test)"
      fi
      if RunDryrunWrapper "#setup dryrun $attempt-$i $msg"; then
        return 0
      fi
    fi

    # work on lines starting like  >=dev-libs/xmlsec-1.3.4 openssl
    local f_nec_flag=./etc/portage/package.use/27-$attempt-$i-b-necessary-use-flag
    local f_nec_test=./etc/portage/package.env/27-$attempt-$i-notest-b-necessary-use-flag
    rm -f $f_temp
    grep -A 300 'The following USE changes are necessary to proceed:' $drylog |
      grep '^>=.* .*' |
      grep -v -e 'abi_x86_32' -e '_target' -e 'video_cards_' |
      while read -r p f; do
        pn=$(qatom -F "%{CATEGORY}/%{PN}" $p)
        for flag in $f; do
          if [[ $flag =~ test ]]; then
            if grep -q "^${pn}  .*notest" ./etc/portage/package.env/*; then
              printf "%-36s notest\n" $pn >>$f_nec_test
            fi
          elif ! grep -q "^${pn}  .*$flag" ./etc/portage/package.use/*; then
            printf "%-36s %s\n" $pn $flag >>$f_temp
          fi
        done
      done

    if [[ -s $f_temp || -s $f_nec_test ]]; then

      if [[ -s $f_temp ]]; then
        mv $f_temp $f_nec_flag
        msg+=" # necessary: $(xargs <$f_nec_flag)"
      fi
      if [[ -s $f_nec_test ]]; then
        msg+=" # notest: $(xargs <$f_nec_test)"
      fi
      if RunDryrunWrapper "#setup dryrun $attempt-$i $msg"; then
        return 0
      fi
    fi

    # if no changes were found (and tested) then give up
    if [[ ! -s $f_circ_flag && ! -s $f_circ_test && ! -s $f_nec_flag && ! -s $f_nec_test ]]; then
      break
    fi
  done

  # keep the notest
  rm -f ./etc/portage/package.use/27-*-*
  return 1
}

# helper of ThrowFlags
function ShuffleUseFlags() {
  local max=$1      # pick up to $max
  local mask=$2     # mask about $mask of them
  local min=${3:-0} # pick up at least $min

  shuf -n $((RANDOM % (max - min + 1) + min)) |
    sort |
    while read -r flag; do
      if dice $mask $max; then
        echo -n "-"
      fi
      echo -n "$flag "
    done
}

# throw USE flags till a dry run of @world succeeds
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
    grep -v -x -f $tbhome/tb/data/IGNORE_USE_FLAGS |
    ShuffleUseFlags 100 6 30 |
    xargs -s 73 |
    sed -e "s,^,*/*  ," >./etc/portage/package.use/23thrown_global_use_flags

  grep -Hl 'flag name="' .$reposdir/gentoo/*/*/metadata.xml |
    grep -v -f $tbhome/tb/data/IGNORE_PACKAGES |
    shuf -n $((RANDOM % 1500 + 700)) |
    sort |
    while read -r file; do
      pn=$(cut -f 6-7 -d '/' -s <<<$file)
      grep 'flag name="' $file |
        grep -v -i -F -e 'UNSUPPORTED' -e 'UNSTABLE' -e '(requires' |
        cut -f 2 -d '"' -s |
        grep -v -x -f $tbhome/tb/data/IGNORE_USE_FLAGS |
        ShuffleUseFlags 9 3 |
        xargs |
        xargs -I {} -r printf "%-36s %s\n" "$pn" "{}"
    done >./etc/portage/package.use/24thrown_package_use_flags
}

function CompileUseFlagFiles() {
  echo "$(date) ${FUNCNAME[0]} ..."

  cat <<EOF >./var/tmp/tb/dryrun_wrapper.sh
set -euf

echo "# start dryrun"
EOF

  cat <<EOF >>./var/tmp/tb/dryrun_wrapper.sh
#!/bin/bash

cat /var/tmp/tb/task
echo "-------"
EOF
  if [[ $profile =~ "/llvm" ]]; then
    cat <<EOF >>./var/tmp/tb/dryrun_wrapper.sh
emerge -1 --selective=n --deep=0 -u =\$(portageq best_visible / sys-devel/clang) =\$(portageq best_visible / sys-devel/llvm) --pretend
echo "-------"
emerge -u @world --backtrack=50 --pretend
EOF
  elif [[ $profile =~ '23.0/no-multilib/hardened' ]]; then
    cat <<EOF >>./var/tmp/tb/dryrun_wrapper.sh
emerge -1 --selective=n --deep=0 -u =\$(portageq best_visible / sys-devel/gcc) sys-devel/binutils sys-libs/glibc --pretend
echo "-------"
emerge -e @world --pretend
EOF
  else
    cat <<EOF >>./var/tmp/tb/dryrun_wrapper.sh
emerge -1 --selective=n --deep=0 -u =\$(portageq best_visible / sys-devel/gcc) --pretend
echo "-------"
emerge -u @world --backtrack=50 --pretend
EOF
  fi
  cat <<EOF >>./var/tmp/tb/dryrun_wrapper.sh
echo "-------"
EOF

  chmod u+x ./var/tmp/tb/dryrun_wrapper.sh
  local drylog=./var/tmp/tb/logs/dryrun.log
  rm -f ./var/tmp/tb/logs/dryrun{,.*}.log

  if [[ -n $useconfigof ]]; then
    echo
    date
    echo " +++  run dryrun once using config of $useconfigof  +++"
    if [[ $useconfigof != "me" ]]; then
      if [[ $(basename $useconfigof) != $(basename $name) ]]; then
        for i in accept_keywords env mask unmask use; do
          cp ~tinderbox/img/$(basename $useconfigof)/etc/portage/package.$i/* ./etc/portage/package.$i/
        done
      fi
    fi
    if FixPossibleUseFlagIssues 0; then
      return 0
    fi
  else
    local attempt=0
    while [[ $((++attempt)) -le 175 ]]; do
      echo
      date
      echo "==========================================================="
      ThrowFlags $attempt
      local current=./var/tmp/tb/logs/dryrun.$(printf "%03i" $attempt).log
      touch $current
      ln -f $current $drylog
      if FixPossibleUseFlagIssues $attempt; then
        return 0
      fi
    done
    echo -e "\n max attempts reached, giving up"
  fi
  return 125
}

function Finalize() {
  echo "$(date) ${FUNCNAME[0]} ..."

  cp $tbhome/tb/conf/bashrc ./etc/portage

  if ! wc -l -w ./etc/portage/package.use/2* 2>/dev/null; then
    echo -e "\n no image specific USE flags"
  fi

  if [[ $start_it == "y" ]]; then
    cd $tbhome/run
    ln -sf ../img/$name
    sleep 1 # reap recently used cgroup
    echo
    sudo -u tinderbox $(dirname $0)/start_img.sh $name
    echo
  fi
}

#############################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

trace_file=/tmp/$(basename $0).trace.$$.log
exec 42>$trace_file
BASH_XTRACEFD="42"
set -x

trap Exit INT QUIT TERM EXIT
echo -e "\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++$(date)\n $0 start"

tbhome=~tinderbox
reposdir=/var/db/repos

InitOptions
while getopts R:a:k:p:m:M:st:u: opt; do
  case $opt in
  R)
    cd $tbhome/img/$(basename $OPTARG)
    name=$(cat ./var/tmp/tb/name)
    profile=$(readlink ./etc/portage/make.profile | sed -e 's,.*amd64/,,')
    useconfigof="me"
    [[ $name =~ "_test" ]] && testfeature="y"
    [[ $name =~ "_abi32+64" ]] && abi3264="y"
    cd ./var/db/repos/gentoo
    git pull -q
    cd - 1>/dev/null
    CompileUseFlagFiles
    Finalize
    exit 0
    ;;
  a) abi3264="$OPTARG" ;;                                       # "y" or "n"
  k) keyword="$OPTARG" ;;                                       # "amd64"
  p) profile=$(sed -e 's,default/linux/amd64/,,' <<<$OPTARG) ;; # "23.0/desktop"
  s) start_it="y" ;;
  t) testfeature="$OPTARG" ;; # "y" or "n"
  u) useconfigof="$OPTARG" ;; # "me" or e.g. "23.0_desktop_systemd-20230624-014416"
  *)
    echo "unknown parameter '$opt'"
    exit 1
    ;;
  esac
done

CheckOptions
InitImageFromStage3
InitRepository
CompileTinderboxFiles
CompilePortageFiles
CompileMakeConf
CompileMiscFiles
CreateBacklogs
CreateSetupScript
RunSetupScript
set +x
CompileUseFlagFiles
set -x
Finalize
