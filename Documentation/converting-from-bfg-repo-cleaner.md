# Cheat Sheet: Converting from BFG Repo Cleaner

This document is aimed at folks who are familiar with BFG Repo Cleaner
and want to learn how to convert over to using filter-repo.

## Table of Contents

  * [Half-hearted conversions](#half-hearted-conversions)
  * [Intention of "equivalent" commands](#intention-of-equivalent-commands)
  * [Basic Differences](#basic-differences)
  * [Cheat Sheet: Conversion of Examples from BFG](#cheat-sheet-conversion-of-examples-from-bfg)

## Half-hearted conversions

You can switch most any BFG command to use filter-repo under the
covers by just replacing the `java -jar bfg.jar` part of the command
with [`bfg-ish`](../contrib/filter-repo-demos/bfg-ish).

bfg-ish is a reasonable tool, and provides a number of bug fixes and
features on top of bfg, but most of my focus is naturally on
filter-repo which has a number of capabilities lacking in bfg-ish.

## Intention of "equivalent" commands

BFG and filter-repo have a few differences, highlighted in the Basic
Differences section below, that make it hard to get commands that
behave identically.  Rather than focusing on matching BFG output as
exactly as possible, I treat the BFG examples as idiomatic ways to
solve a certain type of problem with BFG, and express how one would
idiomatically solve the same problem in filter-repo.  Sometimes that
means the results are not identical, but they are largely the same in
each case.

## Basic Differences

BFG operates directly on tree objects, which have no notion of their
leading path.  Thus, it has no way of differentiating between
'README.md' at the toplevel versus in some subdirectory.  You simply
operate on the basename of files and directories.  This precludes
doing things like renaming files and directories or other bigger
restructures.  By directly operating on trees, it also runs into
problems with loose vs. packed objects, loose vs. packed refs, not
understanding replace refs or grafts, and not understanding the index
and working tree as another data source.

With `git filter-repo`, you are essentially given an editing tool to
operate on the [fast-export](https://git-scm.com/docs/git-fast-export)
serialization of a repo, which operates on filenames including their
full paths from the toplevel of the repo.  Directories are not
separately specified, so any directory-related filtering is done by
checking the leading path of each file.  Further, you aren't limited
to the pre-defined filtering types, python callbacks which operate on
the data structures from the fast-export stream can be provided to do
just about anything you want.  By leveraging fast-export and
fast-import, filter-repo gains automatic handling of objects and refs
whether they are packed or not, automatic handling of replace refs and
grafts, and future features that may appear.  It also tries hard to
provide a full rewrite solution, so it takes care of additional
important concerns such as updating the index and working tree and
running an automatic gc for the user afterwards.

The "protection" and "privacy" defaults in BFG are something I
fundamentally disagreed with for a variety of reasons; see the
comments at the top of the
[bfg-ish](../contrib/filter-repo-demos/bfg-ish) script if you want
details.  The bfg-ish script implemented these protection and privacy
options since it was designed to act like BFG, but still flipped the
default to the opposite of what BFG chose.  I left the "protection"
and "non-private" features out of filter-repo entirely.  This means a
number of things with filter-repo:
  * any filters you specify will also be applied to HEAD, so that you
    don't have a weird disconnect from your history transformations
    only being applied to most commits
  * `[formerly OLDHASH]` references are not munged into commit
    messages; the replace refs that filter-repo adds are a much
    cleaner way of looking up commits by old commit hashes.
  * `Former-commit-id:` footers are not added to commit messages; the
    replace refs that filter-repo adds are a much cleaner way of
    looking up commits by old commit hashes.
  * History is not littered with `<filename>.REMOVED.git-id` files.

BFG expects you to specify the repository to rewrite as its final
argument, whereas filter-repo expects you to cd into the repo and then
run filter-repo.

## Cheat Sheet: Conversion of Examples from BFG

### Stripping big blobs

```shell
  java -jar bfg.jar --strip-blobs-bigger-than 100M some-big-repo.git
```

becomes

```shell
  git filter-repo --strip-blobs-bigger-than 100M
```

### Deleting files

```shell
  java -jar bfg.jar --delete-files id_{dsa,rsa}  my-repo.git
```

becomes

```shell
  git filter-repo --use-base-name --path id_dsa --path id_rsa --invert-paths
```

### Removing sensitive content

```shell
  java -jar bfg.jar --replace-text passwords.txt my-repo.git
```

becomes

```shell
  git filter-repo --replace-text passwords.txt
```

The `--replace-text` was a really clever idea that the BFG came up
with and I just implemented mostly as-is within filter-repo.  Sadly,
BFG didn't document the format of files passed to --replace text very
well, but I added more detail in the filter-repo documentation.

There is one small but important difference between the two tools: if
you use both "regex:" and "==>" on a single line to specify a regex
search and replace, then filter-repo will use "\1", "\2", "\3",
etc. for replacement strings whereas BFG used "$1", "$2", "$3", etc.
The reason for this difference is simply that python used backslashes
in its regex format while scala used dollar signs, and both tools
wanted to just pass along the strings unmodified to the underlying
language.  (Since bfg-ish attempts to emulate the BFG, it accepts
"$1", "$2" and so forth and translates them to "\1", "\2", etc. so
that filter-repo/python will understand it.)

### Removing files and folders with a certain name

```shell
  java -jar bfg.jar --delete-folders .git --delete-files .git --no-blob-protection  my-repo.git
```

becomes

```shell
  git filter-repo --invert-paths --path-glob '*/.git' --path .git
```

Yes, that glob will handle .git directories one or more directories
deep; it's a git-style glob rather than a shell-style glob.  Also, the
`--path .git` was added because `--path-glob '*/.git'` won't match a
directory named .git in the toplevel directory since it has a '/'
character in the glob expression (though I would hope the repository
doesn't have a tracked .git toplevel directory in its history).
