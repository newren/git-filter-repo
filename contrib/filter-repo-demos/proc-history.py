#!/usr/bin/env python3

"""
Run shell command on each file in history and add or replace the file with cmd's output.

It also rewrites commit hashes in commit messages to
refer to the new commits with the rewritten files.

Run <prog> --help for more details.
   <prog> py:percent --arg whatever --another-arg

Based on https://github.com/newren/git-filter-repo/blob/main/contrib/filter-repo-demos/lint-history

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
from pathlib import Path, PurePath
from typing import List
import subprocess
import tempfile
import textwrap

try:
    import git_filter_repo as fr
except ImportError:
    raise SystemExit(
        "Error: Couldn't find git_filter_repo.py. "
        "\n  Did you symlink your in-PATH `git-filter-repo` --> `git_filter_repo.py` "
        "or did you forget to put the latter in your PYTHONPATH?"
    )

example_text = """CALLBACKS

    When you pass --relevant 'BODY', the following style of function
    will be compiled and called:

        def is_relevant(fpath: pathlib.PurePath) -> bool:
            BODY

    where `fpath` is a pathlib.PurePath instance with the full relative path
    from the toplevel of the repository.

    Respectively the --outfpath 'BODY', the following style of function is formed:

        def make_out_fpath(fpath: pathlib.Path) -> pathlib.Path:
            BODY

EXAMPLES

    To only process files with a ".txt" extension you would run

        %(prog)s --relevant 'return fpath.suffix.lower() == ".txt"' ...

    To convert all notebooks in history to py:percent (the default)
    with the `jupyext` comandv (notice the "--" pseudo-argumernt is needed
    for considering the `--to <format>` option as part of the `command`):

        %(prog)s \\
            --relevant 'return fpath.suffix.lower() == ".ipynb"'  \\
            --outfpath 'return fpath.with_suffix(".py")' \\
            --drop-src \\
            -- \\
            jupytext --to 'py:percent'

    To maintain a CONTENTS.txt file with all file headers on each commit
    (in bash, and not the best use this tool):

    $ file-header() {
        echo "- $1:"
        head -n3 $1 |  sed 's/^/    /'
        echo
    }
    $ export -f file-header collect-
    $ %(prog)s \\
        --relevant 'return fpath.suffix.lower() == ".ipynb"'  \\
        --outfpath 'return fpath.with_suffix(".py")' \\
        --drop-src \\
        -- \\
        jupytext --to 'py:percent'

INTERNALS

    Processing of files in history is done by writting the "relevant" files
    into a temporary directory before running the `command` which should produce
    the new file specified by the --outpath; the location of this temporary directory
    can be controlled via the TMPDIR environment variable as per
    https://docs.python.org/3/library/tempfile.html#tempfile.mkdtemp.
    """

parser = argparse.ArgumentParser(
    description="Run a program over files in history to convert them or append more",
    epilog=example_text,
    formatter_class=argparse.RawDescriptionHelpFormatter,
)

parser.add_argument(
    "--relevant",
    metavar="FUNCTION_BODY",
    help=(
        """
    Python code returning truthy when `command` should run for `fpath`
    (given as a `pathlib.PurePath` instance).\
    If not given, all files are relevant [%(default)s].
    See CALLBACKS, below.
    """
    ),
    default="return True",
)
parser.add_argument(
    "--outpath",
    metavar="FUNCTION_BODY",
    help="""
    Python code returning the output filepath when `command` runs on a source `fpath`
    (given as a `pathlib.Path` instance).
    If not given, same as source assumed [%(default)s].
    Note that the command runs in a temporary dir, so leave its parent paths as is.
    See CALLBACKS, below.
    """,
    default="return fpath",
)
parser.add_argument(
    "--drop-src",
    action="store_true",
    help=(
        "Replace the relevant file with the --outpath from `command` "
        "(by default both source & destination paths are kept in history).  "
        "Ignored if `outpath` identical to source."
    ),
)
parser.add_argument(
    "--exec-shell",
    action="store_true",
    help="Whether to execute the command in a shell (eg. to inherit functions).",
)
parser.add_argument(
    "--refs",
    nargs="+",
    help=(
        "Limit history rewriting to the specified refs. "
        "Implies --partial of git-filter-repo (and all its "
        "implications)."
    ),
)
parser.add_argument(
    "--force",
    "-f",
    action="store_true",
    help=" Rewrite history even if the current repo does not look like a fresh clone.",
)
parser.add_argument(
    "command",
    nargs="+",
    help="""
        The command to process each relevant file and produce `outpath` 
        *without* its filename at the end.
        See INTERNALS, below.
    """,
)
cli_args = parser.parse_args()
if not cli_args.command:
    raise SystemExit("Error: Need to specify a file-processing command")

utf8 = "utf-8"
blobs_handled = {}
cat_file_process = None


def process_file(change: fr.FileChange) -> List[fr.FileChange]:
    # Get the old blob contents
    cat_file_process.stdin.write(change.blob_id + b"\n")
    cat_file_process.stdin.flush()
    objhash, objtype, objsize = cat_file_process.stdout.readline().split()
    contents_plus_newline = cat_file_process.stdout.read(int(objsize) + 1)

    src = PurePath(change.filename.decode(utf8))

    try:
        # Write it out to a file with the same basename
        tmp_src = tmpdir / src.name
        with open(tmp_src, "wb") as f:
            f.write(contents_plus_newline[:-1])

        # Execute the command
        cmd_args = [*cli_args.command, str(tmp_src)]
        subprocess.check_call(cmd_args, shell=cli_args.exec_shell)

        # Validate output indeed created..
        tmp_out = make_out_fpath(tmp_src)
        try:
            if not tmp_out.exists():
                raise SystemExit(
                    f"Error: command({' '.join(cmd_args)!r}) should have created file: {tmp_out}"
                )

            # Get the new contents
            with open(tmp_out, "rb") as f:
                blob = fr.Blob(f.read())

            # Remove tempfiles
        finally:
            tmp_out.unlink(missing_ok=True)
    finally:
        tmp_src.unlink()

    # Insert the new file into the filter's stream, and remove the tempfile
    filter.insert(blob)

    new_changes = []

    if src.name == tmp_out.name:
        # Record processing to update blob-references in this and future changes.
        blobs_handled[change.blob_id] = change.blob_id = blob.id
    else:
        new_filename = str(src.with_name(tmp_out.name)).encode(utf8)
        change_type = b"M"  # no need for b'A' ever
        if cli_args.drop_src:
            # Dress current change as the out-file and delete old
            # and record processing to update blob-references.
            new_changes.append(fr.FileChange(b"D", change.filename))
            blobs_handled[change.blob_id] = change.blob_id = blob.id
            change.filename = new_filename
            change.type = change_type
        else:
            # Add/modify new out-file and keep old (so no blob-refs updates)
            new_changes.append(
                fr.FileChange(change_type, new_filename, blob.id, change.mode)
            )

    return new_changes


def process_file_changes(commit: fr.Commit, metadata):
    new_changes = []
    file_changes: list[fr.FileChange] = commit.file_changes
    for change in file_changes:
        if change.blob_id in blobs_handled:
            change.blob_id = blobs_handled[change.blob_id]
        elif change.type == b"D" or not is_relevant(
            PurePath(change.filename.decode(utf8))
        ):
            continue
        else:
            new_changes.extend(process_file(change))

    file_changes.extend(new_changes)


body = textwrap.indent(cli_args.relevant, "  ")
exec(
    f"def is_relevant(fpath):\n{body}",
    globals(),
)
body = textwrap.indent(cli_args.outpath, "  ")
exec(
    f"def make_out_fpath(fpath):\n{body}",
    globals(),
)


filter_args = []
if cli_args.refs:
    filter_args = ["--replace-refs", "update-no-add", "--refs", *cli_args.refs]
fr_args = fr.FilteringOptions.parse_args(filter_args, error_on_empty=False)
if cli_args.force:
    fr_args.force = True
tmpdir = Path(tempfile.mkdtemp())
cat_file_process = subprocess.Popen(
    ["git", "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE
)

filter = fr.RepoFilter(fr_args, commit_callback=process_file_changes)
filter.run()

cat_file_process.stdin.close()
cat_file_process.wait()

tmpdir.rmdir()
