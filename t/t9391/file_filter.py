#!/usr/bin/env python3

"""
Please see the
  ***** API BACKWARD COMPATIBILITY CAVEAT *****
near the top of git-filter-repo.

Also, note that splicing repos may need some special care as fast-export
only shows the files that changed relative to the first parent, so there
may be gotchas if you are to splice near merge commits; this example does
not try to handle any such special cases.
"""

import sys
import git_filter_repo as fr

def drop_file_by_contents(blob):
  bad_file_contents = b'The launch code is 1-2-3-4.'
  if blob.data == bad_file_contents:
    blob.skip()

def drop_files_by_name(commit):
  new_file_changes = []
  for change in commit.file_changes:
    if not change.filename.endswith(b'.doc'):
      new_file_changes.append(change)
  commit.file_changes = new_file_changes

sys.argv.append('--force')
args = fr.FilteringOptions.parse_args(sys.argv[1:])

filter = fr.RepoFilter(args,
                       blob_callback   = drop_file_by_contents,
                       commit_callback = drop_files_by_name)
filter.run()
