#!/bin/bash
#
# set -x


# This is the tinderbox script itself.
# The main function is WorkOnTask().
# The remaining code just parses the output.
# That's all.


# strip away non-printable chars
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
    s,\xc0,,g;
    s,\xdf,,g;
    print;
  '
}


# send out a non-MIME-compliant email
#
# $1 (mandatory) is the subject,
# $2 (optionally) contains either the body itself or a text file
#
function Mail() {
  subject=$(echo "$1" | stresc | cut -c1-200 | tr '\n' ' ')

  # the Debian mailx automatically adds a MIME Header line to the mail since 2017.
  # But uuencode is not MIME-compliant, therefore newer Thunderbird versions show
  # any attachment as inline text only :-(
  #
  opt=""
  if [[ -f $2 ]]; then
    grep -q "^begin 644 " $2
    if [[ $? -eq 0 ]]; then
      opt='-a'
    fi
  fi

  (
    if [[ -f $2 ]]; then
      stresc < $2
    else
      echo "${2:-<no body>}"
    fi
  ) | timeout 120 mail -s "$subject    @ $name" $mailto $opt "" &>> /var/tmp/tb/mail.log # the "" belongs to $opt but doesn't hurt here and let the mail body be looking less ugly

  local rc=$?

  if [[ $rc -ne 0 ]]; then
    # direct this both to stdout (could be catched eg. by logcheck.sh) and to an image specific logfile
    #
    echo "$(date) mail failed, rc=$rc, bgo.sh ~/img/$name/$issuedir" | tee -a /var/tmp/tb/mail.log
  fi
}


# clean up and exit
#
# $1: return code
# $2: email Subject
# $3: file to be attached
#
function Finish()  {
  local rc=$1

  # although stresc() will be called in Mail() run it here b/c $2 might contain quotes
  #
  subject=$(echo "$2" | stresc | cut -c1-200 | tr '\n' ' ')
  if [[ $rc -eq 0 ]]; then
    Mail "Finish ok: $subject"
  else
    Mail "Finish NOT ok, rc=$rc: $subject" ${3:-$logfile}
  fi

  rm -f /var/tmp/tb/STOP

  exit $rc
}


# move next item of the appropriate backlog into $task
#
function setTask()  {
  # 1st prio backlog rules always
  #
  if [[ -s $backlog ]]; then
    bl=$backlog

  # Gentoo repository changes
  # backlog.upd is updated regularly by update_backlog.sh
  # 1/N probability if no special action is in common backlog (whcih might happen by cloning from an origin)
  #
  elif [[ -s /var/tmp/tb/backlog.upd && $(($RANDOM % 5)) -eq 0 && -z "$(grep -E '^(INFO|STOP|@|%)' /var/tmp/tb/backlog)" ]]; then
    bl=/var/tmp/tb/backlog.upd

  # common backlog
  # backlog is filled up at image setup and will only decrease
  #
  elif [[ -s /var/tmp/tb/backlog ]]; then
    bl=/var/tmp/tb/backlog

  # last chance for updated packages
  #
  elif [[ -s /var/tmp/tb/backlog.upd ]]; then
    bl=/var/tmp/tb/backlog.upd

  # this is the end, my friend, the end ...
  #
  else
    n=$(qlist --installed | wc -l)
    Finish 0 "empty backlogs, $n packages installed"
  fi

  # splice last line from the winning backlog file
  #
  task=$(tail -n 1 $bl)
  sed -i -e '$d' $bl
}


# verify/parse $task accordingly to the needs of the tinderbox
#
function getNextTask() {
  while :
  do
    setTask

    if [[ -z "$task" ]]; then
      continue  # empty line is allowed

    elif [[ $task =~ ^INFO ]]; then
      Mail "$task"

    elif [[ $task =~ ^STOP ]]; then
      Finish 0 "$task"

    elif [[ $task =~ ^# ]]; then
      continue  # comment is allowed

    elif [[ $task =~ ^= || $task =~ ^@ || $task =~ ^% ]]; then
      return  # work on either a pinned version || @set || command

    else
      if [[ ! "$bl" = "/var/tmp/tb/backlog.1st" ]]; then
        echo "$task" | grep -q -f /mnt/tb/data/IGNORE_PACKAGES
        if [[ $? -eq 0 ]]; then
          continue
        fi
      fi

      # skip if $task is masked, keyworded eor just invalid
      #
      best_visible=$(portageq best_visible / $task 2>/var/tmp/tb/err.tmp)
      if [[ $? -ne 0 ]]; then
        # bail out if portage itself is broken (eg. after by a Python upgrade)
        #
        if [[ "$(grep -ch 'Traceback' /var/tmp/tb/err.tmp)" -ne "0" ]]; then
          Finish 1 "FATAL: portageq broken" /var/tmp/tb/err.tmp
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
  pushd / 1>/dev/null
  tar -cjpf $issuedir/files/etc.portage.tbz2 --dereference etc/portage
  popd 1>/dev/null
}


# b.g.o. has a limit of 1 MB
#
function CompressIssueFiles()  {
  for f in $( ls $issuedir/files/* $issuedir/_* 2>/dev/null )
  do
    if [[ $(wc -c < $f) -gt 1000000 ]]; then
      bzip2 $f
    fi
  done
}


# helper of GotAnIssue()
# gather together what's needed for the email and b.g.o.
#
function CollectIssueFiles() {
  ehist=/var/tmp/tb/emerge-history.txt

  qlop -V | grep -q "portage-utils-0.74"
  if [[ $? -eq 0 ]]; then
    local cmd="qlop --nocolor --verbose --gauge --human --time"
  else
    local cmd="qlop --nocolor --verbose --merge --unmerge"
  fi

  cat << EOF > $ehist
# This file contains the emerge history got with:
# $cmd
#
EOF
  ($cmd) &>> $ehist

  apout=$(grep -m 1 -A 2 'Include in your bugreport the contents of'                 $bak | grep "\.out"          | cut -f5 -d' ' -s)
  cmlog=$(grep -m 1 -A 2 'Configuring incomplete, errors occurred'                   $bak | grep "CMake.*\.log"   | cut -f2 -d'"' -s)
  cmerr=$(grep -m 1      'CMake Error: Parse error in cache file'                    $bak | sed  "s/txt./txt/"    | cut -f8 -d' ' -s)
  oracl=$(grep -m 1 -A 1 '# An error report file with more information is saved as:' $bak | grep "\.log"          | cut -f2 -d' ' -s)
  envir=$(grep -m 1      'The ebuild environment file is located at'                 $bak                         | cut -f2 -d"'" -s)
  salso=$(grep -m 1 -A 2 ' See also'                                                 $bak | grep "\.log"          | awk '{ print $1 }' )
  sandb=$(grep -m 1 -A 1 'ACCESS VIOLATION SUMMARY' $bak                                  | grep "sandbox.*\.log" | cut -f2 -d'"' -s)
  roslg=$(grep -m 1 -A 1 'Tests failed. When you file a bug, please attach the following file: ' $bak | grep "/LastTest\.log" | awk ' { print $2 } ')

  for f in $ehist $pkglog $sandb $apout $cmlog $cmerr $oracl $envir $salso $roslg
  do
    if [[ -f $f ]]; then
      stresc < $f > $issuedir/files/${f##*/}
    fi
  done

  CompressIssueFiles

  if [[ -d "$workdir" ]]; then
    # catch all log file(s)
    #
    (
      f=/var/tmp/tb/files
      cd "$workdir/.." &&\
      find ./ -name "*.log" -o -name "testlog.*" > $f &&\
      [[ -s $f ]] &&\
      tar -cjpf $issuedir/files/logs.tbz2 --files-from $f --warning='no-file-ignored'
      rm -f $f
    )

    # additional cmake files
    #
    cp ${workdir}/*/CMakeCache.txt $issuedir/files/ 2>/dev/null

    # provide the whole temp dir if possible
    #
    (
      cd "$workdir"/../.. &&\
      [[ -d ./temp ]]     &&\
      timeout -s 15 180 tar -cjpf $issuedir/files/temp.tbz2 \
          --dereference --warning='no-file-removed' --warning='no-file-ignored'  \
          --exclude='*/kerneldir/*' --exclude='*/var-tests/*' --exclude='*/go-build[0-9]*/*' \
          --exclude='*/testdirsymlink/*' \
          ./temp
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
function getPkgVarsFromIssuelog()  {
  pkg=$(grep -m 1 -F ' * Package: ' $logfile | awk ' { print $3 } ')
  if [[ -z "$pkg" ]]; then
    pkg="$(cd /var/tmp/portage; ls -1td */* 2>/dev/null | head -n 1)"
  fi

  pkglog=$(grep -m 1 "The complete build log is located at" $logfile | cut -f2 -d"'" -s)
  if [[ -z "$pkglog" ]]; then
    pkglog=$(grep -m 1 -A 1 "', Log file:" $logfile | tail -n 1 | cut -f2 -d"'" -s)
    if [[ -z "$pkglog" ]]; then
      pkglog=$(grep -m 1 "^>>>  '" $logfile | cut -f2 -d"'" -s)
      if [[ -z "$pkglog" ]]; then
        if [[ -n "$pkg" ]]; then
          pkglog=$(ls -1t /var/log/portage/$(echo "$pkg" | tr '/' ':'):????????-??????.log 2>/dev/null | head -n 1)
        fi
      fi
    fi
  fi

  if [[ -z "$pkg" ]]; then
    if [[ -n "$pkglog" ]]; then
      pkg=$(cut -f1-2 -d':' -s <<< ${pkglog##*/} | tr ':' '/')
    fi
  fi

  pkgname=$(pn2p "$pkg")
  repo_path=$( portageq get_repo_path / gentoo )
  if [[ ! -d $repo_path/$pkgname ]]; then
    pkg=""
    pkglog=""
    pkgname=""
  fi
}


# get assignee and cc for the b.g.o. report
#
function GetAssigneeAndCc() {
  # all meta info
  #
  m=$( equery meta -m $pkgname | grep '@' | xargs )
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
    if [[ -f $f ]]; then
      s=$( wc -c < $f )
      if [[ $s -gt 0 && $s -lt 1048576 ]]; then
        echo >> $issuedir/body
        uuencode $f ${f##*/} >> $issuedir/body
        echo >> $issuedir/body
      fi
    fi
  done
}


# query b.g.o. about same/similar bug reports
#
function AddVersionAssigneeAndCC() {
  cat << EOF >> $issuedir/body

--
versions: $(eshowkw -a amd64 $pkgname | grep -A 100 '^-' | grep -v '^-' | awk '{ if ($3 == "+") { print $1 } else if ($3 == "o") { print "**"$1 } else { print $3$1 } }' | xargs)
assignee: $(cat $issuedir/assignee)
cc:       $(cat $issuedir/cc 2>/dev/null)
--

EOF
}


# strip away the version (get $PN from $P)
#
function pn2p() {
  qatom --quiet "$1" 2>/dev/null | grep -v '(null)' | cut -f1-2 -d' ' | tr ' ' '/'
}


function CreateIssueDir() {
  while [[ : ]]; do
    issuedir=/var/tmp/tb/issues/$(date +%Y%m%d-%H%M%S)-$(echo $pkg | tr '/' '_')
    if [[ ! -d $issuedir ]]; then
      break
    fi
    sleep 1
  done

  mkdir -p $issuedir/files
  chmod 777 $issuedir # to edit title, issue etc
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
  echo "=$pkg nosandbox" >> /etc/portage/package.env/nosandbox
  try_again=1
  echo "sandbox issue" > $issuedir/title
  head -n 10 $sandb >> $issuedir/issue
}


# helper of ClassifyIssue()
#
function collectTestIssueResults() {
  grep -q "=$pkg " /etc/portage/package.env/test-fail-continue 2>/dev/null
  if [[ $? -ne 0 ]]; then
    echo "=$pkg test-fail-continue" >> /etc/portage/package.env/test-fail-continue
    try_again=1
  fi

  # tar returns an error if it can't find at least one directory
  # therefore feed only existing dirs to it
  #
  pushd "$workdir" 1>/dev/null
  dirs="$(ls -d ./tests ./regress ./t ./Testing ./testsuite.dir 2>/dev/null)"
  if [[ -n "$dirs" ]]; then
    tar -cjpf $issuedir/files/tests.tbz2 \
      --exclude="*/dev/*" --exclude="*/proc/*" --exclude="*/sys/*" --exclude="*/run/*" \
      --exclude='*.o' --exclude="*/symlinktest/*" \
      --dereference --sparse --one-file-system --warning='no-file-ignored' \
      $dirs
  fi
  popd 1>/dev/null
}


# helper of GotAnIssue()
# get the issue and a descriptive title
#
function ClassifyIssue() {
  touch $issuedir/{issue,title}

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

    pushd /var/tmp/tb 1>/dev/null

    # catch the issue and guess a better title based on manual collected pattern
    #
    cat /mnt/tb/data/CATCH_ISSUES.$phase /mnt/tb/data/CATCH_ISSUES 2>/dev/null | split --lines=1 --suffix-length=2
    for x in x??
    do
      grep -a -m 1 -B 2 -A 3 -f $x $bak > issue
      if [[ $? -eq 0 ]]; then
        mv issue $issuedir
        # take 3rd line (therefore -A 3) as the new title, strip quotes before
        #
        sed -n '3p' < $issuedir/issue | sed -e 's,['\''‘’"`], ,g' > $issuedir/title

        # if the issue file is too big, then delete at least the 1st line
        #
        if [[ $(wc -c < $issuedir/issue) -gt 1024 ]]; then
          sed -i -e "1d" $issuedir/issue
        fi
        break
      fi
    done

    rm x??

    popd 1>/dev/null

    # strip away hex addresses, line and time numbers and other stuff
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
            -e 's/(@INC contains:.*)/.../g'     \
            -e "s,ld: /.*/cc......\.o: ,ld: ,g" \
            $issuedir/title
  fi
}


# test title against known blocker
# the BLOCKER file contains paragraphs like:
#
#   # comment
#   <bug id>
#   <pattern string ready for grep -E>
#   ...
#
# if <pattern> is defined more than once then the first makes it
#
function SearchForBlocker() {
  block=""

  if [[ ! -s $issuedir/title ]]; then
    return 0
  fi

  # use < <(...) b/c $block is an outer variable
  #
  bugno=""
  while read line
  do
    if [[ $line =~ ^[0-9].*$ ]]; then
      bugno=$line
      continue
    fi

    grep -q -E "$line" $issuedir/title
    if [[ $? -eq 0 ]]; then
      block="-b $bugno"
      break
    fi
  done < <(grep -v -e '^#' -e '^$' /mnt/tb/data/BLOCKER)
}


# enrich email body by b.g.o. findings and links
#
function SearchForAnAlreadyFiledBug() {
  if [[ ! -s $issuedir/title ]]; then
    return
  fi

  bsi=$issuedir/bugz_search_items     # the title acts as a set of space separated patterns
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

  # for the file collision case: remove the package version from the installed package
  #
  grep -q "file collision" $bsi
  if [[ $? -eq 0 ]]; then
    sed -i -e 's/\-[0-9\-r\.]*$//g' $bsi
  fi

  # search first for the same version, second for category/package name
  # take the highest bug id and put the summary of the next (newest) 10 bugs into the email body
  #
  for i in $pkg $pkgname
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

  bgo.sh -d ~/img?/$name/$issuedir $block -i $id -c 'it is still an issue at $keyword amd64 tinderbox image $name'

EOF
  else
    cat << EOF >> $issuedir/body

  bgo.sh -d ~/img?/$name/$issuedir $block

EOF
    h='https://bugs.gentoo.org/buglist.cgi?query_format=advanced&short_desc_type=allwordssubstr'
    g='stabilize|Bump| keyword| bump'

    echo "  OPEN:     $h&resolution=---&short_desc=$pkgname"      >> $issuedir/body
    timeout 300 bugz --columns 400 -q search --show-status      $pkgname 2>> $issuedir/body | grep -v -i -E "$g" | sort -u -n -r | head -n 20 >> $issuedir/body

    echo "" >> $issuedir/body
    echo "  RESOLVED: $h&bug_status=RESOLVED&short_desc=$pkgname" >> $issuedir/body
    timeout 300 bugz --columns 400 -q search --status RESOLVED  $pkgname 2>> $issuedir/body | grep -v -i -E "$g" | sort -u -n -r | head -n 20  >> $issuedir/body
  fi

  # a newline makes copy+paste more convenient
  #
  echo >> $issuedir/body
}


# b.g.o. limits "Summary"
#
function TrimTitle()  {
  n=${1:-255}

  if [[ $(wc -c < $issuedir/title) -gt $n ]]; then
    truncate -s $n $issuedir/title
  fi
}


# helper of GotAnIssue()
# creates an email containing convenient links and a command line ready for copy+paste
#
function CompileIssueMail() {
  emerge -p --info $pkgname &> $issuedir/emerge-info.txt

  # shrink too long error messages
  #
  sed -i -e 's,/[^ ]*\(/[^/:]*:\),/...\1,g' $issuedir/title

  # shrink a too long #comment0
  #
  while [[ $(wc -c < $issuedir/issue) -gt 4000 ]]
  do
    sed -i '1d' $issuedir/issue
  done

  # copy issue to the email body before enhancing the issue file further to become comment#0 eventually
  #
  cp $issuedir/issue $issuedir/body
  AddWhoamiToIssue

  SearchForBlocker
  if [[ -n "$block" ]]; then
    cat <<EOF >> $issuedir/issue
  Please see the tracker bug for details.

EOF
  fi

  grep -q -e "Can't locate .* in @INC" ${bak}
  if [[ $? -eq 0 ]]; then
    cat <<EOF >> $issuedir/issue
  Please see https://wiki.gentoo.org/wiki/Project:Perl/Dot-In-INC-Removal#Counter_Balance

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
$(eselect rust    list 2>/dev/null)
$( [[ -x /usr/bin/java-config ]] && echo java-config: && java-config --list-available-vms --nocolor )
$(eselect java-vm list 2>/dev/null)

repository timestamp:

$(tail -v /var/db/repos/*/metadata/timestamp*)

emerge -qpvO $pkgname
$(head -n 1 $issuedir/emerge-qpvO)
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
    sed -i -e "s,^,$pkg : [TEST] ," $issuedir/title
  else
    sed -i -e "s,^,$pkg : ," $issuedir/title
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
  if [[ -s $issuedir/title ]]; then
    # do not inform a known issue twice
    #
    grep -F -q -f $issuedir/title /mnt/tb/data/ALREADY_CATCHED 2>/dev/null
    if [[ $? -eq 0 ]]; then
      return
    fi
    cat $issuedir/title >> /mnt/tb/data/ALREADY_CATCHED
  fi
  Mail "$(cat $issuedir/bgo_result 2>/dev/null)$(cat $issuedir/title)" $issuedir/body
}


# helper of GotAnIssue()
# add successfully emerged packages to world (otherwise we'd need "--deep" unconditionally)
# https://bugs.gentoo.org/show_bug.cgi?id=563482
#
function PutDepsIntoWorldFile() {
  emerge --depclean --pretend --verbose=n 2>/dev/null |\
  grep "^All selected packages: "                     |\
  cut -f2- -d':' -s                                   |\
  xargs --no-run-if-empty emerge -O --noreplace
}


# helper of GotAnIssue()
# for ABI_X86="32 64" we have two ./work directories in /var/tmp/portage/<category>/<name>
#
function setWorkDir() {
  workdir=$(fgrep -m 1 " * Working directory: '" $bak | cut -f2 -d"'" -s)
  if [[ ! -d "$workdir" ]]; then
    workdir=$(fgrep -m 1 ">>> Source unpacked in " $bak | cut -f5 -d" " -s)
    if [[ ! -d "$workdir" ]]; then
      workdir=/var/tmp/portage/$pkg/work/${pkg##*/}
      if [[ ! -d "$workdir" ]]; then
        workdir=""
      fi
    fi
  fi
}


function add2backlog()  {
  if [[ ! "$(tail -n 1 $backlog)" = "${@}" ]]; then
    echo "${@}" >> $backlog
  fi
}


# collect files and compile an email
#
function GotAnIssue()  {
  grep -q -F '^>>> Installing ' $bak
  if [[ $? -eq 0 ]]; then
    PutDepsIntoWorldFile &>/dev/null
  fi

  fatal=$(grep -m 1 -f /mnt/tb/data/FATAL_ISSUES $bak)
  if [[ -n "$fatal" ]]; then
    Finish 1 "FATAL: $fatal"
  fi

  grep -q -e "Exiting on signal" -e " \* The ebuild phase '.*' has been killed by signal" $bak
  if [[ $? -eq 0 ]]; then
    Finish 1 "KILLED"
  fi

  getPkgVarsFromIssuelog
  if [[ -z "$pkg" ]]; then
    return
  fi

  CreateIssueDir
  emerge -qpvO $pkgname &> $issuedir/emerge-qpvO
  GetAssigneeAndCc
  cp $bak $issuedir
  setWorkDir
  CollectIssueFiles

  phase=""          # test", "compile" etc.
  ClassifyIssue
  CompileIssueMail

  # https://bugs.gentoo.org/687226
  #
  grep -q -e "MiscXS.c: loadable library and perl binaries are mismatched" $bak
  if [[ $? -eq 0 ]]; then
    try_again=1
    add2backlog "$task"
    add2backlog "%emerge -1 sys-apps/texinfo"
    Mail "info: catched broken sys-apps/texinfo, task=$task, failed=$failed" $bak
    return
  fi

  # still seen
  #
  grep -q \
          -e "configure: error: perl module Locale::gettext required" \
          -e "Can't locate Locale/Messages.pm in @INC"                \
          $bak
  if [[ $? -eq 0 ]]; then
    if [[ $try_again -eq 0 ]]; then
      try_again=1
      add2backlog "$task"
    fi
    add2backlog "%perl-cleaner --all"
    Mail "info: catched broken Perl deps, task=$task, failed=$failed" $bak
    return
  fi

  if [[ $try_again -eq 1 ]]; then
    add2backlog "$task"
  else
    echo "=$pkg" >> /etc/portage/package.mask/self
  fi

  grep -q -f /mnt/tb/data/IGNORE_ISSUES $issuedir/title
  if [[ $? -ne 0 ]]; then
    SendoutIssueMail
  fi
}


# helper of PostEmerge()
#
function BuildKernel()  {
  echo "$FUNCNAME" >> $logfile
  (
    cd /usr/src/linux
    make distclean
    make defconfig
    make -j1
  ) &>> $logfile
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

    gcc-config --nocolor $latest &>> $logfile
    source /etc/profile

    # bug https://bugs.gentoo.org/459038
    #
    add2backlog "%revdep-rebuild"

    # force catching issues of using old GCC installation artefacts
    #
    add2backlog "%emerge --unmerge sys-devel/gcc:$verold"
  fi
}


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
      awk ' { print $2 } ' | shuf -n 1
    )
    if [[ -n "$new" && "$new" != "$old" ]]; then
      eselect java-vm set system $new 1>> $logfile
    fi
  fi
}


# helper of RunAndCheck()
# it schedules follow-ups from the last emerge operation
#
function PostEmerge() {
  # prefix our log backup file with "_" to distinguish it from portages log file
  #
  bak=/var/log/portage/_emerge-$(date +%Y%m%d-%H%M%S).log
  stresc < $logfile > $bak

  # don't change these config files after image setup
  #
  rm -f /etc/._cfg????_{hosts,resolv.conf}
  rm -f /etc/ssmtp/._cfg????_ssmtp.conf
  rm -f /etc/portage/._cfg????_make.conf

  ls /etc/._cfg????_locale.gen &>/dev/null
  if [[ $? -eq 0 ]]; then
    locale-gen > /dev/null
    rm /etc/._cfg????_locale.gen
  else
    grep -q "IMPORTANT: config file '/etc/locale.gen' needs updating." $bak
    if [[ $? -eq 0 ]]; then
      locale-gen > /dev/null
    fi
  fi

  # merge the remaining config files automatically
  # and update the runtime environment
  #
  etc-update --automode -5 1>/dev/null
  env-update &>/dev/null

  source /etc/profile
  if [[ $? -ne 0 ]]; then
    Finish 2 "can't source /etc/profile"
  fi

  # the very last step after an emerge
  #
  grep -q "Use emerge @preserved-rebuild to rebuild packages using these libraries" $bak
  if [[ $? -eq 0 ]]; then
    if [[ ! $task =~ "@preserved-rebuild" || $try_again -eq 0 ]]; then
      add2backlog "@preserved-rebuild"
    fi
  fi

  grep -q ">>> Installing .* sys-kernel/.*-sources" $bak
  if [[ $? -eq 0 ]]; then
    current=$(eselect kernel show | cut -f4 -d'/' -s )
    latest=$( eselect kernel list | tail -n 1 | awk ' { print $2 } ' )
    if [[ "$current" != "$latest" ]]; then
      eselect kernel set $latest
    fi

    if [[ ! -f /usr/src/linux/.config ]]; then
      add2backlog "%BuildKernel"
    fi
  fi

  grep -q -e "Please, run 'haskell-updater'" -e "ghc-pkg check: 'checking for other broken packages:'" $bak
  if [[ $? -eq 0 ]]; then
    add2backlog "%haskell-updater"
  fi

  grep -q ">>> Installing .* dev-lang/perl-[1-9]" $bak
  if [[ $? -eq 0 ]]; then
    add2backlog "%perl-cleaner --all"
  fi

  grep -q ">>> Installing .* sys-devel/gcc-[1-9]" $bak
  if [[ $? -eq 0 ]]; then
    add2backlog "%SwitchGCC"
  fi

  # daily subsequent image updates
  #
  if [[ ! -s $backlog && -f /var/tmp/tb/@system.history ]]; then
    let "diff = ( $(date +%s) - $(stat -c%Y /var/tmp/tb/@system.history) ) / 86400"
    if [[ $diff -ge 1 ]]; then
      add2backlog "@system"
      add2backlog "%SwitchJDK"
    fi
  fi

  grep -q ">>> Installing .* dev-lang/python-[1-9]" $bak
  if [[ $? -eq 0 ]]; then
    add2backlog "%eselect python update"
  fi

  grep -q ">>> Installing .* dev-lang/ruby-[1-9]" $bak
  if [[ $? -eq 0 ]]; then
    current=$(eselect ruby show | head -n 2 | tail -n 1 | xargs)
    latest=$(eselect ruby list | tail -n 1 | awk ' { print $2 } ')

    if [[ "$current" != "$latest" ]]; then
      add2backlog "%eselect ruby set $latest"
    fi
  fi
}


# helper of RunAndCheck()
#
function CheckQA() {
  pushd /var/tmp/tb 1>/dev/null

  # process each QA issue separately (there might be more than 1 in the same elog file)
  #
  split --lines=1 --suffix-length=2 /mnt/tb/data/CATCH_QA

  find /var/log/portage/elog -name '*.log' |\
  while read elogfile
  do
    pkg=$(cut -f1-2 -d':' -s <<< ${elogfile##*/} | tr ':' '/')
    pkgname=$(pn2p "$pkg")
    pkglog=$(ls -1t /var/log/portage/$(echo "$pkg" | tr '/' ':'):????????-??????.log 2>/dev/null | head -n 1)

    for x in x??
    do
      grep -q -a -f $x $elogfile
      if [[ $? -eq 0 ]]; then
        CreateIssueDir
        grep -a -f $x           $elogfile > $issuedir/title
        grep -a -f $x -B 1 -A 5 $elogfile | tee $issuedir/body > $issuedir/issue
        # if it contains more than 6 lines then attach it too
        #
        if [[ $( wc -l < $elogfile ) -gt 6 ]]; then
          cp $elogfile $issuedir/files/elog-${elogfile##*/}
        fi
        cp $pkglog $issuedir/files/

        AddWhoamiToIssue
        SearchForBlocker
        GetAssigneeAndCc
        AddVersionAssigneeAndCC
        SearchForAnAlreadyFiledBug
        AddBugzillaData
        collectPortageDir
        sed -i -e "s,^,$pkg : ," $issuedir/title
        TrimTitle
        AttachFilesToBody $issuedir/files/elog*
        CompressIssueFiles

        chmod 777     $issuedir/
        chmod -R a+rw $issuedir/
        if [[ -z "$id" ]]; then
          SendoutIssueMail
        fi
      fi
    done

    mv $elogfile $elogfile.checked
  done

  rm x??

  popd 1>/dev/null
}


# helper of WorkOnTask()
# run ($1) and act on result
#
function RunAndCheck() {
  ($1) &>> $logfile
  local rc=$?

  PostEmerge

  if [[ ! $keyword = "stable" ]]; then
    CheckQA
  fi

  if [[ $rc -eq 0 ]]; then
    return $rc
  fi

  if [[ $rc -lt 128 ]]; then
    GotAnIssue
  else
    let signal="$rc - 128"
    if [[ $signal -eq 9 ]]; then
      Finish 0 "catched signal $signal - exiting"
    else
      Mail "INFO: emerge got signal $signal" $bak
    fi
  fi

  return $rc
}


# this is the heart of the tinderbox
#
function WorkOnTask() {
  try_again=0   # 1 usually means to retry task, but eg. with "test-fail-continue"
  pkg=""
  pkglog=""
  pkgname=""

  # @set
  #
  if [[ $task =~ ^@ ]]; then
    opts=""
    if [[ $task = "@system" || $task = "@world" ]]; then
      opts="--update --changed-use --deep --exclude kernel/gentoo-sources --backtrack=30"
    fi
    RunAndCheck "emerge $task $opts"
    local rc=$?

    cp $logfile /var/tmp/tb/$task.last.log

    if [[ $rc -ne 0 ]]; then
      if [[ -n "$pkg" ]]; then
        echo "$(date) $pkg" >> /var/tmp/tb/$task.history
      else
        echo "$(date) NOT ok" >> /var/tmp/tb/$task.history
      fi

      grep -q "The following USE changes are necessary to proceed:" $bak
      if [[ $? -eq 0 ]]; then
        Finish 1 "$task failed due to USE flag constraints"
      fi

      if [[ $try_again -eq 0 ]]; then
        if [[ -n "$pkg" ]]; then
          add2backlog "%emerge --resume --skip-first"
        elif [[ $task = "@system" ]]; then
          # especially a QT upgrade yields into blocker for @system
          add2backlog "@world"
        fi
      fi

    else
      echo "$(date) ok" >> /var/tmp/tb/$task.history
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
          if [[ -n "$pkg" ]]; then
            add2backlog "%emerge --resume --skip-first"
          else
            grep -q ' Invalid resume list:' $bak
            if [[ $? -eq 0 ]]; then
              add2backlog "$(tac $taskfile.history | grep -m 1 '^%')"
            fi
          fi
        elif [[ ! $task =~ " --unmerge " && ! $task =~ " --depclean" && ! $task =~ "BuildKernel" ]]; then
          Finish 3 "command: '$cmd'"
        fi
      fi
    fi

  # pinned package version
  #
  elif [[ $task =~ ^= ]]; then
    RunAndCheck "emerge $task"

  # straight package name
  #
  else
    RunAndCheck "emerge --update $task"
  fi
}


# detect a loop
#
function DetectALoop() {
  x=5
  if [[ $name =~ "test" ]]; then
    let "x = x * 3"
  fi
  let "y = x * 2"

  for t in "@preserved-rebuild" "%perl-cleaner"
  do
    if [[ ! $task =~ $t ]]; then
      continue
    fi

    n=$(tail -n $y $taskfile.history | grep -c "$t")
    if [[ $n -ge $x ]]; then
      for i in $(seq 1 $y); do
        echo "#" >> $taskfile.history
      done
      Finish 1 "${n}x $t among last $y tasks"
    fi
  done
}


function syncRepo() {
  ts=gentoo/metadata/timestamp.chk
  tsMnt=$(cat /mnt/repos/$ts    2>/dev/null)
  tsImg=$(cat /var/db/repos/$ts 2>/dev/null)
  gitlck=/mnt/repos/gentoo/.git/index.lock

  if [[  "$tsMnt" = "$tsImg" && ! -e $gitlck && -e /var/db/repos/$ts ]]; then
    return 0
  fi

  while [[ -f $gitlck ]]; do
    sleep 1
  done

  rsync -aC /mnt/repos/gentoo /var/db/repos/

  if [[ -d /var/db/repos/libressl ]]; then
    rsync -aC /mnt/repos/libressl /var/db/repos/
  fi

  # handle a possible race condition
  sleep 10
  syncRepo
}


#############################################################################
#
#       main
#
mailto="tinderbox@zwiebeltoralf.de"
taskfile=/var/tmp/tb/task           # holds the current task
logfile=$taskfile.log               # holds always output of the running task command
backlog=/var/tmp/tb/backlog.1st     # this is the high prio backlog

export GCC_COLORS=""                # suppress colour output of gcc-4.9 and above
export GREP_COLORS="never"

# needed eg. for the b.g.o. comment #0
#
name=$( cat /var/tmp/tb/name )
keyword="stable"
grep -q '^ACCEPT_KEYWORDS=.*~amd64' /etc/portage/make.conf
if [[ $? -eq 0 ]]; then
  keyword="unstable"
fi

# if task file is non-empty (eg. if emerge was terminated due to a reboot) then retry it
#
if [[ -s $taskfile ]]; then
  add2backlog "$(cat $taskfile)"
  truncate -s 0 $taskfile
fi

while :
do
  if [[ -f /var/tmp/tb/STOP ]]; then
    Finish 0 "catched STOP file" /var/tmp/tb/STOP
  fi

  date > $logfile

  # auto-clean is deactivated in FEATURES to collect issue files
  #
  rm -rf /var/tmp/portage/*

  getNextTask

  if [[ -x /var/tmp/tb/pretask.sh ]]; then
    /var/tmp/tb/pretask.sh &> /var/tmp/tb/pretask.sh.log
  fi

  echo "$task" | tee -a $taskfile.history > $taskfile
  WorkOnTask

  # this line isn't reached if Finish() is called
  # therefore $task intentionally is retried at next start
  #
  truncate -s 0 $taskfile

  DetectALoop

  # do at at the end of this loop to avoid a rsync storm after reboot
  #
  syncRepo
done
