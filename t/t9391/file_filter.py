#!/usr/bin/env python

# python makes importing files with dashes hard, sorry.  Renaming would
# allow us to simplify this to
#   import git_repo_filter
# However, since git style commands are dashed and git-filter-repo is used more
# as a tool than a library, renaming is not an option, so import is 5 lines:
import imp
import sys
sys.dont_write_bytecode = True # .pyc generation -> ugly 'git-filter-repoc' files
with open("../../../git-filter-repo") as f:
  repo_filter = imp.load_source('repo_filter', "git-filter-repo", f)
# End of convoluted import of git-filter-repo

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

filter = repo_filter.RepoFilter(args,
                                blob_callback   = drop_file_by_contents,
                                commit_callback = drop_files_by_name)
filter.run()
