git filter-repo is a tool for rewriting history, which includes some
capabilities I have not found anywhere else.  It is most similar to
[git filter-branch](https://git-scm.com/docs/git-filter-branch),
though it fixes what I perceive to be some glaring deficiencies in
that tool and brings a much different taste in usability.  Also, being
based on fast-export/fast-import, it is orders of magnitude faster (it
has speed roughly comparable to BFG repo cleaner, but isn't
multi-threaded).

filter-repo is a single-file python script, depending only on the
python standard library (and execution of git commands), all of which
is designed to make build/installation trivial: just copy it into your
$PATH.

# Table of Contents

  * Background
    * [Why create another repo filtering tool?](#why-git-filter-repo)
    * [Warnings: Not yet ready for external usage](
      #warnings-not-yet-ready-for-external-usage)
    * [Why not $FAVORITE_COMPETITOR](#why-not-favorite_competitor)
  * [Usage](#usage)

# Background

## Why git-filter-repo?

None of the [existing repository filtering
tools](#why-not-favorite_competitor) do what I want.  They're all good
in their own way, but come up short for my needs.  In no particular order:

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

  1. [Commit message consistency] If commit messages refer to other
     commits by ID (e.g. "this reverts commit 01234567890abcdef", "In
     commit 0013deadbeef9a..."), those commit messages should be
     rewritten to refer to the new commit IDs.

  1. [Empty pruning] Commits which become empty due to filtering
     should be pruned.  Note that pruning of commits which become
     empty can potentially cause topology changes, and there are lots
     of special cases.  The most basic is that if the parent of a
     commit is pruned, the first non-pruned ancestor needs to become
     the new parent; if no non-pruned ancestor exists, the commit
     becomes a new root commit.  Normally, merge commits are not
     removed since they are needed to preserve the graph topology, but
     the pruning of parents and other ancestors can ultimately result
     in the loss of one or more parents.  If a merge commit loses
     enough parents to become a non-merge commit and it has no file
     changes, then it too can be pruned.  Topology changes are also
     possible if the entire non-first-parent history is pruned away;
     rather than having that parent of the merge be rewritten to the
     merge base, it may (depending on whether the merge also had file
     changes of its own) instead make sense to just prune that parent.
     (We do not want to prune away a first parent being rewritten to
     the merge base since some projects prefer --no-ff merges, though
     this could be made an option.)  Finally, note that we originally
     talked not about pruning empty commits, but about pruning commits
     which become empty.  Some projects intentionally create empty
     commits for versioning or publishing reasons, and these should
     not be removed.  Instead, only commits which become empty should
     be pruned.  (As a special case, commits which started empty but
     originally had a parent and which become a root commit due to the
     pruning of other commits will also be considered to have "become
     empty".)

  1. [Speed] Filtering should be reasonably fast

## Warnings: Not yet ready for external usage

This repository is still under heavy construction.  Some caveats:

  * It will not work without a specially compiled version of git:
    * git clone --branch fast-export-import-improvements https://github.com/newren/git/
    * Build according to normal git.git build instructions.  You can find 'em.
  * I have a list of known bugs, conveniently mostly tracked in my head.
    I'll fix that, but the fact that you're reading this sentence means
    I haven't yet.
  * Actually, there's a couple exceptions to where bugs are tracked mentioned
    above.  In particular, the following bugs are tracked here:
    * Multiple unimplemented placeholder option flags exist.  Just because it
      shows up in --help doesn't mean it does anything.
    * Usage instructions and examples at the end of this document are rather
      lacking.
    * Random debugging code or extraneous files might be checked in at any
      given time; I'll probably rewrite history to remove them...eventually.
  * I reserve the right to:
    * Rename the tool altogether (filter-repo to be like filter-branch?)
    * Rename or redefine any command line options
    * Rewrite the history of this repository at any time
  * and possibly more...but do you really need any more reasons than
    the above?  This isn't ready for widespread use.

## Why not $FAVORITE_COMPETITOR?

Here are some of the prominent competitors I know of:
  * git_fast_filter.py (Original link dead, use google if you care; this repo
    is the successor, though.)
  * [reposurgeon](http://www.catb.org/esr/reposurgeon/)
  * [BFG repo cleaner](https://rtyley.github.io/bfg-repo-cleaner/)
  * [git filter-branch](https://mirrors.edge.kernel.org/pub/software/scm/git/docs/git-filter-branch.html)

Here's why I think these tools don't meet my needs:

  * git_fast_filter.py:
    * This was actually the basis for filter-repo, though it required lots of
      additional work.
    * Was meant as a library more than a tool, and had too high of an
      activation energy.
    * empty commit pruning was not as thorough as it should have been
    * had no provision for commit message rewriting for commit message
      consistency.
    * missing lots of little conveniences

  * reposurgeon
    * focused on converting repositories between version control systems,
      and handles all the crazy impedance mismatches inherent in such
      conversions.  I only care about rewriting history that starts in git
      and ends in git.  If you care about converting between version control
      systems, though, reposurgeon is a much better tool.
    * might be general enough to use for other uses, but can't find any
      documentation or examples on anything other than huge repository
      conversions between version control systems.
    * way too much effort for many simple repository rewrites that many
      users want to perform

  * BFG repo cleaner
    * Very focused on just removing crazy big files and sensitive data.
      Probably the best tool if that's all you want.  But lacks the ability
      to handle anything outside this special (but important!) usecase.
    * Has useful options for helping you remove the N biggest blobs, but
      nothing to help you know how big N should be.
    * Doesn't prune commits which become empty due to filtering; if you
      just want to extract a directory added 3 months ago and its history,
      you'd be stuck with years of commits touching other directories, all
      empty.
    * The refusal to rewrite HEAD, while it makes sense when trying to
      remove a few crazy big files and sensitive data (users tend to
      re-add and re-commit bad files if you didn't manually remove it
      and have them update), is totally misaligned with more general
      rewrite cases (e.g. the desire to turn a subdirectory into the
      root of a repository, or move the root of the repository into a
      subdirectory for merging into some other bigger repo.)
    * Telling the user how to shrink the repo afterwards seems lame since
      that was the whole point; just do it for them by default.

  * git filter-branch

    * Fundamental design flaw causing it to be orders of magnitude
      slower than it should be for most repo rewriting jobs.  So slow
      that it becomes a major usability impediment, if not a deal
      breaker.  However, it is _extremely_ versatile.
    * Generally quick for users to invoke (quick one-liners with lots
      of examples), just missing some useful capabilities like
      selecting wanted paths (as opposed to unwanted paths) and
      providing easier path renaming (also, e.g. no
      --to-subdirectory-filter as the opposite of
      --subdirectory-filter)
    * Doesn't rewrite commit hashes in commit messages, causing commit messages
      to refer to phantom commits instead.
    * Mixes old repository information (original tags, unrewritten branches)
      with new, risking re-pushing the old stuff
    * Lame defaults
      * --prune-empty should be default (although only commits which become
        empty, not ones which started empty)
      * allows user to mess with repos which aren't a clean clone without an
        override
      * Makes it very difficult to actually get rid of unwanted objects and
        shrink repository.  Long multi-step instructions in manpage for this,
        which are incomplete when --tag-name-filter is in use.

# Usage

Run `git filter-repo --help` and figure it out from there.  Good luck.
