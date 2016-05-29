#!/bin/sh
#
# set -x

# this is the tinderbox script - it runs within the chroot image for few weeks
#

# barrier start
# this prevents the start of a broken copy of ourself - see end of file too
#
(

# strip away escape sequences
#
function stresc() {
  # remove colour ESC sequences, ^[[K and carriage return
  # do not use perl -ne 's/\e\[?.*?[\@-~]//g; print' due to : https://bugs.gentoo.org/show_bug.cgi?id=564998#c6
  #
  perl -MTerm::ANSIColor=colorstrip -nle '$_ = colorstrip($_); s/\e\[K//g; s/\r/\n/g; print'
}


# send out an email with $1 as the subject(length-limited) and $2 as the body
#
function Mail() {
  ( [[ -e $2 ]] && cat $2 || date ) | stresc | mail -s "$(echo "$1" | cut -c1-200)    @ $name" $mailto &>> /tmp/mail.log &
}


# clean up and exit
#
function Finish()  {
  Mail "FINISHED: $*" $log
  rm -f /tmp/STOP

  exit 0
}


# move last line of the package list $pks into $task
# or exit from here
#
function GetNextTask() {
  # update @system immediately after setup of an image
  #
  if [[ ! -f /tmp/timestamp.system ]]; then
    touch /tmp/timestamp.system
    task="@system"
    return
  fi

  #   update @system once a day, if nothing special is scheduled
  #
  let "diff = $(date +%s) - $(date +%s -r /tmp/timestamp.system)"
  if [[ $diff -gt 86400 ]]; then
    grep -q -E "^(STOP|INFO|%|@)" $pks
    if [[ $? -ne 0 ]]; then
      task="@system"
      return
    fi
  fi

  while :;
  do
    task=$(tail -n 1 $pks)
    sed -i -e '$d' $pks     # deletes the last line of a file

    if [[ -n "$(echo $task | grep '^INFO')" ]]; then
      Mail "$task"

    elif [[ -n "$(echo $task | grep '^STOP')" ]]; then
      Finish "$task"

    elif  [[ -z "$task" ]]; then   # an empty line is allowed
      if [[ -s $pks ]]; then
        continue  # package list is not empty
      fi

      # we reached end of lifetime of this image
      #
      /usr/bin/pfl &>/dev/null
      n=$(qlist --installed | wc -l)
      date > $log
      Finish "$n packages emerged"

    elif [[ "$(echo $task | cut -c1)" = '%' ]]; then
      return  # a complete command line

    elif [[ "$(echo $task | cut -c1)" = '@' ]]; then
      return  # a package set

    else
      echo "$task" | grep -q -f /tmp/tb/data/IGNORE_PACKAGES
      if [[ $? -eq 0 ]]; then
        continue
      fi

      # no result set: $task can't be emerged or is a malformed string
      #
      if [[ -z "$(portageq $task 2>/dev/null)" ]]; then
        continue
      fi

      # empty eg. if all unstable package versions are hard masked
      #
      typeset best_visible=$(portageq best_visible / $task)
      if [[ -z "$best_visible" ]]; then
        continue
      fi

      # if $task is already installed then don't downgrade it
      #
      typeset installed=$(qlist --installed --verbose $task | tail -n 1)  # use tail to catch the highest slot only
      if [[ -n "$installed" ]]; then
        qatom --compare $installed $best_visible | grep -q '>'
        if [[ $? -eq 0 ]]; then
          continue
        fi
      fi

      # ok, try to emerge $task
      #
      return
    fi
  done
}


# compile convenient information together
#
function CollectIssueFiles() {
  ehist=/var/tmp/portage/emerge-history.txt
  cmd="qlop --nocolor --gauge --human --list --unlist"

  echo "# This file contains the emerge history got with:" > $ehist
  echo "# $cmd" >> $ehist
  echo "#"      >> $ehist
  $cmd          >> $ehist

  # the log file name of the failed package
  #
  failedlog=$(grep -m 1 "The complete build log is located at" $bak | cut -f2 -d"'")
  if [[ -z "$failedlog" ]]; then
    failedlog=$(grep -m 1 -A 1 "', Log file:" $bak | tail -n 1 | cut -f2 -d"'")
    if [[ -z "$failedlog" ]]; then
      failedlog=$(ls -1t /var/log/portage/$(echo "$failed" | tr '/' ':'):????????-??????.log 2>/dev/null | head -n 1)
    fi
  fi

  # misc build log files
  #
  cflog=$(grep -m 1 -A 2 'Please attach the following file when seeking support:'    $bak | grep "config\.log"     | cut -f2 -d' ')
  apout=$(grep -m 1 -A 2 'Include in your bugreport the contents of'                 $bak | grep "\.out"           | cut -f5 -d' ')
  cmlog=$(grep -m 1 -A 2 'Configuring incomplete, errors occurred'                   $bak | grep "CMake.*\.log"    | cut -f2 -d'"')
  cmerr=$(grep -m 1      'CMake Error: Parse error in cache file'                    $bak | sed  "s/txt./txt/"     | cut -f8 -d' ')
  sandb=$(grep -m 1 -A 1 'ACCESS VIOLATION SUMMARY'                                  $bak | grep "sandbox.*\.log"  | cut -f2 -d'"')
  oracl=$(grep -m 1 -A 1 '# An error report file with more information is saved as:' $bak | grep "\.log"           | cut -f2 -d' ')
  envir=$(grep -m 1      'The ebuild environment file is located at'                 $bak                          | cut -f2 -d"'")
  salso=$(grep -m 1 -A 2 ' See also'                                                 $bak | grep "\.log"           | awk '{ print $1 }' )

  # strip away color escape sequences
  # the echo command expands "foo/bar-*.log" terms
  #
  for f in $(echo $ehist $failedlog $cflog $apout $cmlog $cmerr $sandb $oracl $envir $salso)
  do
    if [[ -f $f ]]; then
      stresc < $f > $issuedir/files/$(basename $f)
    fi
  done

  # compress files bigger than 1 MB
  #
  for f in $issuedir/files/*
  do
    c=$(wc -c < $f)
    if [[ $c -gt 1000000 ]]; then
      bzip2 $f
    fi
  done
  chmod a+r $issuedir/files/*

  # create an email body containing convenient links + info
  # ready for being picked up by copy+paste
  #
  cat << EOF >> $issuedir/emerge-info.txt
  -----------------------------------------------------------------

  This is an $(cat /tmp/MASK) amd64 chroot image (named $name) at a hardened host acting as a tinderbox.

  -----------------------------------------------------------------

  make.conf: USE="$(source /etc/portage/make.conf; echo $USE)"

  -----------------------------------------------------------------

EOF
emerge --info >> $issuedir/emerge-info.txt

  # get assignee and cc, GLEP 67 rules
  #
  m=$(equery meta -m $failed | grep '@' | xargs)
  if [[ -z "$m" ]]; then
    m="maintainer-needed@gentoo.org"
  fi

  # if we found more than 1 maintainer, then put the 1st into assignee and the other(s) into cc
  #
  echo "$m" | grep -q ' '
  if [[ $? -eq 0 ]]; then
    echo "$m" | cut -f1  -d ' ' > $issuedir/assignee
    echo "$m" | cut -f2- -d ' ' | tr ' ' ',' > $issuedir/cc
  else
    echo "$m" > $issuedir/assignee
    touch $issuedir/cc
  fi

  # try to find a descriptive title and the last meaningful lines of the issue
  #
  touch $issuedir/title

  if [[ -n "$(grep -m 1 ' Detected file collision(s):' $bak)" ]]; then
    # inform the maintainers of the already installed package too
    # sort -u guarantees, that $issuedir/cc is completely read in before it will be overwritten
    #
    s=$(grep -m 1 -A 2 'Press Ctrl-C to Stop' $bak | grep '::' | tr ':' ' ' | cut -f3 -d' ')
    cc=$(equery meta -m $s | grep '@' | grep -v "$(cat $issuedir/assignee)" | xargs)
    (cat $issuedir/cc; echo $cc) | tr ',' ' '| xargs -n 1 | sort -u | xargs | tr ' ' ',' > $issuedir/cc
    
    grep -m 1 -A 15 ' Detected file collision(s):' $bak > $issuedir/issue
    echo "file collision with $s"                       > $issuedir/title

  elif [[ -f $sandb ]]; then
    # handle sandbox issues in a special way
    #
    head -n 20 $sandb     > $issuedir/issue
    echo "sandbox issue"  > $issuedir/title

  else
    # we have do catch for the actual error
    # therefore we loop over all patterns exactly in their given order
    # therefore we can't use something like "grep -f CATCH_ISSUES" here
    #
    cat /tmp/tb/data/CATCH_ISSUES |\
    while read c
    do
      grep -m 1 -B 2 -A 3 "$c" $bak | cut -c1-400 > $issuedir/issue
      if [[ -s $issuedir/issue ]]; then
        grep -m 1 "$c" $issuedir/issue >> $issuedir/title
        break
      fi
    done
  fi

  if [[ ! -s $issuedir/issue || ! -s $issuedir/title ]]; then
    Mail "info: $failed: either no issue catched or title is empty" $bak
    return
  fi

  # shrink looong path names in title
  #
  sed -i -e 's#/[^ ]*\(/[^/:]*:\)#/...\1#g' $issuedir/title

  # limit the length of the title
  #
  len=$(wc -c < $issuedir/title)
  max=210
  if [[ $len -gt $max ]]; then
    truncate -s $max $issuedir/title
  fi

  chmod    777  $issuedir/{,files}
  chmod -R a+rw $issuedir/

  # guess from the title if there's a bug tracker for this
  # the BLOCKER file must follow this syntax:
  #
  #   # comment
  #   bug id
  #   pattern
  #   ...
  block=$(
    grep -v -e '^#' -e '^[1-9]*' /tmp/tb/data/BLOCKER |\
    while read line
    do
      grep -q "$line" $issuedir/title
      if [[ $? -eq 0 ]]; then
        grep -m 1 -B 1 "$line" /tmp/tb/data/BLOCKER | head -n 1 && break
      fi
    done
  )

  # fill the email body with log file info, a search link and a bgo.sh command line ready for copy+paste
  #
  short=$(qatom $failed | cut -f1-2 -d' ' | tr ' ' '/')
  cp $issuedir/issue $issuedir/body
  cat << EOF >> $issuedir/body


versions: $(eshowkw -a amd64 $short | grep -A 100 '^-' | grep -v '^-' | awk '{ if ($3 == "+") { print $1 } else { print $3$1 } }' | xargs)
assignee: $(cat $issuedir/assignee)
cc:       $(cat $issuedir/cc)

https://bugs.gentoo.org/buglist.cgi?query_format=advanced&resolution=---&short_desc=$short&short_desc_type=allwordssubstr

~/tb/bin/bgo.sh -d ~/images?/$name/$issuedir $block

EOF

  # FWIW: uuencode is not mime-compliant and although thunderbird is able to display such attachments
  # it cannot forward such a composed email: https://bugzilla.mozilla.org/show_bug.cgi?id=1178073
  #
  for f in $issuedir/emerge-info.txt $issuedir/files/* $bak
  do
    uuencode $f $(basename $f) >> $issuedir/body
  done
}


# process the issue
#
function GotAnIssue()  {
  # prefix our log backup file with an "_" to distinguish it from portage's log files
  #
  typeset bak=/var/log/portage/_emerge_$(date +%Y%m%d-%H%M%S).log
  stresc < $log > $bak

  # guess the actually failed package
  #
  failed=""
  line=$(tac /var/log/emerge.log | grep -m 1 -E ':  === |: Started emerge on: ')
  echo "$line" | grep -q ':  === ('
  if [[ $? -eq 0 ]]; then
    failed=$(echo "$line" | cut -f3 -d'(' | cut -f1 -d':')

    # put all already successfully emerged dependencies of $task into the world file
    # otherwise we'd need "--deep" (https://bugs.gentoo.org/show_bug.cgi?id=563482) unconditionally
    #
    echo "$line" | grep -q ':  === (1 of '
    if [[ $? -ne 0 ]]; then
      emerge --depclean --pretend 2>/dev/null | grep "^All selected packages: " | cut -f2- -d':' | xargs emerge --noreplace &>/dev/null
    fi
  else
    # alternatives :
    #[20:43] <_AxS_> toralf:   grep -l "If you need support, post the output of" /var/tmp/portage/*/*/temp/build.log   <-- that should work in all but maybe fetch failures.
    #[20:38] <kensington> something like itfailed() { echo "${PF} - $(date)" >> failed.log }  register_die_hook itfailed in /etc/portage/bashrc
    #
    failed="$(cd /var/tmp/portage; ls -1d */* 2>/dev/null)"
  fi

  # mostly OOM
  #
  fatal=$(grep -f /tmp/tb/data/FATAL_ISSUES $bak)
  if [[ -n "$fatal" ]]; then
    Finish "FATAL: $fatal"
  fi

  # the host repository is synced every 3 hours, that might interfere with a longer emerge operation
  # the final solution is a local repo, but no way as long as we just have 16 GB RAM at all
  #
  grep -q 'AssertionError: ebuild not found for' $bak
  if [[ $? -eq 0 ]]; then
    echo "$task" >> $pks    # try it again
    Mail "info: race of repository sync and local emerge" $bak  # mail to us to check that we're not in a loop
    return
  fi

  # inform us about @sets and %commands failures
  #
  if [[ "$task" = "@system" || "$task" = "@world" ]]; then
    Mail "info: $task failed" $bak

  elif [[ "$task" = "@preserved-rebuild" ]]; then
    # don't spam the inbox too often
    #
    diff=1000000
    if [[ -f /tmp/timestamp.preserved-rebuild ]]; then
      let "diff = $(date +%s) - $(date +%s -r /tmp/timestamp.preserved-rebuild)"
    fi
    if [[ $diff -gt 14400 ]]; then
      Mail "warn: $task failed" $bak
      touch /tmp/timestamp.preserved-rebuild
    fi

  elif [[ "$(echo $task | cut -c1)" = "%" ]]; then
    echo "$task" | grep -q "^%emerge -C"
    if [[ $? -eq 0 ]]; then
      return
    fi
    Mail "info: $task failed" $bak
  fi

  # missing or wrong USE flags, license, fetch restrictions et al
  # we do not mask those package b/c the root cause might be fixed/circumvent during the lifetime of the image
  #
  grep -q -f /tmp/tb/data/IGNORE_ISSUES $bak
  if [[ $? -eq 0 ]]; then
    return
  fi

  # after this point we expect that we catched the failed package (== $failed is not empty)
  #
  if [[ -z "$failed" ]]; then
    Mail "warn: \$failed is empty -> issue handling is not implemented for: $task"
    return
  fi

  # compile build/log files into $issuedir
  #
  issuedir=/tmp/issues/$(date +%Y%m%d-%H%M%S)_$(echo $failed | tr '/' '_')
  mkdir -p $issuedir/files
  CollectIssueFiles
  
  # broken Perl upgrade: https://bugs.gentoo.org/show_bug.cgi?id=463976
  #
  grep -q "Can't locate Locale/Messages.pm in @INC" $bak
  if [[ $? -eq 0 ]]; then
    Mail "info: handle perl upgrade issue" $issuedir/body
    echo -e "$task\n%perl-cleaner --all" >> $pks
    return
  fi

  # mask this package version at this image
  #
  grep -q "=$failed " /etc/portage/package.mask/self
  if [[ $? -ne 0 ]]; then
    echo "=$failed" >> /etc/portage/package.mask/self
  fi

  # don't mail the same issue again to us
  #
  fgrep -q -f $issuedir/title /tmp/tb/data/ALREADY_CATCHED
  if [[ $? -ne 0 ]]; then
    Mail "ISSUE: $(cat $issuedir/title)" $issuedir/body
    cat $issuedir/title >> /tmp/tb/data/ALREADY_CATCHED
  fi
}


# switch used jdk, usually once a day, triggered by a @system/@world update
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


# *compiled* kernel modules are needed by some packages
#
function BuildKernel()  {
  (
    cd /usr/src/linux     &&\
    make clean            &&\
    make defconfig        &&\
    make modules_prepare  &&\
    make                  &&\
    make modules_install  &&\
    make install
  ) &> $log
  rc=$?

  if [[ $rc -ne 0 ]]; then
    Finish "ERROR: $FUNCNAME failed (rc=$rc)"
  fi
}


# switch to a freshly installed GCC, see: https://wiki.gentoo.org/wiki/Upgrading_GCC
#
function SwitchGCC() {
  latest=$(gcc-config --list-profiles --nocolor | cut -f3 -d' ' | grep 'x86_64-pc-linux-gnu-.*[0-9]$' | tail -n 1)
  gcc-config --list-profiles --nocolor | grep -q "$latest \*$"
  if [[ $? -ne 0 ]]; then
    verold=$(gcc -v 2>&1 | tail -n 1 | cut -f1-3 -d' ')
    gcc-config --nocolor $latest &> $log
    . /etc/profile
    vernew=$(gcc -v 2>&1 | tail -n 1 | cut -f1-3 -d' ')

    subject="$FUNCNAME from $verold to $vernew"

    majold=$(echo $verold | cut -f3 -d ' ' | cut -c1)
    majnew=$(echo $vernew | cut -f3 -d ' ' | cut -c1)

    # schedule re-compiling of kernel object files against new gcc libs
    #
    if [[ -e /usr/src/linux ]]; then
      echo "%BuildKernel" >> $pks
    fi

    if [[ "$majold" = "4" && "$majnew" = "5" ]]; then
      rm -rf /var/cache/revdep-rebuild/*
      revdep-rebuild --library libstdc++.so.6 -- --exclude gcc &> $log
      if [[ $? -ne 0 ]]; then
        echo '%revdep-rebuild --library libstdc++.so.6 -- --exclude gcc' >> $pks
        GotAnIssue
        Finish "FAILED: $subject rebuild failed"   # bail out here to allow a resume
      fi
    fi
  fi
}


# eselect the latest kernel and build necessary
#
function SelectNewKernel() {
  if [[ ! -e /usr/src/linux ]]; then
    return # no sources emerged at this point
  fi

  last=$(ls -1d /usr/src/linux-* | tail -n 1 | cut -f4 -d'/')
  link=$(eselect kernel show | tail -n 1 | sed -e 's/ //g' | cut -f4 -d'/')
  if [[ "$last" != "$link" ]]; then
    eselect kernel set $last &> $log
    if [[ $? -ne 0 ]]; then
      Finish "cannot eselect kernel: last=$last link=$link"
    fi
  fi

  if [[ ! -f /usr/src/linux/.config ]]; then
    BuildKernel
  fi
}


# we do not run an emerge operation here
# but we'll schedule perl/python/haskell - updater if needed
# and we'll switch to a new GCC, kernel and so on
#
function PostEmerge() {
  typeset tmp

  # empty log ?!
  #
  if [[ ! -s $log ]]; then
    return
  fi

  tmp=/tmp/$FUNCNAME.log

  # $log will be overwritten by every call of emerge
  #
  cp $log $tmp

  # do not update these config files
  #
  rm -f /etc/ssmtp/._cfg????_ssmtp.conf
  rm -f /etc/portage/._cfg????_make.conf

  # errors go to nohup.out
  #
  etc-update --automode -5 2>&1 1>/dev/null
  env-update 2>&1 1>/dev/null
  . /etc/profile

  #
  # add cleanup/post-update actions in their reverse order
  #

  # new kernel
  #
  grep -q ">>> Installing .* sys-kernel/.*-sources" $tmp
  if [[ $? -eq 0 ]]; then
    SelectNewKernel
  fi

  # rebuild libs
  #
  grep -q "@preserved-rebuild" $tmp
  if [[ $? -eq 0 ]]; then
    if [[ "$task" = "@preserved-rebuild" ]]; then
      Finish "ERROR: endless-loop : $task"
    fi
    echo "@preserved-rebuild" >> $pks
  fi

  # haskell
  #
  grep -q -e "Please, run 'haskell-updater'" -e ">>> Installing .* dev-lang/ghc-[1-9]" -e "ghc-pkg check: 'checking for other broken packages:'" $tmp
  if [[ $? -eq 0 ]]; then
    echo "$task"            >> $pks
    echo "%haskell-updater" >> $pks
  fi

  # perl: https://bugs.gentoo.org/show_bug.cgi?id=41124  https://bugs.gentoo.org/show_bug.cgi?id=570460
  #
  grep -q 'Use: perl-cleaner' $tmp
  if [[ $? -eq 0 ]]; then
    echo "%perl-cleaner --force --libperl"  >> $pks
    echo "%perl-cleaner --modules"          >> $pks
  else
    grep -q '>>> Installing .* dev-lang/perl-[1-9]' $tmp
    if [[ $? -eq 0 ]]; then
      echo "%perl-cleaner --all" >> $pks
    fi
  fi

  # python
  #
  grep -q '>>> Installing .* dev-lang/python-[1-9]' $tmp
  if [[ $? -eq 0 ]]; then
    echo "%python-updater" >> $pks
  fi

  # GCC
  #
  grep -q ">>> Installing .* sys-devel/gcc-[1-9]" $tmp
  if [[ $? -eq 0 ]]; then
    SwitchGCC
  fi

  # PAX
  #
  grep -q 'Please run "revdep-pax" after installation.' $tmp
  if [[ $? -eq 0 ]]; then
    echo "%revdep-pax" >> $pks
  fi

  rm -f $tmp
}


# test hook, eg. to catch a package which wrongly installs directly in / or left files over in /tmp
#
function check() {
  exe=/tmp/tb/bin/PRE-CHECK.sh

  if [[ -x $exe ]]; then
    $exe &> $log
    rc=$?

    # -1 == 255:-2 == 254, ...
    #
    if [[ $rc -gt 127 ]]; then
      Finish "$exe returned $rc"

    elif [[ $rc -gt 0 ]]; then
      Mail "$exe : rc=$rc, task=$task" $log
    fi
  fi
}


# emerge $task here
#
function EmergeTask() {
  # handle prefix @ in a special way
  #
  if [[ "$(echo $task | cut -c1)" = '@' ]]; then

    if [[ "$task" = "@world" || "$task" = "@system" ]]; then
      opts="--deep --update --newuse --changed-use --with-bdeps=y"

    elif [[ "$task" = "@preserved-rebuild" ]]; then
      opts="--backtrack=60"

    else
      opts="--update"
    fi

    emerge $opts $task &> $log
    if [[ $? -ne 0 ]]; then
      GotAnIssue
      PostEmerge
      # resume as much as possible
      #
      while :;
      do
        emerge --resume --skipfirst &> $log
        if [[ $? -eq 0 ]]; then
          PostEmerge
          break
        else
          grep -q '* unsatisfied dependencies. Please restart/continue the operation' $log
          if [[ $? -eq 0 ]]; then
            break
          fi
          GotAnIssue
          PostEmerge
        fi
      done

    else
      # successful
      #
      if [[ "$task" = "@system" ]]; then
        # do few more daily tasks and try @world BUT only *after* all post-emerge actions
        #
        SwitchJDK
        /usr/bin/pfl &>/dev/null
        echo "@world" >> $pks
      elif [[ "$task" = "@world" ]] ;then
        touch /tmp/timestamp.world  # keep timestamp of the last successful @world update
        echo "%emerge --depclean" >> $pks
      fi
      PostEmerge
    fi

    # one attempt per day, regardless whether successful or not
    #
    if [[ "$task" = "@system" ]] ;then
      touch /tmp/timestamp.system
    fi

  else
    # % prefixes a complete command line
    #
    if [[ "$(echo $task | cut -c1)" = '%' ]]; then
      cmd=$(echo "$task" | cut -c2-)
    else
      cmd="emerge --update $task"
    fi

    $cmd &> $log
    if [[ $? -ne 0 ]]; then
      GotAnIssue
    fi
    PostEmerge
  fi
}


#############################################################################
#
#       main
#
mailto="tinderbox@zwiebeltoralf.de"

log=/tmp/task.log                           # holds always output of "emerge ... "
tsfile=/usr/portage/metadata/timestamp.chk
old=$(cat $tsfile 2>/dev/null)              # timestamp of the package repository
pks=/tmp/packages                           # the package list file, pre-filled at setup

# eg.: PORTAGE_ELOG_MAILFROM="amd64-gnome-unstable_20150913-104240 <tinderbox@zwiebeltoralf.de>"
#
name=$(grep "^PORTAGE_ELOG_MAILFROM=" /etc/portage/make.conf | cut -f2 -d '"' | cut -f1 -d ' ')

export GCC_COLORS="never"                   # suppress colour output of gcc-4.9 and above
export XDG_CACHE_HOME=/tmp/xdg              # https://bugs.gentoo.org/show_bug.cgi?id=567192

while :;
do
  # run this before we clean the /var/tmp/portage directory
  #
  check

  # pick up after ourself now, we can't use FEATURES=fail-clean
  # b/c that would delete files before we could pick them up for a bug report
  #
  rm -rf /var/tmp/portage/*
  date > $log

  # start an updated instance of ourself if we do differ from origin
  #
  diff -q /tmp/tb/bin/job.sh /tmp/job.sh 1>/dev/null
  if [[ $? -ne 0 ]]; then
    exit 125
  fi

  GetNextTask
  
  if [[ -f /tmp/STOP  ]]; then
    echo "$task" >> $pks  # push it back on top of the list
    Finish "stopped"
  fi
  
  EmergeTask

done

Finish "we should never reach this line"

# barrier end (see start of this file too)
#
)
