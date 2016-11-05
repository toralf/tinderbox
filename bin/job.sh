# #!/bin/sh
#
# set -x

# this is the tinderbox script itself
# main function: EmergeTask()
# the remaining code just parses the output, that's all

# barrier start
# this prevents the start of a broken copy of ourself - see end of file too
#
(

# strip away escape sequences
#
function stresc() {
  perl -MTerm::ANSIColor=colorstrip -nle '$_ = colorstrip($_); s/\e\[K//g; s/\e\[\[//g; s/\r/\n/g; print'
}


# send out an email with $1 as the subject and $2 as the body
#
function Mail() {
  subject=$(echo "$1" | cut -c1-200 | tr '\n' ' ' | stresc)
  ( [[ -e $2 ]] && stresc < $2 || echo "<no body>" ) | mail -s "$subject    @ $name" $mailto &>> /tmp/mail.log
}


# clean up and exit
#
function Finish()  {
  Mail "FINISHED: $*" $log

  eix-update -q
  rm -f /tmp/STOP

  exit 0
}


# arbitraily choose a java engine
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


# for a package do evaluate here if it is worth to call emerge
#
function GetNextTask() {
  #   update @system once a day, if no special task is scheduled
  #
  ts=/tmp/timestamp.system
  if [[ ! -f $ts ]]; then
    touch $ts
  else
    let "diff = $(date +%s) - $(date +%s -r $ts)"
    if [[ $diff -gt 86400 ]]; then
      grep -q -E "^(STOP|INFO|%|@)" $pks
      if [[ $? -ne 0 ]]; then
        task="@system"
        SwitchJDK
        return
      fi
    fi
  fi

  # splice last line of the package list $pks into $task
  #
  while :;
  do
    task=$(tail -n 1 $pks)
    sed -i -e '$d' $pks

    if [[ -n "$(echo "$task" | grep '^INFO')" ]]; then
      Mail "$task"

    elif [[ -n "$(echo "$task" | grep '^STOP')" ]]; then
      Finish "$task"

    elif  [[ -z "$task" ]]; then
      if [[ -s $pks ]]; then
        continue  # package list itself isn't empty, just this line
      fi

      # package list is empty
      #
      /usr/bin/pfl &>/dev/null
      n=$(qlist --installed | wc -l)
      Finish "$n packages emerged, spin up a new one"

    elif [[ "$(echo "$task" | cut -c1)" = '%' ]]; then
      return  # a complete command line

    elif [[ "$(echo "$task" | cut -c1)" = '@' ]]; then
      return  # a package set

    elif [[ "$(echo "$task" | cut -c1)" = '#' ]]; then
      continue  # just a comment line

    else
      # ignore known trouble makers
      #
      echo "$task" | grep -q -f /tmp/tb/data/IGNORE_PACKAGES
      if [[ $? -eq 0 ]]; then
        continue
      fi

      # make some pre-checks here
      # emerge takes too much time before it gives up

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


# gather together what we do need for a bugzilla report
#
function CollectIssueFiles() {
  ehist=/var/tmp/portage/emerge-history.txt
  cmd="qlop --nocolor --gauge --human --list --unlist"

  echo "# This file contains the emerge history got with:" > $ehist
  echo "# $cmd" >> $ehist
  echo "#"      >> $ehist
  $cmd          >> $ehist

  # misc build logs
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

  # strip away escape sequences, echo is used to expand those variables containing place holders
  #
  for f in $(echo $ehist $failedlog $cflog $apout $cmlog $cmerr $sandb $oracl $envir $salso)
  do
    if [[ -f $f ]]; then
      stresc < $f > $issuedir/files/$(basename $f)
    fi
  done

  cp $bak $issuedir

  # compress files bigger than 1 MiByte
  #
  for f in $issuedir/files/* $issuedir/_*
  do
    c=$(wc -c < $f)
    if [[ $c -gt 1000000 ]]; then
      bzip2 $f
    fi
  done
  chmod a+r $issuedir/files/*
}


# create an email containing convenient links + info ready for being picked up by copy+paste
#
function CompileInfoMail() {
  keyword="stable"
  grep -q '^ACCEPT_KEYWORDS=.*~amd64' /etc/portage/make.conf
  if [[ $? -eq 0 ]]; then
    keyword="unstable"
  fi

  cat << EOF >> $issuedir/emerge-info.txt
  -----------------------------------------------------------------

  This is an $keyword amd64 chroot image (named $name) at a hardened host acting as a tinderbox.

  -----------------------------------------------------------------
  USE flags ...

  ... in make.conf:
USE="$(source /etc/portage/make.conf; echo -n '  '; echo $USE)"

  ... in /etc/portage/package.use/*:
$(grep -v -e '^#' -e '^$' /etc/portage/package.use/* | cut -f2- -d':' | sed 's/^/  /g')

  entries in /etc/portage/package.unmask/*:
$(grep -v -e '^#' -e '^$' /etc/portage/package.unmask/* | cut -f2- -d':' | sed 's/^/  /g')
  -----------------------------------------------------------------

gcc-config -l:
$(gcc-config -l 2>&1                && echo)
llvm-config --version:
$(llvm-config --version 2>&1        && echo)
$(eselect java-vm list 2>/dev/null  && echo)
$(eselect python  list 2>&1         && echo)
$(eselect ruby    list 2>/dev/null  && echo)
java-config:
$(java-config --list-available-vms --nocolor 2>/dev/null  && echo)
  -----------------------------------------------------------------

EOF

  short=$(qatom $failed | cut -f1-2 -d' ' | tr ' ' '/')

  # no --verbose, output size would exceed the 16 KB limit of b.g.o.
  #
  emerge --info --verbose=n $short >> $issuedir/emerge-info.txt

  # get bug report assignee and cc, GLEP 67 rules
  #
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

  # try to find a descriptive title and the most meaningful lines of the issue
  #
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
    retry_with_changed_env=1

    p="$(grep -m1 ^A: $sandb)"
    echo "$p" | grep -q "A: /root/"
    if [[ $? -eq 0 ]]; then
      # handle XDG sandbox issues in a special way
      #
      cat <<EOF > $issuedir/issue
This issue is forced at the tinderbox by making:

$(grep '^export XDG_' /tmp/job.sh)

pls see bug #567192 too

EOF
      echo "sandbox issue (XDG_xxx_DIR related)" > $issuedir/title
    else
      # other sandbox issues
      #
      echo "sandbox issue $p" > $issuedir/title
    fi
    head -n 20 $sandb >> $issuedir/issue

  else
    # to catch the real culprit loop over all patterns exactly in their defined order
    # therefore "grep -f CATCH_ISSUES" won't work
    #
    cat /tmp/tb/data/CATCH_ISSUES |\
    while read c
    do
      grep -m 1 -B 2 -A 3 "$c" $bak > $issuedir/issue
      if [[ -s $issuedir/issue ]]; then
        head -n 3 < $issuedir/issue | tail -n 1 > $issuedir/title
        break
      fi
    done

    # this gcc-6 issue is forced by us, masking this package
    # would prevent tinderboxing of a lot of affected deps
    # therefore rebuild this package with default CXX flags
    #
    grep -q '\[\-Werror=terminate\]' $issuedir/title
    if [[ $? -eq 0 ]]; then
      echo "=$failed cxx" >> /etc/portage/package.env/cxx
      retry_with_changed_env=1
    fi
  fi

  # shrink too long error messages
  #
  sed -i -e 's#/[^ ]*\(/[^/:]*:\)#/...\1#g' $issuedir/title

  # kick off hex addresses and such stuff to improve search results matching in b.g.o.
  #
  sed -i -e 's/0x[0-9a-f]*/<snip>/g' -e 's/: line [0-9]*:/:line <snip>:/g' $issuedir/title

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

  # the email contains:
  # - the issue, package version and maintainer
  # - a bgo.sh command line ready for copy+paste
  # - bugzilla search result/s
  #
  cp $issuedir/issue $issuedir/body

  cat << EOF >> $issuedir/body

--
versions: $(eshowkw -a amd64 $short | grep -A 100 '^-' | grep -v '^-' | awk '{ if ($3 == "+") { print $1 } else { print $3$1 } }' | xargs)
assignee: $(cat $issuedir/assignee)
cc:       $(cat $issuedir/cc)
--

EOF

  # search if this $issue was already filed, if not then return a list of matching records
  #
  search_string=$(cut -f3- -d' ' $issuedir/title | sed "s/['‘’\"]/ /g")

  # handle file collision case: remove the package version from the counterpart
  #
  grep -q "file collision" $issuedir/title
  if [[ $? -eq 0 ]]; then
    search_string=$(echo "$search_string" | sed -e 's/\-[0-9\-r\.]*$//g')
  fi

  # get the newest bug number
  #
  id=$(bugz -q --columns 400 search --status OPEN,RESOLVED --show-status $short "$search_string" | tail -n 1 | grep '^[[:digit:]]* ' | tee -a $issuedir/body | cut -f1 -d ' ')

  if [[ -n "$id" ]]; then
    cat << EOF >> $issuedir/body
  https://bugs.gentoo.org/show_bug.cgi?id=$id

  ~/tb/bin/bgo.sh -d $name/$issuedir -a $id

EOF
  else
    echo -e "  ~/tb/bin/bgo.sh -d $name/$issuedir $block\n" >> $issuedir/body

    h="https://bugs.gentoo.org/buglist.cgi?query_format=advanced&short_desc_type=allwordssubstr"
    g="stabilize|Bump| keyword| bump"

    echo "  OPEN:     $h&resolution=---&short_desc=$short"      >> $issuedir/body
    bugz --columns 400 -q search --show-status      $short 2>&1 | grep -v -i -E "$g" | tail -n 20 | tac >> $issuedir/body

    echo "" >> $issuedir/body
    echo "  RESOLVED: $h&bug_status=RESOLVED&short_desc=$short" >> $issuedir/body
    bugz --columns 400 -q search --status RESOLVED  $short 2>&1 | grep -v -i -E "$g" | tail -n 20 | tac >> $issuedir/body
  fi

  for f in $issuedir/emerge-info.txt $issuedir/files/* $issuedir/_*
  do
    uuencode $f $(basename $f) >> $issuedir/body
  done

  # prefix it with package name + version
  #
  sed -i -e "s#^#$failed : #" $issuedir/title

  # b.g.o. limits "Summary" to 255 chars
  #
  if [[ $(wc -c < $issuedir/title) -gt 255 ]]; then
    truncate -s 255 $issuedir/title
  fi

  chmod    777  $issuedir/{,files}
  chmod -R a+rw $issuedir/
}


# emerge failed for some reason, parse the output
# return 1 if a Perl Upgrade issue appears, b/c in this case no resume should be made
#
function GotAnIssue()  {
  # prefix our log backup file with an "_" to distinguish it from portage's log files
  #
  bak=/var/log/portage/_emerge_$(date +%Y%m%d-%H%M%S).log
  stresc < $log > $bak

  # put all successfully emerged dependencies of $task into the world file
  # otherwise we'd need "--deep" (https://bugs.gentoo.org/show_bug.cgi?id=563482)
  #
  line=$(tac /var/log/emerge.log | grep -m 1 -E ':  === |: Started emerge on: ')
  echo "$line" | grep -q ':  === ('
  if [[ $? -eq 0 ]]; then
    echo "$line" | grep -q ':  === (1 of '
    if [[ $? -ne 0 ]]; then
      emerge --depclean --pretend --verbose=n 2>/dev/null | grep "^All selected packages: " | cut -f2- -d':' | xargs emerge --noreplace &>/dev/null
    fi
  fi

  # bail out if an OOM happened or gcc upgrade failed
  #
  fatal=$(grep -f /tmp/tb/data/FATAL_ISSUES $bak)
  if [[ -n "$fatal" ]]; then
    Finish "FATAL: $fatal"
  fi

  # our current shared repository solution is (although rarely) racy
  #
  grep -q -e 'AssertionError: ebuild not found for' -e 'portage.exception.FileNotFound:' $bak
  if [[ $? -eq 0 ]]; then
    Mail "notice: race of host repository sync and running emerge" $bak
    echo "$task" >> $pks
    return
  fi

  # just ignore few issues and do not mask affected packages
  #
  grep -q -f /tmp/tb/data/IGNORE_ISSUES $bak
  if [[ $? -eq 0 ]]; then
    return
  fi

  # guess the failed package name from its log file name
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
    # try the opposite way: guess the log file name from the package name
    #
    if [[ -z "$failedlog" ]]; then
      failedlog=$(ls -1t /var/log/portage/$(echo "$failed" | tr '/' ':'):????????-??????.log 2>/dev/null | head -n 1)
    fi
  fi

  # after this point we expect to have a failed package name
  #
  if [[ -z "$failed" ]]; then
    Mail "warn: \$failed is empty for task: $task" $bak
    return
  fi

  # collect all related files in $issuedir
  #
  issuedir=/tmp/issues/$(date +%Y%m%d-%H%M%S)_$(echo $failed | tr '/' '_')
  mkdir -p $issuedir/files

  retry_with_changed_env=0
  CollectIssueFiles
  CompileInfoMail

  # handle the Perl upgrade issue: https://bugs.gentoo.org/show_bug.cgi?id=596664
  #
  grep -q -e 'perl module is required for intltool' -e "Can't locate .* in @INC" $bak
  if [[ $? -eq 0 ]]; then
    (
    cd /
    tar --dereference -cjpf $issuedir/var.db.pkg.tbz2       var/db/pkg
    tar --dereference -cjpf $issuedir/var.lib.portage.tbz2  var/lib/portage
    tar --dereference -cjpf $issuedir/etc.portage.tbz2      etc/portage
    )
    return 1
  fi

  if [[ $retry_with_changed_env -eq 1 ]]; then
    echo "$task" >> $pks
  else
    echo "=$failed" >> /etc/portage/package.mask/self
  fi

  # send an email if the issue was not yet catched
  #
  grep -F -q -f $issuedir/title /tmp/tb/data/ALREADY_CATCHED
  if [[ $? -ne 0 ]]; then
    cat $issuedir/title >> /tmp/tb/data/ALREADY_CATCHED
    Mail "${id:-ISSUE} $(cat $issuedir/title)" $issuedir/body
  fi
}


# *compiled* kernel modules are needed by some packages
#
function BuildKernel()  {
  (
    cd /usr/src/linux     &&\
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


# switch to latest GCC
#
function SwitchGCC() {
  latest=$(gcc-config --list-profiles --nocolor | cut -f3 -d' ' | grep 'x86_64-pc-linux-gnu-.*[0-9]$' | tail -n 1)
  gcc-config --list-profiles --nocolor | grep -q "$latest \*$"
  if [[ $? -ne 0 ]]; then
    verold=$(gcc -dumpversion)
    gcc-config --nocolor $latest &> $log
    . /etc/profile
    vernew=$(gcc -dumpversion)

    # this will avoid to append packages by insert_pkgs.sh onto our package list $pks
    #
    echo "# gcc switch from $verold to $vernew" >> $pks

    majold=$(echo $verold | cut -c1)
    majnew=$(echo $vernew | cut -c1)

    # rebuild libs at a major version number change
    #
    if [[ "$majold" != "$majnew" ]]; then
      # avoid: "cc1: error: incompatible gcc/plugin versions"
      #
      if [[ -e /usr/src/linux/.config ]]; then
        (cd /usr/src/linux && make clean &>>$log)
        BuildKernel &>> $log
      fi

      revdep-rebuild --ignore --library libstdc++.so.6 -- --exclude gcc &>> $log
      if [[ $? -ne 0 ]]; then
        GotAnIssue
        Finish "FAILED: $FUNCNAME revdep-rebuild failed"
      fi

      # double-ensure that packages are build against the new gcc headers/libs
      #
      fix_libtool_files.sh $verold &>>$log
      if [[ $? -ne 0 ]]; then
        Finish "FAILED: $FUNCNAME fix_libtool_files.sh $verold failed"
      fi

      emerge --unmerge =sys-devel/gcc-$verold &>>$log
      if [[ $? -ne 0 ]]; then
        Finish "FAILED: $FUNCNAME unmerge of gcc $verold failed"
      fi

      # per request of Soap this is forced for the new gcc-6
      # if a package fails therefore then it will be get special package.env settings next time
      #
      if [[ $majnew -eq 6 ]]; then
        sed -i -e 's/^CXXFLAGS="/CXXFLAGS="-Werror=terminate /' /etc/portage/make.conf
      fi
    fi
  fi
}


# eselect the latest *emerged* kernel and schedule a build of it
#
function SelectNewKernel() {
  last=$(ls -1dt /usr/src/linux-* | head -n 1 | cut -f4 -d'/')
  link=$(eselect kernel show | tail -n 1 | sed -e 's/ //g' | cut -f4 -d'/')

  if [[ "$last" != "$link" ]]; then
    eselect kernel set $last &>> $log
    if [[ ! -f /usr/src/linux/.config ]]; then
      echo "%BuildKernel" >> $pks
    fi
  fi
}


# work on follow-ups from the previous emerge operation
# but only *schedule* a needed emerge operation her
#
function PostEmerge() {
  # don't change these config files
  #
  rm -f /etc/ssmtp/._cfg????_ssmtp.conf
  rm -f /etc/portage/._cfg????_make.conf

  etc-update --automode -5 &>/dev/null
  env-update &>/dev/null
  . /etc/profile

  grep -q "IMPORTANT: config file '/etc/locale.gen' needs updating." $log
  if [[ $? -eq 0 ]]; then
    locale-gen &>/dev/null
  fi

  grep -q ">>> Installing .* sys-kernel/.*-sources" $log
  if [[ $? -eq 0 ]]; then
    SelectNewKernel
  fi

  # sometimes we run into a @preserved-rebuild loop, bail out then
  # especially sci-bio/embassy is often the culprit
  #
  grep -q "Use emerge @preserved-rebuild to rebuild packages using these libraries" $log
  if [[ $? -eq 0 ]]; then
    n=$(tac /var/log/emerge.log | grep -F -m 20 '*** emerge' | grep -c "emerge .* @preserved-rebuild")
    if [[ $n -gt 4 ]]; then
      # empty that file manually will let this check passed
      #
      f=/tmp/timestamp.preserved-rebuild
      if [[ -s $f ]]; then
        chmod a+w $f
        Finish "${n}x @preserved-rebuild, run 'truncate -s 0 $name/$f' and restart this image"
      fi
    fi
    echo "@preserved-rebuild" >> $pks
  fi

  grep -q -e "Please, run 'haskell-updater'" -e "ghc-pkg check: 'checking for other broken packages:'" $log
  if [[ $? -eq 0 ]]; then
    echo "%haskell-updater" >> $pks
  fi

  grep -q ">>> Installing .* sys-devel/gcc-[1-9]" $log
  if [[ $? -eq 0 ]]; then
    echo "%SwitchGCC" >> $pks
  fi

  grep -q 'Please run "revdep-pax" after installation.' $log
  if [[ $? -eq 0 ]]; then
    echo "%revdep-pax" >> $pks
  fi

  grep -q ">>> Installing .* dev-lang/perl-[1-9]" $log
  if [[ $? -eq 0 ]]; then
    echo "%ionice -c 3 perl-cleaner --all" >> $pks
  fi
}


# re-try emerge to update as much as possible
#
function SkipFirstAndResume() {
  while :;
  do
    emerge --resume --skipfirst &> $log
    if [[ $? -ne 0 ]]; then
      grep -q '* unsatisfied dependencies. Please restart/continue the operation' $log
      if [[ $? -eq 0 ]]; then
        break
      fi
      GotAnIssue
      echo "$(date) $failed" >> /tmp/timestamp.world
      PostEmerge
    else
      echo "$(date) resumed" >> /tmp/timestamp.world
      PostEmerge
      break
    fi
  done
}


# this is the tinderbox, the rest is just output parsing
#
function EmergeTask() {
  if [[ "$task" = "@preserved-rebuild" ]]; then
    emerge --backtrack=30 $task &> $log
    if [[ $? -ne 0 ]]; then
      GotAnIssue
      echo "$(date) $failed"  >> /tmp/timestamp.preserved-rebuild
    else
      echo "$(date) ok"       >> /tmp/timestamp.preserved-rebuild
    fi
    PostEmerge

  elif [[ "$task" = "@system" ]]; then
    emerge --deep --update --changed-use --with-bdeps=y $task &> $log
    if [[ $? -ne 0 ]]; then
      GotAnIssue
      rc=$?
      echo "$(date) $failed"  >> /tmp/timestamp.system
      PostEmerge
      if [[ $rc -eq 0 ]]; then
        SkipFirstAndResume
      else
        Mail "notice: fixing Perl upgrade issue: $task" $log
        echo "$task" >> $pks
        echo "%perl-cleaner --all" >> $pks
      fi
    else
      echo "$(date) ok"       >> /tmp/timestamp.system
      echo "@world" >> $pks
      PostEmerge
      # activate 32/64 bit library (re-)build if not yet done and @system was successful
      #
      grep -q '^#ABI_X86=' /etc/portage/make.conf
      if [[ $? -eq 0 ]]; then
        sed -i -e 's/^#ABI_X86=/ABI_X86=/' /etc/portage/make.conf
        echo "@system" >> $pks
      fi
    fi
    /usr/bin/pfl &>/dev/null

  elif [[ "$task" = "@world" ]]; then
    emerge --deep --update --changed-use --with-bdeps=y $task &> $log
    if [[ $? -ne 0 ]]; then
      GotAnIssue
      echo "$(date) $failed"  >> /tmp/timestamp.world
      PostEmerge
      SkipFirstAndResume
    else
      echo "$(date) ok"       >> /tmp/timestamp.world
      echo "%emerge --depclean" >> $pks
      PostEmerge
    fi
    /usr/bin/pfl &>/dev/null

  elif [[ "$(echo $task | cut -c1)" = '%' ]]; then
    #  a command line, prefixed with an '%'
    #
    cmd=$(echo "$task" | cut -c2-)
    ($cmd) &> $log
    if [[ $? -ne 0 ]]; then
      GotAnIssue
      PostEmerge
      Finish "cmd '$cmd' failed"
    fi
    PostEmerge

  else
    # just a package
    #
    emerge --update $task &> $log
    if [[ $? -ne 0 ]]; then
      GotAnIssue
    fi
    PostEmerge
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
      Mail "$exe returned $rc, task=$task" $out
      Finish "error: stopped"
    fi

    if [[ $rc -ne 0 ]]; then
      echo                                  >> $out
      echo "seen at tinderbox image $name"  >> $out
      echo                                  >> $out
      tail -n 30 $log                       >> $out
      echo                                  >> $out
      emerge --info --verbose=n $task       >> $out
      echo                                  >> $out
      Mail "$exe : rc=$rc, task=$task" $out
    fi

    rm $out
  fi
}

#############################################################################
#
#       main
#
mailto="tinderbox@zwiebeltoralf.de"
log=/tmp/task.log                   # holds always output of "emerge ... "
pks=/tmp/packages                   # the pre-filled package list file

export GCC_COLORS=""                # suppress colour output of gcc-4.9 and above

# eg.: amd64-gnome-unstable_20150913-104240
#
name=$(grep "^PORTAGE_ELOG_MAILFROM=" /etc/portage/make.conf | cut -f2 -d '"' | cut -f1 -d ' ')

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
  # restart ourself if origin was edited
  #
  diff -q /tmp/tb/bin/job.sh /tmp/job.sh 1>/dev/null
  if [[ $? -ne 0 ]]; then
    exit 125
  fi

  pre-check

  date > $log

  # this is one of exits of this loop
  #
  if [[ -f /tmp/STOP ]]; then
    Finish "catched stop signal"
  fi

  # clean up from a previous emerge operation
  # this isn't made by portage b/c we had to collect build files first
  #
  rm -rf /var/tmp/portage/*

  # another regular exit of this loop: append STOP onto $pks or empty it
  #
  GetNextTask

  # the heart of the tinderbox
  #
  EmergeTask
done

# barrier end (see start of this file too)
#
)
