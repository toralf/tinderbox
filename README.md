[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# tinderbox

## Goal

The goal is to detect build issues/conflicts of [Gentoo Linux](https://www.gentoo.org/) packages.
For that about a dozen sandbox'ed Gentoo images are running in parallel.
Each image is setup from a recent _stage3_ tarball as an arbitrary combination of _~amd64_ + _profile_ + _USE flag_ set.
Within each image all Gentoo packages are scheduled for installation, in a randomized order for each image.

## Usage

The kick off of new images is done by _setup_img.sh_.
Watch their status:

```bash
whatsup.sh -dcp
whatsup.sh -otl
```

The file _~tinderbox/tb/findings/ALREADY_CAUGHT_ holds reported findings.
A new finding is send via email to the user specified in _./sdata/mailto_.
The Gentoo bug tracker can be searched (again) by _check_bgo.sh_.
If not yet reported then the finding can be filed by _bgo.sh_.

## Installation

Create the user _tinderbox_, which :

1. must not be allowed to edit files under _/opt/tb/_
1. needs to be granted to read/execute the scripts under _/opt/tb/bin/_
1. must have read/write permissions for files under _~tinderbox/tb/_
1. must not be allowed to read the file under _/opt/tb/sdata/_.

Create in its HOME the directories: _./distfiles/_, _./img/_, _./logs/_, _./run/_ and _./tb/_.
Clone this Git repository or unpack a release artefact.
Move _./conf_, _./data_ and _./patches_ to _~tinderbox/tb/_.
Move _./bin_ and _./sdata_ to _/opt/tb/_ and set ownership to _root_.
Edit the MTA config files in _/opt/tb/sdata/\*.sample_ and strip away the suffix _.sample_.
Grant sudo rights to the user _tinderbox_:

```bash
tinderbox  ALL=(ALL) NOPASSWD: /opt/tb/bin/bwrap.sh,/opt/tb/bin/collect_data.sh,/opt/tb/bin/debug_img.sh,/opt/tb/bin/house_keeping.sh,/opt/tb/bin/kill_img.sh,/opt/tb/bin/retest.sh,/opt/tb/bin/setup_img.sh,/usr/sbin/emaint
```

Adapt the values [desired_count](./bin/replace_img.sh#L96), [cgroup memory](./bin/bwrap.sh#L7) and [jobs](./bin/setup_img.sh#L60) for your machine size.

Example for a startup file:

```bash
#!/bin/bash
# set -x

set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

rm -f ~tinderbox/run/*/var/tmp/tb/STOP
/opt/tb/bin/start_img.sh
/opt/tb/bin/index.sh

nice /opt/fuzz-utils/bwrap.sh /opt/fuzz-utils/simple-http-server.py --address 65.21.94.49 --port 54321 --directory ~tinderbox/img/ &>/tmp/web-tinderbox.log &
```

## Why bash ?!?

I started this project with as a tiny 100+ lines Bash script.
And then I missed the Point of no Return to switch to some other language.

## Links

[My homepage](https://www.zwiebeltoralf.de/tinderbox.html)
