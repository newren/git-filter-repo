#!/usr/bin/env python3

"""
This is a simple program that will run a linting program on all non-binary
files in history.  It also rewrites commit hashes in commit messages to
refer to the new commits with the rewritten files.  You call it like this:
   lint-history my-lint-command --arg whatever --another-arg
and it will repeatedly call
   my-lint-command --arg whatever --another-arg $TEMPORARY_FILE
with $TEMPORARY_FILE having contents of some file from history.

NOTE: Several people have taken and modified this script for a variety
of special cases (linting python files, linting jupyter notebooks, just
linting java files, etc.) and posted their modifications at
  https://github.com/newren/git-filter-repo/issues/45
Feel free to take a look and adopt some of their ideas.  Most of these
modifications are probably strictly unnecessary since you could just make
a lint-script that takes the filename, checks that it matches what you
want, and then calls the real linter.  But I guess folks don't like making
an intermediate script.  So I eventually added the --relevant flag for
picking out certain files providing yet another way to handle it.
"""

"""
Please see the
  ***** API BACKWARD COMPATIBILITY CAVEAT *****
near the top of git-filter-repo.
"""

# Technically, if you are only running on all non-binary files and don't care
# about filenames, then this program could be replaced by a "one-liner"; e.g.
#    git filter-repo --force --blob-callback '
#      if not b"\0" in blob.data[0:8192]:
#        filename = '.git/info/tmpfile'
#        with open(filename, "wb") as f:
#          f.write(blob.data)
#        subprocess.check_call(["lint_program", "--some", "arg", filename])
#        with open(filename, "rb") as f:
#          blob.data = f.read()
#        os.remove(filename)
#      '
# but let's do it as a full-fledged program that imports git_filter_repo
# and show how to also do it with filename handling...

import argparse
import os
import subprocess
import tempfile
try:
  import git_filter_repo as fr
except ImportError:
  raise SystemExit("Error: Couldn't find git_filter_repo.py.  Did you forget to make a symlink to git-filter-repo named git_filter_repo.py or did you forget to put the latter in your PYTHONPATH?")

example_text = '''CALLBACK

    When you pass --relevant 'BODY', the following style of function
    will be compiled and called:

        def is_relevant(filename):
            BODY

    Where filename is the full relative path from the toplevel of the
    repository.

    Thus, to only run on files with a ".txt" extension you would run
        lint-history --relevant 'return filename.endswith(b".txt")' ...

EXAMPLES

    To run dos2unix on all non-binary files in history:
        lint-history dos2unix

    To run eslint --fix on all .js files in history:
        lint-history --relevant 'return filename.endswith(b".js")' eslint --fix

INTERNALS

    Linting of files in history will be done by writing the files to a
    temporary directory before running the linting program; the
    location of this temporary directory can be controlled via the
    TMPDIR environment variable as per
    https://docs.python.org/3/library/tempfile.html#tempfile.mkdtemp.
    '''

parser = argparse.ArgumentParser(description='Run a program (e.g. code formatter or linter) on files in history',
                                 epilog = example_text,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)

parser.add_argument('--relevant', metavar="FUNCTION_BODY",
        help=("Python code for determining whether to apply linter to a "
              "given filename.  Implies --filenames-important.  See CALLBACK "
              "below."))
parser.add_argument('--filenames-important', action='store_true',
        help=("By default, contents are written to a temporary file with a "
              "random name.  If the linting program needs to know the file "
              "basename to operate correctly (e.g. because it needs to know "
              "the file's extension), then pass this argument"))
parser.add_argument('command', nargs=argparse.REMAINDER,
        help=("Lint command to run, other than the filename at the end"))
lint_args = parser.parse_args()
if not lint_args.command:
  raise SystemExit("Error: Need to specify a lint command")

tmpdir = None
blobs_handled = {}
cat_file_process = None
def lint_with_real_filenames(commit, metadata):
  for change in commit.file_changes:
    if change.blob_id in blobs_handled:
      change.blob_id = blobs_handled[change.blob_id]
    elif change.type == b'D':
      continue
    elif not is_relevant(change.filename):
      continue
    else:
      # Get the old blob contents
      cat_file_process.stdin.write(change.blob_id + b'\n')
      cat_file_process.stdin.flush()
      objhash, objtype, objsize = cat_file_process.stdout.readline().split()
      contents_plus_newline = cat_file_process.stdout.read(int(objsize)+1)

      # Write it out to a file with the same basename
      filename = os.path.join(tmpdir, os.path.basename(change.filename))
      with open(filename, "wb") as f:
        f.write(contents_plus_newline[:-1])

      # Lint the file
      subprocess.check_call(lint_args.command + [filename.decode('utf-8')])

      # Get the new contents
      with open(filename, "rb") as f:
        blob = fr.Blob(f.read())

      # Insert the new file into the filter's stream, and remove the tempfile
      filter.insert(blob)
      os.remove(filename)

      # Record our handling of the blob and use it for this change
      blobs_handled[change.blob_id] = blob.id
      change.blob_id = blob.id

def lint_non_binary_blobs(blob, metadata):
  if not b"\0" in blob.data[0:8192]:
    filename = '.git/info/tmpfile'
    with open(filename, "wb") as f:
      f.write(blob.data)
    subprocess.check_call(lint_args.command + [filename])
    with open(filename, "rb") as f:
      blob.data = f.read()
    os.remove(filename)

if lint_args.filenames_important and not lint_args.relevant:
  lint_args.relevant = 'return True'
if lint_args.relevant:
  body = lint_args.relevant
  exec('def is_relevant(filename):\n  '+'\n  '.join(body.splitlines()),
       globals())
  lint_args.filenames_important = True
args = fr.FilteringOptions.default_options()
args.force = True
if lint_args.filenames_important:
  tmpdir = tempfile.mkdtemp().encode()
  cat_file_process = subprocess.Popen(['git', 'cat-file', '--batch'],
                                      stdin = subprocess.PIPE,
                                      stdout = subprocess.PIPE)
  filter = fr.RepoFilter(args, commit_callback=lint_with_real_filenames)
  filter.run()
  cat_file_process.stdin.close()
  cat_file_process.wait()
else:
  filter = fr.RepoFilter(args, blob_callback=lint_non_binary_blobs)
  filter.run()
