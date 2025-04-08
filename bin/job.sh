#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# This is the tinderbox script itself.
# The main function is WorkOnTask().
# The remaining code just parses the output.
# That's all.

function Mail() {
  local subject=$(stripQuotesAndMore <<<${1:-"NO SUBJECT"} | strings -w | cut -c 1-200 | tr '\n' ' ')
  local attachment=${2-}

  if [[ -n $attachment ]]; then
    echo
    tail -v -n 100 $attachment
  fi |
    strings -w |
    sed -e 's,^>, >,' |
    if ! mail -s "$subject @ $name" ${MAILTO:-tinderbox} &>/var/tmp/mail.log; then
      echo "$(date) mail issue, \$subject=$subject \$attachment=$attachment" >&2
      cat /var/tmp/mail.log >&2
    fi
}

function ReachedEOL() {
  local subject=${1:-"NO SUBJECT"}
  local attachment=${2-}

  if [[ -z $attachment ]]; then
    if [[ -s /var/tmp/tb/EOL ]]; then
      attachment="/var/tmp/tb/EOL"
    elif [[ -s /var/tmp/tb/STOP ]]; then
      attachment="/var/tmp/tb/STOP"
    fi
  fi

  echo "$subject" >>/var/tmp/tb/EOL
  chmod a+w /var/tmp/tb/EOL
  truncate -s 0 $taskfile
  local new=$(ls /var/tmp/tb/issues/*/.reported 2>/dev/null | wc -l)
  local all=$(ls -d /var/tmp/tb/issues/* 2>/dev/null | wc -l)
  /usr/bin/pfl &>/dev/null || true
  subject+=", $(grep -c ' ::: completed emerge' /var/log/emerge.log) completed, $new#$all bug(s) new"
  Finish "EOL $subject" $attachment
}

# this is the end ...
function Finish() {
  local rc=$?
  set +e
  trap - INT QUIT TERM EXIT

  local subject
  if [[ -z ${1-} ]]; then
    subject="INTERNAL ERROR"
  else
    subject="finished"
  fi
  if [[ $rc -ne 0 ]]; then
    subject+=" rc=$rc"
  fi
  subject+=" $(stripQuotesAndMore <<<${1-})"

  Mail "$subject" ${2-}
  if [[ $rc -ne 0 || -z ${1-} ]]; then
    echo "$subject" >>/var/tmp/tb/STOP
  else
    rm -f /var/tmp/tb/STOP
  fi
  exit $rc
}

# helper of getNextTask()
function setBacklog() {
  if [[ -s /var/tmp/tb/backlog.1st ]]; then
    echo "/var/tmp/tb/backlog.1st"

  elif [[ -s /var/tmp/tb/backlog.upd && $((RANDOM % 4)) -eq 0 ]]; then
    echo "/var/tmp/tb/backlog.upd"

  elif [[ -s /var/tmp/tb/backlog ]]; then
    echo "/var/tmp/tb/backlog"

  elif [[ -s /var/tmp/tb/backlog.upd ]]; then
    echo "/var/tmp/tb/backlog.upd"

  else
    return 1
  fi
}

# either set $task to a valid entry or exit
function getNextTask() {
  while :; do
    if ! backlog=$(setBacklog); then
      ReachedEOL "all work DONE"
    fi

    # move content of the last line of $backlog into $task
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
      Finish "$task"

    elif [[ $task =~ ^@ || $task =~ ^% || $task =~ ' ' ]]; then
      break

    elif [[ $task =~ ^= ]]; then
      if portageq best_visible / $task &>/dev/null; then
        break
      fi

    else
      # skip it if no package version for $task is visible
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

      # skip it if $task would be downgraded
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
  local cmd="qlop --nocolor --verbose --merge --unmerge" # no --summary, b/c that would force alphabetical sorting

  local outfile=$issuedir/files/emerge-history.txt
  cat <<EOF >$outfile
# This file contains the emerge history, created at $(date) by:
# $cmd
#
EOF
  $cmd >>$outfile

  outfile=$issuedir/files/qlist-info.txt
  cmd="qlist --nocolor --verbose --installed --umap --slots --slots" # twice to get subslots too
  cat <<EOF >$outfile
# This file contains the qlist info, created at $(date) by:
# $cmd
#
EOF
  $cmd >>$outfile

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
      cd "$workdir/.."
      f=/tmp/files
      find ./ \
        -name 'CMake*.*' \
        -o -name 'testlog.*' \
        -o -name '*.binlog' \
        -o -name '*.log' \
        -o -name '*.txt' \
        -o -wholename '*/tests/*.out' |
        grep -v -e '/docs/' >$f
      if [[ -s $f ]]; then
        $tar -cJpf $issuedir/files/logs.tar.xz --files-from $f --dereference --warning=none 2>/dev/null
      fi
      rm $f
    )

    cp ${workdir}/*/CMakeCache.txt $issuedir/files/ 2>/dev/null || true

    if [[ -d $workdir/../../temp ]]; then
      $tar -C $workdir/../.. -cJpf $issuedir/files/temp.tar.xz \
        --warning=none --sparse \
        --exclude='*/.tmp??????/*' \
        --exclude='*/cc*.ltrans*.o' \
        --exclude='*/garbage.*' \
        --exclude='*/go-build/??/*' \
        --exclude='*/go-cache/??/*' \
        --exclude='*/go-mod/*' \
        --exclude='*/kerneldir/*' \
        --exclude='*/nested_link_to_dir/*' \
        --exclude='*/rustc-*-src/vendor/*' \
        --exclude='*/temp/NuGetScratchportage/*' \
        --exclude='*/temp/nugets/*' \
        --exclude='*/testdirsymlink/*' \
        --exclude='*/var-tests/*' \
        --exclude='*/zig-cache/*' \
        ./temp
    fi

    # ICE
    cp $workdir/../gcc-build-logs.tar.* $issuedir/files 2>/dev/null || true
  fi

  if grep -q "^$pkgname$" /mnt/tb/data/KEEP_BUILD_ARTEFACTS; then
    find $workdir/.. -ls 2>&1 | xz >$issuedir/files/var-tmp-portage.filelist.txt.xz
    $tar --warning=none -C /var/tmp/portage/ -cJpf $issuedir/files/var-tmp-portage.tar.xz .
    Mail "INFO: kept artefacts in $issuedir" $tasklog_stripped
    echo "kept artefacts in $issuedir" >>/var/tmp/tb/KEEP
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
    printf "%-55s %s\n" "<=$pkg" "nosandbox" >>/etc/portage/package.env/nosandbox
    try_again=1
  fi
  echo "sandbox issue" >$issuedir/title
  if [[ -s $sandb ]]; then
    head -v -n 20 $sandb >$issuedir/issue
  else
    echo "cannot found $sandb" >$issuedir/issue
  fi
}

# helper of ClassifyIssue()
function foundCflagsIssue() {
  if ! grep -q "=$pkg " /etc/portage/package.env/cflags_default 2>/dev/null; then
    printf "%-55s %s\n" "<=$pkg" "cflags_default" >>/etc/portage/package.env/cflags_default
    try_again=1
  fi
  echo "$1" >$issuedir/title
}

# helper of ClassifyIssue()
function foundGenericIssue() {
  (
    cd /mnt/tb/data/
    # the order of patterns rules

    cat CATCH_ISSUES-pre
    cat CATCH_ISSUES.${phase:-compile}
    cat CATCH_ISSUES-post
  ) |
    split --lines=1 --suffix-length=4 - /tmp/x_

  for x in /tmp/x_????; do
    if grep -a -m 1 -B 6 -A 2 -f $x $pkglog_stripped >$issuedir/issue; then
      if [[ ! -s $issuedir/issue ]]; then
        # happened e.g. for media-libs/esdl
        ReachedEOL "empty issue" $pkglog_stripped
      fi
      grep -m 1 -f $x $issuedir/issue | stripQuotesAndMore >$issuedir/title
      break
    fi
  done
  rm /tmp/x_????
}

# helper of ClassifyIssue()
function handleFeatureTest() {
  if ! grep -q "<=$pkg " /etc/portage/package.env/notest 2>/dev/null && ! grep -q -e "^$pkgname .*notest" /etc/portage/package.env/80test-y; then
    try_again=1
    if [[ $phase == "test" ]] && ! grep -q "<=$pkg " /etc/portage/package.env/test-fail-continue 2>/dev/null; then
      # try to keep the dependency tree
      printf "%-55s %s\n" "<=$pkg" "test-fail-continue" >>/etc/portage/package.env/test-fail-continue
    else
      # no chance, note: already installed dependencies might no longer be needed and therefore are candidates for being depcleaned
      printf "%-55s %s\n" "<=$pkg" "notest" >>/etc/portage/package.env/notest
    fi
  fi

  # gtar returns an error if it can't find any directory, therefore feed dirs to it to catch only real tar issues
  (
    cd "$workdir"
    dirs="$(ls -d ./tests ./regress ./t ./Testing ./testsuite.dir 2>/dev/null)"
    if [[ -n $dirs ]]; then
      $tar --warning=none -cJpf $issuedir/files/tests.tar.xz \
        --one-file-system --sparse \
        --exclude='*.o' \
        --exclude="*/dev/*" \
        --exclude="*/proc/*" \
        --exclude="*/run/*" \
        --exclude="*/sys/*" \
        $dirs
    fi
  )
}

# helper of WorkAtIssue()
# get the issue and a descriptive title
function ClassifyIssue() {
  if grep -q -f /mnt/tb/data/CATCH_ISSUES-fatal $pkglog_stripped; then
    ReachedEOL "FATAL issue" $pkglog_stripped
  fi

  if [[ $name =~ "_test" ]]; then
    handleFeatureTest
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
    cut -c -300 <$issuedir/issue >>/tmp/issue
    mv /tmp/issue $issuedir/issue
  fi

  if [[ ! -s $issuedir/title ]]; then
    Mail "INFO: no title for $issuedir" $issuedir/issue
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
EOF

  if grep -q -r "# DICE.*\[.*\]" /etc/portage/package.{accept_keywords,unmask}/; then
    (
      echo -e "\n  KEYWORDED/UNMASKED"
      while read -r dice; do
        echo -en "\n  "
        (grep -A 1 "^\[$dice\]" /mnt/tb/data/DICE_DESCRIPTIONS || echo) | xargs
        grep -hr " \[$dice\]" /etc/portage/package.{accept_keywords,unmask}/ |
          awk '{ print (" ", $1) }' |
          sort -u
      done < <(
        grep -hr "# DICE.*\[.*\]" /etc/portage/package.{accept_keywords,unmask}/ |
          grep -Eo '(\[.*\])' |
          tr -d '][' |
          sort -u
      )
    ) >>$issuedir/comment0
  fi

  if grep -q "^GNUMAKEFLAGS.*--shuffle" /etc/portage/make.conf; then
    (
      echo -e "\n  Block bug #351559 if this looks like a parallel build issue."
      if [[ -s $pkglog_stripped ]]; then
        shuffle=$(grep -h -m 1 -Eo "( shuffle=[1-9].*)" $pkglog_stripped)
        if [[ -n $shuffle ]]; then
          echo "  Possible reproducer: MAKEOPTS='... $shuffle'"
        fi
      fi
    ) >>$issuedir/comment0
  fi

  cat <<EOF >>$issuedir/comment0

  The attached etc.portage.tar.xz has all details.
  -------------------------------------------------------------------

EOF

  (
    grep -e "^CC=" -e "^CXX=" -e "^GNUMAKEFLAGS" /etc/portage/make.conf
    grep -e "^GENTOO_VM=" -e "^JAVACFLAGS=" $tasklog_stripped
    echo "gcc-config -l:"
    gcc-config -l
    clang --version | head -n 1
    echo -n "llvm-config: "
    llvm-config --version
    python -V
    go version
    eselect php list cli
    eselect ruby list
    eselect rust list
    java-config --list-available-vms --nocolor
    eselect java-vm list
    ghc --version

    for i in /var/db/repos/*/.git; do
      cd $i/..
      echo -e "\n  HEAD of ::$(basename $PWD)"
      git show -s HEAD
    done

    echo -e "\nemerge -qpvO =$pkg"
    emerge -qpvO =$pkg | head -n 1
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
        # there's no work dir e.g. in "fetch" phase
        workdir=""
      fi
    fi
  fi
}

function add2backlog() {
  local bl=/var/tmp/tb/backlog.1st

  if [[ $1 == '@preserved-rebuild' ]]; then
    # this has lowest prio
    sed -i -e "/$1/d" $bl # dups
    if [[ -s $bl ]]; then
      sed -i -e "1 i$1" $bl # insert before 1st line == will be the last task
    else
      echo "$1" >>$bl # backlog was empty before
    fi
  elif [[ $1 =~ "emerge -e @world" ]]; then
    echo "%emerge --resume" >>$bl
  else
    sed -i -e "/^$(sed -e 's,/,\\/,g' <<<$1)$/d" $bl # dups
    echo "$1" >>$bl                                  # append it == will be the next task
  fi

  # re-schedule it to be the next task
  if [[ $1 != "%SwitchGCC" ]] && grep -q '%SwitchGCC' $bl; then
    sed -i -e '/%SwitchGCC/d' $bl
    echo "%SwitchGCC" >>$bl
  fi
}

function finishTitle() {
  # strip away hex addresses, line numbers, timestamps, paths etc.
  sed -i \
    -e 's,ld: /.*/cc......\.o: ,ld: ,g' \
    -e 's,/[^ ]*/\([^/:]*\),/.../\1,g' \
    -e 's,^\.*/*\.\.\./,,' \
    -e 's, \.\.\./, ,g' \
    -e 's,:[0-9]*:[0-9]*: ,: ,' \
    -e 's,0x[0-9a-f]*,<snip>,g' \
    -e 's,:[0-9]*): ,:<snip>:, g' \
    -e 's,([0-9]* of [0-9]*),(<snip> of <snip)>,g' \
    -e 's,[0-9]*[\.][0-9]* sec,,g' \
    -e 's,[0-9]*[\.][0-9]* s,,g' \
    -e 's,([0-9]*[\.][0-9]*s),,g' \
    -e 's,..:..:..\.... \[error\],,g' \
    -e 's,; did you mean .* \?$,,g' \
    -e 's,config\......./,config.<snip>/,g' \
    -e 's,GMfifo.*,GMfifo<snip>,g' \
    -e 's,(@INC contains:.*),<@INC snip>,g' \
    -e 's,: line [0-9]*:,:line <snip>:,g' \
    -e 's,ls[0-9]*:,,g' \
    -e 's,Makefile.*.tmp:[0-9]*,Makefile,g' \
    -e 's,Makefile:[0-9]*,Makefile:<snip>,g' \
    -e 's,mmake\..*:.*:,,g' \
    -e 's,ninja: error: /.*/,ninja error: ,' \
    -e 's,object index [0-9].*,object index <snip>,g' \
    -e 's,QA Notice: , ,' \
    -e 's,[0-9]* Segmentation fault,<snip> Segmentation fault,g' \
    -e 's,shuffle=[0-9]*,,g' \
    -e 's,target /.*/,target <snip>/,g' \
    -e 's,(\.text[+\.].*):,(<snip>),g' \
    -e 's,\*, ,g' \
    -e 's,___*,_,g' \
    -e 's,\s\s*, ,g' \
    $issuedir/title

  # prefix title
  if [[ $phase == "test" ]]; then
    sed -i -e "s,^,$pkg fails test - ," $issuedir/title
  else
    sed -i -e "s,^,$pkg - ," $issuedir/title
  fi
  sed -i -E 's,\s+, ,g' $issuedir/title
}

function SendIssueMailIfNotYetReported() {
  local do_report=${1:-1}

  if [[ ! -s $issuedir/title ]]; then
    ReachedEOL "empty title"
  fi

  if grep -q -F -f $issuedir/title /mnt/tb/findings/ALREADY_CAUGHT; then
    return 0
  else
    # avoid writes of multiple tinderbox images into the same line
    cat $issuedir/title | tee -a /mnt/tb/findings/ALREADY_CAUGHT 1>/dev/null
  fi

  if [[ $do_report -eq 0 ]]; then
    return 0
  fi

  for f in /mnt/tb/data/IGNORE_ISSUES /mnt/tb/data/CATCH_ISSUES.{pretend,setup}; do
    if grep -q -f $f $issuedir/title; then
      return 0
    fi
  done

  cp $issuedir/issue $issuedir/body
  echo -e "\n\n" >>$issuedir/body
  chmod a+w $issuedir/body

  local hints="bug"
  local force=""

  if checkBgo &>>$issuedir/body; then
    if SearchForSameIssue &>>$issuedir/body; then
      return
    elif BgoIssue; then
      hints+=" b.g.o outage"
    else
      if SearchForSimilarIssue &>>$issuedir/body; then
        hints+=" similar"
        force="                                -f"
      elif BgoIssue; then
        hints+=" b.g.o outage"
      else
        hints+=" new"
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
}

# analyze the issue
function WorkAtIssue() {
  local do_report=${1:-1}

  local pkglog_stripped=$issuedir/$(tr '/' ':' <<<$pkg).stripped.log
  filterPlainText <$pkglog >$pkglog_stripped

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

  if grep -q -F 't locate Locale/gettext.pm in' $pkglog_stripped; then
    ReachedEOL "perl-cleaner Perl dep issue pkg=$pkg" $pkglog_stripped
  fi

  if grep -q -F "Please, run 'haskell-updater'" $pkglog_stripped; then
    do_report=0
    try_again=1
    add2backlog "$task"
    add2backlog "%haskell-updater"
  fi

  SendIssueMailIfNotYetReported $do_report
}

function source_profile() {
  set +u
  source /etc/profile
  set -u
}

function SwitchGCC() {
  local highest=$(gcc-config --list-profiles --nocolor | cut -f 3 -d ' ' -s | grep -E 'x86_64-(pc|gentoo)-linux-(gnu|musl)-[0-9]+$' | tail -n 1)
  if [[ -z $highest ]]; then
    Mail "cannot get GCC version"
    return
  fi

  if [[ $(gcc-config --get-current-profile --nocolor) != "$highest" ]]; then
    local v
    v=$(gcc -dumpversion)
    gcc-config --nocolor $highest
    source_profile
    add2backlog "%emerge -1 --selective=n --deep=0 -u dev-build/libtool"
    # sam_
    if grep -q '^LIBTOOL="rdlibtool"' /etc/portage/make.conf; then
      add2backlog "dev-build/slibtool"
    fi
    add2backlog "%emerge --unmerge sys-devel/gcc:$(cut -f 1 -d '.' <<<$v)"
  fi
}

# helper of RunAndCheck()
# schedules follow-ups from the current emerge operation
function PostEmerge() {
  # immediately needed for the 17.1->23.0 transition
  env-update >/dev/null 2>>$tasklog
  source_profile

  if [[ ! $name =~ "musl" ]]; then
    if ls /etc/._cfg????_locale.gen &>/dev/null; then
      locale-gen >/dev/null
      rm /etc/._cfg????_locale.gen
    elif grep -q "IMPORTANT: config file '/etc/locale.gen' needs updating." $tasklog_stripped; then
      locale-gen >/dev/null
    fi
  fi
  # content pinned by image setup
  rm -f /etc/._cfg????_{hosts,msmtprc,resolv.conf} /etc/conf.d/._cfg????_hostname /etc/portage/._cfg????_make.conf /etc/ssmtp/._cfg????_ssmtp.conf
  etc-update --automode -5 >/dev/null 2>>$tasklog

  # catch updated /etc
  env-update >/dev/null 2>>$tasklog
  source_profile

  # quirk for left over processes
  for p in dirmngr gpg-agent; do
    if pgrep -a $p &>>/var/tmp/pkill.log; then
      pkill -e $p &>>/var/tmp/pkill.log
    fi
  done

  # run this as the very last step
  if grep -q 'Use emerge @preserved-rebuild to rebuild packages using these libraries' $tasklog_stripped; then
    add2backlog "@preserved-rebuild"
    # no @world and no deplean after this
  fi

  if grep -q -F 'Use: perl-cleaner --all' $tasklog_stripped; then
    add2backlog '%perl-cleaner --all'
  fi

  if grep -q ">>> Installing .* dev-lang/ruby-[1-9]" $tasklog_stripped; then
    local highest current
    highest=$(eselect ruby list | awk 'END { print $2 }')
    if [[ -n $highest ]]; then
      current=$(eselect ruby show | sed -n -e '2p' | xargs)
      if [[ $current != "$highest" ]]; then
        add2backlog "%eselect ruby set $highest"
      fi
    fi
  fi

  if grep -q ">>> Installing .* sys-devel/gcc-[1-9]" $tasklog_stripped; then
    if ! grep -q "%emerge -e @world" /var/tmp/tb/backlog.1st; then
      # needed at least for -flto and/or merged-usr to avoid segfaults of lto1
      add2backlog "%emerge -1u /lib*/*.a /usr/lib*/*.a @world" # adding @world here avoids dep issues
    fi
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

    local stripped=/tmp/$(basename $pkglog).stripped
    filterPlainText <$pkglog >$stripped

    pkg=$(basename $pkglog | cut -f 1-2 -d ':' -s | tr ':' '/')
    phase=""
    pkgname=$(qatom --quiet "$pkg" | grep -v -F '(null)' | cut -f 1-2 -d ' ' -s | tr ' ' '/')

    # grep for "GiB", but take the KiB values; this works b/c size_sum above 4 GiB is of interest (which is greater than 2)
    read -r size_build size_install <<<$(grep -A 1 -e ' Final size of build directory: .* GiB' $stripped | grep -Eo '[0-9\.]+ KiB' | cut -f 1 -d ' ' -s | xargs)
    if [[ -n $size_build && -n $size_install ]]; then
      size_sum=$(awk '{ printf ("%.1f", ($1 + $2) / 1024.0 / 1024.0) }' <<<"$size_build $size_install")
      echo "$size_sum GiB $pkg" >>/var/tmp/xgqt.txt
    fi

    # create for each finding an own issue
    grep -f /mnt/tb/data/CATCH_MISC $stripped |
      while read -r line; do
        createIssueDir
        echo "$line" >$issuedir/title
        grep -m 1 -A 7 -F -e "$line" $stripped >$issuedir/issue
        cp $pkglog $issuedir/files
        cp $stripped $issuedir
        finishTitle
        cp $issuedir/issue $issuedir/comment0
        cat <<EOF >>$issuedir/comment0

  -------------------------------------------------------------------

  This is an $keyword amd64 chroot image at a tinderbox (==build bot)
  name: $name

  The build log matches a QA pattern or sth. requested by a dev.
  The attached etc.portage.tar.xz has all details.
  -------------------------------------------------------------------

EOF
        CollectClangFiles
        collectPortageFiles
        CreateEmergeInfo
        CompressIssueFiles
        SendIssueMailIfNotYetReported
      done
    rm $stripped
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
      pkg=$(grep -F ' * Fetch failed' $tasklog_stripped | grep -o "'.*'" | tr -d \')
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
  # the 48 hours are for -j 4
  timeout --signal=15 --kill-after=5m 48h bash -c "$1" &>>$tasklog
  local rc=$?
  set -e

  echo -e "\n--\n$(date)\nrc=$rc" >>$tasklog
  pkg=""
  unset phase pkgname pkglog
  try_again=0 # "1" means to retry same task
  filterPlainText <$tasklog >$tasklog_stripped
  PostEmerge

  # exited on kill signal
  if [[ $rc -gt 128 ]]; then
    local signal=$((rc - 128))
    if [[ $signal -eq 9 ]]; then
      ps faux | xz >/var/tmp/tb/ps-faux-after-being-killed-9.log.xz
      Finish "KILLed" $tasklog
    else
      pkg=$(ls -d /var/tmp/portage/*/*/work 2>/dev/null | sed -e 's,/var/tmp/portage/,,' -e 's,/work,,' -e 's,:.*,,')
      if [[ $signal -eq 15 ]]; then
        if GetPkglog; then
          createIssueDir
          echo "$pkg - emerge TERMinated" >$issuedir/title
          WorkAtIssue 0
        fi
      else
        ReachedEOL "signal=$signal  task=$task  pkg=$pkg" $tasklog
      fi
    fi

  # timed out
  elif [[ $rc -eq 124 ]]; then
    ReachedEOL "timeout  task=$task" $tasklog

  # emerge failed
  elif [[ $rc -gt 0 ]] || grep -q -F '* ERROR: ' $tasklog_stripped; then
    if phase=$(grep -e " * The ebuild phase '.*' has exited unexpectedly." $tasklog_stripped | grep -Eo "'.*'"); then
      if [[ -f /var/tmp/tb/EOL ]]; then
        ReachedEOL "caught EOL in $phase()" $tasklog
      elif [[ -f /var/tmp/tb/STOP ]]; then
        Finish "caught STOP in $phase()" $tasklog
      else
        ReachedEOL "$phase() died, rc=$rc" $tasklog
      fi

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
      # to not lose current installed deps put the world file into the similar state
      # as the one where deps would been alreadey emerged before
      if grep -q '^>>> Installing ' $tasklog_stripped; then
        emerge --depclean --verbose=n --pretend 2>/dev/null |
          grep "^All selected packages: " |
          cut -f 2- -d ':' -s |
          xargs -r emerge -O --noreplace &>/dev/null
      fi
    fi
  fi

  if grep -q 'Please run emaint --check world' $tasklog_stripped; then
    emaint --check world 1>/dev/null
  fi

  return $rc
}

# this is the heart of the tinderbox
function WorkOnTask() {
  local backtrack_opt=""

  # dry-run mainly to check for the infamous perl dep issue
  if [[ $task =~ "@world" ]]; then
    local dryrun_cmd="emerge -p -v $task"
    if [[ $task =~ ^% ]]; then
      dryrun_cmd=$(sed -e 's,%emerge,emerge -p -v,' <<<$task)
    fi

    if ! $dryrun_cmd &>>$tasklog; then
      if grep -q -F '(backtrack: 20/20)' $tasklog; then
        backtrack_opt="--backtrack=50"
        if ! $dryrun_cmd $backtrack_opt &>>$tasklog; then
          ReachedEOL "dry-run failed ($backtrack_opt)" $tasklog
        else
          Mail "INFO: $backtrack_opt needed" $tasklog
        fi
      else
        ReachedEOL "dry-run failed" $tasklog
      fi
    fi

    echo -e "\ncheck for Perl dep issue\n" >>$tasklog
    for i in net-libs/libmbim x11-libs/pango; do
      if grep -Eo "^\[ebuild .*(dev-lang/perl|$i|dev-perl/Locale-gettext)" $tasklog |
        cut -f 2- -d ']' |
        awk '{ print $1 }' |
        xargs |
        grep -q -F "dev-perl/Locale-gettext $i dev-lang/perl"; then
        ReachedEOL "Perl dep issue for $i" $tasklog
      fi
    done
    echo -e "\ncheck for Perl dep issue succeeded\n" >>$tasklog
  fi

  if [[ $task == "@world" ]]; then
    if RunAndCheck "emerge $task $backtrack_opt"; then
      if ! grep -q 'WARNING: One or more updates/rebuilds have been skipped due to a dependency conflict:' $tasklog; then
        add2backlog "%emerge --depclean --verbose=n"
      fi
    else
      if [[ -n $pkg ]]; then
        if [[ $try_again -eq 0 ]]; then
          add2backlog "$task"
        fi
      else
        ReachedEOL "$task is broken" $tasklog
      fi
    fi

  # %<command line>
  elif [[ $task =~ ^% ]]; then
    if ! RunAndCheck "$(cut -c 2- <<<$task) $backtrack_opt"; then
      if [[ $try_again -eq 1 ]]; then
        add2backlog "$task"
      elif grep -q 'The following USE changes are necessary to proceed' $tasklog; then
        ReachedEOL "failed: USE changes" $tasklog
      elif [[ $task =~ " --depclean" ]]; then
        if grep -q 'Dependencies could not be completely resolved due to' $tasklog; then
          ReachedEOL "failed: deps" $tasklog
        fi
      elif [[ -n $pkg ]]; then
        if [[ $pkg =~ "sys-devel/gcc" ]] && [[ ! $name =~ "_llvm" ]]; then
          ReachedEOL "system compiler failed: $pkg" $tasklog
        elif [[ $pkg =~ "llvm-core/clang" || $pkg =~ "llvm-core/llvm" ]] && [[ $name =~ "_llvm" ]]; then
          ReachedEOL "system compiler failed: $pkg" $tasklog
        elif [[ $task =~ $pkg ]]; then
          ReachedEOL "failed: $pkg" $tasklog
        else
          add2backlog "$task"
        fi
      else
        ReachedEOL "failed: (no pkg)" $tasklog
      fi
    fi

  # pinned version
  elif [[ $task =~ ^= ]]; then
    if ! RunAndCheck "emerge $task"; then
      if [[ $pkg =~ "^=$task-" ]]; then
        Mail "INFO: failed: $task" $tasklog
      else
        Mail "INFO: dependency of $task failed: $pkg" $tasklog
      fi
    fi

  # common emerge update
  else
    if ! RunAndCheck "emerge --update $task"; then
      if [[ $task == "@preserved-rebuild" ]]; then
        if [[ -n $pkg || $try_again -eq 1 ]]; then
          add2backlog "$task"
        else
          ReachedEOL "$task failed" $tasklog
        fi
      fi
    else
      if [[ $task == "@preserved-rebuild" ]]; then
        if grep -q -F '!!! existing preserved libs:' $tasklog; then
          ReachedEOL "$task still has preserved libs" $tasklog
        fi
      fi
    fi
  fi
}

# especially @preserved-rebuild repeats are likely
function DetectRepeats() {
  local count item
  read -r count item < <(tail -n 90 $taskfile.history | sort | uniq -c | sort -bnr | head -n 1)
  if [[ $count -ge 40 ]]; then
    ls -l /var/tmp/tb/logs | tail -n 30 >/tmp/ls-l.txt
    ReachedEOL "repeated: $count x $item" /tmp/ls-l.txt
  elif [[ ! $name =~ "_test" ]]; then
    if [[ $count -ge 20 ]] || [[ ! $item =~ ^% && $count -ge 10 ]]; then
      ls -l /var/tmp/tb/logs | tail -n 30 >/tmp/ls-l.txt
      ReachedEOL "repeated: $count x $item" /tmp/ls-l.txt
    fi
  fi
}

function syncRepo() {
  cd /var/db/repos/gentoo

  local synclog=/var/tmp/tb/sync.log
  local curr_time=$EPOCHSECONDS

  if ! emaint sync --auto &>$synclog; then
    if grep -q -e 'git fetch error' -e ': Failed to connect to ' -e ': SSL connection timeout' -e ': Connection timed out' -e 'The requested URL returned error:' $synclog; then
      return 0
    elif ! emaint merges --fix &>>$synclog; then
      ReachedEOL "repo sync failure, unable to fix" $synclog
    fi
  fi

  if grep -q -F '* An update to portage is available.' $synclog; then
    add2backlog "sys-apps/portage"
  fi

  if ! grep -B 1 '=== Sync completed for gentoo' $synclog | grep -q 'Already up to date.'; then
    # retest changed ebuilds with a timeshift of 2 hours to ensure that download mirrors are synced
    # ignore stderr here expecially b/c of "warning: log for 'stable' only goes back to"
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
      # cp preserves file perms of the target
      cp /tmp/backlog.upd /var/tmp/tb/backlog.upd
    fi
  fi

  last_sync=$curr_time # global variable

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
export name=$(cat /var/tmp/tb/name)  # the image name used by SwitchGCC()

jobs=$(sed 's,^.*j,,' /etc/portage/package.env/00jobs)
if grep -q '^ACCEPT_KEYWORDS=.*~amd64' /etc/portage/make.conf; then
  keyword="unstable"
else
  keyword="stable"
fi
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

# non-empty if Finish() was called by an internal error -or- bashrc caught a STOP during sleep
if [[ -s $taskfile ]]; then
  add2backlog "$(cat $taskfile)"
fi

echo "#init" >$taskfile

rm -f $tasklog # remove a possible left over hard link
systemd-tmpfiles --create &>$tasklog || true

trap Finish INT QUIT TERM EXIT

# https://bugs.gentoo.org/928938
ulimit -Hn 512000
ulimit -Sn 512000

last_sync=$(stat -c %Z /var/db/repos/gentoo/.git/FETCH_HEAD)
while :; do
  echo "" >$taskfile
  if [[ -f /var/tmp/tb/EOL ]]; then
    ReachedEOL "caught EOL" /var/tmp/tb/EOL
  elif [[ -f /var/tmp/tb/STOP ]]; then
    Finish "caught STOP" /var/tmp/tb/STOP
  fi

  # sync repository hourly
  if [[ $((EPOCHSECONDS - last_sync)) -ge 3600 ]]; then
    echo "#syncing repo" >$taskfile
    syncRepo
  fi

  if [[ ! -s /var/tmp/tb/backlog.1st ]]; then
    last_world=$(ls /var/tmp/tb/logs/task.*._world.log 2>/dev/null | tail -n 1)
    if [[ ! -f $last_world || $((EPOCHSECONDS - $(stat -c %Z $last_world))) -ge 86400 ]]; then
      /usr/bin/pfl &>/dev/null || true
      add2backlog "@world"
    fi
  fi

  echo "#get next task" >$taskfile
  getNextTask
  date >$tasklog
  echo "$task" | tee -a $tasklog $taskfile.history >$taskfile
  task_timestamp_prefix=task.$(date +%Y%m%d-%H%M%S).$(tr -d '\n' <<<$task | tr -c '[:alnum:]' '_' | cut -c -128)
  ln $tasklog /var/tmp/tb/logs/$task_timestamp_prefix.log
  WorkOnTask
  rm $tasklog

  echo "#catch misc" >$taskfile
  catchMisc

  echo "#compressing logs" >$taskfile
  if ! find /var/log/portage -name '*.log' -exec xz {} + &>>$tasklog; then
    Mail "NOTICE: error while compressing logs" $tasklog
  fi

  rm -rf /var/tmp/portage/* # "-f" needed if e.g. "pretend" or "fetch" phase failed

  echo "#detecting repeats" >$taskfile
  DetectRepeats
done
