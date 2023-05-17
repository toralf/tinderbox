#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# This is the tinderbox script itself.
# The main function is WorkOnTask().
# The remaining code just parses the output.
# That's all.

function stripQuotesAndMore() {
  # shellcheck disable=SC1112
  sed -e 's,['\''‘’"`•],,g'
}

# filter leftover of ansifilter
function filterPlainPext() {
  # UTF-2018+2019 (left+right single quotation mark)
  sed -e 's,\xE2\x80\x98,,g' -e 's,\xE2\x80\x99,,g' |
    perl -wne '
      s,\x00,\n,g;
      s,\r\n,\n,g;
      s,\r,\n,g;
      print;
  '
}

function Mail() {
  local subject=$(stripQuotesAndMore <<<$1 | strings -w | cut -c1-200 | tr '\n' ' ')
  local content=${2:-}

  if [[ -f $content ]]; then
    echo
    if [[ $(wc -l <$content) -gt 100 ]]; then
      echo -e " \n \n \n \n full content is in ~tinderbox/img/$name/$content\n \n \n"
      tail -n 100 $content
    else
      cat $content
    fi
  else
    echo -e "$content"
  fi |
    strings -w |
    sed -e 's,^>>>, >>>,' |
    if ! (mail -s "$subject  @  $name" ${MAILTO:-tinderbox} 1>/dev/null); then
      echo "$(date) mail issue, \$subject=$subject \$content=$content" >&2
    fi
}

# 13 triggers a replacement
function ReachedEndfOfLife() {
  local subject=${1:-"EOL"}
  local attachment=${2:-}

  echo "$subject" >>/var/tmp/tb/EOL
  chmod g+w /var/tmp/tb/EOL
  chgrp tinderbox /var/tmp/tb/EOL
  truncate -s 0 $taskfile
  subject+=", $(grep -c ' ::: completed emerge' /var/log/emerge.log 2>/dev/null) completed"
  local new=$(ls /var/tmp/tb/issues/*/.reported 2>/dev/null | wc -l)
  subject+=", $new new bug(s)"

  Finish 13 "$subject" $attachment
}

# this is the end ...
function Finish() {
  local exit_code=${1:-$?}
  local subject=${2:-"<INTERNAL ERROR>"}
  local attachment=${3:-}

  trap - INT QUIT TERM EXIT
  set +e

  subject="finished, $(stripQuotesAndMore <<<$subject)"
  Mail "$subject" $attachment
  if [[ $exit_code -ne 9 ]]; then
    /usr/bin/pfl &>/dev/null
  fi
  rm -f /var/tmp/tb/STOP
  exit $exit_code
}

# helper of getNextTask()
function setBacklog() {
  if [[ -s /var/tmp/tb/backlog.1st ]]; then
    backlog=/var/tmp/tb/backlog.1st

  elif [[ -s /var/tmp/tb/backlog.upd && $((RANDOM % 2)) -eq 0 ]]; then
    backlog=/var/tmp/tb/backlog.upd

  elif [[ -s /var/tmp/tb/backlog ]]; then
    backlog=/var/tmp/tb/backlog

  elif [[ -s /var/tmp/tb/backlog.upd ]]; then
    backlog=/var/tmp/tb/backlog.upd

  else
    ReachedEndfOfLife "all work DONE"
  fi
}

function getNextTask() {
  while :; do
    setBacklog

    # move last line of $backlog into $task
    task=$(tail -n 1 $backlog)
    sed -i -e '$d' $backlog

    if [[ -z $task || $task =~ ^# ]]; then
      continue

    elif [[ $task =~ ^EOL ]]; then
      ReachedEndfOfLife "$task"

    elif [[ $task =~ ^INFO ]]; then
      Mail "$task"
      continue

    elif [[ $task =~ ^STOP ]]; then
      Finish 0 "$task"

    elif [[ $task =~ ^@ || $task =~ ^% ]]; then
      break

    elif [[ $task =~ ^= ]]; then
      if portageq best_visible / $task &>/dev/null; then
        break
      fi

    else
      local best_visible=$(portageq best_visible / $task 2>/dev/null)
      if [[ $? -ne 0 || -z $best_visible ]]; then
        continue
      fi

      if [[ $backlog != /var/tmp/tb/backlog.1st ]]; then
        if grep -q -f /mnt/tb/data/IGNORE_PACKAGES <<<$best_visible; then
          continue
        fi
      fi

      # skip if $task would be downgraded
      local installed=$(portageq best_version / $task)
      if [[ -n $installed ]]; then
        if qatom --compare $installed $best_visible | grep -q -e ' == ' -e ' > '; then
          continue
        fi
      fi

      # valid $task
      break
    fi
  done
}

function CompressIssueFiles() {
  # shellcheck disable=SC2010
  ls $issuedir/files/ |
    grep -v -F '.bz2' |
    while read -r f; do
      # compress if bigger than 1/4 MB
      if [[ $(wc -c <$issuedir/files/$f) -gt $((2 ** 18)) ]]; then
        bzip2 $issuedir/files/$f
      fi
    done

  chmod 777 $issuedir/{,files}
  chmod -R a+rw $issuedir/ # allow manual editing of e.g. title/body
}

function CreateEmergeHistoryFile() {
  local ehist=$issuedir/files/emerge-history.txt
  local cmd="qlop --nocolor --verbose --merge --unmerge"

  cat <<EOF >$ehist
# This file contains the emerge history got with:
# $cmd
# at $(date)
EOF
  $cmd &>>$ehist
}

# gather together what's needed for the email and b.g.o.
function CollectIssueFiles() {
  apout=$(grep -m 1 -A 2 'Include in your bugreport the contents of' $tasklog_stripped | grep -F '.out' | cut -f5 -d' ' -s)
  cmlog=$(grep -m 1 -A 2 'Configuring incomplete, errors occurred' $tasklog_stripped | grep "CMake.*\.log" | cut -f2 -d'"' -s)
  cmerr=$(grep -m 1 'CMake Error: Parse error in cache file' $tasklog_stripped | sed "s/txt./txt/" | cut -f8 -d' ' -s)
  oracl=$(grep -m 1 -A 1 '# An error report file with more information is saved as' $tasklog_stripped | grep -F '.log' | cut -f2 -d' ' -s)
  envir=$(grep -m 1 'The ebuild environment file is located at' $tasklog_stripped | cut -f2 -d"'" -s)
  salso=$(grep -m 1 -A 2 ' See also' $tasklog_stripped | grep -F '.log' | awk '{ print $1 }')
  sandb=$(grep -m 1 -A 1 'ACCESS VIOLATION SUMMARY' $tasklog_stripped | grep "sandbox.*\.log" | cut -f2 -d'"' -s)
  roslg=$(grep -m 1 -A 1 'Tests failed. When you file a bug, please attach' $tasklog_stripped | grep -F '/LastTest.log' | awk '{ print $2 }')

  for f in $apout $cmlog $cmerr $oracl $envir $salso $sandb $roslg; do
    if [[ -s $f ]]; then
      cp $f $issuedir/files
    fi
  done

  if [[ -d $workdir ]]; then
    # catch relevant logs
    (
      f=/var/tmp/tb/files
      cd "$workdir/.."
      find ./ -name "*.log" \
        -o -name "testlog.*" \
        -o -wholename "./temp/syml*" \
        -o -wholename '*/elf/*.out' \
        -o -wholename '*/softmmu-build/*' \
        -o -name "meson-log.txt" |
        sort -u >$f
      if [[ -s $f ]]; then
        $gtar -cjpf $issuedir/files/logs.tar.bz2 \
          --dereference \
          --warning='no-all' \
          --files-from $f 2>/dev/null
      fi
      rm $f
    )

    # by Flow
    if [[ $pkg =~ "dev-java/scala-cli-bin" ]]; then
      cat /proc/self/cgroup >$issuedir/files/proc_self_cgroup.txt
    fi

    if [[ -d /var/tmp/clang/$pkg ]]; then
      tar -C /var/tmp/clang/ -cjpf $issuedir/files/var.tmp.clang.tar.bz2 ./$pkg 2>/dev/null
    fi
    if [[ -d /etc/clang ]]; then
      tar -C /etc -cjpf $issuedir/files/etc.clang.tar.bz2 ./clang 2>/dev/null
    fi

    # additional CMake files
    cp ${workdir}/*/CMakeCache.txt $issuedir/files/ 2>/dev/null

    # provide the whole temp dir if possible
    (
      cd "$workdir/../.."
      if [[ -d ./temp ]]; then
        timeout --signal=15 --kill-after=1m 3m $gtar --warning=none -cjpf $issuedir/files/temp.tar.bz2 \
          --dereference \
          --warning='no-all' \
          --exclude='*/garbage.*' \
          --exclude='*/go-build[0-9]*/*' \
          --exclude='*/go-cache/??/*' \
          --exclude='*/kerneldir/*' \
          --exclude='*/nested_link_to_dir/*' \
          --exclude='*/syml*' \
          --exclude='*/testdirsymlink/*' \
          --exclude='*/var-tests/*' \
          ./temp
      fi
    )

    # ICE
    cp $workdir/../gcc-build-logs.tar.bz2 $issuedir/files 2>/dev/null
  fi
}

# helper of ClassifyIssue()
function foundCollisionIssue() {
  # get the colliding package name
  local s=$(
    grep -m 1 -A 5 'Press Ctrl-C to Stop' $tasklog_stripped |
      tee -a $issuedir/issue |
      grep -m 1 '::' | tr ':' ' ' | cut -f3 -d' ' -s
  )
  echo "file collision with $s" >$issuedir/title
}

# helper of ClassifyIssue()
function foundSandboxIssue() {
  if ! grep -q "=$pkg " /etc/portage/package.env/nosandbox 2>/dev/null; then
    printf "%-50s %s\n" "<=$pkg" "nosandbox" >>/etc/portage/package.env/nosandbox
    try_again=1
  fi
  echo "sandbox issue" >$issuedir/title
  if [[ -s $sandb ]]; then
    head -v -n 20 $sandb &>$issuedir/issue
  else
    echo "cannot found $sandb" >$issuedir/issue
  fi
}

# helper of ClassifyIssue()
function foundCflagsIssue() {
  if ! grep -q "=$pkg " /etc/portage/package.env/cflags_default 2>/dev/null; then
    printf "%-50s %s\n" "<=$pkg" "cflags_default" >>/etc/portage/package.env/cflags_default
    try_again=1
  fi
  echo "$1" >$issuedir/title
}

# helper of ClassifyIssue()
function foundGenericIssue() {
  # the order of the pattern within the file/s rules
  (
    cat /mnt/tb/data/CATCH_ISSUES-pre
    if [[ -n $phase ]]; then
      cat /mnt/tb/data/CATCH_ISSUES.$phase
    fi
    cat /mnt/tb/data/CATCH_ISSUES-post
  ) |
    split --lines=1 --suffix-length=4 - /tmp/x_

  for x in /tmp/x_????; do
    if grep -a -m 1 -B 6 -A 2 -f $x $pkglog_stripped >/tmp/issue; then
      mv /tmp/issue $issuedir/issue
      grep -m 1 -f $x $issuedir/issue | stripQuotesAndMore >$issuedir/title
      break
    fi
    rm /tmp/issue
  done
  rm /tmp/x_????
}

# helper of ClassifyIssue()
function handleTestPhase() {
  if grep -q "=$pkg " /etc/portage/package.env/test-fail-continue 2>/dev/null; then
    if ! grep -q "=$pkg " /etc/portage/package.env/notest 2>/dev/null; then
      printf "%-50s %s\n" "<=$pkg" "notest" >>/etc/portage/package.env/notest
      try_again=1
    fi
  else
    printf "%-50s %s\n" "<=$pkg" "test-fail-continue" >>/etc/portage/package.env/test-fail-continue
    try_again=1
  fi

  # gtar returns an error if it can't find any directory, therefore feed only existing dirs to it
  pushd "$workdir" 1>/dev/null
  local dirs="$(ls -d ./tests ./regress ./t ./Testing ./testsuite.dir 2>/dev/null)"
  if [[ -n $dirs ]]; then
    # ignore stderr, eg.:    tar: ./automake-1.13.4/t/instspc.dir/a: Cannot stat: No such file or directory
    timeout --signal=15 --kill-after=1m 3m $gtar --warning=none -cjpf $issuedir/files/tests.tar.bz2 \
      --exclude="*/dev/*" --exclude="*/proc/*" --exclude="*/sys/*" --exclude="*/run/*" \
      --exclude='*.o' --exclude="*/symlinktest/*" \
      --dereference --sparse --one-file-system \
      $dirs 2>/dev/null
  fi
  popd 1>/dev/null
}

# helper of WorkAtIssue()
# get the issue and a descriptive title
function ClassifyIssue() {
  if [[ $phase == "test" ]]; then
    handleTestPhase
  fi

  if grep -q -m 1 -F ' * Detected file collision(s):' $pkglog_stripped; then
    foundCollisionIssue

  elif [[ -n $sandb ]]; then # no "-f" b/c it might not exist
    foundSandboxIssue

  # special forced issues
  elif [[ -n "$(grep -m 1 -B 4 -A 1 -e 'sed:.*expression.*unknown option' -e 'error:.*falign-functions=32:25:16' $pkglog_stripped | tee $issuedir/issue)" ]]; then
    foundCflagsIssue 'ebuild uses colon (:) as a sed delimiter'

  else
    # this gets been overwritten if a pattern matches
    grep -m 1 -A 2 "^ \* ERROR:.* failed \(.* phase\):" $pkglog_stripped | tee $issuedir/issue |
      head -n 2 | tail -n 1 >$issuedir/title
    foundGenericIssue
  fi

  if [[ $(wc -c <$issuedir/issue) -gt 1024 ]]; then
    echo -e "too long lines were shrinked:\n" >/tmp/issue
    cut -c-300 <$issuedir/issue >>/tmp/issue
    mv /tmp/issue $issuedir/issue
  fi

  if [[ ! -s $issuedir/title ]]; then
    Mail "INFO: no title got in ClassifyIssue() for $name/$issuedir" $issuedir/issue
  fi
}

# helper of WorkAtIssue()
# creates an email containing convenient links and a command line ready for copy+paste
function CompileIssueComment0() {
  emerge -p --info $pkgname &>$issuedir/emerge-info.txt

  cp $issuedir/issue $issuedir/comment0
  cat <<EOF >>$issuedir/comment0

  -------------------------------------------------------------------

  This is an $keyword amd64 chroot image at a tinderbox (==build bot)
  name: $name

  -------------------------------------------------------------------

EOF

  (
    grep -e "^CC=" -e "^CXX=" -e "^GNUMAKEFLAGS" /etc/portage/make.conf
    echo "gcc-config -l:"
    gcc-config -l
    echo "clang/llvm (if any):"
    clang --version
    llvm-config --prefix --version
    python -V
    eselect ruby list
    eselect rust list
    grep -e "^GENTOO_VM=" -e "^JAVACFLAGS=" $tasklog_stripped
    java-config --list-available-vms --nocolor
    eselect java-vm list
    ghc --version
    echo "php cli (if any):"
    eselect php list cli
    go version

    for i in /var/db/repos/*/.git; do
      cd $i/..
      echo -e "\n  HEAD of ::$(basename $PWD)"
      git show -s HEAD
    done

    echo
    echo "emerge -qpvO $pkgname"
    emerge -qpvO $pkgname | head -n 1
  ) >>$issuedir/comment0 2>/dev/null
}

# put world into same state as if the (successfully installed) deps would have been already emerged in previous task/s
function KeepInstalledDeps() {
  if grep -q '^>>> Installing ' $tasklog_stripped; then
    emerge --depclean --verbose=n --pretend 2>/dev/null |
      grep "^All selected packages: " |
      cut -f2- -d':' -s |
      xargs --no-run-if-empty emerge -O --noreplace &>/dev/null
  fi
}

# helper of WorkAtIssue()
function setWorkDir() {
  workdir=$(grep -F -m 1 ' * Working directory: ' $tasklog_stripped | cut -f2 -d"'" -s)
  if [[ ! -d $workdir ]]; then
    workdir=$(grep -F -m 1 '>>> Source unpacked in ' $tasklog_stripped | cut -f5 -d" " -s)
    if [[ ! -d $workdir ]]; then
      workdir=/var/tmp/portage/$pkg/work/$(basename $pkg)
      if [[ ! -d $workdir ]]; then
        workdir=""
      fi
    fi
  fi
}

# append given arg to the end of the high prio backlog
function add2backlog() {
  local bl=/var/tmp/tb/backlog.1st

  # this is always the very last step
  if [[ $1 == '@preserved-rebuild' ]]; then
    # be the very last and most unimportant task
    sed -i -e "/@preserved-rebuild/d" $bl
    sed -i -e "1 i\@preserved-rebuild" $bl
    return
  fi

  # avoid dups with the last line / the whole file respectively
  if [[ $1 =~ ^@ || $1 =~ ^% ]]; then
    if [[ "$(tail -n 1 $bl)" != "$1" ]]; then
      echo "$1" >>$bl
    fi
  elif ! grep -q "^${1}$" $bl; then
    echo "$1" >>$bl
  fi
}

function finishTitle() {
  # strip away hex addresses, loong path names, line and time numbers and other stuff
  sed -i -e 's,0x[0-9a-f]*,<snip>,g' \
    -e 's,: line [0-9]*:,:line <snip>:,g' \
    -e 's,[0-9]* Segmentation fault,<snip> Segmentation fault,g' \
    -e 's,Makefile:[0-9]*,Makefile:<snip>,g' \
    -e 's,:[[:digit:]]*): ,:<snip>:, g' \
    -e 's,([[:digit:]]* of [[:digit:]]*),(<snip> of <snip)>,g' \
    -e 's,[0-9]*[\.][0-9]* sec,,g' \
    -e 's,[0-9]*[\.][0-9]* s,,g' \
    -e 's,([0-9]*[\.][0-9]*s),,g' \
    -e 's, \.\.\.*\., ,g' \
    -e 's,; did you mean .* \?$,,g' \
    -e 's,(@INC contains:.*),<@INC snip>,g' \
    -e "s,ld: /.*/cc......\.o: ,ld: ,g" \
    -e 's,target /.*/,target <snip>/,g' \
    -e 's,(\.text\..*):,(<snip>),g' \
    -e 's,object index [0-9].*,object index <snip>,g' \
    -e 's,/[^ ]*\(/[^/:]*:\),/...\1,g' \
    -e 's,ninja: error: /.*/,ninja error: .../,' \
    -e 's,:[[:digit:]]*:[[:digit:]]*: ,: ,' \
    -e 's, \w*/.*/\(.*\) , .../\1 ,g' \
    -e 's,\*, ,g' \
    -e 's,___*,_,g' \
    -e 's,\s\s*, ,g' \
    -e 's,mmake\..*:.*:,,g' \
    -e 's,ls[[:digit:]]*:,,g' \
    -e 's,..:..:..\.... \[error\],,g' \
    -e 's,config\......./,config.<snip>/,g' \
    -e 's,GMfifo.*,GMfifo<snip>,g' \
    -e 's,shuffle=[[:digit:]]*,,g' \
    -e 's,Makefile.*.tmp:[[:digit:]]*,Makefile,g' \
    $issuedir/title

  # prefix title
  if [[ $phase == "test" ]]; then
    sed -i -e "s,^,${pkg} fails test - ," $issuedir/title
  else
    sed -i -e "s,^,${pkg} - ," $issuedir/title
  fi
  sed -i -e 's,\s\s*, ,g' $issuedir/title
  truncate -s "<130" $issuedir/title # b.g.o. limits "Summary" length
}

function SendIssueMailIfNotYetReported() {
  if [[ ! -s $issuedir/title ]]; then
    Mail "WARN: no title in ~tinderbox/img/$name/$issuedir" $issuedir/body
    return
  fi
  if ! grep -q -f /mnt/tb/data/IGNORE_ISSUES $issuedir/title; then
    if ! grep -q -F -f $issuedir/title /mnt/tb/data/ALREADY_CAUGHT; then
      # chain "cat" by "echo" b/c cat buffers output which is racy between images
      # shellcheck disable=SC2005
      echo "$(cat $issuedir/title)" >>/mnt/tb/data/ALREADY_CAUGHT

      cp $issuedir/issue $issuedir/body
      echo -e "\n\n" >>$issuedir/body
      chmod a+w $issuedir/body

      local hints="bug"
      local force=""

      if [[ -e /etc/portage/bashrc ]]; then
        hints+=" clang"
      fi
      if checkBgo; then
        createSearchString
        if SearchForSameIssue 1>>$issuedir/body; then
          return
        fi
        if [[ $? -eq 2 ]]; then
          hints+=" b.g.o. issue"
        else
          if SearchForSimilarIssue 1>>$issuedir/body; then
            hints+=" similar"
            force="                        -f"
          else
            if [[ $? -eq 2 ]]; then
              hints+=" b.g.o. issue"
            else
              hints+=" unknown"
              force="                        -f"
            fi
          fi
        fi
      else
        hints+=" raw"
      fi

      echo -e "\n\n\n check_bgo.sh ~tinderbox/img/$name/$issuedir $force\n\n\n;" >>$issuedir/body

      blocker_bug_no=$(LookupForABlocker /mnt/tb/data/BLOCKER)
      if [[ -n $blocker_bug_no ]]; then
        hints+=" blocks $blocker_bug_no"
      fi
      Mail "$hints $(cat $issuedir/title)" $issuedir/body
    fi
  fi
}

function maskPackage() {
  local self=/etc/portage/package.mask/self

  if [[ -n $pkg ]]; then
    if [[ ! -s $self ]] || ! grep -q -e "=$pkg$" $self; then
      echo "=$pkg" >>$self
    fi
  fi
}

function collectPortageDir() {
  tar -C / -cjpf $issuedir/files/etc.portage.tar.bz2 --dereference etc/portage
}

# analyze the issue
function WorkAtIssue() {
  local pkglog_stripped=$issuedir/$(tr '/' ':' <<<$pkg).stripped.log
  filterPlainPext <$pkglog >$pkglog_stripped

  cp $pkglog $issuedir/files
  cp $tasklog $issuedir

  # "-m 1" because for phase "install" grep might have 2 matches ("doins failed" and "newins failed")
  # "-o" is needed for the 1st grep b/c sometimes perl spews a message into the same text line
  phase=$(
    grep -m 1 -o " \* ERROR:.* failed (.* phase):" $pkglog_stripped |
      grep -Eo '\(.* ' |
      tr -d '( '
  )
  setWorkDir
  CreateEmergeHistoryFile
  CollectIssueFiles
  ClassifyIssue
  collectPortageDir
  finishTitle
  CompileIssueComment0
  chmod 777 $issuedir/{,files}
  chmod -R a+rw $issuedir/
  CompressIssueFiles

  # https://bugs.gentoo.org/592880
  if grep -q -e ' perl module .* required' -e 't locate Locale/gettext.pm in' $pkglog_stripped; then
    try_again=1
    add2backlog "$task"
    add2backlog '%perl-cleaner --all'
    return
  fi

  if [[ $try_again -ne 0 ]]; then
    add2backlog "$task"
  fi
  SendIssueMailIfNotYetReported
}

function source_profile() {
  set +u
  source /etc/profile 2>/dev/null
  set -u
}

# helper of PostEmerge()
# switch to highest GCC
function SwitchGCC() {
  local highest=$(gcc-config --list-profiles --nocolor | cut -f3 -d' ' -s | grep -E 'x86_64-(pc|gentoo)-linux-(gnu|musl)-.*[0-9]$' | tail -n 1)

  if ! gcc-config --list-profiles --nocolor | grep -q -F "$highest *"; then
    local current=$(gcc -dumpversion)
    echo "major version change of gcc: $current -> $highest" | tee -a $taskfile.history
    gcc-config --nocolor $highest
    source_profile
    add2backlog "sys-devel/libtool"
    add2backlog "%emerge --unmerge sys-devel/gcc:$(cut -f1 -d'.' <<<$current)"
  fi
}

# helper of RunAndCheck()
# schedules follow-ups from the current emerge operation
function PostEmerge() {
  if ls /etc/._cfg????_locale.gen &>/dev/null; then
    locale-gen >/dev/null
    rm /etc/._cfg????_locale.gen
  elif grep -q "IMPORTANT: config file '/etc/locale.gen' needs updating." $tasklog_stripped; then
    locale-gen >/dev/null
  fi

  # don't change these config files after image setup
  rm -f /etc/._cfg????_{hosts,resolv.conf} /etc/conf.d/._cfg????_hostname /etc/ssmtp/._cfg????_ssmtp.conf /etc/portage/._cfg????_make.conf

  # merge the remaining config files automatically
  etc-update --automode -5 &>/dev/null

  # update the environment
  env-update &>/dev/null
  source_profile

  if grep -q -F 'Use emerge @preserved-rebuild to rebuild packages using these libraries' $tasklog_stripped; then
    add2backlog "@preserved-rebuild"
  fi

  if grep -q -F -e "Please, run 'haskell-updater'" \
    -e "ghc-pkg check: 'checking for other broken packages:'" $tasklog_stripped; then
    add2backlog "%haskell-updater"
  fi

  if grep -q ">>> Installing .* dev-lang/go-[1-9]" $tasklog_stripped && ! grep -q -F '[ebuild .*UD ]  *dev-lang/go' $tasklog_stripped; then
    add2backlog "@golang-rebuild"
  fi

  if grep -q -F '* An update to portage is available.' $tasklog_stripped; then
    add2backlog "sys-apps/portage"
  fi

  if grep -q -e ">>> Installing .* dev-lang/perl-[1-9]" \
    -e 'Use: perl-cleaner' $tasklog_stripped; then
    add2backlog '%perl-cleaner --all'
  fi

  if grep -q ">>> Installing .* dev-lang/ruby-[1-9]" $tasklog_stripped && ! grep -q -F '[ebuild .*UD ]  *dev-lang/ruby' $tasklog_stripped; then
    local current=$(eselect ruby show | head -n 2 | tail -n 1 | xargs)
    local highest=$(eselect ruby list | tail -n 1 | awk '{ print $2 }')

    if [[ $current != "$highest" ]]; then
      add2backlog "%eselect ruby set $highest"
    fi
  fi

  if grep -q ">>> Installing .* sys-devel/gcc-[1-9]" $tasklog_stripped; then
    add2backlog "%SwitchGCC"
  fi

}

function createIssueDir() {
  issuedir=/var/tmp/tb/issues/$(date +%Y%m%d-%H%M%S)-$(tr '/' '_' <<<$pkg)
  mkdir -p $issuedir/files || return $?
  chmod 777 $issuedir # allow to edit title etc. manually
}

function catchMisc() {
  while read -r pkglog; do
    if [[ $(wc -l <$pkglog) -le 6 ]]; then
      continue
    fi

    local pkglog_stripped=/tmp/$(basename $pkglog | sed -e "s,\.log$,.stripped.log,")
    filterPlainPext <$pkglog >$pkglog_stripped
    if grep -q -f /mnt/tb/data/CATCH_MISC $pkglog_stripped; then
      pkg=$(grep -m 1 -F ' * Package: ' $pkglog_stripped | awk '{ print $3 }' | sed -e 's,:.*,,')
      phase=""
      pkgname=$(qatom --quiet "$pkg" | grep -v -F '(null)' | cut -f1-2 -d' ' -s | tr ' ' '/')

      # create for each finding an own issue
      grep -f /mnt/tb/data/CATCH_MISC $pkglog_stripped |
        while read -r line; do
          createIssueDir || continue
          echo "$line" >$issuedir/title
          grep -m 1 -F -e "$line" $pkglog_stripped >$issuedir/issue
          cp $pkglog $issuedir/files
          cp $pkglog_stripped $issuedir
          finishTitle
          cp $issuedir/issue $issuedir/comment0
          cat <<EOF >>$issuedir/comment0

  -------------------------------------------------------------------

  This is an $keyword amd64 chroot image at a tinderbox (==build bot)
  name: $name

  -------------------------------------------------------------------

  The log matches a QA pattern or a pattern requested by a Gentoo developer.

EOF
          collectPortageDir
          CreateEmergeHistoryFile
          CompressIssueFiles
          SendIssueMailIfNotYetReported
        done
    fi
    rm $pkglog_stripped
  done < <(find /var/log/portage/ -mindepth 1 -maxdepth 1 -type f -newer $taskfile)
}

function GetPkglog() {
  if [[ -z $pkg ]]; then
    return 1
  fi
  pkgname=$(qatom --quiet "$pkg" | grep -v -F '(null)' | cut -f1-2 -d' ' -s | tr ' ' '/')
  pkglog=$(grep -o -m 1 "/var/log/portage/$(tr '/' ':' <<<$pkgname).*\.log" $tasklog_stripped)
  if [[ ! -f $pkglog ]]; then
    pkglog=$(ls -1 /var/log/portage/$(tr '/' ':' <<<$pkgname)*.log 2>/dev/null | sort | tail -n 1)
  fi
  if [[ ! -f $pkglog ]]; then
    Mail "INFO: failed to get pkglog=$pkglog  pkg=$pkg  pkgname=$pkgname  task=$task" $tasklog_stripped
    return 1
  fi
}

function GetPkgFromTaskLog() {
  pkg=$(grep -m 1 -F ' * Package: ' $tasklog_stripped | awk '{ print $3 }')
  if [[ -z $pkg ]]; then
    pkg=$(grep -m 1 '>>> Failed to emerge .*/.*' $tasklog_stripped | cut -f5 -d' ' -s | cut -f1 -d',' -s)
    if [[ -z $pkg ]]; then
      pkg=$(grep -F ' * Fetch failed' $tasklog_stripped | grep -o "'.*'" | sed "s,',,g")
      if [[ -z $pkg ]]; then
        return 1
      fi
    fi
  fi
  pkg=$(sed -e 's,:.*,,' <<<$pkg) # strip away the slot
  GetPkglog
}

# helper of WorkOnTask()
# run $1 and act on its results
function RunAndCheck() {
  unset phase pkgname pkglog
  try_again=0 # "1" means to retry same task, but with possible changed USE/ENV/FEATURE/CFLAGS

  timeout --signal=15 --kill-after=5m 48h bash -c "$1" &>>$tasklog
  local rc=$?
  (
    echo
    date
  ) >>$tasklog

  tasklog_stripped="/tmp/tasklog_stripped.log"

  filterPlainPext <$tasklog >$tasklog_stripped
  PostEmerge
  catchMisc
  pkg=""

  if [[ -n "$(ls /tmp/core.* 2>/dev/null)" ]]; then
    if grep -q -F ' -Og -g' /etc/portage/make.conf; then
      local core_files_dir=/var/tmp/tb/core/$task_timestamp_prefix
      mkdir -p $core_files_dir
      mv /tmp/core.* $core_files_dir
      Mail "INFO: kept core files in $core_files_dir" "$(ls -lh $core_files_dir/)" $tasklog
    else
      rm /tmp/core.*
    fi
  fi

  # exited on signal
  if [[ $rc -ge 128 ]]; then
    local signal=$((rc - 128))
    if [[ $signal -eq 9 ]]; then
      Finish 9 "KILLed" $tasklog
    else
      pkg=$(ls -d /var/tmp/portage/*/*/work 2>/dev/null | head -n 1 | sed -e 's,/var/tmp/portage/,,' -e 's,/work,,' -e 's,:.*,,')
      if GetPkglog; then
        createIssueDir
        WorkAtIssue
      fi
      Mail "INFO:  killed=$signal  task=$task  pkg=$pkg" $tasklog
    fi

  # an error occurred
  elif [[ $rc -gt 0 ]]; then
    if GetPkgFromTaskLog; then
      createIssueDir
      WorkAtIssue
    fi
    if [[ $rc -eq 124 ]]; then
      ReachedEndfOfLife "INFO:  timeout  task=$task" $tasklog
    fi
  fi

  if [[ $try_again -eq 0 ]]; then
    maskPackage
    KeepInstalledDeps
  fi

  return $rc
}

# this is the heart of the tinderbox
function WorkOnTask() {
  # @set
  if [[ $task =~ ^@ ]]; then
    local opts=""
    if [[ $task == "@world" ]]; then
      opts+=" --update --changed-use --newuse"
    fi

    if RunAndCheck "emerge $task $opts"; then
      echo "$(date) ok" >>/var/tmp/tb/$task.history
      if [[ $task == "@world" ]]; then
        add2backlog "%emerge --depclean --verbose=n"
        if tail -n 1 /var/tmp/tb/@preserved-rebuild.history 2>/dev/null | grep -q " NOT ok $"; then
          add2backlog "@preserved-rebuild"
        fi
      fi
    else
      echo "$(date) NOT ok $pkg" >>/var/tmp/tb/$task.history
      if [[ -n $pkg ]]; then
        if [[ $try_again -eq 0 ]]; then
          add2backlog "$task"
        fi
      else
        ReachedEndfOfLife "$task is broken" $tasklog
      fi
    fi

  # %<command line>
  elif [[ $task =~ ^% ]]; then
    local cmd="$(cut -c2- <<<$task)"
    if ! RunAndCheck "$cmd"; then
      if [[ ! $cmd =~ " --depclean" && ! $cmd =~ "perl-cleaner" ]]; then
        Mail "INFO: command failed: $cmd" $tasklog
      fi
    fi

  # pinned version
  elif [[ $task =~ ^= ]]; then
    if ! RunAndCheck "emerge $task"; then
      Mail "INFO: pinned atom failed: $task" $tasklog
    fi

  # a common atom
  else
    RunAndCheck "emerge --update $task" || true
  fi
}

# bail out if there's a loop
function DetectRepeats() {
  local p_max=5
  local w_max=18

  for pattern in 'perl-cleaner' '@preserved-rebuild'; do
    if [[ $(tail -n 20 /var/tmp/tb/task.history | grep -c "$pattern") -ge $p_max ]]; then
      ReachedEndfOfLife "too often ($p_max x) repeated: $pattern"
    fi
  done

  if [[ $name =~ _test ]]; then
    ((w_max = 30))
  fi
  pattern='@world'
  if [[ $(tail -n 40 /var/tmp/tb/task.history | grep -c "$pattern") -ge $w_max ]]; then
    ReachedEndfOfLife "too often ($w_max x) repeated: $pattern"
  fi

  local count
  local package
  read -r count package < <(qlop -mv | awk '{ print $3 }' | tail -n 1000 | sort | uniq -c | sort -bn | tail -n 1)
  if [[ $count -ge $p_max ]]; then
    ReachedEndfOfLife "too often emerged: $count x $package"
  fi
}

function syncRepo() {
  local synclog=/var/tmp/tb/sync.log
  local curr_time=$EPOCHSECONDS

  cd /var/db/repos/gentoo

  if ! emaint sync --auto &>$synclog; then
    if grep -q -e 'git fetch error' -e ': Failed to connect to ' -e ': SSL connection timeout' -e ': Connection timed out' -e 'The requested URL returned error:' $synclog; then
      return 0
    fi

    echo "git status" >>$synclog
    git status &>>$synclog

    if (
      echo -e "\nTrying to fix ...\n"
      git stash && git stash drop
      git restore .
    ) &>>$synclog; then
      if ! emaint sync --auto &>>$synclog; then
        ReachedEndfOfLife "still unfixed ::gentoo" $synclog
      fi
    else
      ReachedEndfOfLife "cannot restore ::gentoo" $synclog
    fi
  fi

  if grep -q -F '* An update to portage is available.' $synclog; then
    add2backlog "sys-apps/portage"
  fi

  if ! grep -B 1 '=== Sync completed for gentoo' $synclog | grep -q 'Already up to date.'; then
    # retest change ebuilds with an 1 hour timeshift to have download mirrors be synced
    git diff \
      --diff-filter="ACM" \
      --name-only \
      "@{ $((EPOCHSECONDS - last_sync + 3600)) second ago }..@{ 1 hour ago }" |
      grep -F -e '/files/' -e '.ebuild' -e 'Manifest' |
      cut -f1-2 -d'/' -s |
      grep -v -f /mnt/tb/data/IGNORE_PACKAGES |
      sort -u >/tmp/syncRepo.upd

    if [[ -s /tmp/syncRepo.upd ]]; then
      # mix repo changes and backlog together
      sort -u /tmp/syncRepo.upd /var/tmp/tb/backlog.upd | shuf >/tmp/backlog.upd
      # no mv to preserve target file perms
      cp /tmp/backlog.upd /var/tmp/tb/backlog.upd
    fi
  fi

  last_sync=$curr_time

  cd - 1>/dev/null
}

#############################################################################
#
#       main
#
set -eu
export LANG=C.utf8

if [[ -x "$(command -v gtar)" ]]; then
  gtar=gtar
else
  gtar=tar # hopefully this knows --warning=none et al.
fi

source $(dirname $0)/lib.sh

export -f SwitchGCC add2backlog source_profile syncRepo # called in eval of RunAndCheck() or in SwitchGCC()

export taskfile=/var/tmp/tb/task # holds the current task, and is exported, b/c used in SwitchGCC()
tasklog=$taskfile.log            # holds output of it
name=$(cat /var/tmp/tb/name)     # the image name
grep -q '^ACCEPT_KEYWORDS=.*~amd64' /etc/portage/make.conf && keyword="unstable" || keyword="stable"

export CARGO_TERM_COLOR="never"
export CMAKE_COLOR_DIAGNOSTICS="OFF"
export CMAKE_COLOR_MAKEFILE="OFF"
export GCC_COLORS=""
export OCAML_COLOR="never"
export NOCOLOR="1"
export PY_FORCE_COLOR="0"
export PYTEST_ADDOPTS="--color=no"

export TERM=linux
export TERMINFO=/etc/terminfo

export GIT_PAGER="cat"
export PAGER="cat"

# re-schedule $task (if non-empty then Failed() was called before)
if [[ -s $taskfile ]]; then
  add2backlog "$(cat $taskfile)"
fi

echo "#init" >$taskfile
rm -f $tasklog # remove a left over hard link
systemd-tmpfiles --create &>$tasklog || true

trap Finish INT QUIT TERM EXIT

last_sync=$(stat -c %Y /var/db/repos/gentoo/.git/FETCH_HEAD)
while :; do
  for i in EOL STOP; do
    if [[ -f /var/tmp/tb/$i ]]; then
      echo "#catched $i" >$taskfile
      Finish 0 "catched $i" /var/tmp/tb/$i
    fi
  done

  # if 1st prio is empty then ...
  if [[ ! -s /var/tmp/tb/backlog.1st ]]; then
    # ... hourly sync repository
    if [[ $((EPOCHSECONDS - last_sync)) -ge 3600 ]]; then
      echo "#sync repo" >$taskfile
      syncRepo
    fi
    # ... and daily update @world
    h=/var/tmp/tb/@world.history
    if [[ ! -s $h || $((EPOCHSECONDS - $(stat -c %Y $h))) -ge 86400 ]]; then
      add2backlog "@world"
    fi
  fi

  echo "#get next task" >$taskfile
  getNextTask

  rm -rf /var/tmp/portage/*

  {
    date
    echo
  } >$tasklog
  task_timestamp_prefix=task.$(date +%Y%m%d-%H%M%S).$(tr -d '\n' <<<$task | tr -c '[:alnum:]' '_')
  ln $tasklog /var/tmp/tb/logs/$task_timestamp_prefix.log # the later will remain if the former is deleted
  echo "$task" | tee -a $taskfile.history $tasklog >$taskfile
  WorkOnTask
  rm $tasklog
  find /var/log/portage -name '*.log' -exec bzip2 {} +

  truncate -s 0 $taskfile

  DetectRepeats
done
