git filter-repo is a versatile tool for rewriting history, which includes
[capabilities I have not found anywhere
else](#design-rationale-behind-filter-repo).  It roughly falls into the
same space of tool as [git
filter-branch](https://git-scm.com/docs/git-filter-branch) but without the
capitulation-inducing poor
[performance](https://public-inbox.org/git/CABPp-BGOz8nks0+Tdw5GyGqxeYR-3FF6FT5JcgVqZDYVRQ6qog@mail.gmail.com/),
with far more capabilities, and with a design that scales usability-wise
beyond trivial rewriting cases.  [git filter-repo is now recommended by the
git project](https://git-scm.com/docs/git-filter-branch#_warning) instead
of git filter-branch.

While most users will probably just use filter-repo as a simple command
line tool (and likely only use a few of its flags), at its core filter-repo
contains a library for creating history rewriting tools.  As such, users
with specialized needs can leverage it to quickly create [entirely new
history rewriting tools](contrib/filter-repo-demos).

# Table of Contents

  * [Prerequisites](#prerequisites)
  * [How do I install it?](#how-do-i-install-it)
  * [How do I use it?](#how-do-i-use-it)
  * [Why filter-repo instead of other alternatives?](#why-filter-repo-instead-of-other-alternatives)
    * [filter-branch](#filter-branch)
    * [BFG Repo Cleaner](#bfg-repo-cleaner)
  * [Simple example, with comparisons](#simple-example-with-comparisons)
    * [Solving this with filter-repo](#solving-this-with-filter-repo)
    * [Solving this with BFG Repo Cleaner](#solving-this-with-bfg-repo-cleaner)
    * [Solving this with filter-branch](#solving-this-with-filter-branch)
    * [Solving this with fast-export/fast-import](#solving-this-with-fast-exportfast-import)
  * [Design rationale behind filter-repo](#design-rationale-behind-filter-repo)
  * [How do I contribute?](#how-do-i-contribute)
  * [Is there a Code of Conduct?](#is-there-a-code-of-conduct)
  * [Upstream Improvements](#upstream-improvements)

# Prerequisites

filter-repo requires:

  * git >= 2.22.0 at a minimum; [some features](#upstream-improvements)
    require git >= 2.24.0 or later
  * python3 >= 3.5

# How do I install it?

git-filter-repo is a single-file python script, which was done to make
installation for basic use trivial: just copy it into your $PATH.

See [INSTALL.md](INSTALL.md) for things beyond basic usage or special
cases.  The more involved instructions are needed if you

  * are working with a python3 executable named something other than "python3"
  * want to install documentation (beyond the builtin docs shown with -h)
  * want to run some of the [contrib](contrib/filter-repo-demos/) examples
  * want to create your own python filtering scripts using filter-repo as a
    module/library

# How do I use it?

See the [user
manual](https://htmlpreview.github.io/?https://github.com/newren/git-filter-repo/blob/docs/html/git-filter-repo.html).

If you prefer learning from examples:
  * the [simple example](#simple-example-with-comparisons) below may
    be of interest
  * the user manual has an extensive [examples
section](https://htmlpreview.github.io/?https://github.com/newren/git-filter-repo/blob/docs/html/git-filter-repo.html#EXAMPLES)
  * there is a [cheat sheet for converting filter-branch
    commands](Documentation/converting-from-filter-branch.md#cheat-sheet-conversion-of-examples-from-the-filter-branch-manpage),
    which covers every example from the filter-branch manual
  * there is a [cheat sheet for converting BFG Repo Cleaner
    commands](Documentation/converting-from-bfg-repo-cleaner.md#cheat-sheet-conversion-of-examples-from-bfg),
    which covers every example from the BFG website

External sites also have [alternative formats of the user
manual](https://www.mankier.com/1/git-filter-repo) available, at least
for the most recent release.  This also may be beneficial if
htmlpreview.github.io starts hitting load limits.

# Why filter-repo instead of other alternatives?

This was covered in more detail in a [Git Rev News article on
filter-repo](https://git.github.io/rev_news/2019/08/21/edition-54/#an-introduction-to-git-filter-repo--written-by-elijah-newren),
but some highlights for the main competitors:

## filter-branch

  * filter-branch is [extremely to unusably
    slow](https://public-inbox.org/git/CABPp-BGOz8nks0+Tdw5GyGqxeYR-3FF6FT5JcgVqZDYVRQ6qog@mail.gmail.com/)
    ([multiple orders of magnitude slower than it should
    be](https://git-scm.com/docs/git-filter-branch#PERFORMANCE))
    for non-trivial repositories.

  * [filter-branch is riddled with
    gotchas](https://git-scm.com/docs/git-filter-branch#SAFETY) that can
    silently corrupt your rewrite or at least thwart your "cleanup"
    efforts by giving you something more problematic and messy than what
    you started with.

  * filter-branch is [very onerous](#simple-example-with-comparisons)
    [to
    use](https://github.com/newren/git-filter-repo/blob/a6a6a1b0f62d365bbe2e76f823e1621857ec4dbd/contrib/filter-repo-demos/filter-lamely#L9-L61)
    for any rewrite which is even slightly non-trivial.

  * the git project has stated that the above issues with filter-branch
    cannot be backward compatibly fixed; they recommend that you [stop
    using
    filter-branch](https://git-scm.com/docs/git-filter-branch#_warning)

  * die-hard fans of filter-branch may be interested in
    [filter-lamely](contrib/filter-repo-demos/filter-lamely)
    (a.k.a. [filter-branch-ish](contrib/filter-repo-demos/filter-branch-ish)),
    a reimplementation of filter-branch based on filter-repo which is
    more performant (though not nearly as fast or safe as
    filter-repo).

  * a [cheat
    sheet](Documentation/converting-from-filter-branch.md#cheat-sheet-conversion-of-examples-from-the-filter-branch-manpage)
    is available showing how to convert example commands from the manual of
    filter-branch into filter-repo commands.

## BFG Repo Cleaner

  * great tool for its time, but while it makes some things simple, it
    is limited to a few kinds of rewrites.

  * its architecture is not amenable to handling more types of
    rewrites.

  * its architecture presents some shortcomings and bugs even for its
    intended usecase.

  * fans of bfg may be interested in
    [bfg-ish](contrib/filter-repo-demos/bfg-ish), a reimplementation of bfg
    based on filter-repo which includes several new features and bugfixes
    relative to bfg.

  * a [cheat
    sheet](Documentation/converting-from-bfg-repo-cleaner.md#cheat-sheet-conversion-of-examples-from-bfg)
    is available showing how to convert example commands from the manual of
    BFG Repo Cleaner into filter-repo commands.

# Simple example, with comparisons

Let's say that we want to extract a piece of a repository, with the intent
on merging just that piece into some other bigger repo.  For extraction, we
want to:

  * extract the history of a single directory, src/.  This means that only
    paths under src/ remain in the repo, and any commits that only touched
    paths outside this directory will be removed.
  * rename all files to have a new leading directory, my-module/ (e.g. so that
    src/foo.c becomes my-module/src/foo.c)
  * rename any tags in the extracted repository to have a 'my-module-'
    prefix (to avoid any conflicts when we later merge this repo into
    something else)

## Solving this with filter-repo

Doing this with filter-repo is as simple as the following command:
```shell
  git filter-repo --path src/ --to-subdirectory-filter my-module --tag-rename '':'my-module-'
```
(the single quotes are unnecessary, but make it clearer to a human that we
are replacing the empty string as a prefix with `my-module-`)

## Solving this with BFG Repo Cleaner

BFG Repo Cleaner is not capable of this kind of rewrite; in fact, all
three types of wanted changes are outside of its capabilities.

## Solving this with filter-branch

filter-branch comes with a pile of caveats (more on that below) even
once you figure out the necessary invocation(s):

```shell
  git filter-branch \
      --tree-filter 'mkdir -p my-module && \
                     git ls-files \
                         | grep -v ^src/ \
                         | xargs git rm -f -q && \
                     ls -d * \
                         | grep -v my-module \
                         | xargs -I files mv files my-module/' \
          --tag-name-filter 'echo "my-module-$(cat)"' \
	  --prune-empty -- --all
  git clone file://$(pwd) newcopy
  cd newcopy
  git for-each-ref --format="delete %(refname)" refs/tags/ \
      | grep -v refs/tags/my-module- \
      | git update-ref --stdin
  git gc --prune=now
```

Some might notice that the above filter-branch invocation will be really
slow due to using --tree-filter; you could alternatively use the
--index-filter option of filter-branch, changing the above commands to:

```shell
  git filter-branch \
      --index-filter 'git ls-files \
                          | grep -v ^src/ \
                          | xargs git rm -q --cached;
                      git ls-files -s \
                          | sed "s%$(printf \\t)%&my-module/%" \
                          | git update-index --index-info;
                      git ls-files \
                          | grep -v ^my-module/ \
                          | xargs git rm -q --cached' \
      --tag-name-filter 'echo "my-module-$(cat)"' \
      --prune-empty -- --all
  git clone file://$(pwd) newcopy
  cd newcopy
  git for-each-ref --format="delete %(refname)" refs/tags/ \
      | grep -v refs/tags/my-module- \
      | git update-ref --stdin
  git gc --prune=now
```

However, for either filter-branch command there are a pile of caveats.
First, some may be wondering why I list five commands here for
filter-branch.  Despite the use of --all and --tag-name-filter, and
filter-branch's manpage claiming that a clone is enough to get rid of
old objects, the extra steps to delete the other tags and do another
gc are still required to clean out the old objects and avoid mixing
new and old history before pushing somewhere.  Other caveats:
  * Commit messages are not rewritten; so if some of your commit
    messages refer to prior commits by (abbreviated) sha1, after the
    rewrite those messages will now refer to commits that are no longer
    part of the history.  It would be better to rewrite those
    (abbreviated) sha1 references to refer to the new commit ids.
  * The --prune-empty flag sometimes misses commits that should be
    pruned, and it will also prune commits that *started* empty rather
    than just ended empty due to filtering.  For repositories that
    intentionally use empty commits for versioning and publishing
    related purposes, this can be detrimental.
  * The commands above are OS-specific.  GNU vs. BSD issues for sed,
    xargs, and other commands often trip up users; I think I failed to
    get most folks to use --index-filter since the only example in the
    filter-branch manpage that both uses it and shows how to move
    everything into a subdirectory is linux-specific, and it is not
    obvious to the reader that it has a portability issue since it
    silently misbehaves rather than failing loudly.
  * The --index-filter version of the filter-branch command may be two to
    three times faster than the --tree-filter version, but both
    filter-branch commands are going to be multiple orders of magnitude
    slower than filter-repo.
  * Both commands assume all filenames are composed entirely of ascii
    characters (even special ascii characters such as tabs or double
    quotes will wreak havoc and likely result in missing files or
    misnamed files)

## Solving this with fast-export/fast-import

One can kind of hack this together with something like:

```shell
  git fast-export --no-data --reencode=yes --mark-tags --fake-missing-tagger \
      --signed-tags=strip --tag-of-filtered-object=rewrite --all \
      | grep -vP '^M [0-9]+ [0-9a-f]+ (?!src/)' \
      | grep -vP '^D (?!src/)' \
      | perl -pe 's%^(M [0-9]+ [0-9a-f]+ )(.*)$%\1my-module/\2%' \
      | perl -pe 's%^(D )(.*)$%\1my-module/\2%' \
      | perl -pe s%refs/tags/%refs/tags/my-module-% \
      | git -c core.ignorecase=false fast-import --date-format=raw-permissive \
            --force --quiet
  git for-each-ref --format="delete %(refname)" refs/tags/ \
      | grep -v refs/tags/my-module- \
      | git update-ref --stdin
  git reset --hard
  git reflog expire --expire=now --all
  git gc --prune=now
```

But this comes with some nasty caveats and limitations:
  * The various greps and regex replacements operate on the entire
    fast-export stream and thus might accidentally corrupt unintended
    portions of it, such as commit messages.  If you needed to edit
    file contents and thus dropped the --no-data flag, it could also
    end up corrupting file contents.
  * This command assumes all filenames in the repository are composed
    entirely of ascii characters, and also exclude special characters
    such as tabs or double quotes.  If such a special filename exists
    within the old src/ directory, it will be pruned even though it
    was intended to be kept.  (In slightly different repository
    rewrites, this type of editing also risks corrupting filenames
    with special characters by adding extra double quotes near the end
    of the filename and in some leading directory name.)
  * This command will leave behind huge numbers of useless empty
    commits, and has no realistic way of pruning them.  (And if you
    tried to combine this technique with another tool to prune the
    empty commits, then you now have no way to distinguish between
    commits which were made empty by the filtering that you want to
    remove, and commits which were empty before the filtering process
    and which you thus may want to keep.)
  * Commit messages which reference other commits by hash will now
    reference old commits that no longer exist.  Attempting to edit
    the commit messages to update them is extraordinarily difficult to
    add to this kind of direct rewrite.

# Design rationale behind filter-repo

None of the existing repository filtering tools did what I wanted;
they all came up short for my needs.  No tool provided any of the
first eight traits below I wanted, and all failed to provide at least
one of the last four traits as well:

  1. [Starting report] Provide user an analysis of their repo to help
     them get started on what to prune or rename, instead of expecting
     them to guess or find other tools to figure it out.  (Triggered, e.g.
     by running the first time with a special flag, such as --analyze.)

  1. [Keep vs. remove] Instead of just providing a way for users to
     easily remove selected paths, also provide flags for users to
     only *keep* certain paths.  Sure, users could workaround this by
     specifying to remove all paths other than the ones they want to
     keep, but the need to specify all paths that *ever* existed in
     **any** version of the repository could sometimes be quite
     painful.  For filter-branch, using pipelines like `git ls-files |
     grep -v ... | xargs -r git rm` might be a reasonable workaround
     but can get unwieldy and isn't as straightforward for users; plus
     those commands are often operating-system specific (can you spot
     the GNUism in the snippet I provided?).

  1. [Renaming] It should be easy to rename paths.  For example, in
     addition to allowing one to treat some subdirectory as the root
     of the repository, also provide options for users to make the
     root of the repository just become a subdirectory.  And more
     generally allow files and directories to be easily renamed.
     Provide sanity checks if renaming causes multiple files to exist
     at the same path.  (And add special handling so that if a commit
     merely copied oldname->newname without modification, then
     filtering oldname->newname doesn't trigger the sanity check and
     die on that commit.)

  1. [More intelligent safety] Writing copies of the original refs to
     a special namespace within the repo does not provide a
     user-friendly recovery mechanism.  Many would struggle to recover
     using that.  Almost everyone I've ever seen do a repository
     filtering operation has done so with a fresh clone, because
     wiping out the clone in case of error is a vastly easier recovery
     mechanism.  Strongly encourage that workflow by [detecting and
     bailing if we're not in a fresh
     clone](https://htmlpreview.github.io/?https://github.com/newren/git-filter-repo/blob/docs/html/git-filter-repo.html#FRESHCLONE),
     unless the user overrides with --force.

  1. [Auto shrink] Automatically remove old cruft and repack the
     repository for the user after filtering (unless overridden); this
     simplifies things for the user, helps avoid mixing old and new
     history together, and avoids problems where the multi-step
     process for shrinking the repo documented in the manpage doesn't
     actually work in some cases.  (I'm looking at you,
     filter-branch.)

  1. [Clean separation] Avoid confusing users (and prevent accidental
     re-pushing of old stuff) due to mixing old repo and rewritten
     repo together.  (This is particularly a problem with filter-branch
     when using the --tag-name-filter option, and sometimes also an
     issue when only filtering a subset of branches.)

  1. [Versatility] Provide the user the ability to extend the tool or
     even write new tools that leverage existing capabilities, and
     provide this extensibility in a way that (a) avoids the need to
     fork separate processes (which would destroy performance), (b)
     avoids making the user specify OS-dependent shell commands (which
     would prevent users from sharing commands with each other), (c)
     takes advantage of rich data structures (because hashes, dicts,
     lists, and arrays are prohibitively difficult in shell) and (d)
     provides reasonable string manipulation capabilities (which are
     sorely lacking in shell).

  1. [Old commit references] Provide a way for users to use old commit
     IDs with the new repository (in particular via mapping from old to
     new hashes with refs/replace/ references).

  1. [Commit message consistency] If commit messages refer to other
     commits by ID (e.g. "this reverts commit 01234567890abcdef", "In
     commit 0013deadbeef9a..."), those commit messages should be
     rewritten to refer to the new commit IDs.

  1. [Become-empty pruning] Commits which become empty due to filtering
     should be pruned.  If the parent of a commit is pruned, the first
     non-pruned ancestor needs to become the new parent.  If no
     non-pruned ancestor exists and the commit was not a merge, then it
     becomes a new root commit.  If no non-pruned ancestor exists and
     the commit was a merge, then the merge will have one less parent
     (and thus make it likely to become a non-merge commit which would
     itself be pruned if it had no file changes of its own).  One
     special thing to note here is that we prune commits which become
     empty, NOT commits which start empty.  Some projects intentionally
     create empty commits for versioning or publishing reasons, and
     these should not be removed.  (As a special case, commits which
     started empty but whose parent was pruned away will also be
     considered to have "become empty".)

  1. [Become-degenerate pruning] Pruning of commits which become empty
     can potentially cause topology changes, and there are lots of
     special cases.  Normally, merge commits are not removed since they
     are needed to preserve the graph topology, but the pruning of
     parents and other ancestors can ultimately result in the loss of
     one or more parents.  A simple case was already noted above: if a
     merge commit loses enough parents to become a non-merge commit and
     it has no file changes, then it too can be pruned.  Merge commits
     can also have a topology that becomes degenerate: it could end up
     with the merge_base serving as both parents (if all intervening
     commits from the original repo were pruned), or it could end up
     with one parent which is an ancestor of its other parent.  In such
     cases, if the merge has no file changes of its own, then the merge
     commit can also be pruned.  However, much as we do with empty
     pruning we do not prune merge commits that started degenerate
     (which indicates it may have been intentional, such as with --no-ff
     merges) but only merge commits that become degenerate and have no
     file changes of their own.

  1. [Speed] Filtering should be reasonably fast

# How do I contribute?

See the [contributing guidelines](Documentation/Contributing.md).

# Is there a Code of Conduct?

Participants in the filter-repo community are expected to adhere to
the same standards as for the git project, so the [git Code of
Conduct](https://git.kernel.org/pub/scm/git/git.git/tree/CODE_OF_CONDUCT.md)
applies.

# Upstream Improvements

Work on filter-repo and [its
predecessor](https://public-inbox.org/git/51419b2c0904072035u1182b507o836a67ac308d32b9@mail.gmail.com/)
has also driven numerous improvements to fast-export and fast-import
(and occasionally other commands) in core git, based on things
filter-repo needs to do its work:

  * git-2.28.0
    * [fast-import: add new --date-format=raw-permissive format](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=d42a2fb72f)
  * git-2.24.0
    * [fast-export: handle nested tags](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=941790d7de)
    * [t9350: add tests for tags of things other than a commit](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=8d7d33c1ce)
    * [fast-export: allow user to request tags be marked with --mark-tags](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=a1638cfe12)
    * [fast-export: add support for --import-marks-if-exists](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=208d69246e)
    * [fast-import: add support for new 'alias' command](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=b8f50e5b60)
    * [fast-import: allow tags to be identified by mark labels](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=f73b2aba05)
    * [fast-import: fix handling of deleted tags](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=3164e6bd24)
    * [fast-export: fix exporting a tag and nothing else](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=af2abd870b)
    * [git-fast-import.txt: clarify that multiple merge commits are allowed](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=d1387d3895)
  * git-2.23.0
    * [t9350: fix encoding test to actually test reencoding](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=32615ce762)
    * [fast-import: support 'encoding' commit header](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=3edfcc65fd)
    * [fast-export: avoid stripping encoding header if we cannot reencode](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=ccbfc96dc4)
    * [fast-export: differentiate between explicitly UTF-8 and implicitly
      UTF-8](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=57a8be2cb0)
    * [fast-export: do automatic reencoding of commit messages only if
      requested](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=e80001f8fd)
  * git-2.22.0
    * [log,diff-tree: add --combined-all-paths option](
        https://git.kernel.org/pub/scm/git/git.git/commit/?id=d76ce4f734)
    * [t9300: demonstrate bug with get-mark and empty orphan commits](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=62edbec7de)
    * [git-fast-import.txt: fix wording about where ls command can appear](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=a63c54a019)
    * [fast-import: check most prominent commands first](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=5056bb7646)
    * [fast-import: only allow cat-blob requests where it makes sense](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=7ffde293f2)
    * [fast-import: fix erroneous handling of get-mark with empty orphan
      commits](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=cf7b857a77)
    * [Honor core.precomposeUnicode in more places](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=8e712ef6fc)
  * git-2.21.0
    * [fast-export: convert sha1 to oid](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=843b9e6d48)
    * [git-fast-import.txt: fix documentation for --quiet option](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=f55c979b14)
    * [git-fast-export.txt: clarify misleading documentation about rev-list
      args](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=4532be7cba)
    * [fast-export: use value from correct enum](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=b93b81e799)
    * [fast-export: avoid dying when filtering by paths and old tags exist](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=1f30c904b3)
    * [fast-export: move commit rewriting logic into a function for reuse](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=f129c4275c)
    * [fast-export: when using paths, avoid corrupt stream with non-existent
      mark](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=cd13762d8f)
    * [fast-export: ensure we export requested refs](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=fdf31b6369)
    * [fast-export: add --reference-excluded-parents option](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=530ca19c02)
    * [fast-import: remove unmaintained duplicate documentation](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=25dd3e4889)
    * [fast-export: add a --show-original-ids option to show
      original names](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=a965bb3116)
    * [git-show-ref.txt: fix order of flags](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=bd8d6f0def)
  * git-2.20.0
    * [update-ref: fix type of update_flags variable to
      match its usage](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=e4c34855a2)
    * [update-ref: allow --no-deref with --stdin](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=d345e9fbe7)
  * git-1.7.3
    * [fast-export: Fix dropping of files with --import-marks and path
      limiting](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=4087a02e45)
    * [fast-export: Add a --full-tree option](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=7f40ab0916)
    * [fast-export: Fix output order of D/F changes](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=060df62422)
    * [fast-import: Improve robustness when D->F changes provided in wrong
      order](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=253fb5f889)
  * git-1.6.4:
    * [fast-export: Set revs.topo_order before calling setup_revisions](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=668f3aa776)
    * [fast-export: Omit tags that tag trees](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=02c48cd69b)
    * [fast-export: Make sure we show actual ref names instead of "(null)"](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=2374502c6c)
    * [fast-export: Do parent rewriting to avoid dropping relevant commits](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=32164131db)
    * [fast-export: Add a --tag-of-filtered-object option for newly
      dangling tags](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=2d8ad46919)
    * [Add new fast-export testcases](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=25e0ca5dd6)
    * [fast-export: Document the fact that git-rev-list arguments are
      accepted](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=8af15d282e)
  * git-1.6.3:
    * [git-filter-branch: avoid collisions with variables in eval'ed
      commands](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=d5b0c97d13)
    * [Correct missing SP characters in grammar comment at top of
      fast-import.c](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=98e1a4186a)
    * [fast-export: Avoid dropping files from commits](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=ebeec7dbc5)
  * git-1.6.1.4:
    * [fast-export: ensure we traverse commits in topological order](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=784f8affe4)
