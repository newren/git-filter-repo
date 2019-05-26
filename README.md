git filter-repo is a versatile tool for rewriting history, which includes
[capabilities I have not found anywhere
else](#design-rationale-behind-filter-repo-why-create-a-new-tool).  It
roughly falls into the same space of tool as [git
filter-branch](https://git-scm.com/docs/git-filter-branch) but without the
[capitulation-inducing poor
performance](https://public-inbox.org/git/CABPp-BGOz8nks0+Tdw5GyGqxeYR-3FF6FT5JcgVqZDYVRQ6qog@mail.gmail.com/),
and with a design that scales usability-wise beyond trivial rewriting
cases.

While most users will probably just use filter-repo as a simple command
line tool (and likely only use a few of its flags), at its core filter-repo
contains a library for creating history rewriting tools.  As such, users
with specialized needs can leverage it to quickly create entirely new
history rewriting tools.

filter-repo is a single-file python script, depending only on the python
standard library (and execution of git commands), all of which is designed
to make build/installation trivial: just copy it into your $PATH.

# Table of Contents

  * [Background](#background)
    * [Why filter-repo instead of filter-branch?](#why-filter-repo-instead-of-filter-branch)
    * [Example usage, comparing to filter-branch](#example-usage-comparing-to-filter-branch)
    * [Design rationale behind filter-repo](#design-rationale-behind-filter-repo-why-create-a-new-tool)
  * [Usage](#usage)
    * [The bigger picture](#the-bigger-picture)
    * [Examples](#examples)
      * [Path based filtering](#path-based-filtering)
      * [Content based filtering](#content-based-filtering)
      * [Refname based filtering](#refname-based-filtering)
      * [User and email based filtering](#user-and-email-based-filtering)
      * [Parent rewriting](#parent-rewriting)
      * [Callbacks](#callbacks)
      * [Using filter-repo as a library](#using-filter-repo-as-a-library)
  * [Internals](#internals)
    * [How filter-repo works](#how-filter-repo-works)
    * [Limitations](#limitations)
      * [Inherited limitations](#inherited-limitations)
      * [Intrinsic limitations](#intrinsic-limitations)
      * [Issues specific to filter-repo](#issues-specific-to-filter-repo)
      * [Comments on reversibility](#comments-on-reversibility)

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
     merely copied oldname->newname without modification, then
     filtering oldname->newname doesn't trigger the sanity check and
     die on that commit.)

  1. [More intelligent safety] Writing copies of the original refs to
     a special namespace within the repo does not provide a
     user-friendly recovery mechanism.  Many would struggle to recover
     using that.  Almost everyone I've ever seen do a repository
     filtering operation has done so with a fresh clone, because
     wiping out the clone in case of error is a vastly easier recovery
     mechanism.  Strongly encourage that workflow by detecting and
     bailing if we're not in a fresh clone, unless the user overrides
     with --force.

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

## The bigger picture

Using filter-repo is relatively simple, but rewriting history is part of a
larger discussion in terms of collaboration.  When you rewrite history, the
old and new histories are no longer compatible; if you push this history
somewhere for others to view, it will look as though you've done a rebase
of all branches and tags.  Make sure you are familiar with the ["Recovering
from upstream rebase" section of
git-rebase(1)](https://git-scm.com/docs/git-rebase#_recovering_from_upstream_rebase)
(and in particular, "The hard case") before proceeding, in addition to this
section.

Steps to use filter-repo as part of the bigger picture of doing a history
rewrite are roughly as follows:

  1. Create a clone of your repository (if you created special refs outside
     of refs/heads/ or refs/tags/, make sure to fetch those too).  Note
     that `--bare` and `--mirror` clones are supported too, if you prefer.

  1. (Optional) Run `git filter-repo --analyze`.  This will create a
     directory of reports mentioning renames that have occurred in your
     repo and also listing sizes of objects aggregated by
     path/directory/extension/blob-id; this information may be useful in
     choosing how to filter your repo.  It can also be useful to re-run
     --analyze after filtering to verify the changes look correct.

  1. Run filter-repo with your desired filtering options.  Many examples
     are given below.  For more complex cases, note that doing the
     filtering in multiple steps (by running multiple filter-repo
     invocations in a sequence) is supported.  If anything goes wrong here,
     simply delete your clone and restart.

  1. Push your new repository to its new home (note that
     refs/remotes/origin/* will have been moved to refs/heads/* as the
     first part of filter-repo, so you can just deal with normal branches
     instead of remote tracking branches).  While you can force push this
     to the same URL you cloned from, there are good reasons to consider
     pushing to a different location instead:

     1. People who cloned from the original repo will have old history.
        When they fetch the new history you force pushed up, unless they do
        a `git reset --hard @{u}` on their branches or rebase their local
        work, git will think they have hundreds or thousands of commits
        with very similar commit messages as what exist upstream (but which
        include files you wanted excised from history), and allow the user
        to merge the two histories, resulting in what looks like two copies
        of each commit.  If they then push this history back up, then
        everyone now has history with two copies of each commit and the bad
        files have returned.  You're more likely to succeed in forcing
        people to get rid of the old history if they have to clone a new
        URL.

     1. Rewriting history will rewrite tags; those who have already
        downloaded tags will not get the updated tags by default (see the
        ["On Re-tagging" section of the
        git-tag(1)](https://git-scm.com/docs/git-tag#_on_re_tagging)
        manpage).  Every user trying to use an existing clone will have to
	forcibly delete all tags and re-fetch them; it may be easier for
	them to just re-clone, which they are more likely to do with a new
	clone URL.

     1. Rewriting history may delete some refs (e.g. branches that only had
        files that you wanted excised from history); unless you run git
        push with the `--mirror` or `--prune` options, those refs will
        continue to exist on the server.  If folks then merge these
        branches into others, then people have started mixing old and new
        history.  If users had already cloned these branches, removing them
        from the server isn't enough; you need all users to delete any
        local branches based on these refs and run fetch with the `--prune`
        option as well.  Simply re-cloning from a new URL is easier.

     1. The server may not allow you to force push over some refs.  For
        example, code review systems may have special ref namespaces
        (e.g. refs/changes/, refs/pull/, refs/merge-requests/) that they
        have locked down.

  1. (Optional) Some additional considerations

     1. filter-repo by default creates replace refs (see
        [git-replace(1)](https://git-scm.com/docs/git-replace)) for each
        rewritten commit ID, allowing you to use old (unabbreviated) commit
        hashes to refer to the newly rewritten commits.  If you want to use
        these replace refs, push them to the relevant clone URL and tell
        users to adjust their fetch refspec (e.g. `git config --add
        remote.origin.fetch +refs/replace/*:refs/replace/*`) Sadly, some
        existing git servers (e.g. Gerrit, GitHub) do not yet understand
        replace refs, and thus one can't use old commit hashes within their
        UI; this may change in the future.  But replace refs at least help
        users locally within the git CLI.

     1. If you have a central repo, you may want to prevent people from
        pushing old commit IDs, in order to avoid mixing old and new
        history.  Every repository manager does this differently, some
        provide [specialized
        commands](https://gerrit-review.googlesource.com/Documentation/cmd-ban-commit.html),
        others require you to write hooks.

## Examples

### Path based filtering

To only keep the 'README.md' file plus the directories 'guides' and
'tools/releases/':

```shell
  git filter-repo --path README.md --path guides/ --path tools/releases
```

Directory names can be given with or without a trailing slash, and all
filenames are relative to the toplevel of the repo.  To keep all files
except these paths, just add `--invert-paths`:

```shell
  git filter-repo --path README.md --path guides/ --path tools/releases --invert-paths
```

If you want to have both an inclusion filter and an exclusion filter, just
run filter-repo multiple times.  For example, to keep the src/main
subdirectory but exclude files under src/main named 'data', run:

```shell
  git filter-repo --path src/main/
  git filter-repo --path-glob 'src/*/data' --invert-paths
```

Note that the asterisk ('*') will match across multiple directories, so the
second command would remove e.g. src/main/org/whatever/data.  Also, the
second command by itself would also remove e.g. src/not-main/foo/data, but
since src/not-main/ was removed by the first command, that's not an issue.
Also, the use of quotes around the asterisk is sometimes important to avoid
glob expansion by the shell.

You can also select paths by [regular
expression](https://docs.python.org/3/library/re.html#regular-expression-syntax).
For example, to only include files from the repo whose name is in the
format YYYY-MM-DD.txt and is found at least two subdirectories deep:

```shell
  git filter-repo --path-regex '^.*/.*/[0-9]{4}-[0-9]{2}-[0-9]{2}.txt$'
```

If you want two directories to be renamed (and maybe merged if both are
renamed to the same location), use --path-rename; for example, to rename
both 'cmds/' and 'src/scripts/' to 'tools/':

```shell
  git filter-repo --path-rename cmds:tools --path-rename src/scripts/:tools/
```

As with `--path`, directories can be specified with or without a
trailing slash for `--path-rename`.

If you do a `--path-rename` to something that was already in use, it will
be silently overwritten.  However, if you try to rename multiple files to
the same location (e.g. src/scripts/run_release.sh and cmds/run_release.sh
both existed and had different content with the renames above), then you
will be given an error.  If you have such a case, you may want to add
another rename command to move one of the paths somewhere else where it
won't collide:

```shell
  git filter-repo --path-rename cmds/run_release.sh:tools/do_release.sh \
                  --path-rename cmds/:tools/ \
                  --path-rename src/scripts/:tools/
```

Also, `--path-rename` brings up ordering issues; all path arguments are
applied in order.  Thus, a command like

```shell
  git filter-repo --path-rename sources/:src/main/ --path src/main/
```

would make sense but reversing the two arguments would not (src/main/ is
created by the rename so reversing the two would give you an empty repo).
Also, note that the rename of cmds/run_release.sh a couple examples ago was
done before the other renames.

If you prefer to filter based solely on basename, use the `--use-base-name`
flag (though this is incompatible with --path-rename).  For example, to
only include README.md and Makefile files from any directory:

```shell
  git filter-repo --use-base-name --path README.md --path Makefile
```

If you wanted to delete all .DS_Store files in any directory, you could
either use:

```shell
  git filter-repo --invert-paths --path '.DS_Store' --use-base-name
```

or

```shell
  git filter-repo --invert-paths --path-glob '*/.DS_Store' --path '.DS_Store'
```

(the `--path-glob` isn't sufficient by itself as it might miss a toplevel
.DS_Store file; further while something like `--path-glob '*.DS_Store'`
would workaround that problem it would also grab files named 'foo.DS_Store'
or 'bar/baz.DS_Store')

If you have a long list of files, directories, globs, or regular
expressions to filter on, you can stick them in a file and use
`--paths-from-file`; for example, with a file named stuff-i-want.txt with
contents of

```
README.md
guides/
tools/releases
glob:*.py
regex:^.*/.*/[0-9]{4}-[0-9]{2}-[0-9]{2}.txt$
tools/==>scripts/
regex:(.*)/([^/]*)/([^/]*)\.text$==>\2/\1/\3.txt
```

then you could run
```shell
  git filter-repo --paths-from-file stuff-i-want.txt
```

to get a repo containing only the toplevel README.md file, the guides/ and
tools/releases/ directories, all python files, files whose name was of the
form YYYY.MM-DD.txt at least two subdirectories deep, and would rename
tools/ to scripts/ and rename files like foo/bar/baz/bleh.text to
baz/foo/bar/bleh.txt.  Note the special line prefixes of `glob:` and
`regex:` and the special string `==>` denoting renames.

Finally, see also the `--filename-callback` from the [callbacks
section](#callbacks).

### Content based filtering

If you want to filter out all files bigger than a certain size, you can use
`--strip-blobs-bigger-than` with some size (K, M, and G suffixes are
recognized), e.g.:

```shell
  git filter-repo --strip-blobs-bigger-than 10M
```

If you want to strip out all files with specified git object ids (hashes),
list the hashes in a file and run

```shell
  git filter-repo --strip-blobs-with-ids FILE_WITH_GIT_BLOB_IDS
```

If you want to modify file contents, you can do so based on a list of
expressions in a file, one per line.  For example, with a file named
expressions.txt containing
```
p455w0rd
foo==>bar
glob:*666*==>
regex:\bdriver\b==>pilot
literal:MM/DD/YYYY=>YYYY-MM-DD
regex:([0-9]{2})/([0-9]{2})/([0-9]{4})==>\3-\1-\2
```

then running
```shell
  git filter-repo --replace-text expressions.txt
```

will go through and replace `p455w0rd` with `***REMOVED***`, `foo` with
`bar`, any line containing `666` with a blank line, the word `driver` with
`pilot` (but not if it has letters before or after; e.g. `drivers` will be
unmodified), replace the exact text `MM/DD/YYYY` with `YYYY-MM-DD` and
replace date strings of the form MM/DD/YYYY with ones of the form
YYYY-MM-DD.  In the expressions file, there are a few things to note:

  * Every line has a replacement, given by whatever is on the right of
    `==>`.  If `==>` does not appear on the line, the default replacement
    is `***REMOVED***`.
  * Lines can start with `literal:`, `glob:`, or `regex:` to specify
    whether to do literal string matches,
    [globs](https://docs.python.org/3/library/fnmatch.html), or [regular
    expressions](https://docs.python.org/3/library/re.html#regular-expression-syntax).
    If none of these are specified, `literal:` is assumed.
  * globs and regexes are applied to each line of the file; it is not
    possible with --replace-text to match a multi-line string.
  * If multiple matches are found on a line, all are replaced.

See also the `--blob-callback` from the [callbacks section](#callbacks).

### Refname based filtering

To rename tags, use `--tag-rename`, e.g.:

```shell
  git filter-repo --tag-rename foo:bar
```

This will rename any tags starting with `foo` to now start with `bar`.
Either side of the colon could be blank, e.g.

```shell
  git filter-repo --tag-rename '':'my-module-'
```

For more general refname modification, see `--refname-callback` from
the [callbacks section](#callbacks).

### User and email based filtering

To modify username and emails of commits, you can create a [mailmap
file](https://git-scm.com/docs/git-shortlog#_mapping_authors) in the
format accepted by
[git-shortlog(1)](https://git-scm.com/docs/git-shortlog).  For example,
if you have a file named my-mailmap you can run

```shell
  git filter-repo --mailmap my-mailmap
```

and if the current contents of that file are as follows (if the
specified mailmap file is version controlled, historical versions of
the file are ignored):

```
Name For User <email@addre.ss>
<new@ema.il> <old1@ema.il>
New Name And <new@ema.il> <old2@ema.il>
New Name And <new@ema.il> Old Name And <old3@ema.il>
```

then we can update username and/or emails based on the specified
mapping.

See also the `--name-callback` and `--email-callback` from the
[callbacks section](#callbacks).

### Parent rewriting

To replace $commit_A with $commit_B (e.g. make all commits which had
$commit_A as a parent instead have $commit_B for that parent), and
rewrite history to make it permanent:

```shell
  git replace $commit_A $commit_B
  git filter-repo --force
```

To create a new commit with the same contents as $commit_A except with
different parent(s) and then replace $commit_A with the new commit,
and rewrite history to make it permanent:

```shell
  git replace --graft $commit_A $new_parent_or_parents
  git filter-repo --force
```

The reason to specify --force is two-fold: filter-repo will error out
if no arguments are specified, and the new graft commit would
otherwise trigger the not-a-fresh-clone check.

### Callbacks

For flexibility, filter-repo allows you to specify functions on the
command line to further filter all changes.  Please note that there
are some [API compatibility
caveats](https://github.com/newren/git-filter-repo/blob/develop/git-filter-repo#L13-L30)
associated with these callbacks that you should be aware of before
using them.

All callback functions are of the same general format.  For a command line
argument like
```shell
  --foo-callback 'BODY'
```

the following code will be compiled and called:
```python
  def foo_callback(foo):
    BODY
```

Thus, you just need to make sure your _BODY_ modifies and returns
_foo_ appropriately.  One important thing to note for all callbacks is
that filter-repo uses
[bytestrings](https://docs.python.org/3/library/stdtypes.html#bytes)
everywhere instead of strings.

There are three callbacks that allow you to operate directly on raw
objects that contain data that's easy to write in [fast-import(1)
format](https://git-scm.com/docs/git-fast-import#_input_format):
```
  --blob-callback
  --commit-callback
  --tag-callback
  --reset-callback
```

We'll come back to these later because it is often the case that the
other callbacks are more convenient.  The other callbacks operate on a
small piece of the raw objects or operate on pieces across multiple
types of raw object (e.g. author names and committer names and tagger
names across commits and tags, or refnames across commits, tags, and
resets, or messages across commits and tags).  The convenience
callbacks are:
```
  --filename-callback
  --message-callback
  --name-callback
  --email-callback
  --refname-callback
```
in each you are expected to simply return a new value based on the one
passed in.  For example,

```shell
  git-filter-repo --name-callback 'return name.replace(b"Wiliam", b"William")'
```
would result in the following function being called:
```python
  def name_callback(name):
    return name.replace(b"Wiliam", b"William")
```

The email callback is quite similar:
```shell
  git-filter-repo --email-callback 'return email.replace(b".cm", b".com")'
```

The refname callback is also similar, but note that the refname passed in
and returned are expected to be fully qualified (e.g. b"refs/heads/master"
instead of just b"master" and b"refs/tags/v1.0.7" instead of b"1.0.7"):
```shell
  git-filter-repo --refname-callback '
    # Change e.g. refs/heads/master to refs/heads/prefix-master
    rdir,rpath = os.path.split(refname)
    return rdir + b"/prefix-" + rpath'
```

The message callback is quite similar to the previous three callbacks,
though it operates on a bytestring that is likely more than one line:
```shell
  git-filter-repo --message-callback '
    if b"Signed-off-by:" not in message:
      message += b"\nSigned-off-by: Me My <self@and.eye>"
    return re.sub(b"[Ee]-?[Mm][Aa][Ii][Ll]", b"email", message)'
```

The filename callback is slightly more interesting.  Returning None means
the file should be removed from all commits, returning the filename
unmodified marks the file to be kept, and returning a different name means
the file should be renamed.  An example:

```shell
  git-filter-repo --filename-callback '
    if b"/src/" in filename:
      # Remove all files with a directory named "src" in their path
      # (except when "src" appears at the toplevel).
      return None
    elif filename.startswith(b"tools/"):
      # Rename tools/ -> scripts/misc/
      return b"scripts/misc/" + filename[6:]
    else:
      # Keep the filename and do not rename it
      return filename
    '
```

In contrast, the blob, reset, tag, and commit callbacks are not
expected to return a value, but are instead expected to modify the
object passed in.  Major fields for these objects are (subject to [API
backward compatibility
caveats](https://github.com/newren/git-filter-repo/blob/develop/git-filter-repo#L13-L30)
mentioned previously):

  * Blob: `original_id` (original hash) and `data`
  * Reset: `ref` (name of reference) and `from_ref` (hash or integer mark)
  * Tag: `ref`, `from_ref`, `original_id`, `tagger_name`, `tagger_email`,
         `tagger_date`, `message`
  * Commit: `branch`, `original_id`, `author_name`, `author_email`,
            `author_date`, `committer_name`, `committer_email`,
            `committer_date `, `message`, `file_changes` (list of
            FileChange objects, each containing a `type`, `filename`,
            `mode`, and `blob_id`), `parents` (list of hashes or integer
            marks)

An example of each:

```shell
  git filter-repo --blob-callback '
    if len(blob.data) > 25:
      # Mark this blob for removal from all commits
      blob.skip()
    else:
      blob.data = blob.data.sub(b"Hello", b"Goodbye")
    '
```

```shell
  git filter-repo --reset-callback 'reset.ref = reset.ref.replace(b"master", b"dev")'
```

```shell
  git filter-repo --tag-callback '
    if tag.tagger_name == "Jim Williams":
      # Omit this tag
      tag.skip()
    else:
      tag.message = tag.message + b"\n\nTag of %s by %s on %s" % (tag.ref, tag.tagger_email, tag.tagger_date)'
```

```shell
  git filter-repo --commit-callback '
    # Remove executable files with three 6s in their name (including
    # from leading directories).
    # Also, undo deletion of sources/foo/bar.txt (change types are either
    # b"D" (deletion) or b"M" (add or modify); renames are handled by deleting
    # the old file and adding a new one)
    commit.file_changes = [change for change in commit.file_changes
                           if not (change.mode == b"100755" and
			           change.filename.count(b"6") == 3) and
			      not (change.type == b"D" and
			           change.filename == b"sources/foo/bar.txt")]
    # Mark all .sh files as executable; modes in git are always one of
    # 100644 (normal file), 100755 (executable), 120000 (symlink), or
    # 160000 (submodule)
    for change in commit.file_changes:
      if change.filename.endswith(b".sh"):
        change.mode = b"100755"
    '
```

### Using filter-repo as a library

git-filter-repo can also be imported as a library in Python, allowing
for further flexibility.  Some [simple
examples](https://github.com/newren/git-filter-repo/tree/master/t/t9391)
exist in the testsuite.  For this to work, the symlink to
git-filter-repo named git_filter_repo.py either needs to have been
installed in your $PYTHONPATH, or you need to create a symlink to (or
a copy of) git-filter-repo named git_filter_repo.py and stick it in
your $PYTHONPATH.


# Internals

You probably don't need to read this section unless you are just very
curious or you are trying to do a very complex history rewrite.

## How filter-repo works

Roughly, filter-repo works by running
```shell
   git fast-export <options> | filter | git fast-import <options>
```
where filter-repo not only launches the whole pipeline but also serves as
the _filter_ in the middle.  However, filter-repo does a few additional
things on top in order to make it into a well-rounded filtering tool.  A
sequence that more accurately reflects what filter-repo runs is:
  1. Verify we're in a fresh clone
  1. `git fetch -u . refs/remotes/origin/*:refs/heads/*`
  1. `git remote rm origin`
  1. `git fast-export --show-original-ids --fake-missing-tagger --signed-tags=strip --tag-of-filtered-object=rewrite --use-done-feature --no-data --reencode=yes --all | filter | git fast-import --force --quiet`
  1. `git update-ref --no-deref --stdin`, fed with a list of refs to nuke, and a list of [replace refs](https://git-scm.com/docs/git-replace) to delete, create, or update.
  1. `git reset --hard`
  1. `git reflog expire --expire=now --all`
  1. `git gc --prune=now`

Some notes or exceptions on each of the above:
  1. If we're not in a fresh clone, users will not be able to recover if
     they used the wrong command or ran in the wrong repo.  (Though
     `--force` overrides this check, and it's also off if you've already
     ran filter-repo once in this repo.)
  1. Technically, we actually use a `git update-ref` command fed with a lot
     of input due to the fact that users can use `--force` when local
     branches might not match remote branches.  But this fetch command
     catches the intent rather succinctly.
  1. We don't want users accidentally pushing back to the original repo, as
     discussed in the section on [the bigger picture](#the-bigger-picture).
     It also reminds users that since history has been rewritten, this repo
     is no longer compatible with the original.  Finally, another minor
     benefit is this allows users to push with the `--mirror` option to
     their new home without accidentally sending remote tracking branches.
  1. Some of these flags are always used but others are actually
     conditional.  For example, filter-repo's `--replace-text` and
     `--blob-callback` options need to work on blobs so `--no-data` cannot
     be passed to fast-export.  But when we don't need to work on blobs,
     passing `--no-data` speeds things up.  Also, other flags may change
     the structure of the pipeline as well (e.g. `--dry-run` and `--debug`)
  1. Selection of files based on paths could cause every commit in the
     history of a branch or tag to be pruned, resulting in the branch or
     tag needing to be pruned.  However, filter-repo just works by
     stripping out the 'commit' and 'tag' directives for each one that's
     not needed, meaning fast-import won't do the branch or tag deletion
     for us.  So we do it in a post-processing step to ensure we avoid
     mixing old and new history.  Also, we use this step to write replace
     refs for accessing the newly written commit hashes using their
     previous names.
  1. Users also have old versions of files in their working tree and index;
     we want those cleaned up to match the rewritten history as well.  Note
     that this step is skipped in bare repos.
  1. Reflogs will hold on to old history, so we need to expire them.
  1. We need to gc to avoid mixing new and old history.  Also, it shrinks
     the repository for users, so they don't have to do extra work.  (Odds
     are that they've only rewritten trees and commits and maybe a few
     blobs, so `--aggressive` isn't needed and would be too slow.)

Information about these steps is printed out when `--debug` is passed to
filter-repo.

## Limitations

### Inherited limitations

Since git filter-repo calls fast-export and fast-import to do a lot of the
heavy lifting, it inherits limitations from those systems:

  * extended commit headers, if any, are stripped
  * commits get rewritten meaning they will have new hashes; therefore,
    signatures on commits and tags cannot continue to work and instead are
    just removed (thus signed tags become annotated tags)
  * tags of commits are supported; tags of anything else (blobs, trees, or
    tags) are not.  (fast-export aborts on tags of blobs and tags of tags,
    and simply ignores tags of trees with a warning.)
  * annotated and signed tags outside of the refs/tags/ namespace are not
    supported (their location will be mangled in weird ways)
  * fast-import will die on various forms of invalid input, such as a
    timezone with more than four digits
  * fast-export cannot reencode commit messages into UTF-8 if the commit
    message is not valid in its specified encoding (in such cases, it'll
    leave the commit message and the encoding header alone).
  * commits without an author will be given one matching the committer
  * tags without a tagger will be given a fake tagger
  * references that include commit cycles in their history (which can be
    created with git-replace(1)) will not be flagged to the user as an
    error but will be silently deleted by fast-export as though the branch
    or tag contained no interesting files

There are also some limitations due to the design of these systems:

  * Trying to insert additional files into the stream can be tricky; since
    fast-export only lists file changes in a merge relative to its first
    parent, if you insert additional files into a commit that is in the
    second (or third or fourth) parent history of a merge, then you also
    need to add it to the merge manually.

  * fast-export and fast-import work with exact file contents, not patches.
    (e.g. "Whatever the current contents of this file, update them to now
    have these contents") Because of this, removing the changes made in a
    single commit or inserting additional changes to a file in some commit
    and expecting them to propagate forward is not something that can be
    done with these tools.  Use
    [git-rebase(1)](https://git-scm.com/docs/git-rebase) for that.

### Intrinsic limitations

Some types of filtering have limitations that would affect any tool
attempting to perform them; the most any tool can do is attempt to notify
the user when it detects an issue:

  * When rewriting commit hashes in commit messages, there are a variety
    of cases when the hash will not be updated (whenever this happens, a
    note is written to `.git/filter-repo/suboptimal-issues`):
    * if a commit hash does not correspond to a commit in the old repo
    * if a commit hash corresponds to a commit that gets pruned
    * if an abbreviated hash is not unique

  * Pruning of empty commits can cause a merge commit to lose an entire
    ancestry line and become a non-merge.  If the merge commit had no
    changes then it can be pruned too, but if it still has changes it needs
    to be kept.  This might cause minor confusion since the commit will
    likely have a commit message that makes it sound like a merge commit
    even though it's not.  (Whenever a merge commit becomes a non-merge
    commit, a note is written to `.git/filter-repo/suboptimal-issues`)

### Issues specific to filter-repo

  * Multiple repositories in the wild have been observed which use a bogus
    timezone (`+051800`); google will find you some reports.  The intended
    timezone wasn't clear or wasn't always the same.  Replace with a
    different bogus timezone that fast-import will accept (`+0261`).

  * `--path-rename` can result in pathname collisions; to avoid excessive
    memory requirements of tracking which files are in all commits or
    looking up what files exist with either every commit or every usage of
    --path-rename, we just tell the user that they might clobber other
    changes if they aren't careful.  We can check if the clobbering comes
    from another --path-rename without much overhead.  (Perhaps in the
    future it's worth adding a slow mode to --path-rename that will do the
    more exhaustive checks?)

  * There is no mechanism for directly controlling which flags are passed
    to fast-export (or fast-import); only pre-defined flags can be turned
    on or off as a side-effect of other options.  Direct control would make
    little sense because some options like `--full-tree` would require
    additional code in filter-repo (to parse new directives), and others
    such as `-M` or `-C` would break assumptions used in other places of
    filter-repo.

### Comments on reversibility

Some people are interested in reversibility of of a rewrite; e.g. rewrite
history, possibly add some commits, then unrewrite and get the original
history back plus a few new "unrewritten" commits.  Obviously this is
impossible if your rewrite involves throwing away information
(e.g. filtering out files or replacing several different strings with
`***REMOVED***`), but may be possible with some rewrites.  filter-repo is
likely to be a poor fit for this type of workflow for a few reasons:

  * most of the limitations inherited from fast-export and fast-import
    are of a type that cause reversibility issues
  * grafts and replace refs, if present, are used in the rewrite and made
    permanent
  * rewriting of commit hashes will probably be reversible, but it is
    possible for rewritten abbreviated hashes to not be unique even if the
    original abbreviated hashes were.
  * filter-repo defaults to several forms of unreversible rewriting that
    you may need to turn off (e.g. the last two bullet points above or
    reencoding commit messages into UTF-8); it's possible that additional
    forms of unreversible rewrites will be added in the future.
  * I assume that people use filter-repo for one-shot conversions, not
    ongoing data transfers.  I explicitly reserve the right to [change any
    API in
    filter-repo](https://github.com/newren/git-filter-repo/blob/develop/git-filter-repo#L13-L30)
    based on this presumption.  You have been warned.
