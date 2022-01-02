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
  perl -wne ' s,\x00,\n,g; s,\r\n,\n,g; s,\r,\n,g; print; '
}


function Mail() {
  local subject=$(stripQuotesAndMore <<< $1 | cut -c1-200 | tr '\n' ' ')
  local content=${2:-}

  if [[ -f $content ]]; then
    echo
    head -n 10000 $content | sed -e 's,^>>>, >>>,'
    echo
  else
    echo -e "$content"
  fi |\
  if ! mail -s "$subject    @ $name" -- ${MAILTO:-tinderbox} &>> /var/tmp/tb/mail.log; then
    echo "$(date) issue, \$subject=$subject \$content=$content" | tee -a /var/tmp/tb/mail.log
    chmod a+rw /var/tmp/tb/mail.log
  fi
}


# http://www.portagefilelist.de
function feedPfl()  {
  if [[ -x /usr/bin/pfl ]]; then
    /usr/bin/pfl &>/dev/null
  fi
  return 0
}


# this is the end ...
function Finish()  {
  local exit_code=${1:-$?}
  local subject=${2:-<internal error>}

  trap - INT QUIT TERM EXIT
  set +e

  feedPfl
  subject=$(stripQuotesAndMore <<< $subject | tr '\n' ' ' | cut -c1-200)
  if [[ $exit_code -eq 0 ]]; then
    Mail "finish ok: $subject" ${3:-}
    truncate -s 0 $taskfile
  else
    Mail "finish NOT ok, exit_code=$exit_code: $subject" ${3:-}
  fi
  rm -f /var/tmp/tb/STOP

  exit $exit_code
}


# helper of getNextTask()
function setTaskAndBacklog()  {
  if [[ -s /var/tmp/tb/backlog.1st ]]; then
    backlog=/var/tmp/tb/backlog.1st

  elif [[ -s /var/tmp/tb/backlog.upd && $(($RANDOM % 4)) -eq 0 ]]; then
    backlog=/var/tmp/tb/backlog.upd

  elif [[ -s /var/tmp/tb/backlog ]]; then
    backlog=/var/tmp/tb/backlog

  elif [[ -s /var/tmp/tb/backlog.upd ]]; then
    backlog=/var/tmp/tb/backlog.upd

  else
    return 1
  fi

  # move last line of $backlog into $task
  task=$(tail -n 1 $backlog)
  sed -i -e '$d' $backlog

  return 0
}


function getNextTask() {
  while :
  do
    if ! setTaskAndBacklog; then
      echo "#empty backlogs" > $taskfile
      return 1
    fi

    if [[ -z "$task" || $task =~ ^# ]]; then
      continue  # empty line or comment

    elif [[ $task =~ ^INFO ]]; then
      Mail "$task"
      continue

    elif [[ $task =~ ^STOP ]]; then
      echo "#task: $task" > $taskfile
      return 1

    elif [[ $task =~ ^@ || $task =~ ^% ]]; then
      break  # @set or %command

    elif [[ $task =~ ^= ]]; then
      # pinned version, but check validity
      if portageq best_visible / $task &>/dev/null; then
        break
      fi

    else
      if [[ ! "$backlog" = /var/tmp/tb/backlog.1st ]]; then
        if grep -q -f /mnt/tb/data/IGNORE_PACKAGES <<< $task; then
          continue
        fi
      fi

      local best_visible
      if ! best_visible=$(portageq best_visible / $task 2>/dev/null); then
        continue
      fi

      # skip if $task would be downgraded
      local installed=$(portageq best_version / $task)
      if [[ -n "$installed" ]]; then
        if qatom --compare $installed $best_visible | grep -q -e ' == ' -e ' > '; then
          continue
        fi
      fi

      # $task is valid
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
  for f in $(ls $issuedir/task.log $issuedir/files/* 2>/dev/null | grep -v -F '.bz2')
  do
    if [[ $(wc -c < $f) -gt 1000000 ]]; then
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
  apout=$(grep -m 1 -A 2 'Include in your bugreport the contents of'                 $tasklog_stripped | grep "\.out"          | cut -f5 -d' ' -s)
  cmlog=$(grep -m 1 -A 2 'Configuring incomplete, errors occurred'                   $tasklog_stripped | grep "CMake.*\.log"   | cut -f2 -d'"' -s)
  cmerr=$(grep -m 1      'CMake Error: Parse error in cache file'                    $tasklog_stripped | sed  "s/txt./txt/"    | cut -f8 -d' ' -s)
  oracl=$(grep -m 1 -A 1 '# An error report file with more information is saved as:' $tasklog_stripped | grep "\.log"          | cut -f2 -d' ' -s)
  envir=$(grep -m 1      'The ebuild environment file is located at'                 $tasklog_stripped                         | cut -f2 -d"'" -s)
  salso=$(grep -m 1 -A 2 ' See also'                                                 $tasklog_stripped | grep "\.log"          | awk '{ print $1 }' )
  sandb=$(grep -m 1 -A 1 'ACCESS VIOLATION SUMMARY' $tasklog_stripped                                  | grep "sandbox.*\.log" | cut -f2 -d'"' -s)
  roslg=$(grep -m 1 -A 1 'Tests failed. When you file a bug, please attach the following file: ' $tasklog_stripped | grep "/LastTest\.log" | awk ' { print $2 } ')

  for f in $apout $cmlog $cmerr $oracl $envir $salso $sandb $roslg
  do
    if [[ -f $f ]]; then
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
  # run line by line over the pattern files in the order the lines are specified there
  # to avoid globbing effects split lines of each file intotemp files and use that in "grep ... -f"
  (
    if [[ -n "$phase" ]]; then
      cat /mnt/tb/data/CATCH_ISSUES.$phase
    fi
    cat /mnt/tb/data/CATCH_ISSUES
  ) | split --lines=1 --suffix-length=3 - /tmp/x_

  for x in /tmp/x_???
  do
    if grep -m 1 -a -B 4 -A 2 -f $x $log_stripped > /tmp/issue; then
      mv /tmp/issue $issuedir
      sed -n "5p" $issuedir/issue | stripQuotesAndMore > $issuedir/title # 5 == B+1 -> at least B+1 lines are expected
      break
    fi
  done
  rm -f /tmp/x_??? /tmp/issue
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

  if grep -q -m 1 -F ' * Detected file collision(s):' $log_stripped; then
    foundCollisionIssue

  elif [[ -n $sandb ]]; then # no "-f" b/c it might not exist
    foundSandboxIssue

  # special forced issues
  elif [[ -n "$(grep -m 1 -B 4 -A 1 'sed:.*expression.*unknown option' $log_stripped | tee $issuedir/issue)" ]]; then
    foundCflagsIssue 'ebuild uses colon (:) as a sed delimiter'

  else
    grep -m 1 -A 2 " \* ERROR:.* failed (.* phase):" $log_stripped | tee $issuedir/issue |\
    head -n 2 | tail -n 1 > $issuedir/title
    foundGenericIssue
  fi

  if [[ $(wc -c < $issuedir/issue) -gt 1024 ]]; then
    echo -e "too long lines were shrinked:\n" > /tmp/issue
    cut -c-300 < $issuedir/issue >> /tmp/issue
    mv /tmp/issue $issuedir/issue
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

    clang --version
    llvm-config --prefix --version
    python -V
    eselect ruby list
    eselect rust list
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

# make world state same as if (succesfully) installed deps were emerged step by step in previous emerges
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
  if [[ ! "$(tail -n 1 /var/tmp/tb/backlog.1st)" = "$1" ]]; then
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
      # put cat into echo due to buffered output of cat
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
  local signal=$1

  log_stripped=$issuedir/$(tr '/' ':' <<< $pkg).log
  filterPlainPext < $pkglog > $log_stripped

  cp $pkglog  $issuedir/files
  cp $tasklog $issuedir

  # "-m 1" because for phase "install" grep might have 2 matches ("doins failed" and "newins failed")
  # "-o" is needed for the 1st grep b/c sometimes perl spews a message into the same text line
  phase=$(
    grep -m 1 -o " \* ERROR:.* failed (.* phase):" $log_stripped |\
    grep -Eo '\(.* ' |\
    tr -d '[( ]'
  )
  if [[ $signal -eq 0 ]]; then
    setWorkDir
    CreateEmergeHistoryFile
    CollectIssueFiles
    CompressIssueFiles
    ClassifyIssue
  else
    echo "emerge seemed to hang" > $issuedir/title
    echo "emerge was killed with $signal" | tee > $issuedir/issue
  fi

  collectPortageDir
  finishTitle
  CompileIssueComment0
  # grant write permissions to all artifacts
  chmod    777  $issuedir/{,files}
  chmod -R a+rw $issuedir/

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
      add2backlog "$task"
    fi
  fi

  if [[ $signal -eq 0 ]]; then
    if [[ $try_again -eq 0 ]]; then
      maskPackage
    fi
  else
    if [[ $phase = "test" ]]; then
      # if it was killed then do not retry with test-fail-continue
      if ! grep -q -e "^=$pkg " /etc/portage/package.env/notest 2>/dev/null; then
        try_again=1
        printf "%-50s %s\n" "=$pkg" "notest" >> /etc/portage/package.env/notest
        add2backlog "@world"  # force a depclean under the hood b/c with "notest" the dependency tree usually changed
      else
        Mail "logic error in retrying a test case pks: $pkg" /etc/portage/package.env/notest
      fi
    else
      maskPackage
    fi
  fi

  if [[ $try_again -eq 1 ]]; then
    add2backlog "$task"
  fi

  SendIssueMailIfNotYetReported
}


function source_profile(){
  local old_setting=${-//[^u]/}
  set +u
  source /etc/profile 2>/dev/null
  [[ -n "${old_setting}" ]] && set -u || true
}


# helper of PostEmerge()
# switch to latest GCC
function SwitchGCC() {
  local latest=$(gcc-config --list-profiles --nocolor | cut -f3 -d' ' -s | grep -E 'x86_64-(pc|gentoo)-linux-(gnu|musl)-.*[0-9]$'| tail -n 1)
  local curr=$(gcc -dumpversion | cut -f1 -d'.')

  if gcc-config --list-profiles --nocolor | grep -q -F "$latest *"; then
    echo "SwitchGCC: is latest: $curr"
  else
    echo "SwitchGCC: switch from $curr to $latest" >> $taskfile.history
    gcc-config --nocolor $latest
    source_profile
    add2backlog "%emerge @preserved-rebuild"
    if grep -q LIBTOOL /etc/portage/make.conf; then
      add2backlog "%emerge -1 sys-devel/slibtool"
    else
      add2backlog "%emerge -1 sys-devel/libtool"
    fi
    add2backlog "%emerge --unmerge sys-devel/gcc:$curr"
  fi
}


# helper of RunAndCheck()
# it schedules follow-ups from the last emerge operation
function PostEmerge() {
  # don't change these config files after image setup
  rm -f /etc/._cfg????_{hosts,resolv.conf}
  rm -f /etc/conf.d/._cfg????_hostname
  rm -f /etc/ssmtp/._cfg????_ssmtp.conf
  rm -f /etc/portage/._cfg????_make.conf

  # if eg. a new glibc was installed then rebuild the locales
  if ls /etc/._cfg????_locale.gen &>/dev/null; then
    locale-gen > /dev/null
    rm /etc/._cfg????_locale.gen
  elif grep -q "IMPORTANT: config file '/etc/locale.gen' needs updating." $tasklog_stripped; then
    locale-gen > /dev/null
  fi

  # merge the remaining config files automatically
  etc-update --automode -5 1>/dev/null

  # update the environment
  env-update &>/dev/null
  source_profile

  # the very last step after an emerge
  if grep -q "Use emerge @preserved-rebuild to rebuild packages using these libraries" $tasklog_stripped; then
    if [[ $try_again -eq 0 ]]; then
      add2backlog "@preserved-rebuild"
    fi
  fi

  if grep -q  -e "Please, run 'haskell-updater'" \
              -e "ghc-pkg check: 'checking for other broken packages:'" $tasklog_stripped; then
    add2backlog "%haskell-updater"
  fi

  if grep -q  -e ">>> Installing .* dev-lang/perl-[1-9]" \
              -e 'Use: perl-cleaner' $tasklog_stripped; then
    add2backlog "%emerge --depclean"
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

  # if 1st prio is empty then check for a schedule of the daily update
  if [[ ! -s /var/tmp/tb/backlog.1st ]]; then
    local h=/var/tmp/tb/@world.history
    if [[ ! -s $h || $(( $(date +%s) - $(stat -c %Y $h) )) -ge 86400 ]]; then
      add2backlog "@world"
    fi
  fi
}


function createIssueDir() {
  sleep 1   # create a unique timestamp of issue dir

  issuedir=/var/tmp/tb/issues/$(date +%Y%m%d-%H%M%S)-$(tr '/' '_' <<< $pkg)
  mkdir -p $issuedir/files
  chmod 777 $issuedir # allow to edit title etc. manually
}


function catchMisc()  {
  find /var/log/portage/ -mindepth 1 -maxdepth 1 -type f -newer $taskfile |\
  while read -r pkglog
  do
    if [[ $(wc -l < $pkglog) -le 6 ]]; then
      continue
    fi

    local log_stripped=/tmp/$(basename $pkglog)
    filterPlainPext < $pkglog > $log_stripped
    if ! grep -q -f /mnt/tb/data/CATCH_MISC $log_stripped; then
      rm $log_stripped
      continue
    fi
    pkg=$(cut -f5 -d'/' <<< $log_stripped | cut -f1-2 -d':' -s | tr ':' '/')
    repo=$(grep -m 1 -F ' * Repository: ' $log_stripped | awk ' { print $3 } ')
    phase=""

    grep -m 1 -f /mnt/tb/data/CATCH_MISC $log_stripped |\
    while read -r line
    do
      createIssueDir
      echo "$line" > $issuedir/title
      grep -m 1 -F -e "$line" $log_stripped > $issuedir/issue
      cp $log_stripped $issuedir
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
    rm $log_stripped
  done
}


function GetPkgFromTaskLog() {
  if grep -q -f /mnt/tb/data/EMERGE_ISSUES $tasklog_stripped; then
    return 1
  fi

  pkg=$(grep -m 1 -F ' * Package: ' $tasklog_stripped | awk ' { print $3 } ')
  if [[ -z "$pkg" ]]; then
    pkg=$(grep -m 1 '>>> Failed to emerge .*/.*' $tasklog_stripped | cut -f5 -d' ' -s | cut -f1 -d',' -s)
    if [[ -z "$pkg" ]]; then
      pkg=$(grep -F ' * Fetch failed' $tasklog_stripped | grep -o "'.*'" | sed "s,',,g")
      if [[ -z $pkg ]]; then
        if ! grep -q -F 'Exiting on signal ' $tasklog_stripped; then
          Mail "INFO: cannot get pkg for task '$task'" $tasklog_stripped
        fi
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
  timeout --signal=15 --kill-after=5m ${2:-12h} bash -c "eval $1" &>> $tasklog
  local rc=$?
  (echo; date) >> $tasklog

  local taskname=task.$(date +%Y%m%d-%H%M%S).$(tr -d '\n' <<< $task | tr -c '[:alnum:]' '_')
  tasklog_stripped="/var/tmp/tb/logs/$taskname.log"

  filterPlainPext < $tasklog > $tasklog_stripped
  PostEmerge

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
  local signal=0
  if [[ $rc -ge 128 ]]; then
    ((signal = rc - 128))
    PutDepsIntoWorldFile
    if [[ $signal -eq 9 ]]; then
      Finish $signal "exiting due to signal $signal" $tasklog_stripped
    else
      Mail "WARN: got signal $signal  task=$task" $tasklog_stripped
    fi

  # timeout
  elif [[ $rc -eq 124 ]]; then
    Mail "INFO: timeout  task=$task" $tasklog_stripped
    PutDepsIntoWorldFile

  # simple failed
  elif [[ $rc -ne 0 ]]; then
    if GetPkgFromTaskLog; then
      createIssueDir
      WorkAtIssue $signal
      if [[ $try_again -eq 0 ]]; then
        PutDepsIntoWorldFile
      fi
    fi
    if fatal=$(grep -m 1 -f /mnt/tb/data/FATAL_ISSUES $tasklog_stripped); then
      Finish 1 "FATAL: $fatal" $tasklog_stripped
    fi
  fi

  catchMisc

  return $rc
}


# this is the heart of the tinderbox
function WorkOnTask() {
  unset phase pkgname pkglog log_stripped

  try_again=0           # "1" means to retry same task, but with possible changed USE/ENV/FEATURE/CFLAGS
  pkg=""

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
        add2backlog "%emerge --depclean"
      fi
    else
      echo "$(date) NOT ok $pkg" >> /var/tmp/tb/$task.history
      if [[ -n "$pkg" ]]; then
        add2backlog "$task"
      elif [[ $task = "@world" ]]; then
        echo "@world is broken" >> /var/tmp/tb/STOP
        return 1
      fi
    fi
    feedPfl

  # %<command line>
  elif [[ $task =~ ^% ]]; then
    local cmd="$(cut -c2- <<< $task)"
    if ! RunAndCheck "$cmd"; then
      if [[ ! $task =~ " --unmerge " && ! $task =~ " --depclean" ]]; then
        if [[ $try_again -eq 0 ]]; then
          echo "failed: $cmd" >> /var/tmp/tb/STOP
          return 1
        fi
      fi
    fi

  # pinned version
  elif [[ $task =~ ^= ]]; then
    if ! RunAndCheck "emerge $task"; then
      Mail "pinned task failed: $task" $tasklog
    fi

  # a common atom
  else
    if ! RunAndCheck "emerge --update $task"; then
      :
    fi
  fi
}


function HasRebuildLoop() {
  local histfile=/var/tmp/tb/@preserved-rebuild.history
  if [[ -s $histfile ]]; then
    # not more than n @preserved-rebuild within N last tasks
    local n=7
    local N=20
    if [[ $(tail -n $N $histfile | grep -c '@preserved-rebuild') -ge $n ]]; then
      echo "$(date) too much rebuilds" >> $histfile
      return 0
    fi
  fi

  return 1
}


function syncRepo()  {
  local last_sync=${1:-0}
  emaint sync --auto &>$tasklog
  local rc=$?

  if grep -q -F 'emerge --oneshot sys-apps/portage' $tasklog; then
    add2backlog "%emerge --oneshot sys-apps/portage"
  fi

  if [[ $rc -ne 0 ]]; then
    return $rc
  elif grep -q -F 'git fetch error in /var/db/repos/gentoo' $tasklog; then
    if grep -q -F 'Protocol "https" not supported or disabled'; then
      return 1
    else
      Mail "git sync issue" $tasklog
      return 0
    fi
  elif grep -B 1 '=== Sync completed for gentoo' $tasklog | grep -q 'Already up to date.'; then
    return 0
  fi

  if [[ $last_sync -eq 0 ]]; then
    return 0
  fi

  cd /var/db/repos/gentoo
  # give mirrors 1 hour to sync
  git diff -l0 --diff-filter="ACM" --name-status "@{ $(( $(date +%s) - $last_sync + 3600 )) second ago }".."@{ 1 hour ago }" |\
  grep -F -e '/files/' -e '.ebuild' -e 'Manifest' |\
  cut -f2- -s |\
  cut -f1-2 -d'/' -s |\
  grep -v -f /mnt/tb/data/IGNORE_PACKAGES |\
  uniq > /tmp/diff.upd

  # mix new entries into the re-mixed backlog
  if [[ -s /tmp/diff.upd ]]; then
    sort -u /tmp/diff.upd /var/tmp/tb/backlog.upd | shuf > /tmp/backlog.upd
    # no mv to preserve target file perms
    cp /tmp/backlog.upd /var/tmp/tb/backlog.upd
    rm /tmp/backlog.upd
  fi

  rm /tmp/diff.upd
}


#############################################################################
#
#       main
#
set -eu
export LANG=C.utf8
export -f SwitchGCC
trap Finish INT QUIT TERM EXIT

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
  echo "/tmp/core.%e.%p.%s.%t" > /proc/sys/kernel/core_pattern
fi

# https://bugs.gentoo.org/816303
echo "#init /run" > $taskfile
if [[ $name =~ "_systemd" ]]; then
  if ! systemd-tmpfiles --create &>$tasklog; then
    Finish 1 "systemd init error" $tasklog
  fi
else
  if ! RC_LIBEXECDIR=/lib/rc/ /lib/rc/sh/init.sh &>$tasklog; then
    Finish 1 "openrc init error" $tasklog
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

  # update ::gentoo repo hourly
  if [[ $(( $(date +%s) - last_sync )) -ge 3600 ]]; then
    echo "#sync repo" > $taskfile
    syncRepo $last_sync
    last_sync=$(stat -c %Y /var/db/repos/gentoo/.git/FETCH_HEAD)
  fi

  (date; echo) > $tasklog
  echo "#get task" > $taskfile
  if ! getNextTask; then
    Finish 0 "$(qlist -Iv | wc -l) packages installed" $taskfile
  fi
  echo "$task" | tee -a $taskfile.history $tasklog > $taskfile
  if ! WorkOnTask; then
    Finish 1 "task: '$task'" $tasklog
  fi
  if HasRebuildLoop; then
    Finish 2 "too much rebuilds" $histfile
  fi
done
