#!/bin/bash
#
# set -x


# This is the tinderbox script itself.
# The main function is WorkOnTask().
# The remaining code just parses the output.
# That's all.


# strip away non-printable sequences
#
function stresc() {
  perl -MTerm::ANSIColor=colorstrip -nle '
    $_ = colorstrip($_);
    s,\r,\n,g;
    s,\x00,,g;
    s,\x08,,g;
    s,\b,,g;
    s,\x1b\x28\x42,,g;
    s,\x1b\x5b\x4b,,g;
    s,\x01,,g;
    s,\x02,,g;
    s,\x03,,g;
    s,\x1b,,g;
    s,\x0f,,g;
    print;
  '
}


# send an email using mailx
#
function Mail() {
  # $1 (mandatory) is the subject,
  # $2 (optional) contains either the text of the body or a filename (with text)
  #
  subject=$(echo "$1" | stresc | cut -c1-200 | tr '\n' ' ')

  opt=""
  if [[ -f $2 ]]; then
    grep -q "^begin 644 " $2
    if [[ $? -eq 0 ]]; then
      opt='-a'       # uuencode is not MIME-compliant
    fi
  fi

  (
    if [[ -f $2 ]]; then
      stresc < $2
    else
      echo "${2:-<no body>}"
    fi
  ) | timeout 120 mail -s "$subject    @ $name" $mailto $opt "" &>> /tmp/mail.log # the "" belongs to $opt but doesn't hurt here and let the mail body be looking less ugly

  local rc=$?

  if [[ $rc -ne 0 ]]; then
    # direct this both to stdout (could be catched eg. by logcheck.sh) and to an image specific logfile
    #
    echo "$(date) mail failed with rc=$rc issuedir=$issuedir" | tee -a /tmp/mail.log
  fi
}


# clean up and exit
#
function Finish()  {
  # $1: return code
  # $2: email Subject
  # $3: file to be attached
  #
  local rc=$1

  # although stresc() is called in Mail() run it here too b/c $2 might contain quotes
  #
  subject=$(echo "$2" | stresc | cut -c1-200 | tr '\n' ' ')

  /usr/bin/pfl &> /dev/null

  if [[ $rc -eq 0 ]]; then
    Mail "Finish ok: $subject"
  else
    Mail "Finish NOT ok, rc=$rc: $subject" ${3:-$log}
  fi

  # if rc != 0 then keep $task in $tsk to retry it at the next start
  # otherwise delete it
  #
  if [[ $rc -eq 0 && -f $tsk ]]; then
    rm $tsk
  fi

  rm -f /tmp/STOP

  exit $rc
}


# move next item of the appropriate backlog into $task
#
function setNextTask() {
  while :
  do
    if [[ -f /tmp/STOP ]]; then
      Finish 0 "catched STOP file" /tmp/STOP
    fi

    # 1st prio backlog rules
    #
    if [[ -s $backlog ]]; then
      bl=$backlog

    # repository updates
    # updated regularly by update_backlog.sh
    #
    # 1/3 probability but only if no special action is scheduled in common backlog
    #
    elif [[ -s /tmp/backlog.upd && $(($RANDOM % 3)) -eq 0 && -z "$(grep -E '^(INFO|STOP|@|%)' /tmp/backlog)" ]]; then
      bl=/tmp/backlog.upd

    # common backlog
    # filled up at image setup and will only decrease
    #
    elif [[ -s /tmp/backlog ]]; then
      bl=/tmp/backlog

    # last chance (1 - 1/3) for updated packages
    #
    elif [[ -s /tmp/backlog.upd ]]; then
      bl=/tmp/backlog.upd

    # this is the end, my friend, the end ...
    #
    else
      n=$(qlist --installed | wc -l)
      Finish 0 "empty backlogs, $n packages emerged"
    fi

    # splice last line from the winning backlog file
    #
    task=$(tail -n 1 $bl)
    sed -i -e '$d' $bl

    if [[ -z "$task" ]]; then
      continue  # empty line

    # INFO and STOP within the backlog are useful for debug purpose
    #
    elif [[ $task =~ ^INFO ]]; then
      Mail "$task"

    elif [[ $task =~ ^STOP ]]; then
      Finish 0 "$task"

    elif [[ $task =~ ^# ]]; then
      continue  # comment

    elif [[ $task =~ ^= || $task =~ ^@ || $task =~ ^% ]]; then
      return  # work on a pinned version || @set || command

    else
      # skip if $task matches any ignore patterns
      #
      echo "$task" | grep -q -f /tmp/tb/data/IGNORE_PACKAGES
      if [[ $? -eq 0 ]]; then
        continue
      fi

      # skip if there's no visible version (eg. $task is masked, keyworded etc.)
      #
      best_visible=$(portageq best_visible / $task 2>/tmp/portageq.err)

      # bail out if portage itself is broken (caused eg. by a buggy Python package)
      #
      if [[ $? -ne 0 ]]; then
        if [[ "$(grep -ch 'Traceback' /tmp/portageq.err)" -ne "0" ]]; then
          Finish 1 "FATAL: portageq broken" /tmp/portageq.err
        fi
        continue
      fi

      # skip if $task is already installed and would be downgraded
      #
      installed=$(portageq best_version / $task)
      if [[ -n "$installed" ]]; then
        qatom --compare $installed $best_visible | grep -q -e ' == ' -e ' > '
        if [[ $? -eq 0 ]]; then
          continue
        fi
      fi

      # $task seems to be valid, work on it
      #
      return
    fi
  done
}


# helper of CollectIssueFiles
#
function collectPortageDir()  {
  (
    cd /
    tar -cjpf $issuedir/files/etc.portage.tbz2 --dereference etc/portage
  )
}


# helper of GotAnIssue()
# gather together what's needed for the email and b.g.o.
#
function CollectIssueFiles() {
  ehist=/var/tmp/portage/emerge-history.txt
  local cmd="qlop --nocolor --gauge --human --list --unlist"

  cat << EOF > $ehist
# This file contains the emerge history got with:
# $cmd
#
EOF
  $cmd >> $ehist

  # collect few more build files, strip away escape sequences
  # and compress files bigger than 1 MiByte
  #
  apout=$(grep -m 1 -A 2 'Include in your bugreport the contents of'                 $bak | grep "\.out"          | cut -f5 -d' ' -s)
  cmlog=$(grep -m 1 -A 2 'Configuring incomplete, errors occurred'                   $bak | grep "CMake.*\.log"   | cut -f2 -d'"' -s)
  cmerr=$(grep -m 1      'CMake Error: Parse error in cache file'                    $bak | sed  "s/txt./txt/"    | cut -f8 -d' ' -s)
  oracl=$(grep -m 1 -A 1 '# An error report file with more information is saved as:' $bak | grep "\.log"          | cut -f2 -d' ' -s)
  envir=$(grep -m 1      'The ebuild environment file is located at'                 $bak                         | cut -f2 -d"'" -s)
  salso=$(grep -m 1 -A 2 ' See also'                                                 $bak | grep "\.log"          | awk '{ print $1 }' )
  sandb=$(grep -m 1 -A 1 'ACCESS VIOLATION SUMMARY' $bak                                  | grep "sandbox.*\.log" | cut -f2 -d'"' -s)
  roslg=$(grep -m 1 -A 1 'Tests failed. When you file a bug, please attach the following file: ' $bak | grep "/LastTest\.log" | awk ' { print $2 } ')

  for f in $ehist $failedlog $sandb $apout $cmlog $cmerr $oracl $envir $salso $roslg
  do
    if [[ -f $f ]]; then
      stresc < $f > $issuedir/files/$(basename $f)
    fi
  done

  # b.g.o. has a limit of 1 MB
  #
  for f in $issuedir/files/* $issuedir/_*
  do
    if [[ $(wc -c < $f) -gt 1000000 ]]; then
      bzip2 $f
    fi
  done

  if [[ -d "$workdir" ]]; then
    # catch all log file(s)
    #
    (
      f=/tmp/files
      cd "$workdir/.." &&\
      find ./ -name "*.log" -o -name "testlog.*" > $f &&\
      [[ -s $f ]] &&\
      tar -cjpf $issuedir/files/logs.tbz2 --files-from $f --warning='no-file-ignored'
      rm -f $f
    )

    # provide the whole temp dir if possible
    #
    (
      cd "$workdir"/../.. &&\
      [[ -d ./temp ]]     &&\
      tar -cjpf $issuedir/files/temp.tbz2 --dereference --warning='no-file-removed' --warning='no-file-ignored' ./temp
    )

    # ICE of GCC ?
    #
    if [[ -f $workdir/gcc-build-logs.tar.bz2 ]]; then
      cp $workdir/gcc-build-logs.tar.bz2 $issuedir/files
    fi
  fi

  collectPortageDir
}


# helper of GotAnIssue()
# guess the failed package and logfile name
#
function setFailedAndShort()  {
  failed=$(grep -m 1 -F ' * Package: ' $log | awk ' { print $3 } ')
  if [[ -z "$failed" ]]; then
    failed="$(cd /var/tmp/portage; ls -1td */* 2>/dev/null | head -n 1)"
  fi

  failedlog=$(grep -m 1 "The complete build log is located at" $log | cut -f2 -d"'" -s)
  if [[ -z "$failedlog" ]]; then
    failedlog=$(grep -m 1 -A 1 "', Log file:" $log | tail -n 1 | cut -f2 -d"'" -s)
    if [[ -z "$failedlog" ]]; then
      failedlog=$(grep -m 1 "^>>>  '" $log | cut -f2 -d"'" -s)
      if [[ -z "$failedlog" ]]; then
        if [[ -n "$failed" ]]; then
          failedlog=$(ls -1t /var/log/portage/$(echo "$failed" | tr '/' ':'):????????-??????.log 2>/dev/null | head -n 1)
        fi
      fi
    fi
  fi

  if [[ -z "$failed" ]]; then
    if [[ -n "$failedlog" ]]; then
      failed=$(basename $failedlog | cut -f1-2 -d':' -s | tr ':' '/')
    fi
  fi

  short=$(pn2p "$failed")
  if [[ ! -d /usr/portage/$short ]]; then
    failed=""
    failedlog=""
    short=""
  fi
}


# get assignee and cc for the b.g.o. report
#
function GetAssigneeAndCc() {
  # all meta info
  #
  m=$( equery meta -m $short | grep '@' | xargs )
  if [[ -z "$m" ]]; then
    echo "maintainer-needed@gentoo.org" > $issuedir/assignee
  else
    echo "$m" | cut -f1 -d' ' > $issuedir/assignee
    if [[ "$m" =~ " " ]]; then
      echo "$m" | cut -f2- -d' ' > $issuedir/cc
    fi
  fi
}


# add this eg. to #comment0 of an b.g.o. record
#
function AddWhoamiToIssue() {
  cat << EOF >> $issuedir/issue

  -------------------------------------------------------------------

  This is an $keyword amd64 chroot image at a tinderbox (==build bot)
  name: $name

  -------------------------------------------------------------------

EOF
}


# attach given files onto the email
# (should be called after the lines of text)
#
function AttachFilesToBody()  {
  for f in $*
  do
    s=$( wc -c < $f )
    if [[ $s -gt 0 && $s -lt 1048576 ]]; then
      echo >> $issuedir/body
      uuencode $f $(basename $f) >> $issuedir/body
      echo >> $issuedir/body
    fi
  done
}


# query b.g.o. about same/similar bug reports
#
function AddVersionAssigneeAndCC() {
  cat << EOF >> $issuedir/body

--
versions: $(eshowkw -a amd64 $short | grep -A 100 '^-' | grep -v '^-' | awk '{ if ($3 == "+") { print $1 } else if ($3 == "o") { print "**"$1 } else { print $3$1 } }' | xargs)
assignee: $(cat $issuedir/assignee)
cc:       $(cat $issuedir/cc 2>/dev/null)
--

EOF
}


# strip away the version (get $PN from $P)
#
function pn2p() {
  qatom -q "$1" 2>/dev/null | grep -v '(null)' | cut -f1-2 -d' ' | tr ' ' '/'
}


function CreateIssueDir() {
  issuedir=/tmp/issues/$(date +%Y%m%d-%H%M%S)_$(echo $failed | tr '/' '_')
  mkdir -p $issuedir/files
  # permit external user to edit files before reporting the bug
  #
  chmod 777 $issuedir
}


# helper of ClassifyIssue()
#
function foundCollisionIssue() {
  grep -m 1 -A 20 ' * Detected file collision(s):' $bak | grep -B 15 ' * Package .* NOT' >> $issuedir/issue

  # get package name+version of the sibbling package
  #
  s=$(grep -m 1 -A 2 'Press Ctrl-C to Stop' $bak | grep '::' | tr ':' ' ' | cut -f3 -d' ' -s)

  if [[ -z "$s" ]]; then
    echo "file collision" > $issuedir/title

  else
    echo "file collision with $s" > $issuedir/title

    # strip away version+release of the sibbling package
    # b/c the repository might be updated in the meanwhile
    #
    cc=$(equery meta -m $(pn2p "$s") | grep '@' | grep -v "$(cat $issuedir/assignee)" | xargs)
    # sort -u guarantees, that the file $issuedir/cc is completely read in before it will be overwritten
    #
    if [[ -n "$cc" ]]; then
      (cat $issuedir/cc 2>/dev/null; echo $cc) | xargs -n 1 | sort -u | xargs > $issuedir/cc
    fi
  fi
}


# helper of ClassifyIssue()
#
function foundSandboxIssue() {
  echo "=$failed nosandbox"     >> /etc/portage/package.env/nosandbox
  echo "=$failed nousersandbox" >> /etc/portage/package.env/nousersandbox
  try_again=1

  p="$(grep -m 1 ^A: $sandb)"
  echo "$p" | grep -q "A: /root/"
  if [[ $? -eq 0 ]]; then
    cat << EOF >> $issuedir/issue
This issue is forced at the tinderbox (pls see bug #567192 too) by setting:

$(grep '^export XDG_' /tmp/job.sh)

sandbox output:

EOF
    echo "sandbox issue (XDG_xxx_DIR related)" > $issuedir/title
  else
    echo "sandbox issue" > $issuedir/title
  fi
  head -n 10 $sandb >> $issuedir/issue
}


# helper of ClassifyIssue()
#
function collectTestIssueResults() {
  grep -q "=$failed " /etc/portage/package.env/test-fail-continue 2>/dev/null
  if [[ $? -ne 0 ]]; then
    echo "=$failed test-fail-continue" >> /etc/portage/package.env/test-fail-continue
    try_again=1
  fi

  (
    cd "$workdir"
    # tar returns an error if it can't find at least one directory
    # therefore feed only existing dirs to it
    #
    dirs="$(ls -d ./tests ./regress ./t ./Testing ./testsuite.dir 2>/dev/null)"
    if [[ -n "$dirs" ]]; then
      tar -cjpf $issuedir/files/tests.tbz2 \
        --exclude="*/dev/*" --exclude="*/proc/*" --exclude="*/sys/*" --exclude="*/run/*" \
        --exclude='*.o' --exclude="*/symlinktest/*" \
        --dereference --sparse --one-file-system --warning='no-file-ignored' \
        $dirs
    fi
  )
}


# helper of GotAnIssue()
# get the issue
# get an descriptive title from the most meaningful lines of the issue
# if needed: change package.env/...  to re-try failed with defaults settings
#
function ClassifyIssue() {
  touch $issuedir/{issue,title}

  # test", "compile" etc.
  #
  phase=""

  if [[ -n "$(grep -m 1 ' * Detected file collision(s):' $bak)" ]]; then
    foundCollisionIssue

  elif [[ -f $sandb ]]; then
    foundSandboxIssue

  else
    phase=$(
      grep -m 1 -A 2 " \* ERROR:.* failed (.* phase):" $bak |\
      tee $issuedir/issue                                   |\
      head -n 1                                             |\
      sed -e 's/.* failed \(.* phase\)/\1/g'                |\
      cut -f2 -d'('                                         |\
      cut -f1 -d' '
    )
    head -n 2 $issuedir/issue | tail -n 1 > $issuedir/title

    if [[ "$phase" = "test" ]]; then
      collectTestIssueResults
    fi

    # try to guess a better title & issue based on pattern files
    # the pattern order within the file is important therefore "grep -f" can't be used
    #
    cat /tmp/tb/data/CATCH_ISSUES.$phase /tmp/tb/data/CATCH_ISSUES 2>/dev/null |\
    while read c
    do
      grep -a -m 1 -B 2 -A 3 "$c" $bak > $issuedir/issue.tmp
      if [[ $? -eq 0 ]]; then
        mv $issuedir/issue.tmp $issuedir/issue
        # take 3rd line for the (new) title
        #
        sed -n '3p' < $issuedir/issue | sed -e 's,['\''‘’"`], ,g' > $issuedir/title

        # if the issue is too big, then delete 1st line
        #
        if [[ $(wc -c < $issuedir/issue) -gt 1024 ]]; then
          sed -i -e "1d" $issuedir/issue
        fi
        break
      fi
    done
    rm -f $issuedir/issue.tmp

    # kick off hex addresses, line and time numbers and other stuff
    #
    sed -i  -e 's/0x[0-9a-f]*/<snip>/g'         \
            -e 's/: line [0-9]*:/:line <snip>:/g' \
            -e 's/[0-9]* Segmentation fault/<snip> Segmentation fault/g' \
            -e 's/Makefile:[0-9]*/Makefile:<snip>/g' \
            -e 's,:[[:digit:]]*): ,:<snip>:,g'  \
            -e 's,([[:digit:]]* of [[:digit:]]*),(<snip> of <snip)>,g'  \
            -e 's,  *, ,g'                      \
            -e 's,[0-9]*[\.][0-9]* sec,,g'      \
            -e 's,[0-9]*[\.][0-9]* s,,g'        \
            -e 's,([0-9]*[\.][0-9]*s),,g'       \
            -e 's/ \.\.\.*\./ /g'               \
            -e 's/___*/_/g'                     \
            -e 's/; did you mean .* \?$//g'     \
            $issuedir/title
  fi
}


# try to match title to a tracker bug
# the BLOCKER file contains 3-line-paragraphs like:
#
#   # comment
#   <bug id>
#   <pattern>
#   ...
#
# if <pattern> is defined more than once then the first makes it
#
function SearchForBlocker() {
  block=""
  if [[ ! -s $issuedir/title ]]; then
    return 0
  fi

  # skip comments and bug id lines
  #
  while read pattern
  do
    grep -q -E -e "$pattern" $issuedir/title
    if [[ $? -eq 0 ]]; then
      # no grep -E here, use -F, the BLOCKER file must not contain something like '\-'
      #
      block="-b "$( grep -m 1 -B 1 -F "${pattern}" /tmp/tb/data/BLOCKER | head -n 1 )
      break
    fi
  done < <(grep -v -e '^#' -e '^[1-9].*$' /tmp/tb/data/BLOCKER)
}


# put  b.g.o. findings+links into the email body
#
function SearchForAnAlreadyFiledBug() {
  bsi=$issuedir/bugz_search_items     # consider the title as a set of patterns separated by spaces
  cp $issuedir/title $bsi

  # get away line numbers, certain special terms and characters
  #
  sed -i  -e 's,&<[[:alnum:]].*>,,g'  \
          -e 's,['\''‘’"`], ,g'       \
          -e 's,/\.\.\./, ,'          \
          -e 's,:[[:alnum:]]*:[[:alnum:]]*: , ,g' \
          -e 's,.* : ,,'              \
          -e 's,[<>&\*\?], ,g'        \
          -e 's,[\(\)], ,g'           \
          $bsi

  # for the file collision case: remove the package version (from the installed package)
  #
  grep -q "file collision" $bsi
  if [[ $? -eq 0 ]]; then
    sed -i -e 's/\-[0-9\-r\.]*$//g' $bsi
  fi

  # search first for the same version, then for category/package name
  # take the highest bug id, but put the summary of the newest 10 bugs into the email body
  #
  for i in $failed $short
  do
    id=$(timeout 300 bugz -q --columns 400 search --show-status $i "$(cat $bsi)" 2>> $issuedir/body | grep -e " CONFIRMED " -e " IN_PROGRESS " | sort -u -n -r | head -n 10 | tee -a $issuedir/body | head -n 1 | cut -f1 -d ' ')
    if [[ -n "$id" ]]; then
      echo "CONFIRMED " >> $issuedir/bgo_result
      break
    fi

    for s in FIXED WORKSFORME DUPLICATE
    do
      id=$(timeout 300 bugz -q --columns 400 search --show-status --resolution "$s" --status RESOLVED $i "$(cat $bsi)" 2>> $issuedir/body | sort -u -n -r | head -n 10 | tee -a $issuedir/body | head -n 1 | cut -f1 -d ' ')
      if [[ -n "$id" ]]; then
        echo "$s " >> $issuedir/bgo_result
        break 2
      fi
    done
  done
}


# compile a command line ready for copy+paste to file a bug
# and add the top 20 b.g.o. search results too
#
function AddBugzillaData() {
  if [[ -n "$id" ]]; then
    cat << EOF >> $issuedir/body
  https://bugs.gentoo.org/show_bug.cgi?id=$id

  bgo.sh -d ~/img?/$name/$issuedir $block -i $id -c 'got at the $keyword amd64 chroot image $name this : $(cat $issuedir/title)'

EOF
  else
    cat << EOF >> $issuedir/body

  bgo.sh -d ~/img?/$name/$issuedir $block

EOF
    h='https://bugs.gentoo.org/buglist.cgi?query_format=advanced&short_desc_type=allwordssubstr'
    g='stabilize|Bump| keyword| bump'

    echo "  OPEN:     ${h}&resolution=---&short_desc=${short}" >> $issuedir/body
    timeout 300 bugz --columns 400 -q search --show-status      $short 2>> $issuedir/body | grep -v -i -E "$g" | sort -u -n -r | head -n 20 >> $issuedir/body

    echo "" >> $issuedir/body
    echo "  RESOLVED: ${h}&bug_status=RESOLVED&short_desc=${short}" >> $issuedir/body
    timeout 300 bugz --columns 400 -q search --status RESOLVED  $short 2>> $issuedir/body | grep -v -i -E "$g" | sort -u -n -r | head -n 20  >> $issuedir/body
  fi

  # this newline makes a manual copy+paste action more convenient
  #
  echo >> $issuedir/body
}


# b.g.o. has a limit for "Summary" of 255 chars
#
function TrimTitle()  {
  n=${1:-255}

  if [[ $(wc -c < $issuedir/title) -gt $n ]]; then
    truncate -s $n $issuedir/title
  fi
}


# helper of GotAnIssue()
# create an email containing convenient links and a command line ready for copy+paste
#
function CompileIssueMail() {
  emerge -p --info $short &> $issuedir/emerge-info.txt

  # shrink too long error messages
  #
  sed -i -e 's,/[^ ]*\(/[^/:]*:\),/...\1,g' $issuedir/title

  # the upper limit is 16 KB at b.g.o.
  #
  while [[ $(wc -c < $issuedir/issue) -gt 12000 ]]
  do
    sed -i '1d' $issuedir/issue
  done

  # copy issue to the email body before enhancing it further to become comment#0
  #
  cp $issuedir/issue $issuedir/body
  AddWhoamiToIssue

  SearchForBlocker
  if [[ -n "$block" ]]; then
    cat <<EOF >> $issuedir/issue
  Please see the tracker bug for details.

EOF
  fi

  AddVersionAssigneeAndCC

  # used languages and compilers
  #
  cat << EOF >> $issuedir/issue
gcc-config -l:
$(gcc-config -l                   )
$( [[ -x /usr/bin/llvm-config ]] && echo llvm-config: && llvm-config --version )
$(eselect python  list 2>/dev/null)
$(eselect ruby    list 2>/dev/null)
$( [[ -x /usr/bin/java-config ]] && echo java-config: && java-config --list-available-vms --nocolor )
$(eselect java-vm list 2>/dev/null)

emerge -qpv $short
$(head -n 1 $issuedir/emerge-qpv)
EOF

  if [[ -s $issuedir/title ]]; then
    TrimTitle 200
    SearchForAnAlreadyFiledBug
  fi

  AddBugzillaData
  AttachFilesToBody $issuedir/emerge-info.txt $issuedir/files/* $issuedir/_*

  # prepend failed package
  #
  if [[ "$phase" = "test" ]]; then
    sed -i -e "s,^,$failed : [TEST] ," $issuedir/title
  else
    sed -i -e "s,^,$failed : ," $issuedir/title
  fi
  TrimTitle

  # grant write permissions to all artefacts
  #
  chmod    777  $issuedir/{,files}
  chmod -R a+rw $issuedir/
}


# helper of GotAnIssue() and CheckQA
#
function SendoutIssueMail()  {
  # no matching pattern in CATCH_* == no title
  #
  if [[ -s $issuedir/title ]]; then
    # do not report the same issue again
    #
    grep -F -q -f $issuedir/title /tmp/tb/data/ALREADY_CATCHED
    if [[ $? -eq 0 ]]; then
      return
    fi

    cat $issuedir/title >> /tmp/tb/data/ALREADY_CATCHED
  fi

  # $issuedir/bgo_result might not exists
  #
  Mail "$(cat $issuedir/bgo_result 2>/dev/null)$(cat $issuedir/title)" $issuedir/body
}


# helper of GotAnIssue()
# add successfully emerged dependencies of $task to the world file
# otherwise we'd need to use "--deep" unconditionally
# (https://bugs.gentoo.org/show_bug.cgi?id=563482)
#
function PutDepsIntoWorldFile() {
  emerge --depclean --pretend --verbose=n 2>/dev/null |\
  grep "^All selected packages: " |\
  cut -f2- -d':' -s |\
  while read p
  do
    emerge -O --noreplace $p &>/dev/null
  done
}


# helper of GotAnIssue()
# for ABI_X86="32 64" we have two ./work directories in /var/tmp/portage/<category>/<name>
#
function setWorkDir() {
  workdir=$(fgrep -m 1 " * Working directory: '" $bak | cut -f2 -d"'" -s)
  if [[ ! -d "$workdir" ]]; then
    workdir=$(fgrep -m 1 ">>> Source unpacked in " $bak | cut -f5 -d" " -s)
    if [[ ! -d "$workdir" ]]; then
      workdir=/var/tmp/portage/$failed/work/$(basename $failed)
      if [[ ! -d "$workdir" ]]; then
        workdir=""
      fi
    fi
  fi
}


# helper of GotAnIssue()
#
function KeepGoing() {
  if [[ $task =~ "revdep-rebuild" ]]; then
    # don't repeat the whole rebuild list
    # (eg. after a GCC upgrade it fails often just in the test phase)
    #
    echo "%emerge --resume" >> $backlog

  else
    # repeat $task instead of just resuming emerge because
    # dependencies might be changed due to a now masked packages,
    # an updated repository or by an altered package.env/* entry
    #
    if [[ "$(tail -n 1 $backlog)" != "$task" ]]; then
      echo "$task" >> $backlog
    fi
  fi
}


# collect files, create (and maybe send out) an email
#
function GotAnIssue()  {
  PutDepsIntoWorldFile

  fatal=$(grep -m 1 -f /tmp/tb/data/FATAL_ISSUES $bak)
  if [[ -n "$fatal" ]]; then
    Finish 1 "FATAL: $fatal"
  fi

  grep -q -e "Exiting on signal" -e " \* The ebuild phase '.*' has been killed by signal" $bak
  if [[ $? -eq 0 ]]; then
    Finish 1 "KILLED"
  fi

  # the shared repository solution is racy: https://bugs.gentoo.org/639374
  #
  grep -q -e 'AssertionError: ebuild not found for' \
          -e 'portage.exception.FileNotFound:'      \
          -e 'portage.exception.PortageKeyError: '  \
          $bak
  if [[ $? -eq 0 ]]; then
    Mail "admin: catched a repo race" $bak
    try_again=1
    KeepGoing
    sleep 60
    return
  fi

  setFailedAndShort

  # emerge error or somethign went wrong before
  #
  if [[ -z "$failed" ]]; then
    return
  fi

  CreateIssueDir
  GetAssigneeAndCc
  cp $bak $issuedir
  setWorkDir
  CollectIssueFiles

  # do this before any /etc/portage/package.*/* file might be altered
  #
  emerge -qpv $short &> $issuedir/emerge-qpv

  ClassifyIssue
  CompileIssueMail

  grep -q -f /tmp/tb/data/IGNORE_ISSUES $issuedir/title
  if [[ $? -ne 0 ]]; then
    SendoutIssueMail
  fi

  # https://bugs.gentoo.org/463976
  # https://bugs.gentoo.org/582046
  # https://bugs.gentoo.org/640866
  # https://bugs.gentoo.org/646698
  #
  grep -q -e "Can't locate .* in @INC"                                \
          -e "configure: error: perl module Locale::gettext required" \
          -e "loadable library and perl binaries are mismatched"      \
          $bak
  if [[ $? -eq 0 ]]; then
    try_again=1   # cleanup Perl before $task can be repeated
    cat << EOF >> $backlog
$task
%perl-cleaner --all
EOF
    return
  fi

  if [[ $try_again -eq 1 ]]; then
    KeepGoing
  else
    echo "=$failed" >> /etc/portage/package.mask/self
  fi
}


# helper of PostEmerge()
#
function BuildKernel()  {
  echo "$FUNCNAME" >> $log
  (
    cd /usr/src/linux
    make distclean
    make defconfig
    make -j1
  ) &>> $log
  return $?
}


# helper of PostEmerge()
# switch to latest GCC
#
function SwitchGCC() {
  latest=$(gcc-config --list-profiles --nocolor | cut -f3 -d' ' -s | grep 'x86_64-pc-linux-gnu-.*[0-9]$' | tail -n 1)

  gcc-config --list-profiles --nocolor | grep -q "$latest \*$"
  if [[ $? -eq 1 ]]; then
    verold=$(gcc -dumpversion)

    gcc-config --nocolor $latest &>> $log
    source /etc/profile

    # bug https://bugs.gentoo.org/459038
    #
    echo "%revdep-rebuild" >> $backlog

    # force catching issues of using old GCC installation artefacts
    #
    echo "%emerge --unmerge sys-devel/gcc:$verold" >> $backlog
  fi
}


# helper of setNextTask()
# choose an arbitrary system java engine
#
function SwitchJDK()  {
  old=$(eselect java-vm show system 2>/dev/null | tail -n 1 | xargs)
  if [[ -n "$old" ]]; then
    new=$(
      eselect java-vm list 2>/dev/null |\
      grep -e ' oracle-jdk-[[:digit:]] ' -e ' icedtea[-bin]*-[[:digit:]] ' |\
      grep -v " icedtea-bin-[[:digit:]].*-x86 " |\
      grep -v ' system-vm' |\
      awk ' { print $2 } ' | sort --random-sort | head -n 1
    )
    if [[ -n "$new" && "$new" != "$old" ]]; then
      eselect java-vm set system $new 1>> $log
    fi
  fi
}


# helper of RunAndCheck()
# it schedules follow-ups from the last emerge operation
#
function PostEmerge() {
  # prefix our log backup file with "_" to distinguish it from portages log file
  #
  bak=/var/log/portage/_emerge_$(date +%Y%m%d-%H%M%S).log
  stresc < $log > $bak

  # don't change these config files after image setup
  #
  rm -f /etc/._cfg????_{hosts,resolv.conf}
  rm -f /etc/ssmtp/._cfg????_ssmtp.conf
  rm -f /etc/portage/._cfg????_make.conf

  ls /etc/._cfg????_locale.gen &>/dev/null
  if [[ $? -eq 0 ]]; then
    locale-gen > /dev/null
    rm /etc/._cfg????_locale.gen
  fi

  # merge the remaining config files automatically
  #
  etc-update --automode -5 1>/dev/null

  # update the runtime environment
  #
  env-update &>/dev/null
  source /etc/profile || Finish 2 "can't source /etc/profile"

  # the very last step after an emerge
  #
  grep -q "Use emerge @preserved-rebuild to rebuild packages using these libraries" $bak
  if [[ $? -eq 0 ]]; then
    if [[ "$(tail -n 1 $backlog)" != "@preserved-rebuild" ]]; then
      echo "@preserved-rebuild" >> $backlog
    fi
  fi

  # switch to the new kernel sources
  # build them asap!
  #
  grep -q ">>> Installing .* sys-kernel/.*-sources" $bak
  if [[ $? -eq 0 ]]; then
    last=$(ls -1dt /usr/src/linux-* | head -n 1 | cut -f4 -d'/' -s)
    link=$(eselect kernel show | tail -n 1 | sed -e 's/ //g' | cut -f4 -d'/' -s)
    if [[ "$last" != "$link" ]]; then
      eselect kernel set $last
    fi

    if [[ ! -f /usr/src/linux/.config ]]; then
      echo "%BuildKernel" >> $backlog
    fi
  fi

  grep -q -e "Please, run 'haskell-updater'" -e "ghc-pkg check: 'checking for other broken packages:'" $bak
  if [[ $? -eq 0 ]]; then
    echo "%haskell-updater" >> $backlog
  fi

  grep -q ">>> Installing .* sys-lang/perl-[1-9]" $bak
  if [[ $? -eq 0 ]]; then
    echo "%perl-cleaner --all" >> $backlog
  fi

  # if $backlog is empty then do 24 hours after the last @system finished in this order:
  #   - switch java VM
  #   - update @system
  #   - update @world
  #
  if [[ ! -s $backlog ]]; then
    let "diff = $(date +%s) - $(stat -c%Y /tmp/@system.history)"
    if [[ $diff -gt 86400 ]]; then
      cat << EOF >> $backlog
@world
@system
%SwitchJDK
EOF
    fi
  fi

  # switch to a new GCC first
  #
  grep -q ">>> Installing .* sys-devel/gcc-[1-9]" $bak
  if [[ $? -eq 0 ]]; then
    echo "%SwitchGCC" >> $backlog
  fi

  # switch to default Python
  #
  grep -q ">>> Installing .* dev-lang/python-[1-9]" $bak
  if [[ $? -eq 0 ]]; then
    echo "%eselect python update" >> $backlog
  fi

  # seems to be a false warning, but it doesn't harm
  #
  grep -q 'Please run emaint --check world' $bak
  if [[ $? -eq 0 ]]; then
    echo "%emaint --check world" >> $backlog
  fi
}


# helper of RunAndCheck()
#
function CheckQA() {
  f=/tmp/qafilenames

  # process all elog files created after the last call of this function
  #
  if [[ -f $f ]]; then
    find /var/log/portage/elog -name '*.log' -newer $f  > $f.tmp
  else
    find /var/log/portage/elog -name '*.log'            > $f.tmp
  fi
  mv $f.tmp $f

  # process each QA issue independent from all others even for the same QA file
  #
  cat $f |\
  while read elogfile
  do
    cat /tmp/tb/data/CATCH_QA |\
    while read reason
    do
      grep -q "$reason" $elogfile
      if [[ $? -eq 0 ]]; then
        failed=$(basename $elogfile | cut -f1-2 -d':' -s | tr ':' '/')
        short=$(pn2p "$failed")

        CreateIssueDir

        GetAssigneeAndCc

        cp $elogfile $issuedir/issue
        AddWhoamiToIssue

        echo "$reason" > $issuedir/title
        SearchForBlocker

        grep -A 10 "$reason" $issuedir/issue > $issuedir/body
        AddVersionAssigneeAndCC

        echo -e "\nbgo.sh -d ~/img?/$name/$issuedir -s QA $block\n" >> $issuedir/body
        id=$(timeout 300 bugz -q --columns 400 search --show-status $short "$reason" 2>> $issuedir/body | sort -u -n | tail -n 1 | tee -a $issuedir/body | cut -f1 -d ' ')

        collectPortageDir
        AttachFilesToBody $issuedir/issue

        sed -i -e "s,^,$failed : [QA] ," $issuedir/title
        TrimTitle

        if [[ -z "$id" ]]; then
          SendoutIssueMail
        fi
      fi
    done
  done
}


# helper of WorkOnTask()
# run ($1) and act on issue if any
#
function RunAndCheck() {
  ($1) &>> $log
  local rc=$?

  PostEmerge
  CheckQA

  if [[ $rc -ne 0 ]]; then
    if [[ $rc -gt 127 ]]; then
      Finish 1 "KILLED by a signal $rc=rc"
    fi
    GotAnIssue
  fi

  return $rc
}


# this is the heart of the tinderbox
#
function WorkOnTask() {
  try_again=0   # 1 with default environment values (if applicable)

  # image update
  #
  if [[ $task = "@system" || $task = "@world" || $task = "@preserved-rebuild" ]]; then
    if [[ $task = "@system" ]]; then
      opts="--update --newuse --changed-use --deep --exclude sys-kernel/vanilla-sources --changed-deps=y"
    elif [[ $task = "@world" ]]; then
      opts="--update --newuse --changed-use --deep --exclude sys-kernel/vanilla-sources"
    else
      opts=""
    fi
    RunAndCheck "emerge $opts $task"
    local rc=$?

    cp $log /tmp/$task.last.log
    /usr/bin/pfl &> /dev/null

    # "ok|NOT ok|<msg>" is used in check_history() of whatsup.sh
    # to display " ", "[SWP]" or "[swp]" respectively
    #
    msg=$(grep -m 1 \
            -e 'The following USE changes are necessary to proceed:'                      \
            -e 'The following REQUIRED_USE flag constraints are unsatisfied:'             \
            -e 'The following update.* been skipped due to unsatisfied dependencies'      \
            -e 'WARNING: One or more updates/rebuilds'                                    \
            -e 'Multiple package instances within a single package slot have been pulled' \
        $bak)

    if [[ $rc -ne 0 ]]; then
      if [[ -n "$failed" ]]; then
        echo "$(date) $failed" >> /tmp/$task.history
      else
        echo "$(date) NOT ok $msg" >> /tmp/$task.history
      fi

      # set package specific USE flags as adviced and repeat @set
      # this is needed *here* to achieve a consistent dep tree
      #
      msg="The following USE changes are necessary to proceed:"
      grep -q "$msg" $bak
      if [[ $? -eq 0 ]]; then
        grep -A 10000 "$msg" $bak |\
        while read line
        do
          if [[ $line =~ ">=" || $line =~ "=" ]]; then
            echo "$line" >> /etc/portage/package.use/z_changed_use_flags
          elif [[ -z "$line" ]]; then
            break
          fi
        done
        echo "$task" >> $backlog

      elif [[ $try_again -eq 0 ]]; then
        if [[ "$task" = "@preserved-rebuild" ]]; then
          Finish 3 "task $task failed"
        elif [[ -n "$failed" ]]; then
          echo "%emerge --resume --skip-first" >> $backlog
        fi
      fi

    else
      echo "$(date) ok $msg" >> /tmp/$task.history

      # keep already installed packages if their deps changed in the meanwhile
      #
      PutDepsIntoWorldFile
    fi


  # %<command>
  #
  elif [[ $task =~ ^% ]]; then
    cmd="$(echo "$task" | cut -c2-)"
    RunAndCheck "$cmd"
    local rc=$?

    if [[ $rc -ne 0 ]]; then
      if [[ $try_again -eq 0 ]]; then
        if [[ $task =~ " --resume" ]]; then
          if [[ -n "$failed" ]]; then
            echo "%emerge --resume --skip-first" >> $backlog
          else
            grep -q ' Invalid resume list:' $bak
            if [[ $? -eq 0 ]]; then
              cat << EOF >> $backlog
@world
@system
EOF
            else
              Finish 3 "resume failed"
            fi
          fi
        elif [[ $task =~ " --unmerge " || $task =~ " -C " || $task =~ "BuildKernel" ]]; then
          :
        else
          Finish 3 "command: '$cmd'"
        fi
      fi
    fi

  # pinned version
  #
  elif [[ $task =~ ^= ]]; then
    RunAndCheck "emerge $task"

  # straight package or a @set
  #
  else
    RunAndCheck "emerge --update $task"
  fi
}


#############################################################################
#
#       main
#
mailto="tinderbox@zwiebeltoralf.de"
tsk=/tmp/task                       # holds the current task
log=$tsk.log                        # holds always output of the running task command
backlog=/tmp/backlog.1st            # this is the high prio backlog

export GCC_COLORS=""                # suppress colour output of gcc-4.9 and above
export GREP_COLORS="never"

# eg.: gnome_20150913-104240
#
name=$(grep '^PORTAGE_ELOG_MAILFROM="' /etc/portage/make.conf | cut -f2 -d '"' -s | cut -f1 -d ' ')

# needed for the b.g.o. comment #0
#
keyword="stable"
grep -q '^ACCEPT_KEYWORDS=.*~amd64' /etc/portage/make.conf
if [[ $? -eq 0 ]]; then
  keyword="unstable"
fi

# https://bugs.gentoo.org/show_bug.cgi?id=567192
#
export XDG_DESKTOP_DIR="/root/Desktop"
export XDG_DOCUMENTS_DIR="/root/Documents"
export XDG_DOWNLOAD_DIR="/root/Downloads"
export XDG_MUSIC_DIR="/root/Music"
export XDG_PICTURES_DIR="/root/Pictures"
export XDG_PUBLICSHARE_DIR="/root/Public"
export XDG_TEMPLATES_DIR="/root/Templates"
export XDG_VIDEOS_DIR="/root/Videos"

export XDG_RUNTIME_DIR="/root/run"
export XDG_CONFIG_HOME="/root/config"
export XDG_CACHE_HOME="/root/cache"
export XDG_DATA_HOME="/root/share"

# if task file is non-empty (eg. due to a reboot or Finish() with rc != 0)
# then retry the previous task
#
if [[ -s $tsk ]]; then
  cat $tsk >> $backlog
  rm $tsk
fi

while :
do
  date > $log

  # auto-clean is deactivated to collect issue files
  #
  rm -rf /var/tmp/portage/*

  if [[ -x /tmp/pretask.sh ]]; then
    /tmp/pretask.sh &> /tmp/pretask.sh.log
  fi

  setNextTask

  # it is not necessary that emerge even starts (b/c deps might not be fullfilled)
  # the emerge attempt itself is sufficient to keep $task in its history file
  #
  echo "$task" | tee -a $tsk.history > $tsk
  chmod g+w $tsk
  chgrp portage $tsk

  WorkOnTask

  # this line is not reached if Finish() is called before
  # therefore $tsk is intentionally retried at next start
  #
  rm $tsk

  # catch a loop of @preserved-rebuild but just after first @world
  #
  if [[ "$task" = "@preserved-rebuild" && -f /tmp/@world.history && $(tail -n 20 $tsk.history | grep -c "@preserved-rebuild") -ge 10 ]]; then
    Finish 3 "@preserved-rebuild loop detected" $tmpfile
  fi

done
