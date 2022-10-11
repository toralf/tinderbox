#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# This is the tinderbox script itself.
# The main function is WorkOnTask().
# The remaining code just parses the output.
# That's all.


function stripQuotesAndMore() {
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
  local subject=$(stripQuotesAndMore <<< $1 | strings -w | cut -c1-200 | tr '\n' ' ')
  local content=${2:-}

  if [[ -f $content ]]; then
    echo
    if [[ $(wc -l < $content) -gt 1000 ]]; then
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
    { echo "$(date) mail issue, \$subject=$subject \$content=$content" >&2 ; }
  fi
}


# http://www.portagefilelist.de
function feedPfl()  {
  local tmp=$(mktemp /tmp/feedPfl_XXXXXX)
  if [[ -x /usr/bin/pfl ]]; then
    if ! /usr/bin/pfl &>$tmp; then
      Mail "WARN: pfl failed" $tmp
    fi
  fi
  rm $tmp
}


# this is the end ...
function Finish()  {
  trap - INT QUIT TERM EXIT
  set +e

  local exit_code=${1:-$?}
  local subject=${2:-<internal error>}

  subject="finished, $(stripQuotesAndMore <<< $subject)"
  if [[ $exit_code -eq 13 ]]; then
    echo "$subject" >>  /var/tmp/tb/EOL
    chmod g+w           /var/tmp/tb/EOL
    chgrp tinderbox     /var/tmp/tb/EOL
    truncate -s 0 $taskfile
    subject+=", $(grep -c ' ::: completed emerge' /var/log/emerge.log 2>/dev/null) completed"
    subject+=", $(ls /var/tmp/tb/issues/*/.reported 2>/dev/null | wc -l) bugs reported"
  fi

  Mail "$subject" ${3:-}
  feedPfl
  rm -f /var/tmp/tb/STOP

  exit $exit_code
}


# helper of getNextTask()
function setBacklog()  {
  if [[ -s /var/tmp/tb/backlog.1st ]]; then
    backlog=/var/tmp/tb/backlog.1st

  elif [[ -s /var/tmp/tb/backlog.upd && $(( RANDOM%4 )) -eq 0 ]]; then
    backlog=/var/tmp/tb/backlog.upd

  elif [[ -s /var/tmp/tb/backlog ]]; then
    backlog=/var/tmp/tb/backlog

  elif [[ -s /var/tmp/tb/backlog.upd ]]; then
    backlog=/var/tmp/tb/backlog.upd

  else
    Finish 13 "all work DONE, reached EOL"   # "13" needed here to trigger a replacement
  fi
}


function getNextTask() {
  while :
  do
    setBacklog

    # move last line of $backlog into $task
    task=$(tail -n 1 $backlog)
    sed -i -e '$d' $backlog

    if [[ -z "$task" || $task =~ ^# ]]; then
      continue

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
      if [[ $? -ne 0 || -z "$best_visible" ]]; then
        continue
      fi

      if [[ "$backlog" != /var/tmp/tb/backlog.1st ]]; then
        if grep -q -f /mnt/tb/data/IGNORE_PACKAGES <<< $best_visible; then
          continue
        fi
      fi

      # skip if $task would be downgraded
      local installed=$(portageq best_version / $task)
      if [[ -n "$installed" ]]; then
        # qatom: error while loading shared libraries: libgomp.so.1: cannot ...
        if qatom --compare $installed $best_visible 2>/dev/null | grep -q -e ' == ' -e ' > '; then
          continue
        fi
      fi

      # valid $task
      break
    fi
  done
}


function CompressIssueFiles()  {
  for f in $(ls $issuedir/files/* 2>/dev/null | grep -v -F '.bz2')
  do
    # compress if bigger than 1/4 MB
    if [[ $(wc -c < $f) -gt $(( 2**18 )) ]]; then
      bzip2 $f
    fi
  done

  # grant write permissions to all artifacts
  chmod    777  $issuedir/{,files}
  chmod -R a+rw $issuedir/
}


function CreateEmergeHistoryFile()  {
  local ehist=$issuedir/files/emerge-history.txt
  local cmd="qlop --nocolor --verbose --merge --unmerge"

  cat << EOF > $ehist
# This file contains the emerge history got with:
# $cmd
EOF
  ($cmd) &>> $ehist
}


# gather together what's needed for the email and b.g.o.
function CollectIssueFiles() {
  apout=$(grep -m 1 -A 2 'Include in your bugreport the contents of'                $tasklog_stripped | grep -F '.out'          | cut -f5 -d' ' -s)
  cmlog=$(grep -m 1 -A 2 'Configuring incomplete, errors occurred'                  $tasklog_stripped | grep "CMake.*\.log"     | cut -f2 -d'"' -s)
  cmerr=$(grep -m 1      'CMake Error: Parse error in cache file'                   $tasklog_stripped | sed  "s/txt./txt/"      | cut -f8 -d' ' -s)
  oracl=$(grep -m 1 -A 1 '# An error report file with more information is saved as' $tasklog_stripped | grep -F '.log'          | cut -f2 -d' ' -s)
  envir=$(grep -m 1      'The ebuild environment file is located at'                $tasklog_stripped                           | cut -f2 -d"'" -s)
  salso=$(grep -m 1 -A 2 ' See also'                                                $tasklog_stripped | grep -F '.log'          | awk '{ print $1 }' )
  sandb=$(grep -m 1 -A 1 'ACCESS VIOLATION SUMMARY'                                 $tasklog_stripped | grep "sandbox.*\.log"   | cut -f2 -d'"' -s)
  roslg=$(grep -m 1 -A 1 'Tests failed. When you file a bug, please attach'         $tasklog_stripped | grep -F '/LastTest.log' | awk '{ print $2 }')

  for f in $apout $cmlog $cmerr $oracl $envir $salso $sandb $roslg
  do
    if [[ -s $f ]]; then
      cp $f $issuedir/files
    fi
  done

  if [[ -d "$workdir" ]]; then
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
          sort -u > $f
      if [[ -s $f ]]; then
        tar -cjpf $issuedir/files/logs.tar.bz2 \
            --dereference \
            --warning='no-file-removed' \
            --warning='no-file-ignored' \
            --files-from $f 2>/dev/null
      fi
      rm $f
    )

    # quirk for sam_
    if [[ -d /var/tmp/clang/$pkg ]]; then
      (
        cd /var/tmp/clang/
        tar -cjpf $issuedir/files/clang.tar.bz2 ./$pkg 2>/dev/null
      )
    fi

    # additional CMake files
    cp ${workdir}/*/CMakeCache.txt $issuedir/files/ 2>/dev/null

    # provide the whole temp dir if possible
    (
      cd "$workdir/../.."
      if [[ -d ./temp ]]; then
        timeout --signal=15 --kill-after=1m 3m tar -cjpf $issuedir/files/temp.tar.bz2 \
            --dereference \
            --warning='no-file-ignored'  \
            --warning='no-file-removed' \
            --exclude='*/go-build[0-9]*/*' \
            --exclude='*/go-cache/??/*' \
            --exclude='*/kerneldir/*' \
            --exclude='*/nested_link_to_dir/*' \
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
    tee -a  $issuedir/issue |
    grep -m 1 '::' | tr ':' ' ' | cut -f3 -d' ' -s
  )
  echo "file collision with $s" > $issuedir/title
}


# helper of ClassifyIssue()
function foundSandboxIssue() {
  if ! grep -q "=$pkg " /etc/portage/package.env/nosandbox 2>/dev/null; then
    printf "%-50s %s\n" "<=$pkg" "nosandbox" >> /etc/portage/package.env/nosandbox
    try_again=1
  fi
  echo "sandbox issue" > $issuedir/title
  if [[ -s $sandb ]]; then
    head -v -n 20 $sandb &> $issuedir/issue
  else
    echo "cannot found $sandb" > $issuedir/issue
  fi
}


# helper of ClassifyIssue()
function foundCflagsIssue() {
  if ! grep -q "=$pkg " /etc/portage/package.env/cflags_default 2>/dev/null; then
    printf "%-50s %s\n" "<=$pkg" "cflags_default" >> /etc/portage/package.env/cflags_default
    try_again=1
  fi
  echo "$1" > $issuedir/title
}


# helper of ClassifyIssue()
function foundGenericIssue() {
  # the order of the pattern within the file/s rules
  (
    if [[ -n "$phase" ]]; then
      cat /mnt/tb/data/CATCH_ISSUES.$phase
    fi
    cat /mnt/tb/data/CATCH_ISSUES
  ) |
  split --lines=1 --suffix-length=4 - /tmp/x_

  for x in /tmp/x_????
  do
    if grep -a -m 1 -B 4 -A 2 -f $x $pkglog_stripped > /tmp/issue; then
      mv /tmp/issue $issuedir/issue
      grep -m 1 -f $x $issuedir/issue | stripQuotesAndMore > $issuedir/title
      break
    fi
  done
  rm /tmp/x_????
}


# helper of ClassifyIssue()
function handleTestPhase() {
  if ! grep -q "=$pkg " /etc/portage/package.env/test-fail-continue 2>/dev/null; then
    printf "%-50s %s\n" "<=$pkg" "test-fail-continue" >> /etc/portage/package.env/test-fail-continue
    try_again=1
  fi

  # tar returns an error if it can't find at least one directory, therefore feed only existing dirs to it
  pushd "$workdir" 1>/dev/null
  local dirs="$(ls -d ./tests ./regress ./t ./Testing ./testsuite.dir 2>/dev/null)"
  if [[ -n "$dirs" ]]; then
    # ignore stderr, eg.:    tar: ./automake-1.13.4/t/instspc.dir/a: Cannot stat: No such file or directory
    tar -cjpf $issuedir/files/tests.tar.bz2 \
        --exclude="*/dev/*" --exclude="*/proc/*" --exclude="*/sys/*" --exclude="*/run/*" \
        --exclude='*.o' --exclude="*/symlinktest/*" \
        --dereference --sparse --one-file-system --warning='no-file-ignored' \
        $dirs 2>/dev/null
  fi
  popd 1>/dev/null
}



# helper of WorkAtIssue()
# get the issue and a descriptive title
function ClassifyIssue() {
  if [[ "$phase" = "test" ]]; then
    handleTestPhase
  fi

  if grep -q -m 1 -F ' * Detected file collision(s):' $pkglog_stripped; then
    foundCollisionIssue

  elif [[ -n $sandb ]]; then # no "-f" b/c it might not exist
    foundSandboxIssue

  # special forced issues
  elif [[ -n "$(grep -m 1 -B 4 -A 1 'sed:.*expression.*unknown option' $pkglog_stripped | tee $issuedir/issue)" ]]; then
    foundCflagsIssue 'ebuild uses colon (:) as a sed delimiter'

  else
    # this gets been overwritten if a pattern matches
    grep -m 1 -A 2 "^ \* ERROR:.* failed \(.* phase\):" $pkglog_stripped | tee $issuedir/issue |
    head -n 2 | tail -n 1 > $issuedir/title
    foundGenericIssue
  fi

  if [[ $(wc -c < $issuedir/issue) -gt 1024 ]]; then
    echo -e "too long lines were shrinked:\n" > /tmp/issue
    cut -c-300 < $issuedir/issue >> /tmp/issue
    mv /tmp/issue $issuedir/issue
  fi

  if [[ ! -s $issuedir/issue || ! -s $issuedir/title ]]; then
    return 1
  fi
}


# helper of WorkAtIssue()
# creates an email containing convenient links and a command line ready for copy+paste
function CompileIssueComment0() {
  emerge -p --info $pkgname &> $issuedir/emerge-info.txt

  cp $issuedir/issue $issuedir/comment0
  cat << EOF >> $issuedir/comment0

  -------------------------------------------------------------------

  This is an $keyword amd64 chroot image at a tinderbox (==build bot)
  name: $name

  -------------------------------------------------------------------

EOF

  (
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
    make --version | head -n 1

    for i in /var/db/repos/*/.git
    do
      cd $i/..
      echo -e "\n  HEAD of ::$(basename $PWD)"
      git show -s HEAD
    done

    echo
    echo "emerge -qpvO $pkgname"
    emerge -qpvO $pkgname | head -n 1
  ) >> $issuedir/comment0 2>/dev/null

  tail -v */etc/portage/package.*/??$keyword >> $issuedir/comment0 2>/dev/null
}


# put world into same state as if the (successfully installed) deps would have been already emerged in previous task/s
function PutDepsIntoWorldFile() {
  if grep -q '^>>> Installing ' $tasklog_stripped; then
    emerge --depclean --verbose=n --pretend 2>/dev/null |
    grep "^All selected packages: "                     |
    cut -f2- -d':' -s                                   |
    xargs --no-run-if-empty emerge -O --noreplace &>/dev/null
  fi
}


# helper of WorkAtIssue()
function setWorkDir() {
  workdir=$(grep -F -m 1 ' * Working directory: ' $tasklog_stripped | cut -f2 -d"'" -s)
  if [[ ! -d "$workdir" ]]; then
    workdir=$(grep -F -m 1 '>>> Source unpacked in ' $tasklog_stripped | cut -f5 -d" " -s)
    if [[ ! -d "$workdir" ]]; then
      workdir=/var/tmp/portage/$pkg/work/$(basename $pkg)
      if [[ ! -d "$workdir" ]]; then
        workdir=""
      fi
    fi
  fi
}


# append to the end of the file to be the next task, but avoid dups
function add2backlog()  {
  if [[ $1 =~ '@' || $1 =~ '%' ]]; then
    if [[ "$(tail -n 1 /var/tmp/tb/backlog.1st)" != "$1" ]]; then
      echo "$1" >> /var/tmp/tb/backlog.1st
    fi
  elif ! grep -q "^${1}$" /var/tmp/tb/backlog.1st; then
    echo "$1" >> /var/tmp/tb/backlog.1st
  fi
}


function finishTitle()  {
  # strip away hex addresses, loong path names, line and time numbers and other stuff
  sed -i  -e 's,0x[0-9a-f]*,<snip>,g'         \
          -e 's,: line [0-9]*:,:line <snip>:,g' \
          -e 's,[0-9]* Segmentation fault,<snip> Segmentation fault,g' \
          -e 's,Makefile:[0-9]*,Makefile:<snip>,g' \
          -e 's,:[[:digit:]]*): ,:<snip>:, g'  \
          -e 's,([[:digit:]]* of [[:digit:]]*),(<snip> of <snip)>,g'  \
          -e 's,[0-9]*[\.][0-9]* sec,,g'      \
          -e 's,[0-9]*[\.][0-9]* s,,g'        \
          -e 's,([0-9]*[\.][0-9]*s),,g'       \
          -e 's, \.\.\.*\., ,g'               \
          -e 's,; did you mean .* \?$,,g'     \
          -e 's,(@INC contains:.*),<@INC snip>,g'     \
          -e "s,ld: /.*/cc......\.o: ,ld: ,g" \
          -e 's,target /.*/,target <snip>/,g' \
          -e 's,(\.text\..*):,(<snip>),g'     \
          -e 's,object index [0-9].*,object index <snip>,g' \
          -e 's,/[^ ]*\(/[^/:]*:\),/...\1,g'  \
          -e 's,ninja: error: /.*/,ninja error: .../,'  \
          -e 's,:[[:digit:]]*:[[:digit:]]*: ,: ,'       \
          -e 's, \w*/.*/\(.*\) , .../\1 ,g' \
          -e 's,\*, ,g'     \
          -e 's,___*,_,g'   \
          -e 's,\s\s*, ,g'  \
          -e 's,mmake\..*:.*:,,g' \
          -e 's,ls[[:digit:]]*:,,g' \
          -e 's,..:..:..\.... \[error\],,g' \
          -e 's,config\......./,config.<snip>/,g' \
        $issuedir/title

  # prefix title
  if [[ $phase = "test" ]]; then
    sed -i -e "s,^,${pkg} fails test - ," $issuedir/title
  else
    sed -i -e "s,^,${pkg} - ," $issuedir/title
  fi
  sed -i -e 's,\s\s*, ,g' $issuedir/title
  truncate -s "<130" $issuedir/title    # b.g.o. limits "Summary" length
}


function SendIssueMailIfNotYetReported()  {
  if ! grep -q -f /mnt/tb/data/IGNORE_ISSUES $issuedir/title; then
    if ! grep -q -F -f $issuedir/title /mnt/tb/data/ALREADY_CAUGHT; then
      # chain "cat" by "echo" b/c cat buffers output which is racy between images
      echo "$(cat $issuedir/title)" >> /mnt/tb/data/ALREADY_CAUGHT

      cp $issuedir/issue $issuedir/body
      echo -e "\n\n\n" >> $issuedir/body
      chmod a+w $issuedir/body

      local known="bug"
      if createSearchString; then
        if SearchForSameIssue 1>> $issuedir/body; then
          return
        elif SearchForSimilarIssue 1>> $issuedir/body; then
          known+=" similar:"
        else
          known+=" unknown:"
        fi
        echo -e "\n\n\ncheck_bgo.sh ~tinderbox/img/$name/$issuedir               -f\n\n\n" >> $issuedir/body
      else
        known+=" raw:"
        echo -e "\n\n\ncheck_bgo.sh ~tinderbox/img/$name/$issuedir\n\n\n" >> $issuedir/body
      fi
      echo "EOF" >> $issuedir/body

      blocker_bug_no=$(LookupForABlocker /mnt/tb/data/BLOCKER)
      if [[ -n $blocker_bug_no ]]; then
        known+=" blocks $blocker_bug_no"
      fi
      Mail "${known} $(cat $issuedir/title)" $issuedir/body
    fi
  fi
}


function maskPackage()  {
  local self=/etc/portage/package.mask/self

  if [[ ! -s $self ]] || ! grep -q -e "=$pkg$" $self; then
    echo "=$pkg" >> $self
  fi
}


function collectPortageDir()  {
  tar -C / -cjpf $issuedir/files/etc.portage.tar.bz2 --dereference etc/portage
}

# analyze the issue
function WorkAtIssue()  {
  local pkglog_stripped=$issuedir/$(tr '/' ':' <<< $pkg).stripped.log
  filterPlainPext < $pkglog > $pkglog_stripped

  cp $pkglog  $issuedir/files
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
  if ! ClassifyIssue; then
    Mail "WARN: cannot classify issue for task '$task'" $pkglog_stripped
  fi

  collectPortageDir
  finishTitle
  CompileIssueComment0
  # grant write permissions to all artifacts
  chmod    777  $issuedir/{,files}
  chmod -R a+rw $issuedir/
  CompressIssueFiles

  if grep -q -e ': perl module .* required' -e 't locate Locale/gettext.pm in' $pkglog_stripped; then
    try_again=1
    add2backlog "$task"
    add2backlog '%perl-cleaner --all'
    return
  fi

  # https://bugs.gentoo.org/show_bug.cgi?id=828872
  if grep -q -e 'internal compiler error:' $issuedir/title; then
    if ! grep -q -e "^=$pkg " /etc/portage/package.env/j1 2>/dev/null; then
      try_again=1
      printf "%-50s %s\n" "=$pkg" "j1" >> /etc/portage/package.env/j1
    fi
  fi

  if [[ $try_again -eq 0 ]]; then
    maskPackage
  else
    add2backlog "$task"
  fi

  SendIssueMailIfNotYetReported
}


function source_profile(){
  set +u
  source /etc/profile 2>/dev/null
  set -u
}


# helper of PostEmerge()
# switch to highest GCC
function SwitchGCC() {
  local highest=$(gcc-config --list-profiles --nocolor | cut -f3 -d' ' -s | grep -E 'x86_64-(pc|gentoo)-linux-(gnu|musl)-.*[0-9]$'| tail -n 1)

  if ! gcc-config --list-profiles --nocolor | grep -q -F "$highest *"; then
    local current=$(gcc -dumpversion)
    echo "$FUNCNAME: major version change detected, switch from $current to $highest" | tee -a $taskfile.history
    gcc-config --nocolor $highest
    source_profile
    add2backlog "@preserved-rebuild"
    if grep -q '^LIBTOOL="rdlibtool"' /etc/portage/make.conf; then
      add2backlog "sys-devel/slibtool"
    fi
    add2backlog "sys-devel/libtool"
    add2backlog "%emerge --unmerge sys-devel/gcc:$(cut -f1 -d'.' <<< $current)"
  fi
}


# helper of RunAndCheck()
# schedules follow-ups from the current emerge operation
function PostEmerge() {
  if ls /etc/._cfg????_locale.gen &>/dev/null; then
    locale-gen > /dev/null
    rm /etc/._cfg????_locale.gen
  elif grep -q "IMPORTANT: config file '/etc/locale.gen' needs updating." $tasklog_stripped; then
    locale-gen > /dev/null
  fi

  # don't change these config files after image setup
  rm -f /etc/._cfg????_{hosts,resolv.conf} /etc/conf.d/._cfg????_hostname /etc/ssmtp/._cfg????_ssmtp.conf /etc/portage/._cfg????_make.conf

  # merge the remaining config files automatically
  etc-update --automode -5 1>/dev/null

  # update the environment
  env-update &>/dev/null
  source_profile

  # this is the least important task
  if grep -q -F 'Use emerge @preserved-rebuild to rebuild packages using these libraries' $tasklog_stripped; then
    add2backlog "@preserved-rebuild"
  fi

  if grep -q -F -e "Please, run 'haskell-updater'" \
                -e "ghc-pkg check: 'checking for other broken packages:'" $tasklog_stripped; then
    add2backlog '@world'
    add2backlog "%haskell-updater"
  fi

  if grep -q  -e ">>> Installing .* dev-lang/perl-[1-9]" \
              -e 'Use: perl-cleaner' $tasklog_stripped; then
    add2backlog '@world'
    add2backlog '%perl-cleaner --all'
  fi

  if grep -q -F '* An update to portage is available.' $tasklog_stripped; then
    add2backlog "sys-apps/portage"
  fi

  if grep -q ">>> Installing .* sys-devel/gcc-[1-9]" $tasklog_stripped; then
    add2backlog "%SwitchGCC"
  fi

  if grep -q ">>> Installing .* dev-lang/ruby-[1-9]" $tasklog_stripped; then
    local current=$(eselect ruby show | head -n 2 | tail -n 1 | xargs)
    local highest=$(eselect ruby list | tail -n 1 | awk '{ print $2 }')

    if [[ "$current" != "$highest" ]]; then
      add2backlog "%eselect ruby set $highest"
    fi
  fi
}


function createIssueDir() {
  issuedir=/var/tmp/tb/issues/$(date +%Y%m%d-%H%M%S)-$(tr '/' '_' <<< $pkg)
  mkdir -p $issuedir/files || return $?
  chmod 777 $issuedir # allow to edit title etc. manually
}


function catchMisc()  {
  find /var/log/portage/ -mindepth 1 -maxdepth 1 -type f -newer $taskfile |
  while read -r pkglog
  do
    if [[ $(wc -l < $pkglog) -le 6 ]]; then
      continue
    fi

    local pkglog_stripped=/tmp/$(basename $pkglog | sed -e "s,\.log$,.stripped.log,")
    filterPlainPext < $pkglog > $pkglog_stripped
    if grep -q -f /mnt/tb/data/CATCH_MISC $pkglog_stripped; then
      pkg=$( grep -m 1 -F ' * Package: '    $pkglog_stripped | awk '{ print $3 }')
      pkg=$(sed -e 's,:.*,,' <<< $pkg)  # strip away the slot
      phase=""
      pkgname=$(qatom --quiet "$pkg" | grep -v -F '(null)' | cut -f1-2 -d' ' -s | tr ' ' '/')

      # create for each finding an own issue
      grep -f /mnt/tb/data/CATCH_MISC $pkglog_stripped |
      while read -r line
      do
        createIssueDir || continue
        echo "$line" > $issuedir/title
        grep -m 1 -F -e "$line" $pkglog_stripped > $issuedir/issue
        cp $pkglog $issuedir/files
        cp $pkglog_stripped $issuedir
        finishTitle
        cp $issuedir/issue $issuedir/comment0
        cat << EOF >> $issuedir/comment0

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
  done
}


function GetPkgFromTaskLog() {
  pkg=$(grep -m 1 -F ' * Package: ' $tasklog_stripped | awk '{ print $3 }')
  if [[ -z "$pkg" ]]; then
    pkg=$(grep -m 1 '>>> Failed to emerge .*/.*' $tasklog_stripped | cut -f5 -d' ' -s | cut -f1 -d',' -s)
    if [[ -z "$pkg" ]]; then
      pkg=$(grep -F ' * Fetch failed' $tasklog_stripped | grep -o "'.*'" | sed "s,',,g")
      if [[ -z $pkg ]]; then
        return 1
      fi
    fi
  fi
  pkg=$(sed -e 's,:.*,,' <<< $pkg)  # strip away the slot

  pkgname=$(qatom --quiet "$pkg" | grep -v -F '(null)' | cut -f1-2 -d' ' -s | tr ' ' '/')
  pkglog=$(grep -o -m 1 "/var/log/portage/$(tr '/' ':' <<< $pkgname).*\.log" $tasklog_stripped)
  if [[ ! -f $pkglog ]]; then
    Mail "INFO: cannot get pkglog for pkg=$pkg task=$task" $tasklog_stripped
    return 1
  fi
}


# helper of WorkOnTask()
# run $1 in a subshell and act on result, timeout after $2
function RunAndCheck() {
  unset phase pkgname pkglog
  try_again=0           # "1" means to retry same task, but with possible changed USE/ENV/FEATURE/CFLAGS

  # the value of -jX of the image name gives the number of parallel build processes
  local j=$(grep -Eo '\-j[0-9]+' <<< $name | cut -c3-)
  local hours=$(( ${2:-24}/j )) # $2 differs usually only for @world
  timeout --signal=15 --kill-after=5m ${hours}h bash -c "eval $1" &>> $tasklog
  local rc=$?
  (echo; date) >> $tasklog

  tasklog_stripped="/tmp/tasklog_stripped.log"    # this is on tmpfs

  filterPlainPext < $tasklog > $tasklog_stripped
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

  # got a signal
  if [[ $rc -ge 128 ]]; then
    local signal=$(( rc-128 ))
    PutDepsIntoWorldFile
    if [[ $signal -eq 9 ]]; then
      Finish 9 "KILLed" $tasklog  # usually before a reboot
    fi
    pkg=$(ls -d /var/tmp/portage/*/*/work 2>/dev/null | head -n 1 | sed -e 's,/var/tmp/portage/,,' -e 's,/work,,')
    pkg=$(sed -e 's,:.*,,' <<< $pkg)  # strip away the slot
    Mail "INFO:  signal=$signal  task=$task  pkg=$pkg" $tasklog
  fi

  if [[ $rc -ne 0 ]]; then
    if GetPkgFromTaskLog; then
      createIssueDir
      WorkAtIssue
      if [[ $try_again -eq 0 ]]; then
        PutDepsIntoWorldFile
      fi
    fi
    if [[ $rc -eq 124 ]]; then
      Finish 13 "INFO:  timeout  task=$task" $tasklog
    fi
  fi

  if fatal=$(grep -m 1 -f /mnt/tb/data/FATAL_ISSUES $tasklog_stripped); then
    Finish 13 "FATAL:  $fatal" $tasklog
  fi

  return $rc
}


# this is the heart of the tinderbox
function WorkOnTask() {
  # @set
  if [[ $task =~ ^@ ]]; then
    local opts=""
    if [[ $task = "@world" ]]; then
      opts+=" --update --changed-use --newuse"
    fi

    if RunAndCheck "emerge $task $opts" "48"; then
      echo "$(date) ok" >> /var/tmp/tb/$task.history
      if [[ $task = "@world" ]]; then
        add2backlog "%emerge --depclean --verbose=n"
        if tail -n 1 /var/tmp/tb/@preserved-rebuild.history 2>/dev/null | grep -q " NOT ok $"; then
          add2backlog "@preserved-rebuild"
        fi
      fi
    else
      echo "$(date) NOT ok $pkg" >> /var/tmp/tb/$task.history
      if [[ -n "$pkg" ]]; then
        if [[ $try_again -eq 0 ]]; then
          add2backlog "$task"
        fi
      else
        Finish 13 "$task is broken" $tasklog
      fi
    fi

  # %<command line>
  elif [[ $task =~ ^% ]]; then
    local cmd="$(cut -c2- <<< $task)"
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
    if ! RunAndCheck "emerge --update $task"; then
      :
    fi
  fi
}


# not more than n attempts of @xy within last N tasks
function DetectTaskLoop() {
  local n=7
  local N=20
  local histfile=/var/tmp/tb/task.history

  for pattern in 'perl-cleaner' '@world' '@preserved-rebuild'
  do
    if [[ $pattern = '@world' ]]; then
      n=12
      if [[ $name =~ "_test" || $name =~ "_debug" ]]; then
        continue
      fi
    fi
    if [[ $(tail -n $N $histfile | grep -c "$pattern") -ge $n ]]; then
      echo "$(date) too much $pattern" >> $histfile
      Finish 13 "detected a repeat in $pattern" $histfile
    fi
  done
}


function syncRepo()  {
  local synclog=/var/tmp/tb/sync.log
  local curr_time=$EPOCHSECONDS

  cd /var/db/repos/gentoo

  if ! emaint sync --auto &>$synclog; then
    if grep -q -e 'git fetch error' -e ': Failed to connect to ' -e ': SSL connection timeout' -e ': Connection timed out' -e 'The requested URL returned error:' $synclog; then
      return 0
    fi

    if (echo -e "\nTrying to restore ...\n"; git stash; git stash drop; git restore .) &>>$synclog; then
      if ! emaint sync --auto &>>$synclog; then
        Finish 13 "still unfixed ::gentoo" $synclog
      else
        Mail "INFO: fixed ::gentoo" $synclog
      fi
    else
      Finish 13 "cannot restore ::gentoo" $synclog
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
        "@{ $(( EPOCHSECONDS-last_sync+3600 )) second ago }".."@{ 1 hour ago }" |
    grep -F -e '/files/' -e '.ebuild' -e 'Manifest' |
    cut -f1-2 -d'/' -s |
    grep -v -f /mnt/tb/data/IGNORE_PACKAGES |
    sort -u > /tmp/syncRepo.upd

    if [[ -s /tmp/syncRepo.upd ]]; then
      # mix repo changes and backlog together
      sort -u /tmp/syncRepo.upd /var/tmp/tb/backlog.upd | shuf > /tmp/backlog.upd
      # no mv to preserve target file perms
      cp /tmp/backlog.upd /var/tmp/tb/backlog.upd
    fi
  fi

  last_sync=$curr_time
}


#############################################################################
#
#       main
#
set -eu
export LANG=C.utf8
trap Finish INT QUIT TERM EXIT

source $(dirname $0)/lib.sh

export -f SwitchGCC syncRepo source_profile add2backlog      # to call it eg. from %SwitchGCC

taskfile=/var/tmp/tb/task           # holds the current task
tasklog=$taskfile.log               # holds output of it
name=$(cat /var/tmp/tb/name)        # the image name
grep -q '^ACCEPT_KEYWORDS=.*~amd64' /etc/portage/make.conf && keyword="unstable" || keyword="stable"

export CARGO_TERM_COLOR="never"
export CMAKE_COLOR_DIAGNOSTICS="OFF"
export CMAKE_COLOR_MAKEFILE="OFF"
export GCC_COLORS=""
export OCAML_COLOR="never"
export PY_FORCE_COLOR="0"
export PYTEST_ADDOPTS="--color=no"

export TERM=linux
export TERMINFO=/etc/terminfo

export GIT_PAGER="cat"
export PAGER="cat"

# re-schedule $task (non-empty == Failed() before)
if [[ -s $taskfile ]]; then
  add2backlog "$(cat $taskfile)"
fi

echo "#init" > $taskfile
rm -f $tasklog  # remove any remaining hard link
if ! systemd-tmpfiles --create &>$tasklog; then
  : # Mail "NOTICE: tmpfiles issue" $tasklog
fi

last_sync=$(stat -c %Y /var/db/repos/gentoo/.git/FETCH_HEAD)
while :
do
  for i in EOL STOP
  do
    if [[ -f /var/tmp/tb/$i ]]; then
      echo "#catched $i" > $taskfile
      Finish 0 "catched $i" /var/tmp/tb/$i
    fi
  done

  if [[ $(( EPOCHSECONDS-last_sync )) -ge 3600 ]]; then
    echo "#sync repo" > $taskfile
    syncRepo
  fi

  echo "#get next task" > $taskfile
  # if 1st prio is empty then schedule the daily update if needed
  if [[ ! -s /var/tmp/tb/backlog.1st ]]; then
    h=/var/tmp/tb/@world.history
    if [[ ! -s $h || $(( EPOCHSECONDS-$(stat -c %Y $h) )) -ge 86400 ]]; then
      add2backlog "@world"
    fi
  fi
  getNextTask

  rm -rf /var/tmp/portage/*
  if [[ $task =~ ^@ ]]; then
    echo "#feed pfl" > $taskfile
    feedPfl
  fi

  { date; echo; } > $tasklog
  task_timestamp_prefix=task.$(date +%Y%m%d-%H%M%S).$(tr -d '\n' <<< $task | tr -c '[:alnum:]' '_')
  ln $tasklog /var/tmp/tb/logs/$task_timestamp_prefix.log
  echo "$task" | tee -a $taskfile.history $tasklog > $taskfile
  WorkOnTask
  rm $tasklog # the hard link target will remain

  if [[ $task =~ ^@ ]]; then
    echo "#feed pfl" > $taskfile
    feedPfl
  fi
  truncate -s 0 $taskfile

  DetectTaskLoop
done
