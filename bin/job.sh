#!/bin/bash
# set -x


# This is the tinderbox script itself.
# The main function is WorkOnTask().
# The remaining code just parses the output.
# That's all.


# strip quotes and friends
function stripQuotesAndMore() {
  sed -e 's,['\''‘’"`•],,g' -e 's/\xE2\x80\x98|\xE2\x80\x99//g' # UTF-2018+2019 (left+right single quotation mark)
}


# filter leftovers of ansifilter
function filterPlainPext() {
  perl -wne '
      s,\x00,\n,g;
      s,\r\n,\n,g;
      s,\r,\n,g;
      print;
  '
}


function Mail() {
  local subject=$(stripQuotesAndMore <<< $1 | cut -c1-200 | tr '\n' ' ')
  local content=${2:-}

  echo "#send out email" > $taskfile
  if [[ -f $content ]]; then
    echo
    tail -n 1000 $content | sed -e 's,^>>>, >>>,'
    echo -e " \n \n \n \n less ~tinderbox/img/$name/$content\n \n \n"
  else
    echo -e "$content"
  fi |\
  if ! (mail -s "$subject   @ $name" -- ${MAILTO:-tinderbox} 1>/dev/null); then
    { echo "$(date) issue, \$subject=$subject \$content=$content" >&2 ; }
  fi
}


# http://www.portagefilelist.de
function feedPfl()  {
  if [[ -x /usr/bin/pfl ]]; then
    cp $taskfile $taskfile.old
    echo "#feed pfl" > $taskfile
    /usr/bin/pfl &>/dev/null
    cp $taskfile.old $taskfile
    rm $taskfile.old
    return 0    # pfl is not mandatory
  fi
}


# this is the end ...
function Finish()  {
  local exit_code=${1:-$?}
  local subject=${2:-<internal error>}

  trap - INT QUIT TERM EXIT
  set +e

  feedPfl
  subject=$(stripQuotesAndMore <<< $subject)
  subject+="; $(grep -c ' ::: completed emerge' /var/log/emerge.log 2>/dev/null || echo '0') completed"
  if [[ $exit_code -eq 0 ]]; then
    Mail "finish ok: $subject" ${3:-}
    truncate -s 0 $taskfile
  else
    Mail "finish NOT ok, exit_code=$exit_code, $subject" ${3:-}
  fi

  if [[ $exit_code -eq 13 ]]; then
    echo "$subject" > /var/tmp/tb/REPLACE_ME
  fi
  rm -f /var/tmp/tb/STOP

  exit $exit_code
}


# helper of getNextTask()
function setTaskAndBacklog()  {
  if [[ -s /var/tmp/tb/backlog.1st ]]; then
    backlog=/var/tmp/tb/backlog.1st

  elif [[ -s /var/tmp/tb/backlog.upd && $(( $RANDOM%4 )) -eq 0 ]]; then
    backlog=/var/tmp/tb/backlog.upd

  elif [[ -s /var/tmp/tb/backlog ]]; then
    backlog=/var/tmp/tb/backlog

  elif [[ -s /var/tmp/tb/backlog.upd ]]; then
    backlog=/var/tmp/tb/backlog.upd

  else
    Finish 13 "#empty backlogs"
  fi

  # move last line of $backlog into $task
  task=$(tail -n 1 $backlog)
  sed -i -e '$d' $backlog
}


function getNextTask() {
  while :
  do
    setTaskAndBacklog

    if [[ -z "$task" || $task =~ ^# ]]; then
      continue  # empty line or comment

    elif [[ $task =~ ^INFO ]]; then
      Mail "$task"
      continue

    elif [[ $task =~ ^STOP ]]; then
      Finish 0 "catched STOP task"

    elif [[ $task =~ ^@ || $task =~ ^% ]]; then
      break  # @set or %command

    elif [[ $task =~ ^= ]]; then
      # pinned version, nevertheless check validity
      if portageq best_visible / $task &>/dev/null; then
        break
      fi

    else
      if [[ "$backlog" != /var/tmp/tb/backlog.1st ]]; then
        if grep -q -f /mnt/tb/data/IGNORE_PACKAGES <<< $task; then
          continue
        fi
      fi

      # skip if $task is not visible
      local best_visible=$(portageq best_visible / $task 2>/dev/null)
      if [[ $? -ne 0 || -z "$best_visible" ]]; then
        continue
      fi

      # skip if $task would be downgraded
      local installed=$(portageq best_version / $task)
      if [[ -n "$installed" ]]; then
        if qatom --compare $installed $best_visible | grep -q -e ' == ' -e ' > '; then
          continue
        fi
      fi

      # valid $task
      break
    fi
  done
}


# helper of CollectIssueFiles
function collectPortageDir()  {
  (cd / && tar -cjpf $issuedir/files/etc.portage.tar.bz2 --dereference etc/portage)
}


# b.g.o. has a limit of 1 MB
function CompressIssueFiles()  {
  for f in $(ls $issuedir/files/* 2>/dev/null | grep -v -F '.bz2')
  do
    if [[ $(wc -c < $f) -gt 1048576 ]]; then
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
  apout=$(grep -m 1 -A 2 'Include in your bugreport the contents of'                 $tasklog_stripped | grep -F '.out'        | cut -f5 -d' ' -s)
  cmlog=$(grep -m 1 -A 2 'Configuring incomplete, errors occurred'                   $tasklog_stripped | grep "CMake.*\.log"   | cut -f2 -d'"' -s)
  cmerr=$(grep -m 1      'CMake Error: Parse error in cache file'                    $tasklog_stripped | sed  "s/txt./txt/"    | cut -f8 -d' ' -s)
  oracl=$(grep -m 1 -A 1 '# An error report file with more information is saved as:' $tasklog_stripped | grep -F '.log'        | cut -f2 -d' ' -s)
  envir=$(grep -m 1      'The ebuild environment file is located at'                 $tasklog_stripped                         | cut -f2 -d"'" -s)
  salso=$(grep -m 1 -A 2 ' See also'                                                 $tasklog_stripped | grep -F '.log'        | awk '{ print $1 }' )
  sandb=$(grep -m 1 -A 1 'ACCESS VIOLATION SUMMARY'                                  $tasklog_stripped | grep "sandbox.*\.log" | cut -f2 -d'"' -s)
  roslg=$(grep -m 1 -A 1 'Tests failed. When you file a bug, please attach the following file: ' $tasklog_stripped | grep -F '/LastTest.log' | awk ' { print $2 } ')

  for f in $apout $cmlog $cmerr $oracl $envir $salso $sandb $roslg
  do
    if [[ -s $f ]]; then
      cp $f $issuedir/files
    fi
  done

  if [[ -d "$workdir" ]]; then
    # catch relevant logs
    (
      set -e
      f=/var/tmp/tb/files
      cd "$workdir/.."
      find ./ -name "*.log" \
          -o -name "testlog.*" \
          -o -wholename '*/elf/*.out' \
          -o -wholename '*/softmmu-build/*' \
          -o -name "meson-log.txt" |\
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

    # additional cmake files
    cp ${workdir}/*/CMakeCache.txt $issuedir/files/ 2>/dev/null

    # provide the whole temp dir if possible
    (
      set -e
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
    if [[ -f $workdir/gcc-build-logs.tar.bz2 ]]; then
      cp $workdir/gcc-build-logs.tar.bz2 $issuedir/files
    fi
  fi
}


# helper of ClassifyIssue()
function foundCollisionIssue() {
  # get the colliding package name
  local s=$(
    grep -m 1 -A 5 'Press Ctrl-C to Stop' $tasklog_stripped |\
    tee -a  $issuedir/issue |\
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
  head -n 10 $sandb &> $issuedir/issue
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
  ) | split --lines=1 --suffix-length=4 - /tmp/x_

  for x in /tmp/x_????
  do
    if grep -m 1 -a -B 4 -A 2 -f $x $pkglog_stripped > /tmp/issue; then
      mv /tmp/issue $issuedir
      sed -n "5p" $issuedir/issue | stripQuotesAndMore > $issuedir/title # works for 5 == B+1 -> at least B+1 lines are expected
      break
    fi
  done
  rm -f /tmp/x_????
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
    grep -m 1 -A 2 " \* ERROR:.* failed (.* phase):" $pkglog_stripped | tee $issuedir/issue |\
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
    echo "php cli:"
    eselect php list cli

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


# make world state similar to that if the (successfully installed) deps were emerged earlier in previous emerge/s
function PutDepsIntoWorldFile() {
  if grep -q '^>>> Installing ' $tasklog_stripped; then
    emerge --depclean --verbose=n --pretend 2>/dev/null |\
    grep "^All selected packages: "                     |\
    cut -f2- -d':' -s                                   |\
    xargs --no-run-if-empty emerge -O --noreplace &>/dev/null
  fi
}


# helper of WorkAtIssue()
# for ABI_X86="32 64" we have two ./work directories in /var/tmp/portage/<category>/<name>
function setWorkDir() {
  workdir=$(fgrep -m 1 " * Working directory: '" $tasklog_stripped | cut -f2 -d"'" -s)
  if [[ ! -d "$workdir" ]]; then
    workdir=$(fgrep -m 1 ">>> Source unpacked in " $tasklog_stripped | cut -f5 -d" " -s)
    if [[ ! -d "$workdir" ]]; then
      workdir=/var/tmp/portage/$pkg/work/$(basename $pkg)
      if [[ ! -d "$workdir" ]]; then
        workdir=""
      fi
    fi
  fi
}


# append onto the file == is the next task
function add2backlog()  {
  # no duplicates
  if [[ "$(tail -n 1 /var/tmp/tb/backlog.1st)" != "$1" ]]; then
    echo "$1" >> /var/tmp/tb/backlog.1st
  fi
}


function finishTitle()  {
  # strip away hex addresses, loong path names, line and time numbers and other stuff
  sed -i  -e 's/0x[0-9a-f]*/<snip>/g'         \
          -e 's/: line [0-9]*:/:line <snip>:/g' \
          -e 's/[0-9]* Segmentation fault/<snip> Segmentation fault/g' \
          -e 's/Makefile:[0-9]*/Makefile:<snip>/g' \
          -e 's,:[[:digit:]]*): ,:<snip>:, g'  \
          -e 's,([[:digit:]]* of [[:digit:]]*),(<snip> of <snip)>,g'  \
          -e 's,[0-9]*[\.][0-9]* sec,,g'      \
          -e 's,[0-9]*[\.][0-9]* s,,g'        \
          -e 's,([0-9]*[\.][0-9]*s),,g'       \
          -e 's/ \.\.\.*\./ /g'               \
          -e 's/; did you mean .* \?$//g'     \
          -e 's/(@INC contains:.*)/<@INC snip>/g'     \
          -e "s,ld: /.*/cc......\.o: ,ld: ,g" \
          -e 's,target /.*/,target <snip>/,g' \
          -e 's,(\.text\..*):,(<snip>),g'     \
          -e 's,object index [0-9].*,object index <snip>,g' \
          -e 's,/[^ ]*\(/[^/:]*:\),/...\1,g'  \
          -e 's,ninja: error: /.*/,ninja error: .../,'  \
          -e 's,:[[:digit:]]*:[[:digit:]]*: ,: ,'       \
          -e 's, \w*/.*/\(.*\) , .../\1 ,g' \
          -e 's,\*, ,g'   \
          -e 's/___*/_/g' \
          -e 's/  */ /g'  \
        $issuedir/title

  # prefix title
  sed -i -e "s,^,${pkg} - ," $issuedir/title
  if [[ $phase = "test" ]]; then
    sed -i -e "s,^,[TEST] ," $issuedir/title
  fi
  sed -i -e 's,  *, ,g' $issuedir/title
  truncate -s "<${1:-130}" $issuedir/title    # b.g.o. limits "Summary" length
}


function SendIssueMailIfNotYetReported()  {
  if ! grep -q -f /mnt/tb/data/IGNORE_ISSUES $issuedir/title; then
    if ! grep -q -F -f $issuedir/title /mnt/tb/data/ALREADY_CATCHED; then
      # chain "cat" by "echo" b/c cat has a buffered output which is racy between images
      echo "$(cat $issuedir/title)" >> /mnt/tb/data/ALREADY_CATCHED
      echo -e "check_bgo.sh ~tinderbox/img/$name/$issuedir\n\n\n" > $issuedir/body
      cat $issuedir/issue >> $issuedir/body
      Mail "$(cat $issuedir/title)" $issuedir/body
    fi
  fi
}


function maskPackage()  {
  local self=/etc/portage/package.mask/self
  # unmask take precedence over mask -> unmasked packages (eg. glibc) cannot be masked in case of a failure
  if ! grep -q -e "=$pkg$" $self; then
    echo "=$pkg" >> $self
  fi
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
    grep -m 1 -o " \* ERROR:.* failed (.* phase):" $pkglog_stripped |\
    grep -Eo '\(.* ' |\
    tr -d '[( ]'
  )
  setWorkDir
  CreateEmergeHistoryFile
  CollectIssueFiles
  if ! ClassifyIssue; then
    Mail "cannot classify issue for task '$task'" $pkglog_stripped
  fi

  collectPortageDir
  finishTitle
  CompileIssueComment0
  # grant write permissions to all artifacts
  chmod    777  $issuedir/{,files}
  chmod -R a+rw $issuedir/
  CompressIssueFiles

  if grep -q -e 'error: perl module .* required' -e 'Cant locate Locale/gettext.pm in' $issuedir/title; then
    try_again=1
    add2backlog "$task"
    add2backlog "%perl-cleaner --all"
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
# switch to latest GCC
function SwitchGCC() {
  local latest=$(gcc-config --list-profiles --nocolor | cut -f3 -d' ' -s | grep -E 'x86_64-(pc|gentoo)-linux-(gnu|musl)-.*[0-9]$'| tail -n 1)
  local current=$(gcc -dumpversion | cut -f1 -d'.')

  if gcc-config --list-profiles --nocolor | grep -q -F "$latest *"; then
    echo "SwitchGCC: $current is $latest"
  else
    echo "SwitchGCC: switch from $current to $latest" >> $taskfile.history
    gcc-config --nocolor $latest
    source_profile
    add2backlog "@preserved-rebuild"
    if grep -q '^LIBTOOL="rdlibtool"' /etc/portage/make.conf; then
      add2backlog "sys-devel/slibtool"
    fi
    add2backlog "sys-devel/libtool"
    add2backlog "%emerge --unmerge sys-devel/gcc:$current"
  fi
}


# helper of RunAndCheck()
# it schedules follow-ups from the last emerge operation
function PostEmerge() {
  # regen locale if eg. a new glibc was installed
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

  # the last next task
  if grep -q -F 'Use emerge @preserved-rebuild to rebuild packages using these libraries' $tasklog_stripped; then
    add2backlog "@preserved-rebuild"
  fi

  if grep -q  -e "Please, run 'haskell-updater'" \
              -e "ghc-pkg check: 'checking for other broken packages:'" $tasklog_stripped; then
    add2backlog "%haskell-updater"
  fi

  if grep -q  -e ">>> Installing .* dev-lang/perl-[1-9]" \
              -e 'Use: perl-cleaner' $tasklog_stripped; then
    add2backlog "@world"      # implies --depclean if successful
    add2backlog "%perl-cleaner --all"
  fi

  if grep -q ">>> Installing .* sys-devel/gcc-[1-9]" $tasklog_stripped; then
    add2backlog "%SwitchGCC"
  fi

  if grep -q ">>> Installing .* dev-lang/ruby-[1-9]" $tasklog_stripped; then
    local current=$(eselect ruby show | head -n 2 | tail -n 1 | xargs)
    local latest=$(eselect ruby list | tail -n 1 | awk ' { print $2 } ')

    if [[ "$current" != "$latest" ]]; then
      add2backlog "%eselect ruby set $latest"
    fi
  fi

  # the first next task
  if grep -q -F '* An update to portage is available.' $tasklog_stripped; then
    add2backlog "sys-apps/portage"
  fi

  # if 1st prio is empty then schedule the daily update if it is time
  if [[ ! -s /var/tmp/tb/backlog.1st ]]; then
    local h=/var/tmp/tb/@world.history
    if [[ ! -s $h || $(( EPOCHSECONDS-$(stat -c %Y $h) )) -ge 86400 ]]; then
      add2backlog "@world"
    fi
  fi
}


function createIssueDir() {
  issuedir=/var/tmp/tb/issues/$(date +%Y%m%d-%H%M%S)-$(tr '/' '_' <<< $pkg)
  mkdir -p $issuedir/files || return $?
  chmod 777 $issuedir # allow to edit title etc. manually
}


function catchMisc()  {
  find /var/log/portage/ -mindepth 1 -maxdepth 1 -type f -newer $taskfile |\
  while read -r pkglog
  do
    if [[ $(wc -l < $pkglog) -le 6 ]]; then
      continue
    fi

    local pkglog_stripped=/tmp/$(basename $pkglog | sed -e "s,\.log$,.stripped.log,")
    filterPlainPext < $pkglog > $pkglog_stripped
    if grep -q -f /mnt/tb/data/CATCH_MISC $pkglog_stripped; then
      pkg=$( grep -m 1 -F ' * Package: '    $pkglog_stripped | awk ' { print $3 } ')
      repo=$(grep -m 1 -F ' * Repository: ' $pkglog_stripped | awk ' { print $3 } ')
      phase=""

      grep -f /mnt/tb/data/CATCH_MISC $pkglog_stripped |\
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
  pkg=$(grep -m 1 -F ' * Package: ' $tasklog_stripped | awk ' { print $3 } ')
  if [[ -z "$pkg" ]]; then
    pkg=$(grep -m 1 '>>> Failed to emerge .*/.*' $tasklog_stripped | cut -f5 -d' ' -s | cut -f1 -d',' -s)
    if [[ -z "$pkg" ]]; then
      pkg=$(grep -F ' * Fetch failed' $tasklog_stripped | grep -o "'.*'" | sed "s,',,g")
      if [[ -z $pkg ]]; then
        return 1
      fi
    fi
  fi

  pkgname=$(qatom --quiet "$pkg" 2>/dev/null | grep -v '(null)' | cut -f1-2 -d' ' -s | tr ' ' '/')
  pkglog=$(grep -o -m 1 "/var/log/portage/$(tr '/' ':' <<< $pkgname).*\.log" $tasklog_stripped)
  if [[ ! -f $pkglog ]]; then
    Mail "INFO: cannot get pkglog for pkg '$pkg' task '$task'" $tasklog_stripped
    return 1
  fi
}


# helper of WorkOnTask()
# run $1 in a subshell and act on result, timeout after $2
function RunAndCheck() {
  unset phase pkgname pkglog
  try_again=0           # "1" means to retry same task, but with possible changed USE/ENV/FEATURE/CFLAGS

  timeout --signal=15 --kill-after=5m ${2:-12h} bash -c "eval $1" &>> $tasklog
  local rc=$?
  (echo; date) >> $tasklog

  local taskname=task.$(date +%Y%m%d-%H%M%S).$(tr -d '\n' <<< $task | tr -c '[:alnum:]' '_')
  tasklog_stripped="/var/tmp/tb/logs/$taskname.log"

  filterPlainPext < $tasklog > $tasklog_stripped
  PostEmerge
  catchMisc

  if [[ -n "$(ls /tmp/core.* 2>/dev/null)" ]]; then
    if grep -q -F ' -Og -g' /etc/portage/make.conf; then
      local taskdirname=/var/tmp/tb/core/$taskname
      mkdir -p $taskdirname
      mv /tmp/core.* $taskdirname
      Mail "INFO: kept core files in $taskdirname" "$(ls -lh $taskdirname/)" $tasklog_stripped
    else
      rm /tmp/core.*
    fi
  fi

  # got a signal
  if [[ $rc -ge 128 ]]; then
    local signal=$(( rc-128 ))
    PutDepsIntoWorldFile
    if [[ $signal -eq 9 ]]; then
      Finish 9 "exiting due to signal $signal" $tasklog_stripped
    else
      Mail "WARN: got signal $signal  task=$task" $tasklog_stripped
    fi

  # timeout
  elif [[ $rc -eq 124 ]]; then
    Mail "INFO: timeout  task=$task" $tasklog_stripped
    PutDepsIntoWorldFile

  # emerge failed
  elif [[ $rc -ne 0 ]]; then
    if GetPkgFromTaskLog; then
      createIssueDir
      WorkAtIssue
      if [[ $try_again -eq 0 ]]; then
        PutDepsIntoWorldFile
      fi
    fi
  fi

  if fatal=$(grep -m 1 -f /mnt/tb/data/FATAL_ISSUES $tasklog_stripped); then
    Finish 1 "FATAL: $fatal" $tasklog_stripped
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

    feedPfl
    if RunAndCheck "emerge $task $opts" "24h"; then
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
        add2backlog "$task"
      elif [[ $task = "@world" ]]; then
        Finish 13 "@world is broken" $tasklog
      fi
    fi
    feedPfl

  # %<command line>
  elif [[ $task =~ ^% ]]; then
    local cmd="$(cut -c2- <<< $task)"
    if ! RunAndCheck "$cmd"; then
      if [[ ! $cmd =~ " --depclean" && ! $cmd =~ "grep -q " ]]; then
        Mail "command failed: $cmd" $tasklog
      fi
    fi

  # pinned version
  elif [[ $task =~ ^= ]]; then
    if ! RunAndCheck "emerge $task"; then
      Mail "pinned atom failed: $task" $tasklog
    fi

  # a common atom
  else
    if ! RunAndCheck "emerge --update $task"; then
      :
    fi
  fi
}


# not more than n @preserved-rebuild within N last tasks
function DetectRebuildLoop() {
  local histfile=/var/tmp/tb/@preserved-rebuild.history
  if [[ -s $histfile ]]; then
    local n=7
    local N=20
    if [[ $(tail -n $N $histfile | grep -c '@preserved-rebuild') -ge $n ]]; then
      echo "$(date) too much rebuilds" >> $histfile
      Finish 13 "detected a rebuild loop" $histfile
    fi
  fi
}


function syncRepo()  {
  cd /var/db/repos/gentoo

  if ! emaint sync --auto &>$tasklog; then
    if ! (git stash; git stash drop; git restore .; git pull) &>>$tasklog; then
      Finish 13 "cannot pull ::gentoo" $tasklog
    fi
    Mail "INFO: fixed git sync issue" $tasklog
  fi
  last_sync=$EPOCHSECONDS

  if grep -B 1 '=== Sync completed for gentoo' $tasklog | grep -q 'Already up to date.'; then
    return 0
  fi

  # get repo changes with an 1 hour timeshift to let download mirrors being synced
  git diff \
      --diff-filter="ACM" \
      --name-only \
      "@{ $(( EPOCHSECONDS-last_sync+3600 )) second ago }".."@{ 1 hour ago }" |\
  grep -F -e '/files/' -e '.ebuild' -e 'Manifest' |\
  cut -f1-2 -d'/' -s |\
  grep -v -f /mnt/tb/data/IGNORE_PACKAGES |\
  sort -u > /tmp/syncRepo.upd

  if [[ -s /tmp/syncRepo.upd ]]; then
    # mix repo changes and backlog together
    sort -u /tmp/syncRepo.upd /var/tmp/tb/backlog.upd | shuf > /tmp/backlog.upd
    # no mv to preserve target file perms
    cp /tmp/backlog.upd /var/tmp/tb/backlog.upd
  fi
}


#############################################################################
#
#       main
#
set -eu
export LANG=C.utf8
trap Finish INT QUIT TERM EXIT

export -f SwitchGCC                 # to call it eg. from retest.sh

taskfile=/var/tmp/tb/task           # holds the current task
tasklog=$taskfile.log               # holds output of it
name=$(cat /var/tmp/tb/name)        # the image name
grep -q '^ACCEPT_KEYWORDS=.*~amd64' /etc/portage/make.conf && keyword="unstable" || keyword="stable"

export CARGO_TERM_COLOR="never"
export GCC_COLORS=""
export OCAML_COLOR="never"
export PY_FORCE_COLOR="0"
export PYTEST_ADDOPTS="--color=no"

# https://bugs.gentoo.org/683118
export TERM=linux
export TERMINFO=/etc/terminfo

export GIT_PAGER="cat"
export PAGER="cat"

if [[ $name =~ _debug ]]; then
  if [[ -x /usr/sbin/minicoredumper ]]; then
    echo '| /usr/sbin/minicoredumper %P %u %g %s %t %h %e' > /proc/sys/kernel/core_pattern
  else
    echo '/tmp/core.%e.%p.%s.%t' > /proc/sys/kernel/core_pattern
  fi
fi

# https://bugs.gentoo.org/816303
echo "#init /run" > $taskfile
if [[ $name =~ "_systemd" ]]; then
  if ! systemd-tmpfiles --create &>$tasklog; then
    Finish 13 "systemd init error" $tasklog
  fi
else
  if ! RC_LIBEXECDIR=/lib/rc/ /lib/rc/sh/init.sh &>$tasklog; then
    Finish 13 "openrc init error" $tasklog
  fi
fi

# re-schedule $task (non-empty == failed before)
if [[ -s $taskfile ]]; then
  add2backlog "$(cat $taskfile)"
fi

last_sync=$(stat -c %Y /var/db/repos/gentoo/.git/FETCH_HEAD)
while :
do
  if [[ -f /var/tmp/tb/STOP ]]; then
    echo "#catched STOP file" > $taskfile
    Finish 0 "catched STOP file" /var/tmp/tb/STOP
  fi

  # update ::gentoo hourly
  if [[ $(( EPOCHSECONDS-last_sync )) -ge 3600 ]]; then
    echo "#sync repo" > $taskfile
    syncRepo
    if grep -q -F '* An update to portage is available.' $tasklog; then
      add2backlog "sys-apps/portage"
    fi
  fi
  if [[ $(( EPOCHSECONDS-$(stat -c %Y /var/db/repos/gentoo/.git/FETCH_HEAD) )) -ge 86400 ]]; then
    Finish 13 "repo too old" $tasklog
  fi

  (date; echo) > $tasklog
  echo "#get task" > $taskfile
  getNextTask
  echo "$task" | tee -a $taskfile.history $tasklog > $taskfile
  WorkOnTask
  DetectRebuildLoop
done
