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
    echo -e "$(date)  setup FAILED for $name with rc=$rc"
  fi
  echo -e "\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
  mv $trace_file $tbhome/img/$name/var/tmp/tb/
  exit $rc
}

# $1:$2, e.g. 3:5
function dice() {
  ((RANDOM % $2 < $1))
}

# helper of InitOptions()
function DiceAProfile() {
  eselect profile list |
    grep '/23.0' |
    grep -v -F -e '/llvm' -e '/musl' -e '/prefix' -e '/selinux' -e '/split-usr' -e '/x32' -e ' (exp)' |
    awk '{ print $2 }' |
    cut -f 4- -d '/' -s |
    shuf -n 1
}

# helper of main()
function InitOptions() {
  echo "$(date) ${FUNCNAME[0]} ..."

  # const
  cflags_default="-O2 -pipe -march=native -fno-diagnostics-color"

  abi3264="n"
  cflags=$cflags_default
  keyword="~amd64"
  ldflags=""
  name="n/a"
  profile=""
  start_it="n"
  testfeature="n"
  useconfigof=""

  # play with -O
  if dice 1 6; then
    if dice 1 3; then
      # used by debug_img.sh
      local debug_flavour=$(xargs -n 1 <<<"1 gdb gdb3" | shuf -n 1)
      cflags=$(sed -e "s,-O2,-Og -g -g$debug_flavour," <<<$cflags)
    else
      # sam_
      local opt_flavour=$(xargs -n 1 <<<"3 s z" | shuf -n 1)
      cflags=$(sed -e "s,-O2,-O$opt_flavour," <<<$cflags)
    fi
  fi

  # /me
  if dice 1 6; then
    cflags+=" -ftrivial-auto-var-init=zero"
  fi

  if dice 1 40; then
    # this sets "*/* ABI_X86: 32 64" via package.use.40abi32+64
    abi3264="y"
  fi

  if dice 1 20; then
    testfeature="y"
  fi
}

function SetProfile() {
  if [[ -z $profile ]]; then
    profile=$(DiceAProfile)
  fi

  # sam_
  if [[ ! $profile =~ "/llvm" ]]; then
    if dice 1 4; then
      ldflags=" -Werror=lto-type-mismatch -Werror=strict-aliasing -Werror=odr -flto"
      cflags+="$ldflags"
    fi
  fi

  if [[ $profile =~ "/no-multilib" ]]; then
    abi3264="n"
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

  if [[ $profile =~ /$ ]]; then
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

  if [[ -n $useconfigof ]]; then
    if [[ ! -d ~tinderbox/img/$useconfigof/etc/portage/ ]]; then
      echo " wrong useconfigof: >>$useconfigof<<"
      return 1
    fi
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

  if [[ $profile =~ '/no-multilib/hardened' ]]; then
    # there's no dedicated stage3, use a 23.0/hardened therefore and switch afterwards
    prefix=$(sed -e 's,nomultilib-,,' <<<$prefix)
  fi

  echo "$(date)   get stage3 file name for prefix $prefix"

  if ! stage3=$(grep -o "^20.*/$prefix-20.*T.*Z\.tar\.\w*" $stage3_list); then
    echo "$(date)   failed"
    return 1
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

  stage3_list="$tbhome/distfiles/latest-stage3.txt"
  mirrors=$(
    source /etc/portage/make.conf
    echo ${GENTOO_MIRRORS:-http://distfiles.gentoo.org}
  )
  mirror_path="releases/amd64/autobuilds"

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

  # the directory has yet the timestamp of the stage3
  touch ~tinderbox/img/$name
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

  mkdir -p ./mnt/tb/data ./var/tmp/tb/{,logs} ./var/cache/distfiles
  echo $EPOCHSECONDS >./var/tmp/tb/setup.timestamp
  echo $name >./var/tmp/tb/name
  chmod a+wx ./var/tmp/tb/
}

# compile make.conf
function CompileMakeConf() {
  echo "$(date) ${FUNCNAME[0]} ..."

  cat <<EOF >./etc/portage/make.conf
LC_MESSAGES=C

# by ztrawhcse:
# set MAKEOPTS="-O" in make.conf as a new setting - this will then be safely appended by package.env
# start off with a base value of -O, and that causes log files to buffer
# when make executes a rule, it will store command output in a pipe and then log all the output at the same time instead of multiple commands concurrently writing to the same log file and getting ... corrupted.
MAKEOPTS="-O"

# set these explicitely here (instead e.g. CXXFLAGS="\$CFLAGS" and so on ...)
CFLAGS="$cflags"
CXXFLAGS="$cflags"
FCFLAGS="$cflags"
FFLAGS="$cflags"

# enable QA check for LDFLAGS being respected by build system
LDFLAGS="\$LDFLAGS -Wl,--defsym=__gentoo_check_ldflags__=0$ldflags"

ACCEPT_KEYWORDS="$keyword"

# just tinderbox'ing, no re-distribution nor any kind of "use"
ACCEPT_LICENSE="* -@EULA"

# no manual interaction
ACCEPT_PROPERTIES="-interactive"
ACCEPT_RESTRICT="-fetch"

FEATURES="-news xattr"
EMERGE_DEFAULT_OPTS="--newuse --changed-use --verbose --verbose-conflicts --nospinner --quiet-build --tree --color=n --ask=n"

CLEAN_DELAY=0
PKGSYSTEM_ENABLE_FSYNC=0

PORT_LOGDIR="/var/log/portage"

PORTAGE_ELOG_CLASSES="qa"
PORTAGE_ELOG_SYSTEM="save"
PORTAGE_ELOG_MAILURI="tinderbox@localhost"
PORTAGE_ELOG_MAILFROM="$name <tinderbox@localhost>"

PORTAGE_LOG_FILTER_FILE_CMD="bash -c 'ansifilter 2>/dev/null; exec cat'"

GENTOO_MIRRORS="$mirrors"

EOF

  if [[ $cflags =~ " -g " ]]; then
    sed -i -e 's,FEATURES=",FEATURES="splitdebug ,' ./etc/portage/make.conf
  fi

  # requested by mgorny (this is unrelated to FEATURES="test")
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

  echo 'SANDBOX_WRITE="/dev/steve"' >./etc/sandbox.d/90steve
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

  # https://bugs.gentoo.org/903921
  echo 'EXTRA_ECONF="DEFAULT_ARCHIVE=/dev/null/BAD_TAR_INVOCATION"' >./etc/portage/env/bad_tar

  # handle broken setup or particular package issue
  echo 'FEATURES="-test -test-full -test-rust -test-suite"' >./etc/portage/env/notest

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

  # replace_img.sh defaults to nproc/3 images, so set make default +1 higher
  # "j1" is the fallback for packages failing with parallel build
  for j in 1 4; do
    cat <<EOF >./etc/portage/env/j$j
MAKEOPTS="\$MAKEOPTS -j$j"

OMP_DYNAMIC=FALSE
OMP_NESTED=FALSE
OMP_NUM_THREADS=$j

RUST_TEST_THREADS=$j
RUST_TEST_TASKS=$j

EOF
  done

  cp ./etc/portage/env/j4 ./etc/portage/env/j4-no-jobserver
  cat <<EOF >>./etc/portage/env/j4
MAKEFLAGS="--jobserver-auth=fifo:/dev/steve"
NINJAOPTS=""

EOF
  printf "%-35s %s\n" '*/*' "j4" >>./etc/portage/package.env/00jobs

  if [[ $keyword == '~amd64' ]]; then
    cpconf $tbhome/tb/conf/package.*.??unstable
  else
    cpconf $tbhome/tb/conf/package.*.??stable
  fi

  if [[ $profile =~ "/llvm" ]]; then
    cpconf $tbhome/tb/conf/package.*.??llvm
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

  # take lines tagged with "# DICE: <topic>[ <m> <N>]" with an m/N chance (default: 50%)
  grep -hrv "^#" ./etc/portage/package.* |
    grep -o '# DICE: .*' |
    cut -f 3- -d ' ' |
    sort -u |
    tr -d '][' |
    while read -r topic m N; do
      if ! dice ${m:-1} ${N:-2}; then
        sed -i \
          -e "/# DICE: $topic$/d" -e "/# DICE: $topic /d" \
          -e "/# DICE: \[$topic\]$/d" -e "/# DICE: \[$topic\] /d" \
          ./etc/portage/package.*/*
      fi
    done

  echo "*/*  $(cpuid2cpuflags)" >./etc/portage/package.use/99cpuflags

  for f in "$tbhome"/tb/conf/profile.*; do
    local target=./etc/portage/profile/$(basename $f | sed -e 's,profile.,,')
    cp $f $target
    chmod a+r $target
  done

  if [[ $cflags =~ " -g " ]]; then
    if ! dice 1 1; then
      cat <<EOF >./etc/portage/env/build-id
# https://bugs.gentoo.org/953869
EXTRA_ECONF="\${EXTRA_ECONF} --enable-linker-build-id"
EOF
      printf "%-35s %s\n" "sys-devel/gcc" "build-id" >>./etc/portage/package.env/91build-id
    fi
  fi

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
@world sys-kernel/gentoo-kernel-bin
%emerge -1u --selective=n --deep=0 =\$(portageq best_visible / llvm-core/clang) =\$(portageq best_visible / llvm-core/llvm)
EOF
  elif [[ $profile =~ '/no-multilib/hardened' ]]; then
    # [11:06:37 pm] <@toralf> Would changing the profile and re-emerging @world with --emptytree do it?
    # [11:27:13 pm] <@dilfridge> switching from/to hardened, and switching from multilib to non-multilib, yes
    # [11:27:31 pm] <@dilfridge> switching from non-multilib to multilib, NO
    cat <<EOF >>$bl.1st
%emerge -e @world sys-kernel/gentoo-kernel-bin
%emerge -1u --selective=n --deep=0 =\$(portageq best_visible / sys-devel/gcc) sys-devel/binutils sys-libs/glibc
EOF
  else
    cat <<EOF >>$bl.1st
@world sys-kernel/gentoo-kernel-bin
%emerge -1u --selective=n --deep=0 =\$(portageq best_visible / sys-devel/gcc)
EOF
  fi
}

function CreateSetupScript() {
  echo "$(date) ${FUNCNAME[0]} ..."

  local mta
  if dice 1 2; then
    mta=msmtp
  else
    mta=ssmtp
  fi
  printf "%-35s %s\n" "mail-mta/$mta" "ssl" >>./etc/portage/package.use/91$mta

  cat <<EOF >./var/tmp/tb/setup.sh
#!/bin/bash
set -x

export LANG=C.utf8
set -euf

date
echo $name

export NO_COLOR=1

# use same user and group id of user tinderbox like at the host to edit files from a host shell
date
echo "#setup user" | tee /var/tmp/tb/task
groupadd -g $(id -g tinderbox) tinderbox
useradd -g $(id -g tinderbox) -u $(id -u tinderbox) -G portage tinderbox
emerge -u acct-group/jobserver acct-user/steve
usermod -a -G jobserver portage

if [[ ! $profile =~ "/musl" ]]; then
  if ((RANDOM % 2 < 1)); then
    cat <<EOF2 >>/etc/locale.gen
en_US ISO-8859-1
# needed by Dotnet SDK
en_US UTF-8
EOF2
  fi

  if [[ $testfeature == "y" ]]; then
    cat <<EOF2 >>/etc/locale.gen
# needed for +test
en_US UTF-8
EOF2
  fi

  date
  echo "#setup locale" | tee /var/tmp/tb/task
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
USE="-cgi -cvs -mediawiki -mediawiki-experimental -perl -subversion -webdav -xinetd -curl_quic_openssl -http2 -http3 -quic ssl" emerge -u dev-vcs/git

date
echo "#setup sync" | tee /var/tmp/tb/task
emaint sync --auto >/dev/null || true

date
echo "#setup portage" | tee /var/tmp/tb/task
emerge -1u sys-apps/portage

echo "#cert setup" | tee /var/tmp/tb/task
update-ca-certificates

# emerge MTA, otherwise the MUA would install nullmailer (the default MTA of virtual/mta)
date
echo "#setup $mta" | tee /var/tmp/tb/task
emerge -u mail-mta/$mta
rm -f /etc/ssmtp/._cfg0000_ssmtp.conf /etc/._cfg0000_msmtprc
emerge -u mail-client/mailx
if ! (msmtp --version 2>/dev/null || ssmtp -V 2>&1) | mail -s "$mta test @ $name" $(<$(dirname $0)/../sdata/mailto) &>/var/tmp/mail.log; then
  echo "\$(date) $mta test failed" >&2
  set +e
  tail -v /var/tmp/mail.log /var/log/msmtp.log >&2
  exit 3
fi

date
echo "#setup tools" | tee /var/tmp/tb/task
USE="-doc -gui -network-cron -qmanifest" emerge -u app-arch/xz-utils app-portage/smart-live-rebuild app-portage/pfl app-portage/portage-utils app-text/ansifilter app-text/recode www-client/pybugz
if [[ $keyword == "~amd64" ]]; then
  emerge -u app-portage/eschwartz-dev-scripts
fi

if [[ "$cflags" =~ " -g " ]]; then
  date
  echo "#setup debug" | tee /var/tmp/tb/task
  emerge -u dev-util/debugedit
fi

if find /etc -type f -name "._cfg0000_*" | grep '.'; then
  echo -e "\n ^^ unexpected changes\n" >&2
  exit 2
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
set +x
qsearch --all --nocolor --name-only --quiet | grep -v -f /mnt/tb/data/IGNORE_PACKAGES | sort -u | shuf >/var/tmp/tb/backlog
set -x

date
echo "#setup done" | tee /var/tmp/tb/task

EOF

  chmod u+x ./var/tmp/tb/setup.sh
}

function RunSetupScript() {
  echo "$(date) ${FUNCNAME[0]} ..."

  rm -f ./var/tmp/tb/setup_wrapper.sh
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
}

function RunDryrunWrapper() {
  for k in EOL STOP; do
    if [[ -f ./var/tmp/tb/$k ]]; then
      tail -v ./var/tmp/tb/$k
      exit 3
    fi
  done

  echo "#setup dryrun $attempt-$fix$1" | tee ./var/tmp/tb/task

  # keep all logs
  (
    cd ./var/tmp/tb/logs/
    current=dryrun.$attempt-$fix.log
    touch $current
    ln -sf $current ./dryrun.log
  )

  if nice -n 3 $(dirname $0)/bwrap.sh -m $name -e ~tinderbox/img/$name/var/tmp/tb/dryrun_wrapper.sh &>$drylog; then
    if grep -q 'WARNING: One or more updates/rebuilds have been skipped due to a dependency conflict:' $drylog; then
      return 1
    else
      echo -e " OK  $attempt-$fix  $name\n"
      return 0
    fi
  elif [[ -s $drylog ]]; then
    return 1
  else
    echo -e "\n FATAL issue\n" >&2
    exit 4
  fi
}

function ChangeIsForbidden() {
  local flag=${1?FLAG NOT GIVEN}

  [[ $flag =~ '_' || $flag == 'test' || $flag == '-test' ]] || grep -q -x $(tr -d '-' <<<$flag) $tbhome/tb/data/IGNORE_USE_FLAGS
}

function IsAlreadySetForPackage() {
  local flag=${1?FLAG NOT GIVEN}
  local pn=${2?PACKAGE NAME NOT GIVEN}

  grep -q -r \
    -e "^$pn  *-*$flag$" \
    -e "^$pn  *-*$flag " \
    -e "^$pn  *.* -*$flag$" \
    -e "^$pn  *.* -*$flag " \
    ./etc/portage/package.use/
}

function FixPossibleUseFlagIssues() {
  local attempt=$1

  for fix in $(seq -w 1 49); do
    local try_again=0
    local msg=""

    if RunDryrunWrapper "$msg"; then
      return 0
    fi

    ###################################################################
    #
    # remove a package from the diced use flags file
    #
    local atoms=$(
      awk '/The ebuild selected to satisfy .* has unmet requirements./,/^$/' $drylog |
        awk '/^- / { print $2 }' |
        cut -f 1 -d ':' -s |
        xargs -r qatom -CF "%{CATEGORY}/%{PN}" |
        grep -v '<unset>'
    )
    if [[ -n $atoms ]]; then
      local dpuf=./etc/portage/package.use/24-diced_package_use_flags
      local removed=""
      for pn in $atoms; do
        if grep -q "^$pn " $dpuf; then
          sed -i -e "/$(sed -e 's,/,\\/,' <<<$pn) /d" $dpuf
          removed+=" $pn"
        fi
      done
      if [[ -n $removed ]]; then
        msg+=" # unmet:$removed"
        if RunDryrunWrapper "$msg"; then
          return 0
        else
          try_again=1
        fi
      fi
    fi

    ###################################################################
    #
    # work on lines like:   >=dev-libs/xmlsec-1.3.4 openssl
    #
    local f_nec_flag=./etc/portage/package.use/27-$attempt-$fix-necessary-use-flag
    local f_nec_test=./etc/portage/package.env/27-$attempt-$fix-necessary-use-flag
    awk '/The following USE changes are necessary to proceed:/,/^$/' $drylog |
      grep -e "^>*=.* .*" |
      grep -v '(This .*' |
      sed -e 's, +, ,g' |
      while read -r p f; do
        if ! pn=$(qatom -CF "%{CATEGORY}/%{PN}" $p) || [[ $pn =~ '<unset>' ]]; then
          echo " nec-use wrong pn '$pn' for '$p'" >&2
          exit 1
        fi
        for flag in $f; do
          if ! ChangeIsForbidden $flag && ! IsAlreadySetForPackage $flag $pn; then
            printf "%-35s %s\n" $pn $flag >>$f_nec_flag
          fi
        done
      done

    if [[ -s $f_nec_flag || -s $f_nec_test ]]; then
      if [[ -s $f_nec_flag ]]; then
        msg+=" # necessary: $(xargs <$f_nec_flag)"
      fi
      if [[ -s $f_nec_test ]]; then
        msg+=" # notest: $(xargs <$f_nec_test)"
      fi
      if RunDryrunWrapper "$msg"; then
        return 0
      else
        try_again=1
      fi
    fi

    ###################################################################
    #
    # work on lines like:   - sys-cluster/mpich-3.4.3 (Change USE: -valgrind)
    #
    local f_circ_flag=./etc/portage/package.use/27-$attempt-$fix-circ-dep
    local f_circ_test=./etc/portage/package.env/27-$attempt-$fix-circ-dep
    awk '/It might be possible to /,/^$/' $drylog |
      grep -F " (Change USE: " |
      grep -v -F -e ', this change violates' -e '(This' |
      sed -e "s,^ *- ,," -e "s, (Change USE:,," -e "s,),," -e 's, +, ,g' |
      while read -r p f; do
        if ! pn=$(qatom -CF "%{CATEGORY}/%{PN}" $p) || [[ $pn =~ '<unset>' ]]; then
          echo " circ-dep wrong pn '$pn' for '$p'" >&2
          exit 1
        fi
        for flag in $f; do
          if ! ChangeIsForbidden $flag && ! IsAlreadySetForPackage $flag $pn; then
            printf "%-35s %s\n" $pn $flag >>$f_circ_flag
          fi
        done
      done

    if [[ -s $f_circ_flag || -s $f_circ_test ]]; then
      if [[ -s $f_circ_flag ]]; then
        msg+=" # circ dep: $(xargs <$f_circ_flag)"
      fi
      if [[ -s $f_circ_test ]]; then
        msg+=" # notest: $(xargs <$f_circ_test)"
      fi
      if RunDryrunWrapper "$msg"; then
        return 0
      else
        try_again=1
      fi
    fi

    if [[ $try_again -eq 0 ]]; then
      break
    fi
  done

  # reset only USE flags, keep env like "notest"
  rm -f ./etc/portage/package.use/27-$attempt-*-*-*
  return 1
}

# helper of ThrowFlags
function ShuffleUseFlags() {
  local max=$1      # pick up to $max
  local mask=$2     # mask about $mask of them
  local min=${3:-0} # pick up at least $min

  [[ $max -ge $mask && $max -ge $min ]] || return 1

  shuf -n $((RANDOM % (max - min) + min)) |
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
    xargs -I {} -r echo "*/*  L10N: {}" >./etc/portage/package.use/22-diced_l10n

  grep -v -e '^$' -e '^#' -e 'internal use only' .$reposdir/gentoo/profiles/use.desc |
    cut -f 1 -d ' ' -s |
    grep -v -x -f $tbhome/tb/data/IGNORE_USE_FLAGS |
    grep -v -e '.*_.*_' -e 'python3_' -e 'pypy3_' |
    ShuffleUseFlags 90 12 10 |
    xargs -s 73 |
    sed -e "s,^,*/*  ," >./etc/portage/package.use/23-diced_global_use_flags

  find .$reposdir/gentoo/ -name metadata.xml |
    grep -v -f $tbhome/tb/data/IGNORE_PACKAGES |
    xargs grep -Hl 'flag name="' |
    shuf -n $((RANDOM % 3000 + 500)) |
    sort |
    while read -r file; do
      pn=$(cut -f 6-7 -d '/' -s <<<$file)
      grep 'flag name="' $file |
        grep -v -i -F -e 'UNSUPPORTED' -e 'UNSTABLE' -e '(requires' |
        cut -f 2 -d '"' -s |
        sort -u |
        grep -v -x -f $tbhome/tb/data/IGNORE_USE_FLAGS |
        grep -v -e '.*_.*_' -e 'python3_' -e 'pypy3_' |
        ShuffleUseFlags 7 1 0 |
        xargs |
        xargs -I {} -r printf "%-35s %s\n" "$pn" "{}"
    done >./etc/portage/package.use/24-diced_package_use_flags
}

function CompileUseFlagFiles() {
  echo "$(date) ${FUNCNAME[0]} ..."

  local line="================================================================="
  rm -f ./var/tmp/tb/dryrun_wrapper.sh
  cat <<EOF >>./var/tmp/tb/dryrun_wrapper.sh
#!/bin/bash

set -euf

echo "# start dryrun"
cat /var/tmp/tb/task

export NO_COLOR=1

echo "$line"
EOF

  if [[ $profile =~ "/llvm" ]]; then
    cat <<EOF >>./var/tmp/tb/dryrun_wrapper.sh
emerge -1up --selective=n --deep=0 =\$(portageq best_visible / llvm-core/clang) =\$(portageq best_visible / llvm-core/llvm)
echo "$line"
emerge -up @world sys-kernel/gentoo-kernel-bin
EOF
  elif [[ $profile =~ '/no-multilib/hardened' ]]; then
    cat <<EOF >>./var/tmp/tb/dryrun_wrapper.sh
emerge -1up --selective=n --deep=0 =\$(portageq best_visible / sys-devel/gcc) sys-devel/binutils sys-libs/glibc
echo "$line"
emerge -ep @world sys-kernel/gentoo-kernel-bin
EOF
  else
    cat <<EOF >>./var/tmp/tb/dryrun_wrapper.sh
emerge -1up --selective=n --deep=0 =\$(portageq best_visible / sys-devel/gcc)
echo "$line"
emerge -up @world sys-kernel/gentoo-kernel-bin
EOF
  fi

  cat <<EOF >>./var/tmp/tb/dryrun_wrapper.sh
echo "$line"
EOF

  chmod u+x ./var/tmp/tb/dryrun_wrapper.sh
  rm -f ./var/tmp/tb/logs/dryrun{,.*-*}.log
  local drylog=./var/tmp/tb/logs/dryrun.log

  # rerun with same USE flags at a new system
  if [[ -n $useconfigof ]]; then
    if [[ $(realpath ~tinderbox/img/$useconfigof) != $(realpath .) ]]; then
      for i in accept_keywords env mask unmask use; do
        cp ~tinderbox/img/$useconfigof/etc/portage/package.$i/* ./etc/portage/package.$i/
      done
    else
      echo "cannot use from myself !" >&2
      return 1
    fi
    if FixPossibleUseFlagIssues 0; then
      return 0
    fi
    return 125
  fi

  # try without any thrown flags
  if dice 1 20; then
    if FixPossibleUseFlagIssues 0; then
      return 0
    fi
  fi

  # go wild
  for attempt in $(seq -w 1 199); do
    echo
    date
    echo "==========================================================="
    if [[ -z $useconfigof ]]; then
      ThrowFlags $attempt
    fi
    if FixPossibleUseFlagIssues $attempt; then
      return 0
    fi
  done
  echo -e "\n max attempts reached, GIVING UP"

  return 125
}

function Finalize() {
  echo "$(date) ${FUNCNAME[0]} ..."

  sed -e "s,^    vcpu=.*,    vcpu=$(nproc)," -e "s,^    load=.*,    load=$(($(nproc) * 5 / 4))," \
    $tbhome/tb/conf/bashrc >./etc/portage/bashrc

  if ! grep -q . ./etc/portage/package.use/2[347]* 2>/dev/null; then
    echo -e "\n NOTICE: no image specific USE flags"
  fi

  if [[ $start_it == "y" ]]; then
    cd $tbhome/run
    ln -sf ../img/$name
    sleep 1 # wait till used cgroup is gone
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
echo -e "\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n$(date) $0 start\n"

tbhome=~tinderbox
reposdir=/var/db/repos

InitOptions
while getopts R:a:k:p:m:M:st:u: opt; do
  case $opt in
  R)
    cd $tbhome/img/$(basename $OPTARG)
    name=$(<./var/tmp/tb/name)
    [[ $name =~ "_abi32+64" ]] && abi3264="y"
    [[ $name =~ "_test" ]] && testfeature="y"
    profile=$(readlink ./etc/portage/make.profile | sed -e 's,.*amd64/,,')
    start_it="y"
    rm -f ./var/tmp/tb/{EOL,STOP}

    CompileUseFlagFiles
    Finalize
    exit 0
    ;;
  a) abi3264="$OPTARG" ;;                                       # "n"
  k) keyword="$OPTARG" ;;                                       # "amd64"
  p) profile=$(sed -e 's,default/linux/amd64/,,' <<<$OPTARG) ;; # "23.0/desktop"
  s) start_it="y" ;;
  t) testfeature="$OPTARG" ;;             # "y"
  u) useconfigof="$(basename $OPTARG)" ;; # "23.0_desktop_systemd-20230624-014416"
  *)
    echo "unknown parameter '$opt'"
    exit 1
    ;;
  esac
done

SetProfile
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
CompileUseFlagFiles
Finalize
