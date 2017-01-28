# #!/bin/sh
#
# set -x

# this is the tinderbox script itself
# main function: WorkOnTask()
# the remaining code just parses the output, that's all

# barrier start
# this prevents the start of a broken copy of ourself - see end of file too
#
(

# strip away escape sequences
#
function stresc() {
  perl -MTerm::ANSIColor=colorstrip -nle '$_ = colorstrip($_); s/\e\[K//g; s/\e\[\[//g; s/\e\[\(B//g; s/\r/\n/g; s/\x00/<NULL>/g; print'
}


# mail out with $1 as the subject and $2 as the body
#
function Mail() {
  subject=$(echo "$1" | cut -c1-200 | tr '\n' ' ' | stresc)
  ( [[ -e $2 ]] && stresc < $2 || echo "<no body>" ) | mail -s "$subject    @ $name" $mailto &>> /tmp/mail.log
}


# clean up and exit
#
function Finish()  {
  rc=$1
  shift
  subject=$(echo "$*" | cut -c1-200 | tr '\n' ' ' | stresc)

  /usr/bin/pfl 1>/dev/null
  eix-update -q
  Mail "FINISHED: $subject" $log

  rm -f /tmp/STOP
  exit $rc
}


# helper of GetNextTask()
# set arbitrarily the system java engine
#
function SwitchJDK()  {
  old=$(eselect java-vm show system 2>/dev/null | tail -n 1 | xargs)
  if [[ -n "$old" ]]; then
    new=$(eselect java-vm list 2>/dev/null | grep -E 'oracle-jdk-[[:digit:]]|icedtea[-bin]*-[[:digit:]]' | grep -v 'system-vm' | awk ' { print $2 } ' | sort --random-sort | head -n 1)
    if [[ -n "$new" ]]; then
      if [[ "$new" != "$old" ]]; then
        eselect java-vm set system $new &> $log
        if [[ $? -ne 0 ]]; then
          Mail "$FUNCNAME failed for $old -> $new" $log
        fi
      fi
    fi
  fi
}


# return the next item (== last line) from the package list
# and store it into $task
#
function GetNextTask() {
  # update @system once a day, if no special task is scheduled
  #
  ts=/tmp/timestamp.system
  if [[ ! -f $ts ]]; then
    touch $ts
  else
    let "diff = $(date +%s) - $(date +%s -r $ts)"
    if [[ $diff -gt 86400 ]]; then
      # here we do not care about the "#" lines
      #
      grep -q -E "^(STOP|INFO|%|@)" $pks
      if [[ $? -eq 1 ]]; then
        task="@system"
        SwitchJDK
        return
      fi
    fi
  fi

  while :;
  do
    # splice last line of the package list $pks into $task
    #
    task=$(tail -n 1 $pks)
    sed -i -e '$d' $pks

    if [[ -n "$(echo "$task" | grep '^INFO')" ]]; then
      Mail "$task"

    elif [[ -n "$(echo "$task" | grep '^STOP')" ]]; then
      Finish 0 "$task"

    elif  [[ -z "$task" ]]; then
      if [[ -s $pks ]]; then
        continue  # this line is empty, but not the package list
      fi
      n=$(qlist --installed | wc -l)
      Finish 0 "$n packages emerged, spin up a new image"

    elif [[ "$(echo "$task" | cut -c1)" = "#" ]]; then
      continue  # comment

    elif [[ -n "$(echo "$task" | cut -c1 | grep -E '(=|@|%)')" ]]; then
      return  # work on a package/set/command

    else
      echo "$task" | grep -q -f /tmp/tb/data/IGNORE_PACKAGES
      if [[ $? -eq 0 ]]; then
        continue
      fi

      # make some checks here to speed up things
      # b/c emerge spend too much time to try alternative paths

      # skip if $task is masked, keyworded or an invalid string
      #
      best_visible=$(portageq best_visible / $task 2>/dev/null)
      if [[ $? -ne 0 || -z "$best_visible" ]]; then
        continue
      fi

      # skip if $task is already installed or would be downgraded
      #
      installed=$(portageq best_version / $task)
      if [[ -n "$installed" ]]; then
        qatom --compare $installed $best_visible | grep -q -e ' == ' -e ' > '
        if [[ $? -eq 0 ]]; then
          continue
        fi
      fi

      # well, emerge $task
      #
      return
    fi
  done
}


# helper of GotAnIssue()
# gather together what we do need for the email and/or the bug report
#
function CollectIssueFiles() {
  mkdir -p $issuedir/files

  ehist=/var/tmp/portage/emerge-history.txt
  local cmd="qlop --nocolor --gauge --human --list --unlist"

  cat << EOF > $ehist
# This file contains the emerge history got with:
# $cmd
#
EOF
  $cmd >> $ehist

  # collect misc build files
  #
  cflog=$(grep -m 1 -A 2 'Please attach the following file when seeking support:'    $bak | grep "config\.log"     | cut -f2 -d' ')
  if [[ -z "$cflog" ]]; then
    cflog=$(ls -1 /var/tmp/portage/$failed/work/*/config.log 2>/dev/null)
  fi
  apout=$(grep -m 1 -A 2 'Include in your bugreport the contents of'                 $bak | grep "\.out"           | cut -f5 -d' ')
  cmlog=$(grep -m 1 -A 2 'Configuring incomplete, errors occurred'                   $bak | grep "CMake.*\.log"    | cut -f2 -d'"')
  cmerr=$(grep -m 1      'CMake Error: Parse error in cache file'                    $bak | sed  "s/txt./txt/"     | cut -f8 -d' ')
  sandb=$(grep -m 1 -A 1 'ACCESS VIOLATION SUMMARY'                                  $bak | grep "sandbox.*\.log"  | cut -f2 -d'"')
  oracl=$(grep -m 1 -A 1 '# An error report file with more information is saved as:' $bak | grep "\.log"           | cut -f2 -d' ')
  envir=$(grep -m 1      'The ebuild environment file is located at'                 $bak                          | cut -f2 -d"'")
  salso=$(grep -m 1 -A 2 ' See also'                                                 $bak | grep "\.log"           | awk '{ print $1 }' )

  # strip away escape sequences
  #
  for f in $ehist $failedlog $cflog $apout $cmlog $cmerr $sandb $oracl $envir $salso
  do
    if [[ -f $f ]]; then
      stresc < $f > $issuedir/files/$(basename $f)
    fi
  done

  # compress files bigger than 1 MiByte
  #
  for f in $issuedir/files/* $issuedir/_*
  do
    c=$(wc -c < $f)
    if [[ $c -gt 1000000 ]]; then
      bzip2 $f
    fi
  done

  # store content of target files instead just their symlinks
  #
  (cd / && tar --dereference -cjpf $issuedir/files/etc.portage.tbz2 etc/portage)

  chmod a+r $issuedir/files/*
}


# get bug report assignee and cc, GLEP 67 rules
#
function GetMailAddresses() {
  m=$(equery meta -m $failed | grep '@' | xargs)
  if [[ -z "$m" ]]; then
    m="maintainer-needed@gentoo.org"
  fi

  # if we found more than 1 maintainer, then take the 1st as the assignee
  #
  echo "$m" | grep -q ' '
  if [[ $? -eq 0 ]]; then
    echo "$m" | cut -f1  -d ' ' > $issuedir/assignee
    echo "$m" | cut -f2- -d ' ' | tr ' ' ',' > $issuedir/cc
  else
    echo "$m" > $issuedir/assignee
    touch $issuedir/cc
  fi
}


function AddWhoamiToIssue() {
  cat << EOF >> $issuedir/issue

  -----------------------------------------------------------------

  This is an $keyword amd64 chroot image (named $name) at a hardened host acting as a tinderbox.

  -----------------------------------------------------------------

EOF
}


# attach content of the given files onto the email body using the old-school uuencode
# (unfortuantely not MIME compliant)
#
function AttachFiles()  {
  for f in $*
  do
    uuencode $f $(basename $f) >> $issuedir/body
  done
}


# this info helps to decide to file a bug for a stable package despite
# the fact that the issue was already fixed in an unstable version
#
function AddMetainfoToBody() {
  cat << EOF >> $issuedir/body

--
versions: $(eshowkw -a amd64 $short | grep -A 100 '^-' | grep -v '^-' | awk '{ if ($3 == "+") { print $1 } else if ($3 == "o") { print "**"$1 } else { print $3$1 } }' | xargs)
assignee: $(cat $issuedir/assignee)
cc:       $(cat $issuedir/cc)
--

EOF
}


# 777: sometimes we have to modify title or issue
#
function CreateIssueDir() {
  issuedir=/tmp/issues/$(date +%Y%m%d-%H%M%S)_$(echo $failed | tr '/' '_')
  mkdir -p $issuedir
  chmod 777 $issuedir
}


# try to find a descriptive title and the most meaningful lines of the issue
#
function GuessTitleAndIssue() {
  touch $issuedir/{issue,title}

  if [[ -n "$(grep -m 1 ' * Detected file collision(s):' $bak)" ]]; then
    # we provide package name+version althought this gives more noise in our mail inbox
    #
    s=$(grep -m 1 -A 2 'Press Ctrl-C to Stop' $bak | grep '::' | tr ':' ' ' | cut -f3 -d' ')
    # inform the maintainers of the already installed package too
    #
    cc=$(equery meta -m $s | grep '@' | grep -v "$(cat $issuedir/assignee)" | xargs)
    # sort -u guarantees, that the file $issuedir/cc is completely read in before it will be overwritten
    #
    (cat $issuedir/cc; echo $cc) | tr ',' ' '| xargs -n 1 | sort -u | xargs | tr ' ' ',' > $issuedir/cc

    grep -m 1 -A 20 ' * Detected file collision(s):' $bak | grep -B 15 ' * Package .* NOT' > $issuedir/issue
    echo "file collision with $s" > $issuedir/title

  elif [[ -f $sandb ]]; then
    echo "=$failed nosandbox" >> /etc/portage/package.env/nosandbox
    try_again=1

    p="$(grep -m1 ^A: $sandb)"
    echo "$p" | grep -q "A: /root/"
    if [[ $? -eq 0 ]]; then
      # handle XDG sandbox issues (forced by us) in a special way
      #
      cat << EOF > $issuedir/issue
This issue is forced at the tinderbox by making:

$(grep '^export XDG_' /tmp/job.sh)

pls see bug #567192 too

EOF
      echo "sandbox issue (XDG_xxx_DIR related)" > $issuedir/title
    else
      # other sandbox issues, strip away temp file name suffix
      #
      echo "sandbox issue $p" | sed 's/\.cache.*/.cache./g' > $issuedir/title
    fi
    head -n 10 $sandb >> $issuedir/issue

  elif [[ -n "$(grep -m 1 ' *   Make check failed. See above for details.' $bak)" ]]; then
    echo "fails with FEATURES=test" > $issuedir/title
    echo "=$failed test-fail-continue" >> /etc/portage/package.env/test-fail-continue
    try_again=1

    (cd /var/tmp/portage/$failed/work/* && tar --dereference -cjpf $issuedir/files/tests.tbz2 ./tests)

  else
    # loop over all patterns exactly in their defined order therefore "grep -f CATCH_ISSUES" won't work here
    #
    cat /tmp/tb/data/CATCH_ISSUES |\
    while read c
    do
      grep -m 1 -B 2 -A 3 "$c" $bak > $issuedir/issue
      if [[ $? -eq 0 ]]; then
        head -n 3 < $issuedir/issue | tail -n 1 > $issuedir/title
        break
      fi
    done

    if [[ $(wc -w <$issuedir/title) -eq 0 ]]; then
      Finish 2 "no title for task $task"
    fi

    if [[ $(wc -w <$issuedir/issue) -eq 0 ]]; then
      Finish 2 "no issue for task $task"
    fi

    # this gcc-6 issue is forced by us, masking this package
    # would prevent tinderboxing of a lot of affected deps
    # therefore build the failed package now with default CXX flags
    #
    grep -q '\[\-Werror=terminate\]' $issuedir/title
    if [[ $? -eq 0 ]]; then
      grep -q "=$failed cxx" /etc/portage/package.env/cxx
      if [[ $? -eq 1 ]]; then
        echo "=$failed cxx" >> /etc/portage/package.env/cxx
        try_again=1
      fi
    fi
  fi
}


# guess from the title if there's a bug tracker for this issue
# the BLOCKER file must follow this syntax:
#
#   # comment
#   <bug id>
#   <pattern>
#   ...
#
# if <pattern> is defined more than once then the first entry will make it
#
function SearchForBlocker() {
  block=$(
    grep -v -e '^#' -e '^[1-9].*$' /tmp/tb/data/BLOCKER |\
    while read line
    do
      grep -q -E "$line" $issuedir/title
      if [[ $? -eq 0 ]]; then
        echo -n "-b "
        grep -m 1 -B 1 "$line" /tmp/tb/data/BLOCKER | head -n 1 # no grep -E here !
        break
      fi
    done
  )

  # distinguish between gcc-5/6
  #
  if [[ "$block" = "-b 582084" ]]; then
    if [[ $(gcc -dumpversion | cut -c1) -eq 5 ]] ; then
      block="-b 603260"
    fi
  fi
}


# don't report this issue if an appropriate bug report exists
#
function SearchForAnAlreadyFiledBug() {
  bsi=$issuedir/bugz_search_items
  bug_report_exists="n"

  # strip away from the bugzilla search string the package name and replace
  # certain characters, line numbers et al with spaces;
  # use a temp file to dangle around special chars
  #
  cp $issuedir/title $bsi
  sed -i -e "s/['‘’\"\`]/ /g" -e 's,/.../, ,' -e 's/:[0-9]*/: /g' -e 's/[<>&\*\?]/ /g' -e 's,[()], ,g' $bsi
  # for the file collision case: remove the package version (from the counterpart)
  #
  grep -q "file collision" $bsi
  if [[ $? -eq 0 ]]; then
    sed -i -e 's/\-[0-9\-r\.]*$//g' $bsi
  fi

  # if a bug was filed but for another package version (== $short)
  # then we have to decide if we file a bug or not
  # eg.: to stabelize a new GCC compiler the stable package might fail with the new compiler
  # but the unstable version was already fixed before
  #
  for i in $failed $short
  do
    id=$(bugz -q --columns 400 search --show-status $i "$(cat $bsi)" 2>/dev/null | grep " CONFIRMED " | sort -u -n | tail -n 1 | tee -a $issuedir/body | cut -f1 -d ' ')
    if [[ -n "$id" ]]; then
      break;
    fi

    id=$(bugz -q --columns 400 search --show-status $i "$(cat $bsi)" 2>/dev/null | grep " IN_PROGRESS " | sort -u -n | tail -n 1 | tee -a $issuedir/body | cut -f1 -d ' ')
    if [[ -n "$id" ]]; then
      break
    fi

    id=$(bugz -q --columns 400 search --show-status --status resolved $i "$(cat $bsi)" 2>/dev/null | sort -u -n | tail -n 1 | tee -a $issuedir/body | cut -f1 -d ' ')
    if [[ -n "$id" ]]; then
      break
    fi
  done

  # compile a command line ready for copy+paste
  # and add bugzilla search results if needed
  #
  if [[ -n "$id" ]]; then
    if [[ "$i" = "$failed" ]]; then
      bug_report_exists="y"
    fi

    cat << EOF >> $issuedir/body
  https://bugs.gentoo.org/show_bug.cgi?id=$id

  ~/tb/bin/bgo.sh -d ~/img?/$name/$issuedir -a $id

EOF
  else
    echo -e "  ~/tb/bin/bgo.sh -d ~/img?/$name/$issuedir $block\n" >> $issuedir/body

    h="https://bugs.gentoo.org/buglist.cgi?query_format=advanced&short_desc_type=allwordssubstr"
    g="stabilize|Bump| keyword| bump"

    echo "  OPEN:     ${h}&resolution=---&short_desc=${short}" >> $issuedir/body
    bugz --columns 400 -q search --show-status      $short 2>/dev/null | grep -v -i -E "$g" | sort -u -n | tail -n 20 | tac >> $issuedir/body

    echo "" >> $issuedir/body
    echo "  RESOLVED: ${h}&bug_status=RESOLVED&short_desc=${short}" >> $issuedir/body
    bugz --columns 400 -q search --status RESOLVED  $short 2>/dev/null | grep -v -i -E "$g" | sort -u -n | tail -n 20 | tac >> $issuedir/body
  fi
}


# helper of GotAnIssue()
# create an email containing convenient links and command lines ready for copy+paste
#
function CompileIssueMail() {
  # no --verbose, output size would exceed the 16 KB limit of b.g.o.
  #
  emerge --info --verbose=n $short > $issuedir/emerge-info.txt

  GetMailAddresses
  GuessTitleAndIssue

  # shrink too long error messages
  #
  sed -i -e 's#/[^ ]*\(/[^/:]*:\)#/...\1#g' $issuedir/title

  # kick off hex addresses and such stuff to improve search results matching in b.g.o.
  #
  sed -i -e 's/0x[0-9a-f]*/<snip>/g' -e 's/: line [0-9]*:/:line <snip>:/g' $issuedir/title

  SearchForBlocker

  # copy the issue to the email body before we extend it for b.g.o. comment#0
  #
  cp $issuedir/issue $issuedir/body
  AddMetainfoToBody
  AddWhoamiToIssue

  cat << EOF >> $issuedir/issue
gcc-config -l:
$(gcc-config -l 2>&1                && echo)
llvm-config --version:
$(llvm-config --version 2>&1        && echo)
$(eselect java-vm list 2>/dev/null  && echo)
$(eselect python  list 2>&1         && echo)
$(eselect ruby    list 2>/dev/null  && echo)
java-config:
$(java-config --list-available-vms --nocolor 2>/dev/null && echo)
  -----------------------------------------------------------------
EOF

  SearchForAnAlreadyFiledBug

  AttachFiles $issuedir/emerge-info.txt $issuedir/files/* $issuedir/_*

  # prefix title with package name + version
  #
  sed -i -e "s#^#$failed : #" $issuedir/title

  # b.g.o. has a limit for "Summary" of 255 chars
  #
  if [[ $(wc -c < $issuedir/title) -gt 255 ]]; then
    truncate -s 255 $issuedir/title
  fi

  # allows us to modify the content as non-root/portage user too
  #
  chmod    777  $issuedir/{,files}
  chmod -R a+rw $issuedir/
}


# emerge failed for some reason, therefore parse the output
#
function GotAnIssue()  {
  # put all successfully emerged dependencies of $task into the world file
  # otherwise we'd need "--deep" (https://bugs.gentoo.org/show_bug.cgi?id=563482)
  #
  line=$(tac /var/log/emerge.log | grep -m 1 -E ':  === |: Started emerge on: ')
  echo "$line" | grep -q ':  === ('
  if [[ $? -eq 0 ]]; then
    echo "$line" | grep -q ':  === (1 of '
    if [[ $? -eq 1 ]]; then
      emerge --depclean --pretend --verbose=n 2>/dev/null | grep "^All selected packages: " | cut -f2- -d':' | xargs emerge --noreplace &> /dev/null
    fi
  fi

  # bail out if an OOM happened or gcc upgrade failed
  #
  fatal=$(grep -f /tmp/tb/data/FATAL_ISSUES $bak)
  if [[ -n "$fatal" ]]; then
    Finish 1 "FATAL: $fatal"
  fi

  # our current shared repository solution is (although rarely) racy
  #
  grep -q -e 'AssertionError: ebuild not found for' -e 'portage.exception.FileNotFound:' $bak
  if [[ $? -eq 0 ]]; then
    echo "$task" >> $pks
    return
  fi

  # ignore certain issues & do not mask those packages
  #
  grep -q -f /tmp/tb/data/IGNORE_ISSUES $bak
  if [[ $? -eq 0 ]]; then
    return
  fi

  # guess the failed package and its log file name
  #
  failedlog=$(grep -m 1 "The complete build log is located at" $bak | cut -f2 -d"'")
  if [[ -z "$failedlog" ]]; then
    failedlog=$(grep -m 1 -A 1 "', Log file:" $bak | tail -n 1 | cut -f2 -d"'")
    if [[ -z "$failedlog" ]]; then
      failedlog=$(grep -m 1 "^>>>  '" $bak | cut -f2 -d"'")
    fi
  fi

  if [[ -n "$failedlog" ]]; then
    failed=$(basename $failedlog | cut -f1-2 -d':' | tr ':' '/')
  else
    failed="$(cd /var/tmp/portage; ls -1d */* 2>/dev/null)"
    if [[ -n "$failed" ]]; then
      failedlog=$(ls -1t /var/log/portage/$(echo "$failed" | tr '/' ':'):????????-??????.log 2>/dev/null | head -n 1)
    else
      failed=$(grep -m1 -F ' * Package:    ' | awk ' { print $3 } ' $bak)
    fi
  fi

  # after this point we must have a failed package name
  #
  if [[ -z "$failed" ]]; then
    Mail "warn: \$failed is empty for task: $task" $bak
    return
  fi

  # strip away the package version
  #
  short=$(qatom $failed | cut -f1-2 -d' ' | tr ' ' '/')

  # short must be a valid atom
  #
  if [[ ! -d /usr/portage/$short ]]; then
    Mail "warn: \$short=$short isn't valid, \$task=$task, \$failed=$failed" $bak
    return
  fi

  CreateIssueDir
  cp $bak $issuedir

  CollectIssueFiles
  CompileIssueMail

  # https://bugs.gentoo.org/show_bug.cgi?id=596664
  #
  grep -q -e 'perl module is required for intltool' -e "Can't locate .* in @INC" $bak
  if [[ $? -eq 0 ]]; then
    # just keep these files, do not put them into the ./files subdir
    # b/c then they would be attached onto the bug report
    #
    (
    cd /
    tar --dereference -cjpf $issuedir/var.db.pkg.tbz2       var/db/pkg
    tar --dereference -cjpf $issuedir/var.lib.portage.tbz2  var/lib/portage
    )

    # do not set try_again here b/c we have to clean up first
    #
    echo "$task" >> $pks
    echo "%perl-cleaner --all" >> $pks
    if [[ "$task" != "@system" ]]; then
      Mail "notice: Perl upgrade issue happened for: $task" $log
    fi
    return
  fi

  if [[ $try_again -eq 0 ]]; then
    echo "=$failed" >> /etc/portage/package.mask/self
  fi

  # process an issue only once, so if it is in ALREADY_CATCHED
  # then don't care for dups nor spam the inbox
  # if a package was fixed w/o a revision bump and should be re-tested
  # then sth. like the following helps:
  #
  #   sed -i -e '/sys-fs\/eudev/d' ~/tb/data/ALREADY_CATCHED ~/run/*/etc/portage/package.mask/self ~/run/*/etc/portage/package.env/{nosandbox,test-fail-continue}
  #   for i in ~/run/*/tmp/packages; do grep -q -E "^(STOP|INFO|%|@|#)" $i || echo 'sys-fs/eudev' >> $i; done
  #
  grep -F -q -f $issuedir/title /tmp/tb/data/ALREADY_CATCHED
  if [[ $? -eq 1 ]]; then
    cat $issuedir/title >> /tmp/tb/data/ALREADY_CATCHED
    if [[ "$bug_report_exists" = "n" ]]; then
      Mail "${id:-ISSUE} $(cat $issuedir/title)" $issuedir/body
    fi
  fi
}


# certain packages depend on *compiled* kernel modules
#
function BuildKernel()  {
  (
    eval $(grep -e ^CC= -e ^CXX= /etc/portage/make.conf)
    export CC CXX

    cd /usr/src/linux     &&\
    make defconfig        &&\
    make modules_prepare  &&\
    make                  &&\
    make modules_install  &&\
    make install
  ) &> $log

  return $?
}


# switch to highest GCC version
#
function SwitchGCC() {
  latest=$(gcc-config --list-profiles --nocolor | cut -f3 -d' ' | grep 'x86_64-pc-linux-gnu-.*[0-9]$' | tail -n 1)
  gcc-config --list-profiles --nocolor | grep -q "$latest \*$"
  if [[ $? -eq 1 ]]; then
    verold=$(gcc -dumpversion)
    gcc-config --nocolor $latest &> $log
    source /etc/profile
    vernew=$(gcc -dumpversion)

    majold=$(echo $verold | cut -c1)
    majnew=$(echo $vernew | cut -c1)

    # rebuild kernel and tool chain after a major version number change
    #
    if [[ "$majold" != "$majnew" ]]; then
      # per request of Soap this is forced with gcc-6
      #
      if [[ $majnew -eq 6 ]]; then
        sed -i -e 's/^CXXFLAGS="/CXXFLAGS="-Werror=terminate /' /etc/portage/make.conf
      fi

      cat << EOF >> $pks
%emerge --unmerge =sys-devel/gcc-$verold
%fix_libtool_files.sh $verold
%revdep-rebuild --ignore --library libstdc++.so.6 -- --exclude gcc
EOF
      # without a *re*build we'd get issues like: "cc1: error: incompatible gcc/plugin versions"
      #
      if [[ -e /usr/src/linux/.config ]]; then
        (cd /usr/src/linux && make clean &> /dev/null)
        echo "%BuildKernel" >> $pks
      fi
    fi
  fi
}


# helper of RunCmd()
# work on follow-ups from the previous emerge operation
# do just *schedule* needed operations
#
function PostEmerge() {
  # prefix our log backup file with an "_" to distinguish it from portage's log files
  #
  bak=/var/log/portage/_emerge_$(date +%Y%m%d-%H%M%S).log
  stresc < $log > $bak

  # don't change these config files
  #
  rm -f /etc/ssmtp/._cfg????_ssmtp.conf
  rm -f /etc/portage/._cfg????_make.conf
  rm -f etc/._cfg0000_locale.gen

  etc-update --automode -5 1>/dev/null
  env-update 1>/dev/null
  source /etc/profile

  # [15:02] <iamben> sandiego: emerge @preserved-rebuild should be your very last step in upgrading, it's not urgent at all.  do "emerge -uDNav @world" first
  #
  grep -q "Use emerge @preserved-rebuild to rebuild packages using these libraries" $bak
  if [[ $? -eq 0 ]]; then
    echo "@preserved-rebuild" >> $pks
  fi

  # switching and building a new kernel should be one of the last steps
  #
  grep -q ">>> Installing .* sys-kernel/.*-sources" $bak
  if [[ $? -eq 0 ]]; then
    last=$(ls -1dt /usr/src/linux-* | head -n 1 | cut -f4 -d'/')
    link=$(eselect kernel show | tail -n 1 | sed -e 's/ //g' | cut -f4 -d'/')
    if [[ "$last" != "$link" ]]; then
      eselect kernel set $last
    fi

    if [[ ! -f /usr/src/linux/.config ]]; then
      echo "%BuildKernel" >> $pks
    fi
  fi

  grep -q -e "Please, run 'haskell-updater'" -e "ghc-pkg check: 'checking for other broken packages:'" $bak
  if [[ $? -eq 0 ]]; then
    echo "%haskell-updater" >> $pks
  fi

  # switching to a new gcc might schedule an upgrade of the linux kernel too
  #
  grep -q ">>> Installing .* sys-devel/gcc-[1-9]" $bak
  if [[ $? -eq 0 ]]; then
    echo "%SwitchGCC" >> $pks
  fi

  # use ionice to lower the impact if many images at the same side would upgrade perl
  #
  grep -q ">>> Installing .* dev-lang/perl-[1-9]" $bak
  if [[ $? -eq 0 ]]; then
    echo "%ionice -c 3 perl-cleaner --all" >> $pks
  fi

  # setting pax permissions shoudld be made asap
  #
  grep -q 'Please run "revdep-pax" after installation.' $bak
  if [[ $? -eq 0 ]]; then
    echo "%revdep-pax" >> $pks
  fi
}


# helper of WorkOnTask()
#
function RunCmd() {
  ($1) &> $log
  rc=$?
  PostEmerge

  if [[ $rc -ne 0 ]]; then
    GotAnIssue
  fi

  if [[ $try_again -eq 1 ]]; then
    echo "$task" >> $pks
  fi

  return $rc
}


# this is the heart of the tinderbox, the rest is just output parsing
#
function WorkOnTask() {
  failed=""       # contains the package
  try_again=0     # flag to repeat $task

  if [[ "$task" = "@preserved-rebuild" ]]; then
    RunCmd "emerge --backtrack=100 $task"
    if [[ $? -ne 0 ]]; then
      if [[ $try_again -eq 0 ]]; then
        grep -q   -e 'WARNING: One or more updates/rebuilds have been skipped due to a dependency conflict:' \
                  -e 'The following mask changes are necessary to proceed:' \
                  -e '* Error: The above package list contains packages which cannot be' \
                  $bak
        if [[ $? -eq 0 ]]; then
          echo "$task" >> $pks
          Finish 0 "notice: broken $task"
        fi
      fi
    fi

    echo "$(date) ${failed:-ok}" >> /tmp/timestamp.preserved-rebuild

  elif [[ "$task" = "@system" ]]; then
    RunCmd "emerge --backtrack=100 --deep --update --newuse --changed-use --with-bdeps=y $task"
    if [[ $? -ne 0 ]]; then
      if [[ $try_again -eq 0 ]]; then
        if [[ -n "$failed" ]]; then
          echo "%emerge --resume --skip-first" >> $pks
        else
          # althought @system failes @world might succeed,
          # but there's no general need to update @world
          # b/c new ebuilds are scheduled by insert_pkgs.sh
          # already
          #
          echo "@world" >> $pks
        fi
      fi

    else
      # activate 32/64 bit ABI if not yet done
      #
      grep -q '^#ABI_X86=' /etc/portage/make.conf
      if [[ $? -eq 0 ]]; then
        sed -i -e 's/^#ABI_X86=/ABI_X86=/' /etc/portage/make.conf
        # start with @system then continue with @world
        #
        echo -e "@world\n@system" >> $pks
      fi
    fi

    echo "$(date) ${failed:-ok}" >> /tmp/timestamp.system
    /usr/bin/pfl &> /dev/null

  elif [[ "$task" = "@world" ]]; then
    RunCmd "emerge --backtrack=100 --deep --update --newuse --changed-use --with-bdeps=y $task"
    if [[ $? -ne 0 ]]; then
      if [[ $try_again -eq 0 ]]; then
        if [[ -n "$failed" ]]; then
          echo "%emerge --resume --skip-first" >> $pks
        fi
      fi
    else
      # if @world was ok then run this before any scheduled @preserved-rebuild would be run
      #
      echo "%emerge --depclean" >> $pks
    fi

    echo "$(date) ${failed:-ok}" >> /tmp/timestamp.world
    /usr/bin/pfl &> /dev/null

  elif [[ "$(echo $task | cut -c1)" = '%' ]]; then
    #  a command: prefixed with a '%'
    #
    RunCmd "$(echo "$task" | cut -c2-)"
    if [[ $? -ne 0 ]]; then
      if [[ $try_again -eq 0 ]]; then
        # jump out except in a "resume + skip first" case
        #
        echo "$RunCmd" | grep -q -e "--resume --skip-first"
        if [[ $? -eq 1 ]]; then
          Finish 2 "command '$RunCmd' failed"
        fi
      fi
    fi

  else
    # just a package (optional prefixed with an "=")
    #
    RunCmd "emerge --update $task"
  fi

  # set in RunCmd()
  #
  if [[ $rc -eq 0 ]]; then
    rm $bak
  fi
}


# test hook, eg. to catch install artefacts
#
function pre-check() {
  exe=/tmp/tb/bin/PRE-CHECK.sh

  if [[ -x $exe ]]; then
    out=/tmp/pre-check.log

    $exe &> $out
    rc=$?

    # -1 == 255:-2 == 254, ...
    #
    if [[ $rc -gt 127 ]]; then
      Mail "$exe returned $rc, task $task" $out
      Finish 2 "error: stopped"
    fi

    if [[ $rc -ne 0 ]]; then
      echo                                  >> $out
      echo "seen at tinderbox image $name"  >> $out
      echo                                  >> $out
      tail -n 30 $log                       >> $out
      echo                                  >> $out
      emerge --info --verbose=n $task       >> $out
      echo                                  >> $out
      Mail "$exe : rc=$rc, task $task" $out
    fi

    rm $out
  fi
}


# here we catch certain QA issues
#
function ParseElogForQA() {
  find /var/log/portage/elog -name '*.log' -newer /tmp/timestamp.qa |\
  while read i
  do
    #  (runtime-paths) - [TRACKER] Ebuild that install into paths that should be created at runtime
    #
    reason="installs into paths that should be created at runtime"
    grep -q "QA Notice: $reason" $i
    if [[ $? -eq 0 ]]; then
      failed=$(basename $i  | cut -f1-2 -d':' | tr ':' '/')
      short=$(qatom $failed | cut -f1-2 -d' ' | tr ' ' '/')
      blocker="-b 520404"

      CreateIssueDir

      cp $i $issuedir/issue
      AddWhoamiToIssue
      AttachFiles $issuedir/issue

      echo "$failed : $reason" > $issuedir/title

      GetMailAddresses
      grep -A 10 $issuedir/issue > $issuedir/body
      AddMetainfoToBody
      echo -e "\n~/tb/bin/bgo.sh -d ~/img?/$name/$issuedir -s QA\n $blocker" >> $issuedir/body
      id=$(bugz -q --columns 400 search --show-status $short "$reason" | sort -u -n | tail -n 1 | tee -a $issuedir/body | cut -f1 -d ' ')

      Mail "${id:-QA} $failed : $reason" $issuedir/body
    fi
  done
}


#############################################################################
#
#       main
#
mailto="tinderbox@zwiebeltoralf.de"
log=/tmp/task.log                   # holds always output of "emerge ... "
pks=/tmp/packages                   # the pre-filled package list file

export GCC_COLORS=""                # suppress colour output of gcc-4.9 and above

# eg.: gnome-unstable_20150913-104240
#
name=$(grep "^PORTAGE_ELOG_MAILFROM=" /etc/portage/make.conf | cut -f2 -d '"' | cut -f1 -d ' ')

# needed for the bugzilla comment #0
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

while :;
do
  # restart this script if its origin was changed
  #
  diff -q /tmp/tb/bin/job.sh /tmp/job.sh 1>/dev/null
  rc=$?
  if [[ $rc -eq 1 ]]; then
    exit 125  # was edited
  elif [[ $rc -eq 2 ]]; then
    exit 1    # trouble
  fi

  # check for install artefacts from previous operations
  #
  pre-check

  if [[ -f /tmp/STOP ]]; then
    Finish 0 "catched STOP"
  fi

  # clean up from a previous emerge operation
  # (not made by portage to collect relevant build and log files first)
  #
  rm -rf /var/tmp/portage/*

  # process only elog files created after this timestamp
  #
  touch /tmp/timestamp.qa

  date > $log
  GetNextTask
  WorkOnTask
  ParseElogForQA
done

# barrier end (see start of this file too)
#
)
