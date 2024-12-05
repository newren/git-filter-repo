# Frequently Answered Questions

## Table of Contents

  * [Why did `git-filter-repo` rewrite commit hashes?](#why-did-git-filter-repo-rewrite-commit-hashes)
  * [Why did `git-filter-repo` rewrite more commit hashes than I expected?](#why-did-git-filter-repo-rewrite-more-commit-hashes-than-i-expected)
  * [Why did `git-filter-repo` rewrite other branches too?](#why-did-git-filter-repo-rewrite-other-branches-too)
  * [How should paths be specified?](#How-should-paths-be-specified)
  * [Help! Can I recover or undo the filtering?](#help-can-i-recover-or-undo-the-filtering)
  * [Can you change `git-filter-repo` to allow future folks to recover from `--force`'d rewrites?](#can-you-change-git-filter-repo-to-allow-future-folks-to-recover-from---forced-rewrites)
  * [Can I use `git-filter-repo` to fix a repository with corruption?](#Can-I-use-git-filter-repo-to-fix-a-repository-with-corruption)
  * [What kinds of problems does `git-filter-repo` not try to solve?](#What-kinds-of-problems-does-git-filter-repo-not-try-to-solve)
    * [Filtering history but magically keeping the same commit IDs](#Filtering-history-but-magically-keeping-the-same-commit-IDs)
    * [Bidirectional development between a filtered and unfiltered repository](#Bidirectional-development-between-a-filtered-and-unfiltered-repository)
    * [Removing specific commits, or filtering based on the difference (a.k.a. patch or change) between commits](#Removing-specific-commits-or-filtering-based-on-the-difference-aka-patch-or-change-between-commits)
    * [Filtering two different clones of the same repository and getting the same new commit IDs](#Filtering-two-different-clones-of-the-same-repository-and-getting-the-same-new-commit-IDs)

## Why did `git-filter-repo` rewrite commit hashes?

This is fundamental to how Git operates.  In more detail...

Each commit in Git is a hash of its contents.  Those contents include
the commit message, the author (name, email, and time authored), the
committer (name, email and time committed), the toplevel tree hash,
and the parent(s) of the commit.  This means that if any of the commit
fields change, including the tree hash or the hash of the parent(s) of
the commit, then the hash for the commit will change.

(The same is true for files ("blobs") and trees stored in git as well;
each is a hash of its contents, so literally if anything changes, the
commit hash will change.)

If you attempt to write a commit (or tree or blob) object with an
incorrect hash, Git will reject it as corrupt.

## Why did `git-filter-repo` rewrite more commit hashes than I expected?

There are two aspects to this, or two possible underlying questions users
might be asking here:
  * Why did commits newer than the ones I expected have their hash change?
  * Why did commits older than the ones I expected have their hash change?

For the first question, see [why filter-repo rewrites commit
hashes](#why-did-git-filter-repo-rewrite-commit-hashes), and note that
if you modify some old commit, perhaps to remove a file, then obviously
that commit's hash must change.  Further, since that commit will have a
new hash, any other commit with that commit as a parent will need to
have a new hash.  That will need to chain all the way to the most recent
commits in history.  This is fundamental to Git and there is nothing you
can do to change this.

For the second question, there are two causes: (1) the filter you
specified applies to the older commits too, or (2) git-fast-export and
git-fast-import (both of which git-filter-repo uses) canonicalize
history in various ways.  The second cause means that even if you have
no filter, these tools sometimes change commit hashes.  This can happen
in any of these cases:

  * If you have signed commits, the signatures will be stripped
  * If you have commits with extended headers, the extended headers will
    be stripped (signed commits are actually a special case of this)
  * If you have commits in an encoding other than UTF-8, they will by
    default be re-encoded into UTF-8
  * If you have a commit without an author, one will be added that
    matches the committer.
  * If you have trees that are not canonical (e.g. incorrect sorting
    order), they will be canonicalized

If this affects you and you really only want to rewrite newer commits in
history, you can use the `--refs` argument to git-filter-repo to specify
a range of history that you want rewritten.

(For those attempting to be clever and use `--refs` for the first
question: Note that if you attempt to only rewrite a few old commits,
then all you'll succeed in is adding new commits that won't be part of
any branch and will be subject to garbage collection.  The branches will
still hold on to the unrewritten versions of the commits.  Thus, you
have to rewrite all the way to the branch tip for the rewrite to be
meaningful.  Said another way, the `--refs` trick is only useful for
restricting the rewrite to newer commits, never for restricting the
rewrite to older commits.)

## Why did `git-filter-repo` rewrite other branches too?

git-filter-repo's name is git-filter-**_repo_**.  Obviously it is going
to rewrite all branches by default.

`git-filter-repo` can restrict its rewriting to a subset of history,
such as a single branch, using the `--refs` option.  However, using that
comes with the risk that one branch now has a different version of some
commits than other branches do; usually, when you rewrite history, you
want all branches that depend on what you are rewriting to be updated.

## How should paths be specified?

Arguments to `--path` should be paths as Git would report them, when run
from the toplevel of the git repository (explained more below after some
examples).

**Good** path examples:
  * `README.md`
  * `Documentation/README.md`
  * `src/modules/flux/capacitor.rs`

You can find examples of valid path names from your repository by
running either `git diff --no-relative --name-only` or `git log
--no-relative --name-only --format=""`.

The following are basic rules about paths the way that Git reports and uses
them:
  * do not use absolute paths
  * always treats paths as relative to the toplevel of the repository
    (do not add a leading slash, and do not specify paths relative to some
     subdirectory of the repository even if that is your current working
     directory)
  * do not use the special directories `.` or `..` anywhere in your path
  * do not use `\`,  the Windows path separator, between directories and
    files; always use `/` regardless of platform.

**Erroneous** path examples (do **_NOT_** use any of these styles):
 * `/absolute/path/to/src/modules/program.c`
 * `/src/modules/program.c`
 * `src/docs/../modules/main.java`
 * `scripts/config/./update.sh`
 * `./tests/fixtures/image.jpg`
 * `../src/main.rs`
 * `C:\absolute\path\to\src\modules\program.c`
 * `src\modules\program.c`

## Help! Can I recover or undo the filtering?

Sure, _if_ you followed the instructions.  The instructions told you to
make a fresh clone before running git-filter-repo.  If you did that (and
didn't force push your rewritten history back over the original), you
can just throw away your clone with the flubbed rewrite, and make a new
clone.

If you didn't make a fresh clone, and you didn't run with `--force`, you
would have seen the following warning:
```
Aborting: Refusing to destructively overwrite repo history since
this does not look like a fresh clone.
[...]
Please operate on a fresh clone instead.  If you want to proceed
anyway, use --force.
```
If you then added `--force`, well, you were warned.

If you didn't make a fresh clone, and you started with `--force`, and you
didn't think to read the description of the `--force` option:
```
	Ignore fresh clone checks and rewrite history (an irreversible
	operation, especially since it by default ends with an
	immediate pruning of reflogs and old objects).
```
and you didn't read even the beginning of the manual
```
git-filter-repo destructively rewrites history
```
and you think it's okay to run a command with `--force` in it on
something you don't have a backup of, then now is the time to reasses
your life choices.  `--force` should be a pretty clear warning sign.
(If someone on the internet suggested `--force`, you can complain at
_them_, but either way you should learn to carefully vet commands
suggested by others on the internet.  Sadly, even sites like Stack
Overflow where someone really ought to be able to correct bad guidance
still unfortunately has a fair amount of this bad advice.)

See also the next question.

## Can you change `git-filter-repo` to allow future folks to recover from --force'd rewrites?

This will never be supported.

* Providing an alternate method to restore would require storing both
  the original history and the new history, meaning that those who are
  trying to shrink their repository size instead see it grow and have to
  figure out extra steps to expunge the old history to see the actual
  size savings.  Experience with other tools showed that this was
  frustrating and difficult to figure out for many users.

* Providing an alternate method to restore would mean that users who are
  trying to purge sensitive data from their repository still find the
  sensitive data after the rewrite because it hasn't actually been
  purged. In order to actually purge it, they have to take extra steps.
  Same as with the last bullet point, experience has shown that extra
  steps to purge the extra information is difficult and error-prone.
  This extra difficulty is particularly problematic when you're trying
  to expunge sensitive data.

* Providing an alternate method to restore would also mean trying to
  figure out what should be backed up and how. The obvious choices used
  by previous tools only actually provided partial backups (reflogs
  would be ignored for example, as would uncommitted changes whether
  staged or not). The more you try to carefully backup everything, the
  more difficult the restoration from backup will be.  The only backup
  mechanism I've found that seems reasonable, is making a separate
  clone.  That's expensive to do automatically for the user (especially
  if the filtering is done via multiple invocations of the tool).  Plus,
  it's not clear where the clone should be stored, especially to avoid
  the previous problems for size-reduction and sensitive-data-removal
  folks.

* Providing an alternate method to restore would also mean providing
  documentation on how to restore. Past methods by other tools in the
  history rewriting space suggested that it was rather difficult for
  users to figure out.  Difficult enough, in fact, that users simply
  didn't ever use them.  They instead made a separate clone before
  rewriting history and if they didn't like the rewrite, then they just
  blew it away and made a new clone to work with.  Since that was
  observed to be the easy restoration method, I simply enforced it with
  this tool, requiring users who look like they might not be operating
  on a fresh clone to use the --force flag.

But more than all that, if there were an alternate method to restore,
why would you have needed to specify the --force flag? Doesn't its
existence (and the wording of its documentation) make it pretty clear on
its own that there isn't going to be a way to restore?

## Can I use `git-filter-repo` to fix a repository with corruption?

Some kinds of corruption can be fixed, in conjunction with `git
replace`.  If `git fsck` reports warnings/errors for certain objects,
you can often [replace them and rewrite
history](examples-from-user-filed-issues.md#Handling-repository-corruption).

## What kinds of problems does `git-filter-repo` not try to solve?

This question is often asked in the form of "How do I..." or even
written as a statement such as "I found a bug with `git-filter-repo`;
the behavior I got was different than I expected..."  But if you're
trying to do one of the things below, then `git-filter-repo` is behaving
as designed and either there is no solution to your problem, or you need
to use a different tool to solve your problem.  The following subsections
address some of these common requests:

### Filtering history but magically keeping the same commit IDs

This is impossible.  If you modify commits, or the files contained in
them, then you change their commit IDs; this is [fundamental to
Git](#why-did-git-filter-repo-rewrite-commit-hashes).

However, _if_ you don't need to modify commits, but just don't want to
download everything, then look into one of the following:
  * [partial clones](https://git-scm.com/docs/partial-clone)
  * the ugly, retarded hack known as [shallow clones](https://git-scm.com/docs/shallow)
  * a massive hack like [cheap fake
    clones](https://github.com/newren/sequester-old-big-blobs) that at
    least let you put your evil overlord laugh to use

### Bidirectional development between a filtered and unfiltered repository

Some folks want to extract a subset of a repository, do development work
on it, then bring those changes back to the original repository, and
send further changes in both directions.  Such a tool can be written
using fast-export and fast-import, but would need to make very different
design decisions than `git-filter-repo` did.  Such a tool would be
capable of supporting this kind of development, but lose the ability
["to write arbitrary filters using a scripting
language"](https://josh-project.github.io/josh/#concept) and other
features that `git-filter-repo` has.

Such a tool exists; it's called [Josh](https://github.com/josh-project/josh).
Use it if this is your usecase.

### Removing specific commits, or filtering based on the difference (a.k.a. patch or change) between commits

You are probably looking for `git rebase`.  `git rebase` operates on the
difference between commits ("diff"), allowing you to e.g. drop or modify
the diff, but then runs the risk of conflicts as it attempts to apply
future diffs. If you tweak one diff in the middle, since it just applies
more diffs for the remaining patches, you'll still see your changes at
the end.

filter-repo, by contrast, uses fast-export and fast-import.  Those tools
treat every commit not as a diff but as a "use the same versions of most
files from the parent commit, but make these five files have these exact
contents". Since you don't have either the diff or ready access to the
version of files from the parent commit, that makes it hard to "undo"
part of the changes to some file.  Further, if you attempt to drop an
entire commit or tweak the contents of those new files in that commit,
those changes will be reverted by the next commit in the stream that
mentions that file because handling the next commit does not involve
applying a diff but a "make this file have these exact contents". So,
filter-repo works well for things like removing a file entirely, but if
you want to make any tweaks to any files you have to make the exact same
tweak over and over for every single commit that touches that file.

In short, `git rebase` is the tool you want for removing specific
commits or otherwise operating on the diff between commits.

### Filtering two different clones of the same repository and getting the same new commit IDs

Sometimes two co-workers have a clone of the same repository and they
run the same `git-filter-repo` command, and they expect to get the same
new commit IDs.  Often they do get the same new commit IDs, but
sometimes they don't.

When people get the same commit IDs, it is only by luck; not by design.
There are three reasons this is unsupported and will never be reliable:

  * Different Git versions used could cause differences in filtering

    Since `git fast-export` and `git fast-import` do various
    canonicalizations of history, and these could change over time,
    having different versions of Git installed can result in differences
    in filtering.

  * Different git-filter-repo versions used could cause differences in
    filtering

    Over time, `git-filter-repo` may include new filterings by default,
    or fix existing filterings, or make any other number of changes.  As
    such, having different versions of `git-filter-repo` installed can
    result in differences in filtering.

  * Different amounts of the repository cloned or differences in
    local-only commits can cause differences in filtering

    If the clones weren't made at the same time, one clone may have more
    commits than the other.  Also, both may have made local commits the
    other doesn't have.  These additional commits could cause history to
    be traversed in a different order, and filtering rules are allowed
    to have order-dependent rules for how they filter.  Further,
    filtering rules are allowed to depend upon what history exists in
    your clone.  As one example, filter-repo's default to update commit
    messages which refer to other commits by abbreviated hash, may be
    unable to find these other commits in your clone but find them in
    your coworkers' clone.  Relatedly, filter-repo's update of
    abbreviated hashes in commit messages only works for commits that
    have already been filtered, and thus depends on the order in which
    fast-export traverses the history.

`git-filter-repo` is designed as a _one_-shot history rewriting tool.
Once you have filtered one clone of the repository, you should not be
using it to filter other clones.  All other clones of the repository
should either be discarded and recloned, or [have all their history
rebased on top of the rewritten
history](https://htmlpreview.github.io/?https://github.com/newren/git-filter-repo/blob/docs/html/git-filter-repo.html#_make_sure_other_copies_are_cleaned_up_clones_of_colleagues).

<!--
## How do I see what was removed?

Run `git rev-list --objects --all` in both a separate fresh clone from
before the rewrite and in the repo where the rewrite was done.  Then
find the objects that exist in the old but not the new.

-->
