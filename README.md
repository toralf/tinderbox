[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# tinderbox

## Goal

The goal is to detect build issues/conflicts of Gentoo Linux packages.

For that a dozen sandbox'ed Gentoo images are running in parallel.

Each image is setup from a recent _stage3_ tarball as an arbitrary combination of _~amd64_ + _profile_ + _USE flag_ set.
Within each image all Gentoo packages are scheduled in a randomized order to be emerged.

## Usage

Setup an image with _replace_img.sh_ or directly with _setup_img.sh_.
See the status of all images:

```bash
whatsup.sh -dcp
whatsup.sh -otl
```

The file _~tinderbox/tb/data/ALREADY_CAUGHT_ holds reported findings.
A new finding is send via email to the user specified by the variable _MAILTO_.
A finding can be filed using _bgo.sh_.
Before the Gentoo bugzilla should be searched by _check_bgo.sh_ for duplicates.

Login interactively into an image with

```bash
sudo /opt/tb/bin/bwrap.sh -m <path to img>
```

## Installation

Create the user _tinderbox_:

```bash
useradd -m tinderbox
usermod -a -G portage tinderbox
```

Create as user _tinderbox_ in its HOME the directories _distfiles_, _img_, _logs_, _run_, _tb_.
Clone this Git repository.
Move _./data_ and _./sdata_ into _~tinderbox/tb/_ and _./bin_ under _/opt/tb/_.
Edit the ssmtp credentials in _~tinderbox/sdata_ and strip away the suffix _.sample_ from the file,
set ownership and grant permissions of this subdirectory and its files e.g. to user _root_ instead _tinderbox_.

The user _tinderbox_:

1. must not be allowed to edit files under in _/opt/tb/_
1. needs to be granted to read/execute the scripts under _/opt/tb/bin/_
1. must have read/write permissions for files under _~tinderbox/tb/_ except the subdirectory _/sdata_

Grant to the user _tinderbox_ these sudo rights:

```bash
tinderbox  ALL=(ALL) NOPASSWD: /opt/tb/bin/bwrap.sh,/opt/tb/bin/setup_img.sh,/opt/tb/bin/house_keeping.sh,/opt/tb/bin/kill_img.sh,/opt/tb/bin/retest.sh,/opt/tb/bin/collect_data.sh
```

## Links

[homepage](https://www.zwiebeltoralf.de/tinderbox.html)
