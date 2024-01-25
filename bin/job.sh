#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# This is the tinderbox script itself.
# The main function is WorkOnTask().
# The remaining code just parses the output.
# That's all.

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
  local content=${2-}

  local subject=$(stripQuotesAndMore <<<$1 | strings -w | cut -c 1-200 | tr '\n' ' ')

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
    sed -e 's,^>, >,' |
    if ! timeout --signal=15 --kill-after=1m 5m mail -s "$subject @ $name" ${MAILTO:-tinderbox@zwiebeltoralf.de} &>/var/tmp/mail.log; then
      echo "$(date) mail issue, \$subject=$subject \$content=$content" >&2
      cat /var/tmp/mail.log >&2
    fi
}

function ReachedEOL() {
  local subject=${1:-"NO SUBJECT"}
  local attachment=${2-}

  echo "$subject" >>/var/tmp/tb/EOL
  chmod a+w /var/tmp/tb/EOL
  truncate -s 0 $taskfile
  local new=$(ls /var/tmp/tb/issues/*/.reported 2>/dev/null | wc -l)
  local all=$(ls -d /var/tmp/tb/issues/* 2>/dev/null | wc -l)
  /usr/bin/pfl &>/dev/null || true
  subject+=", $(grep -c ' ::: completed emerge' /var/log/emerge.log) completed, $new#$all bug(s) new"
  Finish 0 "EOL $subject" $attachment
}

# this is the end ...
function Finish() {
  local exit_code=${1:-$?}
  local subject=${2:-"INTERNAL ERROR"}
  local attachment=${3-}

  trap - INT QUIT TERM EXIT
  set +e

  subject="finished $exit_code $(stripQuotesAndMore <<<$subject)"
  Mail "$subject" $attachment
  rm -f /var/tmp/tb/STOP
  exit $exit_code
}

# helper of getNextTask()
function setBacklog() {
  if [[ -s /var/tmp/tb/backlog.1st ]]; then
    backlog=/var/tmp/tb/backlog.1st

  elif [[ -s /var/tmp/tb/backlog.upd && $((RANDOM % 4)) -eq 0 ]]; then
    backlog=/var/tmp/tb/backlog.upd

  elif [[ -s /var/tmp/tb/backlog ]]; then
    backlog=/var/tmp/tb/backlog

  elif [[ -s /var/tmp/tb/backlog.upd ]]; then
    backlog=/var/tmp/tb/backlog.upd

  else
    ReachedEOL "all work DONE"
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
      ReachedEOL "$task"

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

    elif [[ $task =~ ' ' ]]; then
      break

    else
      # skip if no package version for $task is visible
      if ! best_visible=$(portageq best_visible / $task 2>/dev/null); then
        continue
      fi
      if [[ -z $best_visible ]]; then
        continue
      fi

      if [[ $backlog != /var/tmp/tb/backlog.1st ]]; then
        if grep -q -f /mnt/tb/data/IGNORE_PACKAGES <<<$best_visible; then
          continue
        fi
      fi

      # skip if $task would be downgraded
      if installed=$(portageq best_version / $task); then
        if [[ -n $installed ]]; then
          if qatom --compare $installed $best_visible | grep -q -e ' == ' -e ' > '; then
            continue
          fi
        fi
      fi

      # valid $task
      break
    fi
  done
}

function CompressIssueFiles() {
  chmod a+w $issuedir/{comment0,issue,title}
  chmod a+r $issuedir/files/*
  # shellcheck disable=SC2010
  ls $issuedir/files/ |
    grep -v -F '.xz' |
    while read -r f; do
      # compress if bigger than 1/4 MB
      if [[ $(wc -c <$issuedir/files/$f) -gt $((2 ** 18)) ]]; then
        xz $issuedir/files/$f
      fi
    done
}

function CreateEmergeInfo() {
  local outfile=$issuedir/files/emerge-history.txt
  local cmd="qlop --nocolor --verbose --merge --unmerge" # no --summary, it would sort alphabetically
  cat <<EOF >$outfile
# This file contains the emerge history got with:
# $cmd
# at $(date)
EOF
  $cmd &>>$outfile

  outfile=$issuedir/files/qlist-info.txt
  cmd="qlist --installed --nocolor --verbose --umap --slots --slots"
  cat <<EOF >$outfile
# This file contains the qlist info got with:
# $cmd
# at $(date)
EOF
  $cmd &>>$outfile

  emerge -p --info $pkgname &>$issuedir/emerge-info.txt
}

function CollectClangFiles() {
  # requested by sam_ (clang hook in bashrc)
  if [[ -d /var/tmp/clang/$pkg ]]; then
    $tar -C /var/tmp/clang/ -cJpf $issuedir/files/var.tmp.clang.tar.xz ./$pkg
  fi
  if [[ -d /etc/clang ]]; then
    $tar -C /etc -cJpf $issuedir/files/etc.clang.tar.xz ./clang
  fi
}

# gather together what might be relevant for b.g.o.
function CollectIssueFiles() {
  apout=$(grep -m 1 -A 2 'Include in your bugreport the contents of' $tasklog_stripped | grep -F '.out' | cut -f 5 -d ' ' -s)
  cmlog=$(grep -m 1 -A 2 'Configuring incomplete, errors occurred' $tasklog_stripped | grep "CMake.*\.log" | cut -f 2 -d '"' -s)
  cmerr=$(grep -m 1 'CMake Error: Parse error in cache file' $tasklog_stripped | sed "s/txt./txt/" | cut -f 8 -d ' ' -s)
  oracl=$(grep -m 1 -A 1 '# An error report file with more information is saved as' $tasklog_stripped | grep -F '.log' | cut -f 2 -d ' ' -s)
  envir=$(grep -m 1 'The ebuild environment file is located at' $tasklog_stripped | cut -f 2 -d "'" -s)
  salso=$(grep -m 1 -A 2 ' See also' $tasklog_stripped | grep -F '.log' | awk '{ print $1 }')
  sandb=$(grep -m 1 -A 1 'ACCESS VIOLATION SUMMARY' $tasklog_stripped | grep "sandbox.*\.log" | cut -f 2 -d '"' -s)
  roslg=$(grep -m 1 -A 1 'Tests failed. When you file a bug, please attach' $tasklog_stripped | grep -F '/LastTest.log' | awk '{ print $2 }')

  for f in $apout $cmlog $cmerr $oracl $envir $salso $sandb $roslg; do
    if [[ -s $f ]]; then
      cp $f $issuedir/files
    fi
  done

  if [[ -d $workdir ]]; then
    (
      f=/tmp/files
      cd "$workdir/.."
      find ./ -name "*.log" -print0 \
        -o -name "*.binlog" \
        -o -name "meson-log.txt" \
        -o -name "testlog.*" \
        -o -wholename '*/elf/*.out' \
        -o -wholename '*/softmmu-build/*' \
        -o -wholename "./temp/syml*" >$f
      if [[ -s $f ]]; then
        $tar -cJpf $issuedir/files/logs.tar.xz --null --files-from $f --dereference --warning=none
      fi
      rm $f
    )

    cp ${workdir}/*/CMakeCache.txt $issuedir/files/ 2>/dev/null || true

    if [[ -d $workdir/../../temp ]]; then
      if ! $tar -C $workdir/../.. -cJpf $issuedir/files/temp.tar.xz \
        --dereference --warning=none --sparse \
        --exclude='*/.tmp??????/*' \
        --exclude='*/garbage.*' \
        --exclude='*/go-build[0-9]*/*' \
        --exclude='*/go-cache/??/*' \
        --exclude='*/kerneldir/*' \
        --exclude='*/nested_link_to_dir/*' \
        --exclude='*/syml*' \
        --exclude='*/temp/NuGetScratchportage/*' \
        --exclude='*/temp/nugets/*' \
        --exclude='*/testdirsymlink/*' \
        --exclude='*/var-tests/*' \
        ./temp &>/var/tmp/tar.log; then
        Mail "NOTICE: tar issue with $workdir/../../temp" /var/tmp/tar.log
      fi
    fi

    # ICE
    cp $workdir/../gcc-build-logs.tar.* $issuedir/files 2>/dev/null || true
  fi

  if grep -q "^$pkgname$" /mnt/tb/data/KEEP_BUILD_ARTEFACTS; then
    find $workdir/.. -ls 2>&1 | xz >$issuedir/files/var-tmp-portage.filelist.txt.xz
    $tar --warning=none -C /var/tmp/portage/ -cJpf $issuedir/files/var-tmp-portage.tar.xz .
    Mail "INFO: keep artefacts in $issuedir" $tasklog_stripped
    echo "$issuedir" >>/var/tmp/tb/KEEP
  fi
}

function collectPortageFiles() {
  tar -C / -cJpf $issuedir/files/etc.portage.tar.xz --dereference etc/portage
}

# helper of ClassifyIssue()
function foundCollisionIssue() {
  local s
  s=$(
    grep -m 1 -A 5 'Press Ctrl-C to Stop' $tasklog_stripped |
      tee -a $issuedir/issue |
      grep -m 1 '::' | tr ':' ' ' | cut -f 3 -d ' ' -s
  )
  # colliding package name
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
  cat /mnt/tb/data/CATCH_ISSUES-pre /mnt/tb/data/CATCH_ISSUES.${phase:-compile} /mnt/tb/data/CATCH_ISSUES-post |
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
  (
    cd "$workdir"
    dirs="$(ls -d ./tests ./regress ./t ./Testing ./testsuite.dir 2>/dev/null)"
    if [[ -n $dirs ]]; then
      if ! $tar --warning=none -cJpf $issuedir/files/tests.tar.xz \
        --dereference --one-file-system --sparse \
        --exclude='*.o' \
        --exclude="*/dev/*" \
        --exclude="*/proc/*" \
        --exclude="*/run/*" \
        --exclude="*/symlinktest/*" \
        --exclude="*/sys/*" \
        $dirs &>/var/tmp/tar.log; then
        Mail "NOTICE: tar issue with $workdir" /var/tmp/tar.log
      fi
    fi
  )
}

# helper of WorkAtIssue()
# get the issue and a descriptive title
function ClassifyIssue() {
  if [[ $phase == "test" ]]; then
    handleTestPhase
  fi

  if grep -q -m 1 -F ' * Detected file collision(s):' $pkglog_stripped; then
    foundCollisionIssue

  elif [[ -n $sandb ]]; then # no "-f" b/c it might not been created
    foundSandboxIssue

  # special forced issues
  elif [[ -n "$(grep -m 1 -B 4 -A 1 -e 'sed:.*expression.*unknown option' -e 'error:.*falign-functions=32:25:16' $pkglog_stripped | tee $issuedir/issue)" ]]; then
    foundCflagsIssue 'ebuild uses colon (:) as a sed delimiter'

  else
    foundGenericIssue
    if [[ ! -s $issuedir/title ]]; then
      grep -m 1 -A 2 "^ \* ERROR:.* failed \(.* phase\):" $pkglog_stripped |
        tee $issuedir/issue |
        sed -n -e '2p' >$issuedir/title
    fi
  fi

  if [[ $(wc -c <$issuedir/issue) -gt 1024 ]]; then
    echo -e "too long lines were shrinked:\n" >/tmp/issue
    cut -c-300 <$issuedir/issue >>/tmp/issue
    mv /tmp/issue $issuedir/issue
  fi

  if [[ ! -s $issuedir/title ]]; then
    Mail "INFO: no title for $name/$issuedir" $issuedir/issue
  fi
}

# helper of WorkAtIssue()
# creates an email containing convenient links and a command line ready for copy+paste
function CompileIssueComment0() {
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

# helper of WorkAtIssue()
function setWorkDir() {
  workdir=$(grep -F -m 1 ' * Working directory: ' $tasklog_stripped | cut -f 2 -d "'" -s)
  if [[ ! -d $workdir ]]; then
    workdir=$(grep -m 1 '>>> Source unpacked in ' $tasklog_stripped | cut -f 5 -d " " -s)
    if [[ ! -d $workdir ]]; then
      workdir=/var/tmp/portage/$pkg/work/$(basename $pkg)
      if [[ ! -d $workdir ]]; then
        # no work dir, if "fetch" phase failed
        workdir=""
      fi
    fi
  fi
}

# append given arg to the end of the high prio backlog
function add2backlog() {
  local bl=/var/tmp/tb/backlog.1st

  if [[ $1 == '@preserved-rebuild' ]]; then
    #  it is the very last and lowest prio task
    sed -i -e "/@preserved-rebuild/d" $bl
    sed -i -e "1 i\@preserved-rebuild" $bl
  else
    if [[ $1 =~ ^@ || $1 =~ ^% ]]; then
      # avoid duplicate the current last line (==next task)
      if [[ "$(tail -n 1 $bl)" != "$1" ]]; then
        echo "$1" >>$bl
      fi
    elif ! grep -q "^${1}$" $bl; then # avoid dups in the file
      echo "$1" >>$bl
    fi
  fi
}

function finishTitle() {
  # strip away hex addresses, line numbers, timestamps, shrink loong path names etc.
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
    sed -i -e "s,^,$pkg fails test - ," $issuedir/title
  else
    sed -i -e "s,^,$pkg - ," $issuedir/title
  fi
  sed -i -e 's,\s\s*, ,g' $issuedir/title
  truncate -s "<150" $issuedir/title # b.g.o. limits "Summary" length
}

function SendIssueMailIfNotYetReported() {
  if ! grep -q -f /mnt/tb/data/IGNORE_ISSUES $issuedir/title; then
    if ! grep -q -F -f $issuedir/title /mnt/tb/findings/ALREADY_CAUGHT; then
      # chain "cat" by "echo" b/c "echo" is racy whilst "cat" buffers output till newline
      # shellcheck disable=SC2005
      echo "$(cat $issuedir/title)" >>/mnt/tb/findings/ALREADY_CAUGHT

      cp $issuedir/issue $issuedir/body
      echo -e "\n\n" >>$issuedir/body
      chmod a+w $issuedir/body

      local hints="bug"
      local force=""

      createSearchString
      if checkBgo &>>$issuedir/body; then
        if SearchForSameIssue &>>$issuedir/body; then
          hints+=" same"
        elif ! BgoIssue; then
          if SearchForSimilarIssue &>>$issuedir/body; then
            hints+=" similar"
            force="                                -f"
          elif ! BgoIssue; then
            hints+=" unknown"
          fi
        fi
      fi
      if blocker_bug_no=$(LookupForABlocker /mnt/tb/data/BLOCKER); then
        hints+=" blocks $blocker_bug_no"
      fi
      cat <<EOF >>$issuedir/body


 direct link: http://tinderbox.zwiebeltoralf.de:31560/$name/$issuedir


 check_bgo.sh ~tinderbox/img/$name/$issuedir $force


:

EOF
      Mail "$hints $(cat $issuedir/title)" $issuedir/body
    fi
  fi
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
  CreateEmergeInfo
  CollectClangFiles
  CollectIssueFiles
  collectPortageFiles
  ClassifyIssue
  finishTitle
  CompileIssueComment0
  CompressIssueFiles

  # https://bugs.gentoo.org/592880
  if grep -q -e ' perl module .* required' \
    -e 't locate Locale/gettext.pm in' $pkglog_stripped; then
    try_again=1
    add2backlog "$task"
    add2backlog '%perl-cleaner --all'
    return
  fi

  if grep -q -e "Please, run 'haskell-updater'" $pkglog_stripped; then
    try_again=1
    add2backlog "$task"
    add2backlog "%haskell-updater"
    return
  fi

  if [[ $try_again -eq 1 ]]; then
    add2backlog "$task"
  fi

  if [[ -s $issuedir/title ]]; then
    SendIssueMailIfNotYetReported
  fi
}

function source_profile() {
  set +u
  source /etc/profile
  set -u
}

function SwitchGCC() {
  local highest=$(gcc-config --list-profiles --nocolor | cut -f 3 -d ' ' -s | grep -E 'x86_64-(pc|gentoo)-linux-(gnu|musl)-.*[0-9]$' | tail -n 1)
  if [[ -z $highest ]]; then
    Mail "${FUNCNAME[0]}: cannot get GCC version"
    return
  fi

  if ! gcc-config --list-profiles --nocolor | grep -q -F "$highest *"; then
    local current
    current=$(gcc -dumpversion)
    echo "major version change of gcc: $current -> $highest" | tee -a $taskfile.history
    gcc-config --nocolor $highest
    source_profile
    add2backlog "sys-devel/libtool"
    # sam_
    if grep -q '^LIBTOOL="rdlibtool"' /etc/portage/make.conf; then
      add2backlog "sys-devel/slibtool"
    fi
    add2backlog "%emerge --unmerge sys-devel/gcc:$(cut -f 1 -d '.' <<<$current)"
  fi
}

# helper of RunAndCheck()
# schedules follow-ups from the current emerge operation
function PostEmerge() {
  if [[ ! $name =~ "musl" ]]; then
    if ls /etc/._cfg????_locale.gen &>/dev/null; then
      locale-gen >/dev/null
      rm /etc/._cfg????_locale.gen
    elif grep -q "IMPORTANT: config file '/etc/locale.gen' needs updating." $tasklog_stripped; then
      locale-gen >/dev/null
    fi
  fi

  # pinned by image setup
  rm -f /etc/._cfg????_{hosts,resolv.conf} /etc/conf.d/._cfg????_hostname /etc/portage/._cfg????_make.conf /etc/ssmtp/._cfg????_ssmtp.conf
  etc-update --automode -5 &>/dev/null
  env-update &>/dev/null
  source_profile

  for p in dirmngr gpg-agent; do
    if pgrep -a $p &>>/var/tmp/pkill.log; then
      if ! pkill -e $p &>>/var/tmp/pkill.log; then
        Mail "INFO: kill $p failed" /var/tmp/pkill.log
      fi
    fi
  done

  if grep -q 'Use emerge @preserved-rebuild to rebuild packages using these libraries' $tasklog_stripped; then
    add2backlog "@preserved-rebuild"
    # no @world and no deplean here
  fi

  # https://gitweb.gentoo.org/repo/gentoo.git/tree/dev-lang/perl/perl-5.38.0-r1.ebuild#n129
  if grep -q -e ">>> Installing .* dev-lang/perl-[1-9]" $tasklog_stripped -e 'Use: perl-cleaner' $tasklog_stripped; then
    add2backlog '%perl-cleaner --all'
  fi

  if grep -q ">>> Installing .* dev-lang/ruby-[1-9]" $tasklog_stripped; then
    local highest=$(eselect ruby list | awk 'END { print $2 }')
    if [[ -n $highest ]]; then
      local current=$(eselect ruby show | sed -n -e '2p' | xargs)
      if [[ $current != "$highest" ]]; then
        add2backlog "%eselect ruby set $highest"
      fi
    fi
  fi

  if grep -q ">>> Installing .* sys-devel/gcc-[1-9]" $tasklog_stripped; then
    add2backlog "%SwitchGCC"
  fi

  if grep -q ' An update to portage is available.' $tasklog_stripped; then
    add2backlog "%emerge --oneshot sys-apps/portage"
  fi
}

function createIssueDir() {
  issuedir=/var/tmp/tb/issues/$(date +%Y%m%d-%H%M%S)-$(tr '/' '_' <<<$pkg)
  mkdir -p $issuedir/files
  chmod 777 $issuedir
}

function catchMisc() {
  while read -r pkglog; do
    if [[ $(wc -l <$pkglog) -le 6 ]]; then
      continue
    fi

    local pkglog_stripped=/tmp/$(basename $pkglog).stripped
    pkg=$(basename $pkglog | cut -f 1-2 -d ':' -s | tr ':' '/')
    filterPlainPext <$pkglog >$pkglog_stripped

    # feed the list of xgqt
    read -r size_build size_install <<<$(grep -A 1 -e ' Final size of build directory: .* GiB' $pkglog_stripped | grep -Eo '[0-9\.]+ KiB' | cut -f 1 -d ' ' -s | xargs)
    if [[ -n $size_build && -n $size_install ]]; then
      size_sum=$(echo "scale=1; ($size_build + $size_install) / 1024.0 / 1024.0" | bc)
      echo "$size_sum GiB $pkg" >>/var/tmp/xgqt.txt
    fi

    if grep -q -f /mnt/tb/data/CATCH_MISC $pkglog_stripped; then
      phase=""
      pkgname=$(qatom --quiet "$pkg" | grep -v -F '(null)' | cut -f 1-2 -d ' ' -s | tr ' ' '/')

      # create for each finding an own issue
      grep -f /mnt/tb/data/CATCH_MISC $pkglog_stripped |
        while read -r line; do
          createIssueDir
          echo "$line" >$issuedir/title
          grep -m 1 -A 7 -F -e "$line" $pkglog_stripped >$issuedir/issue
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
          CollectClangFiles
          collectPortageFiles
          CreateEmergeInfo
          CompressIssueFiles
          SendIssueMailIfNotYetReported
        done
    fi
    rm $pkglog_stripped
  done < <(find /var/log/portage/ -type f -name '*.log') # "-newer" not needed, b/c previous logs are compressed
}

function GetPkglog() {
  if [[ -z $pkg ]]; then
    return 1
  fi
  pkgname=$(qatom --quiet "$pkg" | grep -v -F '(null)' | cut -f 1-2 -d ' ' -s | tr ' ' '/')
  pkglog=$(grep -o -m 1 "/var/log/portage/$(tr '/' ':' <<<$pkgname).*\.log" $tasklog_stripped)
  if [[ ! -f $pkglog ]]; then
    pkglog=$(ls -1 /var/log/portage/$(tr '/' ':' <<<$pkgname)*.log 2>/dev/null | sort -r | head -n 1)
  fi
  if [[ ! -f $pkglog ]]; then
    Mail "INFO: failed to get pkglog=$pkglog  pkg=$pkg  pkgname=$pkgname  task=$task" $tasklog_stripped
    return 1
  fi
}

function GetPkgFromTaskLog() {
  pkg=$(grep -m 1 -F ' * Package: ' $tasklog_stripped | awk '{ print $3 }')
  if [[ -z $pkg ]]; then
    pkg=$(grep -m 1 '>>> Failed to emerge .*/.*' $tasklog_stripped | cut -f 5 -d ' ' -s | cut -f 1 -d ',' -s)
    if [[ -z $pkg ]]; then
      pkg=$(grep -F ' * Fetch failed' $tasklog_stripped | grep -o "'.*'" | sed "s,',,g")
      if [[ -z $pkg ]]; then
        # happened if emerge failed in dependency resolution
        return 1
      fi
    fi
  fi
  pkg=$(sed -e 's,:.*,,' <<<$pkg) # strip away the slot
}

# helper of WorkOnTask()
# run $1 and act on its results
function RunAndCheck() {
  set +e
  timeout --signal=15 --kill-after=5m 48h bash -c "$1" &>>$tasklog
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    echo -e "\n--\n$(date)\nrc=$rc" >>$tasklog
  fi

  pkg=""
  unset phase pkgname pkglog
  try_again=0 # "1" means to retry same task, but possibly with changed USE/ENV/FEATURE/CFLAGS file(s)
  filterPlainPext <$tasklog >$tasklog_stripped
  PostEmerge

  # exited on kill signal
  if [[ $rc -gt 128 ]]; then
    local signal=$((rc - 128))
    if [[ $signal -eq 9 ]]; then
      ps faux | xz >/var/tmp/tb/ps-faux-after-being-killed-9.log.xz
      Finish 9 "KILLed" $tasklog
    else
      pkg=$(ls -d /var/tmp/portage/*/*/work 2>/dev/null | sed -e 's,/var/tmp/portage/,,' -e 's,/work,,' -e 's,:.*,,')
      if [[ $(wc -w <<<$pkg) -eq 1 ]]; then
        if GetPkglog; then
          createIssueDir
          echo "$pkg - emerge killed=$signal" >$issuedir/title
          WorkAtIssue
        fi
        Mail "INFO:  killed=$signal  task=$task  pkg=$pkg" $tasklog
      else
        Mail "NOTICE: killed=$signal  task=$task  too much: pkg=$pkg" $tasklog
        pkg=""
      fi
    fi

  elif [[ $rc -eq 124 ]]; then
    ReachedEOL "timeout  task=$task" $tasklog

  # an error occurred
  elif [[ $rc -gt 0 ]]; then
    if phase=$(grep -e " * The ebuild phase '.*' has exited unexpectedly." $tasklog_stripped | grep -Eo "'.*'"); then
      Finish 0 "phase $phase died"

    elif GetPkgFromTaskLog; then
      GetPkglog
      createIssueDir
      WorkAtIssue
    fi
  fi

  if [[ $rc -gt 0 ]]; then
    if [[ $try_again -eq 0 ]]; then
      if [[ -n $pkg ]]; then
        local self=/etc/portage/package.mask/self
        if [[ ! -s $self ]] || ! grep -q -e "=$pkg$" $self; then
          echo "=$pkg" >>$self
        fi
      fi
      # put world file into same state as if the (previously successfully installed) deps would have been already emerged in separate previous task/s
      if grep -q '^>>> Installing ' $tasklog_stripped; then
        emerge --depclean --verbose=n --pretend 2>/dev/null |
          grep "^All selected packages: " |
          cut -f 2- -d ':' -s |
          xargs -r emerge -O --noreplace &>/dev/null
      fi
    fi
  fi

  if grep -q 'Please run emaint --check world' $tasklog_stripped; then
    add2backlog "%emaint --check world"
  fi

  return $rc
}

# this is the heart of the tinderbox
function WorkOnTask() {
  # @set
  if [[ $task =~ ^@ ]]; then
    local opts=""
    if [[ $task =~ "@world" ]]; then
      opts+=" --update --changed-use --newuse"
      if [[ ! $task =~ " --backtrack=50" ]]; then
        if grep -q '@world --backtrack=' $taskfile.history; then
          task+=" --backtrack=50"
        fi
      fi
    fi

    local histfile=/var/tmp/tb/$(cut -f 1 -d ' ' <<<$task).history
    if RunAndCheck "emerge $task $opts"; then
      echo "$(date) ok" >>$histfile
      if [[ $task =~ "@world" ]]; then
        add2backlog "%emerge --depclean --verbose=n"
        if tail -n 1 /var/tmp/tb/@preserved-rebuild.history 2>/dev/null | grep -q " NOT ok $"; then
          add2backlog "@preserved-rebuild"
        fi
      fi
    else
      echo "$(date) NOT ok $pkg" >>$histfile
      if [[ -n $pkg ]]; then
        if [[ $try_again -eq 0 ]]; then
          add2backlog "$task"
        fi
      else
        if [[ ! $task =~ " --backtrack=" ]] && grep -q -e ' --backtrack=30' -e 'backtracking has terminated early' $tasklog; then
          add2backlog "$task --backtrack=50"
        else
          ReachedEOL "$task is broken" $tasklog
        fi
      fi
    fi

  # %<command line>
  elif [[ $task =~ ^% ]]; then
    local cmd="$(cut -c2- <<<$task)"
    if ! RunAndCheck "$cmd"; then
      if [[ $pkg =~ "sys-devel/gcc" ]]; then
        ReachedEOL "gcc update broken" $tasklog
      elif [[ $cmd =~ "haskell-updater" ]]; then
        ReachedEOL "haskell update broken" $tasklog
      elif [[ $cmd =~ "perl-cleaner" ]]; then
        if grep -q 'The following USE changes are necessary to proceed' $tasklog; then
          ReachedEOL "$task is broken" $tasklog
        fi
      elif [[ $cmd =~ " --depclean" ]]; then
        if grep -q 'Dependencies could not be completely resolved due to' $tasklog; then
          ReachedEOL "$task is broken" $tasklog
        fi
      else
        Mail "INFO: command failed: $cmd" $tasklog
      fi
    fi

  # pinned version
  elif [[ $task =~ ^= ]]; then
    if ! RunAndCheck "emerge $task"; then
      if [[ $pkg =~ "^=$task-" ]]; then
        Mail "INFO: pinned atom failed: $task" $tasklog
      else
        Mail "INFO: dependency of pinned atom $task failed: $pkg" $tasklog
      fi
    fi

  # a common atom
  else
    if ! RunAndCheck "emerge --update $task"; then
      # repeat atom if (one of) its dependency failed
      if [[ -n $pkg && ! $pkg =~ "^$task-" ]]; then
        add2backlog "$task"
      fi
    fi
  fi
}

# EOL if there's a loop
function DetectRepeats() {
  local count
  local item

  read -r count item < <(qlop --nocolor --merge --verbose | tail -n 500 | awk '{ print $3 }' | sort | uniq -c | sort -bnr | head -n 1)
  if [[ $count -ge 5 ]]; then
    ReachedEOL "package too often ($count) emerged: $count x $item"
  fi

  read -r count item < <(tail -n 70 $taskfile.history | sort | uniq -c | sort -bnr | head -n 1)
  if [[ $count -ge 27 ]]; then
    ReachedEOL "task too often ($count) repeated: $count x $item"
  fi
}

function syncRepo() {
  cd /var/db/repos/gentoo

  local synclog=/var/tmp/tb/sync.log
  local curr_time=$EPOCHSECONDS

  if ! emaint sync --auto &>$synclog; then
    if grep -q -e 'git fetch error' -e ': Failed to connect to ' -e ': SSL connection timeout' -e ': Connection timed out' -e 'The requested URL returned error:' $synclog; then
      return 0
    else
      if ! emaint merges --fix &>>$synclog; then
        ReachedEOL "broken repo, cannot be fixed" $synclog
      elif ! emaint sync --auto &>>$synclog; then
        ReachedEOL "broken sync of repo" $synclog
      fi
    fi
  fi

  if grep -q -F '* An update to portage is available.' $synclog; then
    add2backlog "sys-apps/portage"
  fi

  if ! grep -B 1 '=== Sync completed for gentoo' $synclog | grep -q 'Already up to date.'; then
    # retest changed ebuilds with a timeshift of 2 hours to have download mirrors being in sync
    # ignore stderr here due to "warning: log for 'stable' only goes back to"
    git diff \
      --diff-filter="ACM" \
      --name-only \
      "@{ $((EPOCHSECONDS - last_sync + 2 * 3600)) second ago }..@{ 2 hour ago }" 2>/dev/null |
      grep -F -e '/files/' -e '.ebuild' -e 'Manifest' |
      cut -f 1-2 -d '/' -s |
      grep -v -f /mnt/tb/data/IGNORE_PACKAGES |
      sort -u >/tmp/syncRepo.upd

    if [[ -s /tmp/syncRepo.upd ]]; then
      # mix repo changes and backlog together
      sort -u /tmp/syncRepo.upd /var/tmp/tb/backlog.upd | shuf >/tmp/backlog.upd
      # use cp to preserve target file perms
      cp /tmp/backlog.upd /var/tmp/tb/backlog.upd
    fi
  fi

  # this includes that the update of the backlog succeeded
  last_sync=$curr_time

  cd - >/dev/null
}

#############################################################################
#
#       main
#
set -eu
export LANG=C.utf8

if [[ -x "$(command -v gtar)" ]]; then
  tar=gtar
else
  tar=tar # hopefully this handles "--warning=none" too
fi

source $(dirname $0)/lib.sh

export -f SwitchGCC syncRepo         # added to backlog by PostEmerge() or by retest.sh respectively
export -f add2backlog source_profile # used by SwitchGCC()

jobs=$(sed 's,^.*j,,' /etc/portage/package.env/00jobs)
if grep -q '^ACCEPT_KEYWORDS=.*~amd64' /etc/portage/make.conf; then
  keyword="unstable"
else
  keyword="stable"
fi
name=$(cat /var/tmp/tb/name)               # the image name
taskfile=/var/tmp/tb/task                  # the current task
tasklog=$taskfile.log                      # holds output of it
tasklog_stripped=/tmp/tasklog_stripped.log # filtered plain text variant

export CARGO_TERM_COLOR="never"
export CMAKE_COLOR_DIAGNOSTICS="OFF"
export CMAKE_COLOR_MAKEFILE="OFF"
export GCC_COLORS=""
export NO_COLOR="1"
export OCAML_COLOR="never"
export PY_FORCE_COLOR="0"
export PYTEST_ADDOPTS="--color=no"

export TERM=linux
export TERMINFO=/etc/terminfo

export GIT_PAGER="cat"
export PAGER="cat"

export XZ_OPT="-9 -T$jobs"

if [[ $name =~ "_test" ]]; then
  export XRD_LOGLEVEL="Debug"
fi

# non-empty if Finish() was called by an internal error -or- bashrc catched a STOP during sleep
if [[ -s $taskfile ]]; then
  add2backlog "$(cat $taskfile)"
fi

echo "#init" >$taskfile

rm -f $tasklog # remove a possible left over hard link
systemd-tmpfiles --create &>$tasklog || true

trap Finish INT QUIT TERM EXIT

last_sync=$(stat -c %Z /var/db/repos/gentoo/.git/FETCH_HEAD)
while :; do
  if [[ -f /var/tmp/tb/EOL ]]; then
    echo "#catched EOL" >$taskfile
    ReachedEOL "catched EOL" /var/tmp/tb/EOL
  elif [[ -f /var/tmp/tb/STOP ]]; then
    echo "" >$taskfile
    Finish 0 "catched STOP" /var/tmp/tb/STOP
  fi

  # if 1st prio backlog is empty then ...
  if [[ ! -s /var/tmp/tb/backlog.1st ]]; then
    # ... sync repository hourly
    if [[ $((EPOCHSECONDS - last_sync)) -ge 3600 ]]; then
      echo "#syncing repo" >$taskfile
      syncRepo
    fi
    # ... update @world (and then later again always 24 hrs after the previous @world finished)
    wh=/var/tmp/tb/@world.history
    if [[ ! -s $wh || $((EPOCHSECONDS - $(stat -c %Z $wh))) -ge 86400 ]]; then
      /usr/bin/pfl &>/dev/null || true
      add2backlog "@world"
    fi
  fi

  echo "#get next task" >$taskfile
  getNextTask
  echo "$task" | tee -a $taskfile.history >$taskfile
  date >$tasklog
  echo "$task" >>$tasklog
  task_timestamp_prefix=task.$(date +%Y%m%d-%H%M%S).$(tr -d '\n' <<<$task | tr -c '[:alnum:]' '_')
  ln $tasklog /var/tmp/tb/logs/$task_timestamp_prefix.log # no symlink here to keep its content when $tasklog is removed
  WorkOnTask
  rm $tasklog

  echo "#catch misc" >$taskfile
  catchMisc

  echo "#compressing logs" >$taskfile
  if ! find /var/log/portage -name '*.log' -exec xz {} + &>>$taskfile; then
    Mail "NOTICE: error while compressing logs" $taskfile
  fi

  rm -rf /var/tmp/portage/* # "-f" needed if e.g. "pretend" or "fetch" phase failed

  echo "#detecting repeats" >$taskfile
  DetectRepeats
done
