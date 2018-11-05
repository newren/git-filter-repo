#!/usr/bin/env python

import imp
import sys
sys.dont_write_bytecode = True # .pyc generation -> ugly 'git-repo-filterc' files

# python makes importing files with dashes hard, sorry.  Renaming would
# allow us to simplify this to "import git_repo_filter"; however,
# since git style commands are dashed and git-repo-filter is used more
# as a tool than a library, renaming is not an option.
with open("../../../git-repo-filter") as f:
  repo_filter = imp.load_module('repo_filter', f, "git-repo-filter", ('.py', 'U', 1))

def drop_file_by_contents(blob):
  bad_file_contents = 'The launch code is 1-2-3-4.'
  if blob.data == bad_file_contents:
    blob.skip()

def drop_files_by_name(commit):
  new_file_changes = []
  for change in commit.file_changes:
    if not change.filename.endswith('.doc'):
      new_file_changes.append(change)
  commit.file_changes = new_file_changes

sys.argv.append('--force')
args = repo_filter.FilteringOptions.parse_args(sys.argv[1:])

repo_filter.RepoFilter.run(args,
                           blob_callback   = drop_file_by_contents,
                           commit_callback = drop_files_by_name)
