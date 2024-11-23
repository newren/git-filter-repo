# Examples from user-filed issues

Lots of people have filed issues against git-filter-repo, and many times their
issue boils down into questions of "How do I?" or "Why doesn't this work?"

Below are a collection of example repository filterings in answer to their
questions, which may be of interest to others.

## Table of Contents

  * [Adding files to root commits](#adding-files-to-root-commits)
  * [Purge a large list of files](#purge-a-large-list-of-files)
  * [Extracting a libary from a repo](#Extracting-a-libary-from-a-repo)
  * [Replace words in all commit messages](#Replace-words-in-all-commit-messages)
  * [Only keep files from two branches](#Only-keep-files-from-two-branches)
  * [Renormalize end-of-line characters and add a .gitattributes](#Renormalize-end-of-line-characters-and-add-a-gitattributes)
  * [Remove spaces at the end of lines](#Remove-spaces-at-the-end-of-lines)
  * [Having both exclude and include rules for filenames](#Having-both-exclude-and-include-rules-for-filenames)
  * [Removing paths with a certain extension](#Removing-paths-with-a-certain-extension)
  * [Removing a directory](#Removing-a-directory)
  * [Convert from NFD filenames to NFC](#Convert-from-NFD-filenames-to-NFC)
  * [Set the committer of the last few commits to myself](#Set-the-committer-of-the-last-few-commits-to-myself)
  * [Handling special characters, e.g. accents in names](#Handling-special-characters-eg-accents-in-names)
  * [Handling repository corruption](#Handling-repository-corruption)
  * [Removing all files with a backslash in them](#Removing-all-files-with-a-backslash-in-them)
  * [Replace a binary blob in history](#Replace-a-binary-blob-in-history)
  * [Remove commits older than N days](#Remove-commits-older-than-N-days)
  * [Replacing pngs with compressed alternative](#Replacing-pngs-with-compressed-alternative)
  * [Updating submodule hashes](#Updating-submodule-hashes)
  * [Using multi-line strings in callbacks](#Using-multi-line-strings-in-callbacks)


## Adding files to root commits

<!-- https://github.com/newren/git-filter-repo/issues/21 -->

Here's an example that will take `/path/to/existing/README.md` and
store it as `README.md` in the repository, and take
`/home/myusers/mymodule.gitignore` and store it as `src/.gitignore` in
the repository:

```
git filter-repo --commit-callback "if not commit.parents: commit.file_changes += [
    FileChange(b'M', b'README.md', b'$(git hash-object -w '/path/to/existing/README.md')', b'100644'), 
    FileChange(b'M', b'src/.gitignore', b'$(git hash-object -w '/home/myusers/mymodule.gitignore')', b'100644')]"
```

Alternatively, you could also use the [insert-beginning](../contrib/filter-repo-demos/insert-beginning) contrib script:

```
mv /path/to/existing/README.md README.md
mv /home/myusers/mymodule.gitignore src/.gitignore
insert-beginning --file README.md
insert-beginning --file src/.gitignore
```

## Purge a large list of files

<!-- https://github.com/newren/git-filter-repo/issues/63 -->

Stick all the files in some file (one per line),
e.g. `../DELETED_FILENAMES.txt`, and then run

```
git filter-repo --invert-paths --paths-from-file ../DELETED_FILENAMES.txt
```

## Extracting a libary from a repo

<!-- https://github.com/newren/git-filter-repo/issues/80 -->

If you want to pick out some subdirectory to keep
(e.g. `src/some-filder/some-feature/`), but don't want it moved to the
repository root (so that --subdirectory-filter isn't applicable) but
instead want it to become some other higher level directory
(e.g. `src/`):

```
git filter-repo \
    --path src/some-folder/some-feature/ \
    --path-rename src/some-folder/some-feature/:src/
```

## Replace words in all commit messages

<!-- https://github.com/newren/git-filter-repo/issues/83 -->

Replace "stuff" in any commit message with "task".

```
git-filter-repo --message-callback 'return message.replace(b"stuff", b"task")'
```

## Only keep files from two branches

<!-- https://github.com/newren/git-filter-repo/issues/91 -->

Let's say you know that the files currently present on two branches
are the only files that matter.  Files that used to exist in either of
these branches, or files that only exist on some other branch, should
all be deleted from all versions of history.  This can be accomplished
by getting a list of files from each branch, combining them, sorting
the list and picking out just the unique entries, then passing the
result to `--paths-from-file`:

```
git ls-tree -r ${BRANCH1} >../my-files
git ls-tree -r ${BRANCH2} >>../my-files
sort ../my-files | uniq >../my-relevant-files
git filter-repo --paths-from-file ../my-relevant-files
```

## Renormalize end-of-line characters and add a .gitattributes

<!-- https://github.com/newren/git-filter-repo/issues/122 -->

```
contrib/filter-repo-demos/lint-history dos2unix
[edit .gitattributes]
contrib/filter-repo-demos/insert-beginning .gitattributes
```

## Remove spaces at the end of lines

<!-- https://github.com/newren/git-filter-repo/issues/145 -->

Removing all spaces at the end of lines of non-binary files, including
converting CRLF to LF:

```
git filter-repo --replace-text <(echo 'regex:[\r\t ]+(\n|$)==>\n')
```

## Having both exclude and include rules for filenames

<!-- https://github.com/newren/git-filter-repo/issues/230 -->

If you want to have rules to both include and exclude filenames, you
can simply invoke `git filter-repo` multiple times.  Alternatively,
you can do it in one run if you dispense with `--path` arguments and
instead use the more generic `--filename-callback`.  For example to
include all files under `src/` except for `src/README.md`:

```
git filter-repo --filename-callback '
    if filename == b"src/README.md":
        return None
    if filename.startswith(b"src/"):
        return filename
  return None'
```

## Removing paths with a certain extension

<!-- https://github.com/newren/git-filter-repo/issues/274 -->

```
git filter-repo --invert-paths --path-glob '*.xsa'
```

or

```
git filter-repo --filename-callback '
    if filename.endswith(b".xsa"):
        return None
    return filename'
```

## Removing a directory

<!-- https://github.com/newren/git-filter-repo/issues/278 -->

```
git filter-repo --path node_modules/electron/dist/ --invert-paths
```

## Convert from NFD filenames to NFC

<!-- https://github.com/newren/git-filter-repo/issues/296 -->

Given that Mac does utf-8 normalization of filenames, and has
historically switched which kind of normalization it does, users may
have committed files with alternative normalizations to their
repository.  If someone wants to convert filenames in NFD form to NFC,
they could run

```
git filter-repo --filename-callback '
    try: 
        return subprocess.check_output("iconv -f utf-8-mac -t utf-8".split(),
                                       input=filename)
    except:
        return filename
'
```

or instead of relying on the system iconv utility and spawning separate
processes, doing it within python:

```
git filter-repo --filename-callback '
    import unicodedata
    try:
       return bytearray(unicodedata.normalize('NFC', filename.decode('utf-8')), 'utf-8')
    except:
      return filename
'
```
  
## Set the committer of the last few commits to myself

<!-- https://github.com/newren/git-filter-repo/issues/379 -->

```
git filter-repo --refs main~5..main --commit-callback '
    commit.commiter_name = b"My Wonderful Self"
    commit.committer_email = b"my@self.org"
'
```

## Handling special characters, e.g. accents and umlauts in names

<!-- https://github.com/newren/git-filter-repo/issues/383 -->

Since characters like ë and á are multi-byte characters and python
won't allow you to directly place those in a bytestring
(e.g. `b"Raphaël González"` would result in a `SyntaxError: bytes can
only contain ASCII literal characters` error from Python), you just
need to make a normal (UTF-8) string and then convert to a bytestring
to handle these.  For example, changing the author name and email
where the author email is currently `example@test.com`:

```
git filter-repo --refs main~5..main --commit-callback '
    if commit.author_email = b"example@test.com":
        commit.author_name = "Raphaël González".encode()
        commit.author_email = b"rgonzalez@test.com"
'
```

## Handling repository corruption

<!-- https://github.com/newren/git-filter-repo/issues/420 -->

First, run fsck to get a list of the corrupt objects, e.g.:
```
$ git fsck
error in commit 166f57b3fbe31257100361ecaf735f305b533b21: missingSpaceBeforeDate: invalid author/committer line - missing space before date
Checking object directories: 100% (256/256), done.
```

Then print out that object literally to a temporary file:
```
$ git cat-file -p 166f57b3fbe31257100361ecaf735f305b533b21 >tmp
```

Taking a look at the file would show, for example:
```
$ cat tmp
tree e1d871155fce791680ec899fe7869067f2b4ffd2
author My Name <my@email.com>1673287380 -0800
committer My Name <my@email.com> 1673287380 -0800

Initial
```

Edit that file to fix the error (in this case, the missing space
between author email and author date):

```
tree e1d871155fce791680ec899fe7869067f2b4ffd2
author My Name <my@email.com> 1673287380 -0800
committer My Name <my@email.com> 1673287380 -0800

Initial
```

Save the updated file, then use `git-replace` to make a replace reference
for it.
```
$ git replace -f 166f57b3fbe31257100361ecaf735f305b533b21 $(git hash-object -t commit -w tmp)
```

Then remove the temporary file `tmp` and run `filter-repo` to consume
the replace reference and make it permanent:

```
$ rm tmp
$ git filter-repo --proceed
```

Note that if you have multiple corrupt objects, you only need to run
filter-repo once; that is, so long as you create all the replacements
before you run filter-repo.

## Removing all files with a backslash in them

<!-- https://github.com/newren/git-filter-repo/issues/427 -->

```
git filter-repo --filename-callback 'return None if b'\\' in filename else filename'
```

## Replace a binary blob in history

<!-- https://github.com/newren/git-filter-repo/issues/436 -->

Let's say you committed a binary blob, perhaps an image file, with
sensitive data, and never modified it.  You want to replace it with
the contents of some alternate file, currently found at
`../alternative-file.jpg` (it can have a different filename than what
is stored in the repository).  Let's also say the hash of the old file
was `f4ede2e944868b9a08401dafeb2b944c7166fd0a`.  You can replace it
with either

```
git filter-repo --blob-callback '
    if blob.original_id == b"f4ede2e944868b9a08401dafeb2b944c7166fd0a":
        blob.data = open("../alternative-file.jpg", "rb").read()
'
```

or

```
git replace -f f4ede2e944868b9a08401dafeb2b944c7166fd0a $(git hash-object -w ../alternative-file.jpg)
git filter-repo --proceed
```

## Remove commits older than N days

<!-- https://github.com/newren/git-filter-repo/issues/300 -->

This is such a bad usecase.  I'm tempted to leave it out, but it has
come up multiple times, and there are people who are totally fine with
changing every commit hash in their repository and throwing away
history periodically.  First, identify an ${OLD_COMMIT} that you want
to be a new root commit, then run:

```
git replace --graft ${OLD_COMMIT}
git filter-repo --proceed
```

(The trick here is that `git replace --graft` takes a commit to replace, and
a list of new parents for the commit.  Since ${OLD_COMMIT} is the final
positional argument, it means the list of new parents is an empty list, i.e.
we are turning it into a new root commit.)

## Replacing pngs with compressed alternative

<!-- https://github.com/newren/git-filter-repo/issues/492 -->

Let's say you committed thousands of pngs that were poorly compressed,
but later aggressively recompressed the pngs and commited and pushed.
Unfortunately, clones are slow because they still contain the poorly
compressed pngs and you'd like to rewrite history to pretend that the
aggressively compressed versions were used when the files were first
introduced.

First, take a look at the commit that aggressively recompressed the pngs:

```
git log -1 --raw --no-abbrev ${COMMIT_WHERE_YOU_COMPRESSED_PNGS}
```

that will show output like
```
:100755 100755 edf570fde099c0705432a389b96cb86489beda09 9cce52ae0806d695956dcf662cd74b497eaa7b12 M      resources/foo.png
:100755 100755 644f7c55e1a88a29779dc86b9ff92f512bf9bc11 88b02e9e45c0a62db2f1751b6c065b0c2e538820 M      resources/bar.png
```

Use that to make a --file-info-callback to fix up the original versions:
```
git filter-repo --file-info-callback '
    if filename == b"resources/foo.png" and blob_id == b"edf570fde099c0705432a389b96cb86489beda09":
        blob_id = b"9cce52ae0806d695956dcf662cd74b497eaa7b12"
    if filename == b"resources/bar.png" and blob_id == b"644f7c55e1a88a29779dc86b9ff92f512bf9bc11":
        blob_id = b"88b02e9e45c0a62db2f1751b6c065b0c2e538820"
    return (filename, mode, blob_id)
'
```

## Updating submodule hashes

<!-- https://github.com/newren/git-filter-repo/issues/537 -->

Let's say you have a repo with a submodule at src/my-submodule, and
that you feel the wrong commit-hashes of the submodule were commited
within your project and you want them updated according to the
following table:
```
old                                      new
edf570fde099c0705432a389b96cb86489beda09 9cce52ae0806d695956dcf662cd74b497eaa7b12
644f7c55e1a88a29779dc86b9ff92f512bf9bc11 88b02e9e45c0a62db2f1751b6c065b0c2e538820
```

You could do this as follows:
```
git filter-repo --file-info-callback '
    if filename == b"src/my-submodule" and blob_id == b"edf570fde099c0705432a389b96cb86489beda09":
        blob_id = b"9cce52ae0806d695956dcf662cd74b497eaa7b12"
    if filename == b"src/my-submodule" and blob_id == b"644f7c55e1a88a29779dc86b9ff92f512bf9bc11":
        blob_id = b"88b02e9e45c0a62db2f1751b6c065b0c2e538820"
    return (filename, mode, blob_id)
```

Yes, `blob_id` is kind of a misnomer here since the file's hash
actually refers to a commit from the sub-project.  But `blob_id` is
the name of the parameter passed to the --file-info-callback, so that
is what must be used.

## Using multi-line strings in callbacks

<!-- https://lore.kernel.org/git/CABPp-BFqbiS8xsbLouNB41QTc5p0hEOy-EoV0Sjnp=xJEShkTw@mail.gmail.com/ -->

Since the text for callbacks have spaces inserted at the front of every
line, multi-line strings are normally munged.  For example, the command

```
git filter-repo --blob-callback '
  blob.data = bytes("""\
This is the new
file that I am
replacing every blob
with.  It is great.\n""", "utf-8")
'
```

would result in a file with extra spaces at the front of every line:
```
  This is the new
  file that I am
  replacing every blob
  with.  It is great.
```

The two spaces at the beginning of every-line were inserted into every
line of the callback when trying to compile it as a function.
However, you can use textwrap.dedent to fix this; in fact, using it
will even allow you to add more leading space so that it looks nicely
indented.  For example:

```
git filter-repo --blob-callback '
  import textwrap
  blob.data = bytes(textwrap.dedent("""\
    This is the new
    file that I am
    replacing every blob
    with.  It is great.\n"""), "utf-8")
'
```

That will result in a file with contents
```
This is the new
file that I am
replacing every blob
with.  It is great.
```

which has no leading spaces on any lines.