# Installation via Package Manager

Installation is as easy as

    $ PACKAGE_TOOL install git-filter-repo

for those using one of the following [package
managers](https://alternativeto.net/software/yellowdog-updater-modified/?license=opensource)
to install software on their system:

[![Packaging status](https://repology.org/badge/vertical-allrepos/git-filter-repo.svg)](https://repology.org/project/git-filter-repo/versions)

This list covers at least Windows (Scoop), Mac OS X (Homebrew), and
Linux (most the rest).  Note that I do not curate this list (and have
no interest in doing so); https://repology.org tracks who packages
these versions.


# Manual Installation

filter-repo only consists of a few files that need to be installed:

  * git-filter-repo

    This can be installed in the directory pointed to by `git --exec-path`,
    or placed anywhere in $PATH.  This is the only thing needed for basic use.

    If your python3 executable is named "python" instead of "python3"
    (this particularly appears to affect a number of Windows users),
    then you'll also need to modify the first line of git-filter-repo
    to replace "python3" with "python".

  * git_filter_repo.py

    If you want to make use of one of the scripts in contrib/filter-repo-demos/,
    or want to write your own script making use of filter-repo as a python
    library, then you need to have a symlink to (or copy of) git-filter-repo
    named git_filter_repo.py in $PYTHONPATH.

  * git-filter-repo.1

    If you want `git filter-repo --help` to display the manpage, this needs
    to be copied into $MANDIR/man1/ where $MANDIR is some entry from $MANPATH.
    (Note that `git filter-repo -h` will show a more limited built-in set of
    instructions regardless of whether the manpage is installed.)

  * git-filter-repo.html

    The manpage is good enough for me and my systems, but an html-formatted
    version of the same page is provided for those who prefer it.  Place it
    where ever you like; I have no idea where such a thing should go.


# Installation via [pip](https://pip.pypa.io/)

For those who prefer to install python packages via pip, you merely need
to run:

    $ pip3 install git-filter-repo


# Installation via Makefile

Installing should be doable by hand, but a Makefile is provided for those
that prefer it.  However, usage of the Makefile really requires overridding
at least a couple of the directories with sane values, e.g.

    $ make prefix=/usr pythondir=/usr/lib64/python3.8/site-packages install

Also, the Makefile will not edit the shebang line (the first line) of
git-filter-repo if your python executable is not named "python3";
you'll still need to do that yourself.
