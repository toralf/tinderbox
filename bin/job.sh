#!/bin/sh
#
# set -x

# this is the tinderbox script - it runs within the chroot image for few weeks
#

# barrier start
# this prevents us to run a broken copy of ourself - see end of file too
#
(

# strip colour ESC sequences
#
function stresc() {
  # https://bugs.gentoo.org/show_bug.cgi?id=564998#c6
  #
  perl -MTerm::ANSIColor=colorstrip -nle 'print colorstrip($_)'
}

# send out an email with $1 as the subject and $2 - if given - as the body
#
function Mail() {
  typeset subject=$(echo "$1" | cut -c1-200)

  (
    if [[ -s $2 ]]; then
      stresc < $2
    else
      date
    fi
  ) | mail -s "$subject    @ $name" $mailto &> /tmp/mail.log
  rc=$?

  if [[ $rc -ne 0 || -s /tmp/mail.log ]]; then
    # this should land in nohup.out too usually
    #
    echo " rc=$rc , $(cat /tmp/mail.log) , happened in $name at $(date) for subject '$subject'"
  fi
}

# clean up and exit
#
function Finish()  {
  /usr/bin/pfl >/dev/null
  Mail "FINISHED: $*" $log

  exit 0
}

# set $task to the last line of the package list file $pks
# return 1 if the package list is empty, 0 otherwise
#
function GetNextTask() {
  # update @system immediately after setup
  #
  if [[ ! -f /tmp/timestamp.system ]]; then
    touch /tmp/timestamp.system
    task="@system"
    return 0
  fi

  # update @system once a day if no special task is scheduled
  #
  grep -q -e "^STOP" -e "^INFO" -e "^%" -e "^@" $pks
  if [[ $? -ne 0 ]]; then
    let diff=$(date +%s)-$(date +%s -r /tmp/timestamp.system)
    if [[ $diff -gt 86400 ]]; then
      task="@system"
      echo "@world" >> $pks # give it a chance
      return 0
    fi
  fi

  while :;
  do
    # splice last line from package list and put it into $task
    #
    task=$(tail -n 1 $pks)
    sed -i -e '$d' $pks

    if [[ -n "$(echo $task | grep '^INFO')" ]]; then
      Mail "$task"

    elif [[ -n "$(echo $task | grep '^STOP')" ]]; then
      Finish "$task"

    elif  [[ -z "$task" ]]; then # an empty line happens sometimes
      if [[ ! -s $pks ]]; then
        return 1  # package list is empty, we reached end of lifetime of this image
      fi

    elif [[ "$(echo $task | cut -c1)" = '%' ]]; then
      return 0  # a complete command line

    elif [[ "$(echo $task | cut -c1)" = '@' ]]; then
      return 0  # a package set

    else
      echo "$task" | grep -q -f /tmp/tb/data/IGNORE_PACKAGES
      if [[ $? -eq 0 ]]; then
        continue
      fi

      # no result set: $task can't be emerged at all
      #
      if [[ -z "$(portageq $task 2>/dev/null)" ]]; then
        continue
      fi

      # we are not interested in downgrading an installed $task
      #
      typeset installed=$(qlist -ICv $task | tail -n 1)
      if [[ -n "$installed" ]]; then
        typeset best_visible=$(portageq best_visible / $task)
        if [[ -n "$best_visible" ]]; then
          qatom --compare $installed $best_visible | grep -q '<'
          if [[ $? -ne 0 ]]; then
            continue  # "installed" package version is NOT lower then "best_visible" package version
          fi
        fi
      fi

      # emerge $task
      #
      return 0
    fi
  done
}


# check an issue, prepare files for bgo.sh
#
function GotAnIssue()  {
  # prefix our log backup file with an "_" to distinguish it from portage's log files
  #
  typeset bak=/var/log/portage/_emerge_$(date +%Y%m%d-%H%M%S).log
  stresc < $log > $bak

  fatal=$(grep -f /tmp/tb/data/FATAL_ISSUES $bak)
  if [[ $? -eq 0 ]]; then
    Finish "FATAL $fatal"
  fi

  # @system should be update-able, @world however is expected to fail
  #
  if [[ "$task" = "@system" ]]; then
    Mail "info: $task failed" $bak
  fi

  grep -q -f /tmp/tb/data/IGNORE_ISSUES $bak
  if [[ $? -eq 0 ]]; then
    return
  fi

  # $curr holds the failed <category / package name - package version>
  #
  line=$(tail -n 10 /var/log/emerge.log | tac | grep -m 1 -e ':  === (' -e ': Started emerge on:')
  echo "$line" | grep -q ':  === ('
  if [[ $? -ne 0 ]]; then
    Mail "TODO: emerge did not even start" $bak
    return
  fi
  curr=$(echo "$line" | cut -f3 -d'(' | cut -f1 -d':')

  if [[ -z "$curr" ]]; then
    Finish "ERROR: \$curr must not be empty: task=$task"
  fi

  # keep all successfully emerged dependencies of $curr in world file
  # otherwise we'd need "--deep" (https://bugs.gentoo.org/show_bug.cgi?id=563482) unconditionally
  #
  tail -n 10 /var/log/emerge.log | tac | grep -m 1 -e ':  === (' | grep -q ':  === (1 of .*) '
  if [[ $? -ne 0 ]]; then
    emerge --depclean --pretend 2>/dev/null | grep "^All selected packages: " | cut -f2- -d':' | xargs emerge --noreplace &>/dev/null
  fi

  # broken Perl upgrade: https://bugs.gentoo.org/show_bug.cgi?id=463976
  #
  if [[ "$task" = "@system" || "$task" = "@world" ]]; then
    grep -q "Can't locate Locale/Messages.pm in @INC" $bak
    rc=$?
    if [[ "$curr" = "sys-apps/help2man" || "$curr" = "dev-scheme/guile" || $rc -eq 0 ]]; then
      Mail "info: auto-repair perl upgrade issue" $bak
      echo -e "$task\n%perl-cleaner --all" >> $pks
      return
    fi
  fi

  # append a trailing space eg.: to distinguish between "webkit-gtk-2.4.9" and "webkit-gtk-2.4.9-r200"
  #
  line="=$(echo $curr | awk ' { printf("%-50s ", $1) } ')# $(date) $name"

  # mask this package version for this image, prefer to continue with a lower version
  # TODO: do not report bugs for older versions
  #
  grep -q "=$curr " /etc/portage/package.mask/self
  if [[ $? -ne 0 ]]; then
    echo "$line" >> /etc/portage/package.mask/self
  fi

  # skip, if this package *version* failed already before (regardless of the issue)
  #
  grep -q "=$curr " /tmp/tb/data/ALREADY_CATCHED
  if [[ $? -eq 0 ]]; then
    return
  fi
  echo "$line" >> /tmp/tb/data/ALREADY_CATCHED

  # ---------------------------
  # prepare the issue mail
  # ---------------------------

  issuedir=/tmp/issues/$(date +%Y%m%d-%H%M%S)_$(echo $curr | tr '/' '_')
  mkdir -p $issuedir/files

  ehist=/var/tmp/portage/emerge-history.txt
  (echo "# This file contains the emerge history"; echo "#"; qlop --nocolor --gauge --human --list --unlist) > $ehist

  # the log file name of the actually failed package
  #
  currlog=$(grep -m 1 "The complete build log is located at" $bak | cut -f2 -d"'")
  if [[ -z "$currlog" ]]; then
    currlog=$(grep -m1 -A 1 "', Log file:" $bak | tail -n 1 | cut -f2 -d"'")
    if [[ -z "$currlog" ]]; then
      currlog=$(ls -1t /var/log/portage/$(echo "$curr" | tr '/' ':'):????????-??????.log 2>/dev/null | head -n 1)
    fi
  fi

  # collect build log files
  #
  cflog=$(grep -m1 -A 2 'Please attach the following file when seeking support:'    $bak | grep "config\.log"     | cut -f2 -d' ')
  apout=$(grep -m1 -A 2 'Include in your bugreport the contents of'                 $bak | grep "\.out"           | cut -f5 -d' ')
  cmlog=$(grep -m1 -A 2 'Configuring incomplete, errors occurred'                   $bak | grep "CMake.*\.log"    | cut -f2 -d'"')
  cmerr=$(grep -m1      'CMake Error: Parse error in cache file'                    $bak | sed  "s/txt./txt/"     | cut -f8 -d' ')
  sandb=$(grep -m1 -A 1 'ACCESS VIOLATION SUMMARY'                                  $bak | grep "sandbox.*\.log"  | cut -f2 -d'"')
  oracl=$(grep -m1 -A 1 '# An error report file with more information is saved as:' $bak | grep "\.log"           | cut -f2 -d' ')
  envir=$(grep -m1      'The ebuild environment file is located at'                 $bak                          | cut -f2 -d"'")
  salso=$(grep -m1 -A 2 ' See also'                                                 $bak | grep "\.log"           | awk '{ print $1 }' )

  # the echo command expands "foo/bar-*.log" terms
  #
  for f in $(echo $ehist $currlog $cflog $apout $cmlog $cmerr $sandb $oracl $envir $salso)
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

  # get assignee and cc, GLEP 67 rules currently
  #
  m=$(equery --no-color meta -m $curr 2>/dev/null | grep '@' | xargs)
  if [[ -z "$m" ]]; then
    m="maintainer-needed@gentoo.org"
  fi
  echo "$m" | cut -f1 -d ' ' > $issuedir/assignee

  echo "$m" | grep -q ' '
  if [[ $? -eq 0 ]]; then
    echo "$m" | cut -f2- -d ' ' | tr ' ' ',' > $issuedir/cc
  else
    touch $issuedir/cc
  fi

  # try to find a descriptive title and the last meaningful lines of the issue
  #
  touch $issuedir/title

  if [[ -n "$(grep -m1 ' Detected file collision(s):' $bak)" ]]; then
    s=$(grep -m1 -A 2 'Press Ctrl-C to Stop' $bak | grep '::' | tr ':' ' ' | cut -f3 -d' ')
    cc=$(equery --no-color meta -m $s 2>/dev/null | grep '@' | grep -v "$(cat $issuedir/assignee)" | xargs)
    all=$( (cat $issuedir/cc; echo $cc) | tr ',' ' '| xargs -n 1 | sort -u | xargs | tr ' ' ',')
    echo "$all" > $issuedir/cc

    echo "file collision with $s" >> $issuedir/title
    grep -m 1 -A 15 ' Detected file collision(s):' $bak > $issuedir/issue

  else
    # we do loop over all patterns exactly in the written order
    # therefore do not use something like "grep -f CATCH_ISSUES" here !
    #
    cat /tmp/tb/data/CATCH_ISSUES |\
    while read c
    do
      grep -m 1 -B 2 -A 3 "$c" $bak > $issuedir/issue
      if [[ $? -eq 0 ]]; then
        grep -m 1 "$c" $issuedir/issue >> $issuedir/title
        break
      fi
    done

    # if we didn't catched a known issue (class)
    # then just take the last (hopefully meaningful) lines
    #
    if [[ ! -s $issuedir/issue ]]; then
      (
        maxLines=65
        maxChars=7000
        if [[ $(tail -n $maxLines $currlog | wc -c) -gt $maxChars ]]; then
          tail -c $maxChars $currlog
        else
          tail -n $maxLines $currlog
        fi
      ) > $issuedir/issue
    fi
  fi

  len=$(wc -c < $issuedir/title)
  max=210
  if [[ $len -gt $max ]]; then
    truncate -s $max $issuedir/title
  fi

  # handle sandbox issues in a special way
  #
  if [[ -f $sandb ]]; then
    head -n 30 $sandb > $issuedir/issue
    sed -i -e "s/.* ACCESS VIOLATION SUMMARY .*/ sandbox issue/" $issuedir/title
  fi

  # shrink looong path names in title
  #
  sed -i -e 's#/[^ ]*\(/[^/:]*:\)#/...\1#g' $issuedir/title

  echo "$curr : $(cat $issuedir/title)" > $issuedir/title
  chmod    777  $issuedir/{,files}
  chmod -R a+rw $issuedir/

  # FWIW: uuencode is not mime-compliant and although thunderbird is able to display such attachments
  # it cannot forward such a composed email: https://bugzilla.mozilla.org/show_bug.cgi?id=1178073
  #
  currShort=$(qatom $curr | cut -f1-2 -d' ' | tr ' ' '/')

  # so much fallout from the glibc-2.23 breakage - worth to automate it
  #
  block=""
  grep -q -e "minor" -e "major" -e "makedev" $issuedir/title
  if [[ $? -eq 0 ]]; then
    block="-b 575232"
    mv $issuedir/issue $issuedir/issue.tmp
    echo -e "This bug report feeds bug #575232 (sys-libs/glibc-2.23.r1 breakage).\n\n" > $issuedir/issue
    cat $issuedir/issue.tmp >> $issuedir/issue
    rm $issuedir/issue.tmp
  fi

  # now create the email body for us
  # containing convenient info, prepared bugz calls and html links
  #
  cp $issuedir/issue $issuedir/body
  cat << EOF >> $issuedir/body

versions: $(ls /usr/portage/$currShort/*.ebuild | xargs qatom | cut -f3- -d' ' | sed 's/ *$//g' | tr " " "-" | sort --numeric | xargs)
assignee: $(cat $issuedir/assignee)
cc:       $(cat $issuedir/cc)
https://bugs.gentoo.org/buglist.cgi?query_format=advanced&resolution=---&short_desc=$currShort&short_desc_type=allwordssubstr

~/tb/bin/bgo.sh -d ~/$name/$issuedir $block

EOF

  # send to us $bak too, at bugz we do only attach the package specific log file
  #
  for f in $issuedir/emerge-info.txt $issuedir/files/* $bak
  do
    uuencode $f $(basename $f) >> $issuedir/body
  done

  Mail "ISSUE: $(cat $issuedir/title)" $issuedir/body
}


# switch java, usually once a day, triggered during a @system/@world update
#
function SwitchJDK()  {
  old=$(eselect java-vm show system 2>/dev/null | tail -n 1 | xargs)
  if [[ -n "$old" ]]; then
    new=$(eselect java-vm list 2>/dev/null | grep -e 'oracle-jdk-1.8' -e 'icedtea-7' -e 'icedtea-bin-7' | grep -v 'system-vm' | awk ' { print $2 } ' | sort --random-sort | head -n 1)
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


# compiled kernel sources are needed by few packages
#
function BuildKernel()  {
  if [[ ! -e /usr/src/linux ]]; then
    return
  fi

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


# switch to the freshly installed gcc, see: https://wiki.gentoo.org/wiki/Upgrading_GCC
#
function SwitchGCC() {
  latest=$(gcc-config --list-profiles --nocolor | cut -f3 -d' ' | grep -e 'x86_64-pc-linux-gnu-.*[0-9]$' | tail -n 1)
  gcc-config --list-profiles --nocolor | grep -q "$latest \*$"
  if [[ $? -ne 0 ]]; then
    verold=$(gcc -v 2>&1 | tail -n 1 | cut -f1-3 -d' ')
    gcc-config --nocolor $latest &> $log
    . /etc/profile
    vernew=$(gcc -v 2>&1 | tail -n 1 | cut -f1-3 -d' ')

    subject="$FUNCNAME from $verold to $vernew"

    majold=$(echo $verold | cut -f3 -d ' ' | cut -c1)
    majnew=$(echo $vernew | cut -f3 -d ' ' | cut -c1)

    # schedule rebuilding of object files against new gcc libs
    #
    echo "%BuildKernel" >> $pks

    if [[ "$majold" = "4" && "$majnew" = "5" ]]; then
      rm -rf /var/cache/revdep-rebuild/*
      revdep-rebuild --library libstdc++.so.6 -- --exclude gcc &> $log
      if [[ $? -ne 0 ]]; then
        GotAnIssue
        Finish "FAILED: $subject rebuild failed"   # bail out here to allow a resume
      fi
    fi
  fi
}


# eselect the latest kernel and build it if not yet done
#
function BuildNewKernel() {
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
# but we'll schedule tasks (perl, python, haskell updater) if needed
# and we'll switch a GCC, build the kernel and so on
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

  # these errors go to nohup.out
  #
  etc-update --automode -5 2>&1 1>/dev/null
  env-update 2>&1 1>/dev/null
  . /etc/profile

  #
  # add cleanup/post-update actions in reverse order to the package list
  #

  # no more than 4x @preserved-rebuild per day
  # a systematic failure would otherwise waste CPU cycles here
  #
  grep -q "@preserved-rebuild" $tmp
  if [[ $? -eq 0 ]]; then
    if [[ ! -f /tmp/timestamp.preserved-rebuild ]]; then
      echo "@preserved-rebuild" >> $pks
    else
      let diff=$(date +%s)-$(date +%s -r /tmp/timestamp.preserved-rebuild)
      if [[ $diff -gt 21200 ]]; then
        echo "@preserved-rebuild" >> $pks
      fi
    fi
  fi

  # haskell
  #
  grep -q -e "run 'haskell-updater'" -e ">>> Installing .* dev-lang/ghc-[1-9]" -e "ghc-pkg check: 'checking for other broken packages:'" $tmp
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

  # PAX
  #
  grep -q 'Please run "revdep-pax" after installation.' $tmp
  if [[ $? -eq 0 ]]; then
    echo "%revdep-pax" >> $pks
  fi

  # gcc
  #
  grep -q ">>> Installing .* sys-devel/gcc-[1-9]" $tmp
  if [[ $? -eq 0 ]]; then
    SwitchGCC
  fi

  # linux sources
  #
  grep -q ">>> Installing .* sys-kernel/" $tmp
  if [[ $? -eq 0 ]]; then
    BuildNewKernel
  fi

  rm -f $tmp
}


# test hook, eg. to catch a package which installs in root / or left files over in /tmp
#
function check() {
  exe=/tmp/tb/bin/PRE-CHECK.sh

  if [[ -x $exe ]]; then
    $exe &> $log
    rc=$?

    equery meta -m $task 1>> $log 2>/dev/null  # failes for @... and %... tasks usually

    # -1 == 255:-2 == 254, ...
    #
    if [[ $rc -gt 127 ]]; then
      Finish "$exe returned $rc"

    elif [[ $rc -gt 0 ]]; then
      Mail "$exe : rc=$rc, task=$task" $log
    fi
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

# eg.; PORTAGE_ELOG_MAILFROM="amd64-gnome-unstable_20150913-104240 <tinderbox@zwiebeltoralf.de>"
#
name=$(grep "^PORTAGE_ELOG_MAILFROM=" /etc/portage/make.conf | cut -f2 -d '"' | cut -f1 -d ' ')

export GCC_COLORS=""                        # suppress colour output of gcc-4.9 and above
export XDG_CACHE_HOME=/tmp/xdg              # https://bugs.gentoo.org/show_bug.cgi?id=567192

# sometimes an update was made outside of this script
# (eg. during setup of a systemd base dimage)
#
SwitchGCC

while :;
do
  # run this before we clean the /var/tmp/portage directory
  #
  check

  # pick up after ourself now, we can't use FEATURES=fail-clean
  # b/c that would delete files before we could pick them up for a bug report
  #
  rm -rf /var/tmp/portage/*
  truncate -s 0 $log

  # start an updated instance of ourself if we do differ from origin
  #
  diff -q /tmp/tb/bin/job.sh /tmp/job.sh 1>/dev/null
  if [[ $? -ne 0 ]]; then
    exit 125
  fi

  # after a sync of the host repository "read" news and update layman
  #
  now=$(cat $tsfile 2>/dev/null)
  if [[ -z "$now" ]]; then
    Finish "$tsfile not found or empty"
  fi
  if [[ ! "$old" = "$now" ]]; then
    eselect news read >/dev/null
    if [[ -x /usr/bin/layman ]]; then
      layman -S &>/dev/null
    fi
    old="$now"
  fi

  GetNextTask
  if [[ $? -ne 0 ]]; then
    break
  fi

  # fire up emerge, handle 2 special prefixes:
  # @ = a package setup
  # % = a command line
  #   = a common package
  #
  if [[ "$(echo $task | cut -c1)" = '@' ]]; then

    if [[ "$task" = "@world" || "$task" = "@system" ]]; then
      opts="--deep --update --newuse --changed-use --with-bdeps=y"
      SwitchJDK
    elif [[ "$task" = "@preserved-rebuild" ]]; then
      opts="--backtrack=30"
    else
      opts="--update"
    fi

    emerge $opts $task &> $log
    if [[ $? -ne 0 ]]; then
      GotAnIssue
      PostEmerge
      # re-try as much as possible
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
      PostEmerge
    fi

    if [[ "$task" = "@world" || "$task" = "@system" ]]; then
      touch /tmp/timestamp.system
      /usr/bin/pfl >/dev/null     # don't do this only in Finish() b/c packages might be removed in the mean while

    elif [[ "$task" = "@preserved-rebuild" ]]; then
      touch /tmp/timestamp.preserved-rebuild
    fi

  elif [[ "$(echo $task | cut -c1)" = '%' ]]; then
    cmd=$(echo "$task" | cut -c2-)
    $cmd &> $log
    if [[ $? -ne 0 ]]; then
      #  if $cmd isn't an emerge operation then we will bail out if $curr is empty
      #
      GotAnIssue
    fi
    PostEmerge

  else
    emerge --update $task &> $log
    if [[ $? -ne 0 ]]; then
      GotAnIssue
    fi
    PostEmerge
  fi

done

# just count the amount of installed packages
#
n=$(qlist --installed --nocolor | wc -l)
date > $log
Finish "$n packages emerged"

# barrier end (see start of this file too)
#
)
