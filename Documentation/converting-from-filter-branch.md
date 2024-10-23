# Cheat Sheet: Converting from filter-branch

This document is aimed at folks who are familiar with filter-branch and want
to learn how to convert over to using filter-repo.

## Table of Contents

  * [Half-hearted conversions](#half-hearted-conversions)
  * [Intention of "equivalent" commands](#intention-of-equivalent-commands)
  * [Basic Differences](#basic-differences)
  * [Cheat Sheet: Conversion of Examples from the filter-branch manpage](#cheat-sheet-conversion-of-examples-from-the-filter-branch-manpage)
  * [Cheat Sheet: Additional conversion examples](#cheat-sheet-additional-conversion-examples)

## Half-hearted conversions

You can switch nearly any `git filter-branch` command to use
filter-repo under the covers by just replacing the `git filter-branch`
part of the command with
[`filter-lamely`](../contrib/filter-repo-demos/filter-lamely).  The
git.git regression testsuite passes when I swap out the filter-branch
script with filter-lamely, for example.  (However, the filter-branch
tests are not very comprehensive, so don't rely on that too much.)

Doing a half-hearted conversion has nearly all of the drawbacks of
filter-branch and nearly none of the benefits of filter-repo, but it
will make your command run a few times faster and makes for a very
simple conversion.

You'll get a lot more performance, safety, and features by just
switching to direct filter-repo commands.

## Intention of "equivalent" commands

filter-branch and filter-repo have different defaults, as highlighted
in the Basic Differences section below.  As such, getting a command
which behaves identically is not possible.  Also, sometimes the
filter-branch manpage lies, e.g. it says "suppose you want to...from
all commits" and then uses a command line like "git filter-branch
... HEAD", which only operates on commits in the current branch rather
than on all commits.

Rather than focusing on matching filter-branch output as exactly as
possible, I treat the filter-branch examples as idiomatic ways to
solve a certain type of problem with filter-branch, and express how
one would idiomatically solve the same problem in filter-repo.
Sometimes that means the results are not identical, but they are
largely the same in each case.

## Basic Differences

With `git filter-branch`, you have a git repository where every single
commit (within the branches or revisions you specify) is checked out
and then you run one or more shell commands to transform the working
copy into your desired end state.

With `git filter-repo`, you are essentially given an editing tool to
operate on the [fast-export](https://git-scm.com/docs/git-fast-export)
serialization of a repo.  That means there is an input stream of all
the contents of the repository, and rather than specifying filters in
the form of commands to run, you usually employ a number of common
pre-defined filters that provide various ways to slice, dice, or
modify the repo based on its components (such as pathnames, file
content, user names or emails, etc.)  That makes common operations
easier, even if it's not as versatile as shell callbacks.  For cases
where more complexity or special casing is needed, filter-repo
provides python callbacks that can operate on the data structures
populated from the fast-export stream to do just about anything you
want.

filter-branch defaults to working on a subset of the repository, and
requires you to specify a branch or branches, meaning you need to
specify `-- --all` to modify all commits.  filter-repo by contrast
defaults to rewriting everything, and you need to specify `--refs
<rev-list-args>` if you want to limit to just a certain set of
branches or range of commits.  (Though any `<rev-list-args>` that
begin with a hyphen are not accepted by filter-repo as they look like
the start of different options.)

filter-repo also takes care of additional concerns automatically, like
rewriting commit messages that reference old commit IDs to instead
reference the rewritten commit IDs, pruning commits which do not start
empty but become empty due to the specified filters, and automatically
shrinking and gc'ing the repo at the end of the filtering operation.

## Cheat Sheet: Conversion of Examples from the filter-branch manpage

### Removing a file

The filter-branch manual provided three different examples of removing
a single file, based on different levels of ease vs. carefulness and
performance:

```shell
  git filter-branch --tree-filter 'rm filename' HEAD
```
```shell
  git filter-branch --tree-filter 'rm -f filename' HEAD
```
```shell
  git filter-branch --index-filter 'git rm --cached --ignore-unmatch filename' HEAD
```

All of these just become

```shell
  git filter-repo --invert-paths --path filename
```

### Extracting a subdirectory

Extracting a subdirectory via

```shell
  git filter-branch --subdirectory-filter foodir -- --all
```

is one of the easiest commands to convert; it just becomes

```shell
  git filter-repo --subdirectory-filter foodir
```

### Moving the whole tree into a subdirectory

Keeping all files but placing them in a new subdirectory via

```shell
  git filter-branch --index-filter \
      'git ls-files -s | sed "s-\t\"*-&newsubdir/-" |
              GIT_INDEX_FILE=$GIT_INDEX_FILE.new \
                      git update-index --index-info &&
       mv "$GIT_INDEX_FILE.new" "$GIT_INDEX_FILE"' HEAD
```

(which happens to be GNU-specific and will fail with BSD userland in
very subtle ways) becomes

```shell
  git filter-repo --to-subdirectory-filter newsubdir
```

(which works fine regardless of GNU vs BSD userland differences.)

### Re-grafting history

The filter-branch manual provided one example with three different
commands that could be used to achieve it, though the first of them
had limited applicability (only when the repo had a single initial
commit).  These three examples were:
```shell
  git filter-branch --parent-filter 'sed "s/^\$/-p <graft-id>/"' HEAD
```
```shell
  git filter-branch --parent-filter \
      'test $GIT_COMMIT = <commit-id> && echo "-p <graft-id>" || cat' HEAD
```
```shell
  git replace --graft $commit-id $graft-id
  git filter-branch $graft-id..HEAD
```

git-replace did not exist when the original two examples were written,
but it is clear that the last example is far easier to understand.  As
such, filter-repo just uses the same mechanism:

```shell
  git replace --graft $commit-id $graft-id
  git filter-repo --proceed
```

NOTE: --proceed is needed here because filter-repo errors out if no
arguments are specified (doing so is usually an error).

### Removing commits by a certain author

WARNING: This is a BAD example for BOTH filter-branch and filter-repo.
It does not remove the changes the user made from the repo, it just
removes the commit in question while smashing the changes from it into
any subsequent commits as though the subsequent authors had been
responsible for those changes as well.  `git rebase` is likely to be a
better fit for what you really want if you are looking at this
example.  (See also [this explanation of the differences between
rebase and
filter-repo](https://github.com/newren/git-filter-repo/issues/62#issuecomment-597725502))

This filter-branch example

```shell
  git filter-branch --commit-filter '
      if [ "$GIT_AUTHOR_NAME" = "Darl McBribe" ];
      then
          skip_commit "$@";
      else
          git commit-tree "$@";
      fi' HEAD
```

becomes

```shell
  git filter-repo --commit-callback '
      if commit.author_name == b"Darl McBribe":
          commit.skip()
      '
```

### Rewriting commit messages -- removing text

Removing git-svn-id: lines from commit messages via

```shell
  git filter-branch --msg-filter '
      sed -e "/^git-svn-id:/d"
      '
```

becomes

```shell
  git filter-repo --message-callback '
      return re.sub(b"^git-svn-id:.*\n", b"", message, flags=re.MULTILINE)
      '
```

### Rewriting commit messages -- adding text

Adding Acked-by lines to the last ten commits via

```shell
  git filter-branch --msg-filter '
          cat &&
          echo "Acked-by: Bugs Bunny <bunny@bugzilla.org>"
      ' master~10..master
```

becomes

```shell
  git filter-repo --message-callback '
          return message + b"Acked-by: Bugs Bunny <bunny@bugzilla.org>\n"
      ' --refs master~10..master
```

### Changing author/committer(/tagger?) information

```shell
  git filter-branch --env-filter '
      if test "$GIT_AUTHOR_EMAIL" = "root@localhost"
      then
              GIT_AUTHOR_EMAIL=john@example.com
      fi
      if test "$GIT_COMMITTER_EMAIL" = "root@localhost"
      then
              GIT_COMMITTER_EMAIL=john@example.com
      fi
      ' -- --all
```

becomes either

```shell
  # Ensure '<john@example.com> <root@localhost>' is a line in .mailmap, then:
  git filter-repo --use-mailmap
```

or

```shell
  git filter-repo --email-callback '
    return email if email != b"root@localhost" else b"john@example.com"
    '
```

(and as a bonus both filter-repo alternatives will fix tagger emails
too, unlike the filter-branch example)


### Restricting to a range

The partial examples

```shell
  git filter-branch ... C..H
```
```shell
  git filter-branch ... C..H ^D
```
```shell
  git filter-branch ... D..H ^C
```

become

```shell
  git filter-repo ... --refs C..H
```
```shell
  git filter-repo ... --refs C..H ^D
```
```shell
  git filter-repo ... --refs D..H ^C
```

Note that filter-branch accepts `--not` among the revision specifiers,
but that appears to python to be a flag name which breaks parsing.
So, instead of e.g. `--not C` as we might use with filter-branch, we
can specify `^C` to filter-repo.

## Cheat Sheet: Additional conversion examples

### Running a code formatter or linter on each file with some extension

Running some program on a subset of files is relatively natural in
filter-branch:

```shell
  git filter-branch --tree-filter '
      git ls-files -z "*.c" \
          | xargs -0 -n 1 clang-format -style=file -i
      '
```

though it has the disadvantage of running on every c file for every
commit in history, even if some commits do not modify any c files.  This
means this kind of command can be excruciatingly slow.

The same functionality is slightly more involved in filter-repo for
two reasons:
  - fast-export and fast-import split file contents and file names into
    completely different data structures that aren't normally available
    together
  - to run a program on a file, you'll need to write the contents to the
    a file, execute the program on that file, and then read the contents
    of the file back in

```shell
  git filter-repo --file-info-callback '
    if not filename.endswith(b".c"):
      return (filename, mode, blob_id)  # no changes

    contents = value.get_contents_by_identifier(blob_id)
    tmpfile = os.path.basename(filename)
    with open(tmpfile, "wb") as f:
      f.write(contents)
    subprocess.check_call(["clang-format", "-style=file", "-i", filename])
    with open(filename, "rb") as f:
      contents = f.read()
    new_blob_id = value.insert_file_with_contents(contents)

    return (filename, mode, new_blob_id)
    '
```

However, one can write a script that uses filter-repo as a library to
simplify this, while also gaining filter-repo's automatic handling of
other concerns like rewriting commit IDs in commit messages or pruning
commits that become empty.  In fact, one of the [contrib
demos](../contrib/filter-repo-demos),
[lint-history](../contrib/filter-repo-demos/lint-history), was
specifically written to make this kind of case really easy:

```shell
  lint-history --relevant 'return filename.endswith(b".c")' \
      clang-format -style=file -i
```
