# #!/bin/sh
#
# set -x

# this is the tinderbox script itself
# main function: WorkOnTask()
# the remaining code just parses the output, that's all


# strip away escape sequences, hint: colorstrip() does not modify its input
#
function stresc() {
  perl -MTerm::ANSIColor=colorstrip -nle '$_ = colorstrip($_); s,\r,\n,g; s/\x00/<0x00>/g; s/\x1b\x28\x42//g; s/\x1b\x5b\x4b//g; print'
}


# send an email, $1 is subject, $2 is body
#
function Mail() {
  subject=$(echo "$1" | stresc | cut -c1-200 | tr '\n' ' ')
  ( [[ -e $2 ]] && stresc < $2 || echo "<no body>" ) | timeout 120 mail -s "$subject    @ $name" $mailto &>> /tmp/mail.log
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "$(date) rc=$rc failed=$failed issuedir=$issuedir"
  fi
}


# clean up and exit
#
function Finish()  {
  ec=$1
  shift
  # althought stresc is made in Mail() too do it here too b/c $1 might contain " and/or '
  #
  subject=$(echo "$@" | stresc | cut -c1-200 | tr '\n' ' ')

  /usr/bin/pfl &>/dev/null
  eix-update -q &>/dev/null
  Mail "FINISHED: $subject" $log

  rm -f /tmp/STOP
  exit $ec
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
        eselect java-vm set system $new &>> $log
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
  if [[ -s $pks ]]; then
    ts=/tmp/timestamp.system
    if [[ ! -f $ts ]]; then
      touch $ts
    else
      let "diff = $(date +%s) - $(date +%s -r $ts)"
      if [[ $diff -gt 86400 ]]; then
        # do not care about "#" lines to schedule @system
        #
        grep -q -E "^(STOP|INFO|%|@)" $pks
        if [[ $? -eq 1 ]]; then
          task="@system"
          # switch the java machine too by the way
          #
          SwitchJDK
          return
        fi
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


# especially in ABI="32 64" we might have more than 1 dir in /var/tmp/portage
#
function SetWorkDir() {
  work=$(fgrep -m 1 " * Working directory: '" $bak | cut -f2 -d"'")
  if [[ ! -d "$work" ]]; then
    work=$(fgrep -m 1 ">>> Source unpacked in " $bak | cut -f5 -d" ")
    if [[ ! -d "$work" ]]; then
      work=/var/tmp/portage/$failed/work/$(basename $failed)
    fi
  fi
}


# helper of GotAnIssue()
# gather together what's needed for the email and/or the bug report
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

  # collect few more build files, strip away escape sequences
  # and compress files bigger than 1 MiByte
  #
  apout=$(grep -m 1 -A 2 'Include in your bugreport the contents of'                 $bak | grep "\.out"          | cut -f5 -d' ')
  cmlog=$(grep -m 1 -A 2 'Configuring incomplete, errors occurred'                   $bak | grep "CMake.*\.log"   | cut -f2 -d'"')
  cmerr=$(grep -m 1      'CMake Error: Parse error in cache file'                    $bak | sed  "s/txt./txt/"    | cut -f8 -d' ')
  oracl=$(grep -m 1 -A 1 '# An error report file with more information is saved as:' $bak | grep "\.log"          | cut -f2 -d' ')
  envir=$(grep -m 1      'The ebuild environment file is located at'                 $bak                         | cut -f2 -d"'")
  salso=$(grep -m 1 -A 2 ' See also'                                                 $bak | grep "\.log"          | awk '{ print $1 }' )
  sandb=$(grep -m 1 -A 1 'ACCESS VIOLATION SUMMARY' $bak                                  | grep "sandbox.*\.log" | cut -f2 -d'"')

  for f in $ehist $failedlog $sandb $apout $cmlog $cmerr $oracl $envir $salso
  do
    if [[ -f $f ]]; then
      stresc < $f > $issuedir/files/$(basename $f)
    fi
  done

  for f in $issuedir/files/* $issuedir/_*
  do
    if [[ $(wc -c < $f) -gt 1000000 ]]; then
      bzip2 $f
    fi
  done

  # get every config.log file
  #
  if [[ -d "$work" ]]; then
    f=/tmp/files
    rm -f $f
    (cd "$work" && find ./ -name "config.log" > $f && [[ -s $f ]] && tar -cjpf $issuedir/files/config.log.tbz2 $(cat $f) && rm $f)
  fi

  # attach all of /etc/portage
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

  # if there's more than 1 maintainer, then take the 1st as the assignee
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


# comment #0 starts with the issue itself, then this info should follow
#
function AddWhoamiToIssue() {
  cat << EOF >> $issuedir/issue

  -----------------------------------------------------------------

  This is an $keyword amd64 chroot image (named $name) at a hardened host acting as a tinderbox.

  -----------------------------------------------------------------

EOF
}


# attach the content of the given files onto the email body
# (TODO: uuencode is not MIME compliant)
#
function AttachFiles()  {
  for f in $*
  do
    uuencode $f $(basename $f) >> $issuedir/body
  done
}


# this info helps to decide
# whether to file a bug for a stable package
# despite the fact that the issue was already fixed in an unstable version
# or not
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


# 777: allow an user to manually modify title or issue
#
function CreateIssueDir() {
  issuedir=/tmp/issues/$(date +%Y%m%d-%H%M%S)_$(echo $failed | tr '/' '_')
  mkdir -p $issuedir
  chmod 777 $issuedir
}


# get an descriptive title from the most meaningful lines of the issue
#
function GuessTitleAndIssue() {
  touch $issuedir/{issue,title}

  if [[ -n "$(grep -m 1 ' * Detected file collision(s):' $bak)" ]]; then
    # provide package name+version althought this gives more noise in our inbox
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

  elif [[ -n "$(grep -m 1 -e ' *   Make check failed. See above for details.' -e "ERROR: .* failed (test phase)" $bak)" ]]; then
    echo "fails with FEATURES=test" > $issuedir/title
    grep -q -e "=$failed" /etc/portage/package.env/test-fail-continue 2>/dev/null
    if [[ $? -eq 0 ]]; then
      Finish 2 "found $failed in /etc/portage/package.env/test-fail-continue"
    else
      echo "=$failed test-fail-continue" >> /etc/portage/package.env/test-fail-continue
      try_again=1
      if [[ -d "$work" ]]; then
        f=/tmp/ls-l.txt
        rm -f $f
        (cd "$work" && tar --dereference -cjpf $issuedir/files/tests.tbz2 ./tests ./regress 2>$f && rm $f)
        if [[ $? -ne 0 || -s $f ]]; then
          ls -ld /var/tmp/portage/*/*/work/*/* >> $f
          Mail "warn: collecting test results for '$work' fails" $f
        fi
      fi
    fi

  else
    # loop over all patterns exactly in their defined order therefore "grep -f CATCH_ISSUES" can't be used here
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
      grep -q "=$failed cxx" /etc/portage/package.env/cxx 2>/dev/null
      if [[ $? -ne 0 ]]; then
        echo "=$failed cxx" >> /etc/portage/package.env/cxx
        try_again=1
      fi
    fi
  fi
}


# guess from the title if there's an appropriate bug tracker
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
  open_bug_report_exists="n"

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

  # search first for opened, then for closed bugs
  # start with same package version, then just for the package name
  #
  for i in $failed $short
  do
    id=$(bugz -q --columns 400 search --show-status $i "$(cat $bsi)" 2>/dev/null | grep " CONFIRMED " | sort -u -n | tail -n 1 | tee -a $issuedir/body | cut -f1 -d ' ')
    if [[ -n "$id" ]]; then
      if [[ "$i" = "$failed" ]]; then
        open_bug_report_exists="y"
      fi
      break
    fi

    id=$(bugz -q --columns 400 search --show-status $i "$(cat $bsi)" 2>/dev/null | grep " IN_PROGRESS " | sort -u -n | tail -n 1 | tee -a $issuedir/body | cut -f1 -d ' ')
    if [[ -n "$id" ]]; then
      if [[ "$i" = "$failed" ]]; then
        open_bug_report_exists="y"
      fi
      break
    fi

    id=$(bugz -q --columns 400 search --resolution "DUPLICATE" --status resolved  $i "$(cat $bsi)" 2>/dev/null | sort -u -n | tail -n 1 | tee -a $issuedir/body | cut -f1 -d ' ')
    if [[ -n "$id" ]]; then
      echo -en "\n ^ duplicate " >> $issuedir/body
      break
    fi

    id=$(bugz -q --columns 400 search --show-status --status resolved $i "$(cat $bsi)" 2>/dev/null | sort -u -n | tail -n 1 | tee -a $issuedir/body | cut -f1 -d ' ')
    if [[ -n "$id" ]]; then
      break
    fi
  done

  # compile a command line ready for copy+paste and add bugzilla search results
  #
  if [[ -n "$id" ]]; then
    cat << EOF >> $issuedir/body
 https://bugs.gentoo.org/show_bug.cgi?id=$id

  bgo.sh -d ~/img?/$name/$issuedir -a $id

EOF
  else
    echo -e "  bgo.sh -d ~/img?/$name/$issuedir $block\n" >> $issuedir/body

    h='https://bugs.gentoo.org/buglist.cgi?query_format=advanced&short_desc_type=allwordssubstr'
    g='stabilize|Bump| keyword| bump'

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
  emerge --info --verbose=n $short &> $issuedir/emerge-info.txt

  GetMailAddresses
  GuessTitleAndIssue

  # shrink too long error messages
  #
  sed -i -e 's#/[^ ]*\(/[^/:]*:\)#/...\1#g' $issuedir/title

  # kick off hex addresses and such stuff to improve search results matching in b.g.o.
  #
  sed -i -e 's/0x[0-9a-f]*/<snip>/g' -e 's/: line [0-9]*:/:line <snip>:/g' $issuedir/title

  SearchForBlocker

  # copy the issue to the email body before it is furnished for b.g.o. as comment#0
  #
  cp $issuedir/issue $issuedir/body
  AddMetainfoToBody
  AddWhoamiToIssue

  # installed versions of languages and compilers
  #
  cat << EOF >> $issuedir/issue
gcc-config -l:
$(gcc-config -l                   )
$( [[ -x /usr/bin/llvm-config ]] && echo llvm-config: && llvm-config --version )
$(eselect python  list 2>/dev/null)
$(eselect ruby    list 2>/dev/null)
$( [[ -x /usr/bin/java-config ]] && echo java-config: && java-config --list-available-vms --nocolor )
$(eselect java-vm list 2>/dev/null)
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


# guess the failed package and its log file name
#
function GetFailed()  {
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

  # must work
  #
  short=$(qatom "$failed" 2>/dev/null | cut -f1-2 -d' ' | tr ' ' '/')
  if [[ ! -d /usr/portage/$short ]]; then
    failed=""
    short=""
  fi
}


# process an issue only once
# if it is in ALREADY_CATCHED then don't care for dups nor spam the inbox
# therefore if a package was fixed w/o a revision bump and should be re-tested
# then sth. like the following is needed:
#
#   sed -i -e '/sys-fs\/eudev/d' ~/tb/data/ALREADY_CATCHED ~/run/*/etc/portage/package.mask/self ~/run/*/etc/portage/package.env/{nosandbox,test-fail-continue,cxx}
#   for i in ~/run/*/tmp/packages; do grep -q -E "^(STOP|INFO|%|@|#)" $i || echo 'sys-fs/eudev' >> $i; done
#
function ReportIssue()  {
  grep -F -q -f $issuedir/title /tmp/tb/data/ALREADY_CATCHED
  if [[ $? -eq 1 ]]; then
    cat $issuedir/title >> /tmp/tb/data/ALREADY_CATCHED
    if [[ "$open_bug_report_exists" = "n" ]]; then
      Mail "${id:-ISSUE} $(cat $issuedir/title)" $issuedir/body
    fi
  fi
}


# put all successfully emerged dependencies of $task in the world file
# otherwise we'd need to use "--deep" unconditionally
# (https://bugs.gentoo.org/show_bug.cgi?id=563482)
#
function KeepDeps() {
  line=$(tac /var/log/emerge.log | grep -m 1 -E ':  === |: Started emerge on: ')
  echo "$line" | grep -q ':  === ('
  if [[ $? -eq 0 ]]; then
    echo "$line" | grep -q ':  === (1 of '
    if [[ $? -eq 1 ]]; then
      emerge --depclean --pretend --verbose=n 2>/dev/null | grep "^All selected packages: " | cut -f2- -d':' | xargs emerge --noreplace &>/dev/null
    fi
  fi
}


# emerge failed for some reason, therefore parse the output
#
function GotAnIssue()  {
  KeepDeps

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

  # ignore certain issues, stop processing of those issues completely
  #
  grep -q -f /tmp/tb/data/IGNORE_ISSUES $bak
  if [[ $? -eq 0 ]]; then
    return
  fi

  GetFailed

  if [[ -z "$failed" ]]; then
    Mail "warn: \$failed is empty for task: $task" $bak
    return
  fi

  CreateIssueDir
  cp $bak $issuedir
  SetWorkDir
  CollectIssueFiles
  CompileIssueMail

  if [[ $try_again -eq 0 ]]; then
    echo "=$failed" >> /etc/portage/package.mask/self
  fi

  ReportIssue
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
  ) &>> $log

  return $?
}


# switch to highest GCC version
#
function SwitchGCC() {
  latest=$(gcc-config --list-profiles --nocolor | cut -f3 -d' ' | grep 'x86_64-pc-linux-gnu-.*[0-9]$' | tail -n 1)
  gcc-config --list-profiles --nocolor | grep -q "$latest \*$"
  if [[ $? -eq 1 ]]; then
    verold=$(gcc -dumpversion)
    gcc-config --nocolor $latest &>> $log
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
        (cd /usr/src/linux && make clean &>/dev/null)
        echo "%BuildKernel" >> $pks
      fi
    fi
  fi
}


# helper of RunCmd()
# *schedule* needed follow-ups from a previously run emerge
#
function PostEmerge() {
  # prefix our log backup file with an "_" to distinguish it from portage's log files
  #
  bak=/var/log/portage/_emerge_$(date +%Y%m%d-%H%M%S).log
  stresc < $log > $bak

  # don't change these config files after setup
  #
  rm -f /etc/ssmtp/._cfg????_ssmtp.conf
  rm -f /etc/portage/._cfg????_make.conf
  ls /etc/._cfg????_locale.gen &>/dev/null
  if [[ $? -eq 0 ]]; then
    echo "%locale-gen" >> $pks
    rm /etc/._cfg????_locale.gen
  fi

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

  # switch to the new GCC soon
  #
  grep -q ">>> Installing .* sys-devel/gcc-[1-9]" $bak
  if [[ $? -eq 0 ]]; then
    echo "%SwitchGCC" >> $pks
  fi

  # fixing Perl is one of the first steps
  #
  grep -q ">>> Installing .* dev-lang/perl-[1-9]" $bak
  if [[ $? -eq 0 ]]; then
    echo "%perl-cleaner --all" >> $pks
  fi

  # set PAX permissions asap
  #
  grep -q 'Please run "revdep-pax" after installation.' $bak
  if [[ $? -eq 0 ]]; then
    echo "%revdep-pax" >> $pks
  fi
}


# just run the command (parameter $1) - usually "emerge <something>" -
# and process the output
#
function RunCmd() {
  ($1) &>> $log
  if [[ $? -ne 0 ]]; then
    status=1
  fi

  PostEmerge

  if [[ $status -eq 1 ]]; then
    GotAnIssue
    # Perl upgrade issue: https://bugs.gentoo.org/show_bug.cgi?id=596664
    #
    grep -q -e 'perl module is required for intltool' -e "Can't locate .* in @INC" $bak
    if [[ $? -eq 0 ]]; then
      try_again=1
      status=2
    fi
  fi

  if [[ $try_again -eq 1 ]]; then
    echo "$task" >> $pks
  fi
}


# this is the heart of the tinderbox
#
# status=0  ok
# status=1  task failed
# status=2  task failed due to Perl upgrade issue
#
function WorkOnTask() {
  status=0
  failed=""       # contains the package atom
  try_again=0     # flag whether to repeat $task or not

  if [[ "$task" = "@preserved-rebuild" ]]; then
    RunCmd "emerge --backtrack=100 $task"
    if [[ $status -eq 1 ]]; then
      if [[ $try_again -eq 0 ]]; then
        if [[ -n "$failed" ]]; then
          echo "%emerge --resume --skip-first" >> $pks
        else
          Finish 2 "$task is broken"
        fi
      fi
    fi

    echo "$(date) ${failed:-ok}" >> /tmp/timestamp.preserved-rebuild

  elif [[ "$task" = "@system" ]]; then
    RunCmd "emerge --backtrack=100 --deep --update --newuse --changed-use --with-bdeps=y $task"
    if [[ $status -eq 1 ]]; then
      if [[ $try_again -eq 0 ]]; then
        if [[ -n "$failed" ]]; then
          echo "%emerge --resume --skip-first" >> $pks
        else
          # there's no general need to update @world
          # b/c new ebuilds are scheduled by insert_pkgs.sh already,
          # but if @system fails then @world might succeed
          #
          echo "@world" >> $pks
        fi
      fi

    elif [[ $status -eq 0 ]]; then
      # activate 32/64 bit ABI if not yet done
      #
      grep -q '^#ABI_X86=' /etc/portage/make.conf
      if [[ $? -eq 0 ]]; then
        sed -i -e 's/^#ABI_X86=/ABI_X86=/' /etc/portage/make.conf
        # first make @system multi-lib ready then @world
        #
        echo -e "@world\n@system" >> $pks
      fi
    fi

    echo "$(date) ${failed:-ok}" >> /tmp/timestamp.system
    /usr/bin/pfl &>/dev/null

  elif [[ "$task" = "@world" ]]; then
    RunCmd "emerge --backtrack=100 --deep --update --newuse --changed-use --with-bdeps=y $task"
    if [[ $status -eq 1 ]]; then
      if [[ $try_again -eq 0 ]]; then
        if [[ -n "$failed" ]]; then
          echo "%emerge --resume --skip-first" >> $pks
        fi
      fi

    elif [[ $status -eq 0 ]]; then
      # if @world was ok then depclean before any scheduled @preserved-rebuild
      #
      echo "%emerge --depclean" >> $pks
    fi

    echo "$(date) ${failed:-ok}" >> /tmp/timestamp.world
    /usr/bin/pfl &>/dev/null

  elif [[ "$(echo "$task" | cut -c1)" = '%' ]]; then
    #  a command: prefixed with a '%'
    #
    cmd="$(echo "$task" | cut -c2-)"
    RunCmd "$cmd"
    if [[ $status -eq 1 ]]; then
      if [[ $try_again -eq 0 ]]; then
        # bail out except ...
        #
        echo "$cmd" | grep -q -e "--resume --skip-first"
        if [[ $? -eq 1 ]]; then
          Finish 2 "command '$cmd' failed"
        fi
      fi
    fi

  else
    # just a package (optional prefixed with "=")
    #
    RunCmd "emerge --update $task"
  fi

  if [[ $status -eq 0 ]]; then
    rm $bak
  elif [[ $status -eq 2 ]]; then
    echo "%perl-cleaner --all" >> $pks
    if [[ "$task" != "@system" ]]; then
      Mail "notice: Perl upgrade issue happened for: $task" $bak
    fi
  fi
}


# test hook, eg. to catch install artefacts
#
function pre-check() {
  exe=/tmp/pre-check.sh
  out=/tmp/pre-check.log

  if [[ ! -x $exe ]]; then
    return
  fi

  $exe &> $out
  rc=$?

  if [[ $rc -eq 0 ]]; then
    rm $out

  elif [[ $rc -gt 127 ]]; then
    Mail "$exe returned $rc, task $task" $out
    Finish 2 "error: stopped"

  else
    cat << EOF >> $out

--
seen at tinderbox image $name
log:
$( tail -n 30 $log )

--
emerge --info:
$( emerge --info --verbose=n $task 2>&1 )
EOF
    Mail "$exe : rc=$rc, task $task" $out
  fi
}


# catch QA issues
#
function ParseElogForQA() {
  find /var/log/portage/elog -name '*.log' $( [[ -f /tmp/timestamp.qa ]] && echo "-newer /tmp/timestamp.qa" ) |\
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
      echo -e "\nbgo.sh -d ~/img?/$name/$issuedir -s QA\n $blocker" >> $issuedir/body
      id=$(bugz -q --columns 400 search --show-status $short "$reason" 2>/dev/null | sort -u -n | tail -n 1 | tee -a $issuedir/body | cut -f1 -d ' ')

      Mail "${id:-QA} $failed : $reason" $issuedir/body
    fi
  done

  # process next time only those elog files which were created after this timestamp
  #
  touch /tmp/timestamp.qa
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
  # check for install artefacts from a previous task
  #
  pre-check

  if [[ -f /tmp/STOP ]]; then
    Finish 0 "catched STOP"
  fi

  # clean up from a previously failed emerge operation
  # it is configured to not be made by portage automatically
  # b/c relevant build files have to be collected before
  #
  rm -rf /var/tmp/portage/*

  date > $log
  GetNextTask
  echo "$task" | tee -a $log> /tmp/task
  WorkOnTask
  ParseElogForQA
  rm /tmp/task
done
