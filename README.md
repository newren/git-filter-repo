git filter-repo is a tool for rewriting history, which includes [some
capabilities I have not found anywhere
else](#design-rationale-behind-filter-repo-why-create-a-new-tool).  It is
most similar to [git
filter-branch](https://git-scm.com/docs/git-filter-branch), though it fixes
what I perceive to be some glaring deficiencies in that tool and brings a
much different taste in usability.  Also, being based on
fast-export/fast-import, it is [orders of magnitude
faster](https://public-inbox.org/git/CABPp-BGOz8nks0+Tdw5GyGqxeYR-3FF6FT5JcgVqZDYVRQ6qog@mail.gmail.com/).

filter-repo is a single-file python script, depending only on the
python standard library (and execution of git commands), all of which
is designed to make build/installation trivial: just copy it into your
$PATH.

# Table of Contents

  * [Why filter-repo instead of filter-branch?](#why-filter-repo-instead-of-filter-branch)
  * [Example usage, comparing to filter-branch](#example-usage-comparing-to-filter-branch)
  * [Design rationale behind filter-repo](#design-rationale-behind-filter-repo-why-create-a-new-tool)
  * [Usage](#usage)

# Background

## Why filter-repo instead of filter-branch?

filter-branch has a number of problems:

  * filter-branch is extremely to unusably slow (multiple orders of
    magnitude slower than it should be) for non-trivial repositories.

  * filter-branch made a number of usability choices that are okay for
    small repos, but these choices sometimes conflict as more options
    are combined, and the overall usability often causes difficulties
    for users trying to work with intermediate or larger repos.

  * filter-branch is missing some basic features.

The first two are intrinsic to filter-branch's design at this point
and cannot be backward-compatibly fixed.


## Example usage, comparing to filter-branch

Let's say that we want to extract a piece of a repository, with the intent
on merging just that piece into some other bigger repo.  We also want to know
how much smaller this extracted repo is without the binary-blobs/ directory
in it.  For extraction, we want to:

  * extract the history of a single directory, src/.  This means that only
    paths under src/ remain in the repo, and any commits that only touched
    paths outside this directory will be removed.
  * rename all files to have a new leading directory, my-module/ (e.g. so that
    src/foo.c becomes my-module/src/foo.c)
  * rename any tags in the extracted repository to have a 'my-module-'
    prefix (to avoid any conflicts when we later merge this repo into
    something else)

Doing this with filter-repo is as simple as the following command:
```shell
  git filter-repo --path src/ --to-subdirectory-filter my-module --tag-rename '':'my-module-'
```
(the single quotes are unnecessary, but make it clearer to a human that we
are replacing the empty string as a prefix with `my-module-`)

By contrast, filter-branch comes with a pile of caveats (more on that
below) even once you figure out the necessary invocation(s):

```shell
  git filter-branch --tree-filter 'mkdir -p my-module && git ls-files | grep -v ^src/ | xargs git rm -f -q && ls -d * | grep -v my-module | xargs -I files mv files my-module/' --tag-name-filter 'echo "my-module-$(cat)"' --prune-empty -- --all
  git clone file://$(pwd) newcopy
  cd newcopy
  git for-each-ref --format="delete %(refname)" refs/tags/ | grep -v refs/tags/my-module- | git update-ref --stdin
  git gc --prune=now
```

Some might notice that the above filter-branch invocation will be really
slow due to using --tree-filter; you could alternatively use the
--index-filter option of filter-branch, changing the above commands to:

```shell
  git filter-branch --index-filter 'git ls-files | grep -v ^src/ | xargs git rm -q --cached; git ls-files -s | sed "s-$(printf \\t)-&my-module/-" | git update-index --index-info; git ls-files | grep -v ^my-module/ | xargs git rm -q --cached' --tag-name-filter 'echo "my-module-$(cat)"' --prune-empty -- --all
  git clone file://$(pwd) newcopy
  cd newcopy
  git for-each-ref --format="delete %(refname)" refs/tags/ | grep -v refs/tags/my-module- | git update-ref --stdin
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
    rewrite those messages will no refer to commits that are no longer
    part of the history.  It would be better to rewrite those
    (abbreviated) sha1 references to refer to the new commit ids.
  * The --prune-empty flag sometimes missing commits that should be
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


## Design rationale behind filter-repo (why create a new tool?)

None of the existing repository filtering tools do what I want.  They're
all good in their own way, but come up short for my needs.  No tool
provided any of the first eight traits below I wanted, and all failed to
provide at least one of the last four traits as well:

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
     merely renamed oldname->newname, then filtering oldname->newname
     doesn't trigger the sanity check and die on that commit.)

  1. [More intelligent safety] Writing copies of the original refs to
     a special namespace within the repo does not provide a
     user-friendly recovery mechanism.  Many would struggle to recover
     using that.  Almost everyone I've ever seen do a repository
     filtering operation has done so with a fresh clone, because
     wiping out the clone in case of error is a vastly easier recovery
     mechanism.  Strongly encourage that workflow by detecting and
     bailing if we're not in a fresh clone, unless the user overrides
     with --force.  (Allow the old filter-branch workflow if a special
     --store-backup flag is provided.)

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


# Usage

Run `git filter-repo -h`; more detailed docs will be added soon...
