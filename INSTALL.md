# Installation via Package Manager

Installation is as easy as

    $ PACKAGE_TOOL install git-filter-repo

for those using a [package
manager](https://alternativeto.net/software/yellowdog-updater-modified/?license=opensource)
to install software on their system from one of the following package
repositories:

[![Packaging status](https://repology.org/badge/vertical-allrepos/git-filter-repo.svg)](https://repology.org/project/git-filter-repo/versions)

This list covers at least Windows (Scoop), Mac OS X (Homebrew), and
Linux (most the rest).  Note that I do not curate this list (and have
no interest in doing so); https://repology.org tracks who packages
these versions.


# Notes for Windows Users

The first hurdle for Windows users is installing a functional version
of Python (it has been reported that Windows ships with a stripped
down python-like program that just doesn't work).  python.org probably
has good instructions here, though many users report a preference
getting it from the [Microsoft
Store](https://docs.microsoft.com/en-us/windows/python/beginners) and
seem to be successful with that (particularly since [msys2 issue
#27](https://github.com/msys2/msys2-runtime/pull/27) was fixed by the
Git for Windows maintainer).

Several users also needed to modify the first line of the
git-filter-repo script to change paths, especially if installing
git-filter-repo using the pip method instead of Scoop, and
particularly with older versions of Git for Windows (anything less
than 2.32.0.windows.1) as GitBash had an unfortunate shebang length
limitation (see [git-for-windows issue
#3165](https://github.com/git-for-windows/git/pull/3165)).

For additional details (if needed, though be aware these might not be
accurate anymore given both git-for-windows and git-filter-repo
fixes), see
[#225](https://github.com/newren/git-filter-repo/pull/225),
[#231](https://github.com/newren/git-filter-repo/pull/231),
[#124](https://github.com/newren/git-filter-repo/issues/124),
[#36](https://github.com/newren/git-filter-repo/issues/36), and [this
git mailing list
thread](https://lore.kernel.org/git/nycvar.QRO.7.76.6.2004251610300.18039@tvgsbejvaqbjf.bet/).


# Manual Installation

filter-repo only consists of a few files that need to be installed:

  * git-filter-repo

    This is the only thing needed for basic use.

    This can be installed in the directory pointed to by `git --exec-path`,
    or placed anywhere in $PATH.

    If your python3 executable is named "python" instead of "python3"
    (this particularly appears to affect a number of Windows users),
    then you'll also need to modify the first line of git-filter-repo
    to replace "python3" with "python".

  * git_filter_repo.py

    This is needed if you want to make use of one of the scripts in
    contrib/filter-repo-demos/, or want to write your own script making use
    of filter-repo as a python library.

    You can create this symlink to (or copy of) git-filter-repo named
    git_filter-repo.py and place it in your python site packages; `python
    -c "import site; print(site.getsitepackages())"` may help you find the
    appropriate location for your system.  Alternatively, you can place
    this file anywhere within $PYTHONPATH.

  * git-filter-repo.1

    This is needed if you want `git filter-repo --help` to succeed in
    displaying the manpage, when help.format is "man" (the default on Linux
    and Mac).

    This can be installed in the directory pointed to by `$(git
    --man-path)/man1/`, or placed anywhere in $MANDIR/man1/ where $MANDIR
    is some entry from $MANPATH.

    Note that `git filter-repo -h` will show a more limited built-in set of
    instructions regardless of whether the manpage is installed.

  * git-filter-repo.html

    This is needed if you want `git filter-repo --help` to succeed in
    displaying the html version of the help, when help.format is set to
    "html" (the default on Windows).

    This can be installed in the directory pointed to by `git --html-path`.

    Note that `git filter-repo -h` will show a more limited built-in set of
    instructions regardless of whether the html version of help is
    installed.

So, installation might look something like the following:

1. If you don't have the necessary documentation files (because you
   are installing from a clone of filter-repo instead of from a
   tarball) then you can first run:

   `make snag_docs`

   (which just copies the generated documentation files from the
   `docs` branch)

2. Run the following

   ```
   cp -a git-filter-repo $(git --exec-path)
   cp -a git-filter-repo.1 $(git --man-path)/man1
   cp -a git-filter-repo.html $(git --html-path)
   ln -s $(git --exec-path)/git-filter-repo \
       $(python -c "import site; print(site.getsitepackages()[-1])")/git_filter_repo.py
   ```

# Installation via [pip](https://pip.pypa.io/)

For those who prefer to install python packages via pip, you merely need
to run:

    $ pip3 install git-filter-repo

However, the place where pip places that package might not be in your
$PATH (thus requiring you to manually update your $PATH afterwards),
and on windows the pip install might not take care of python-specific
issues for you (see "Notes for Windows Users", above).  As such,
installation via package managers is recommended instead.


# Installation via Makefile

Installing should be doable by hand, but a Makefile is provided for those
that prefer it.  However, usage of the Makefile really requires overridding
at least a couple of the directories with sane values, e.g.

    $ make prefix=/usr pythondir=/usr/lib64/python3.8/site-packages install

Also, the Makefile will not edit the shebang line (the first line) of
git-filter-repo if your python executable is not named "python3";
you'll still need to do that yourself.
