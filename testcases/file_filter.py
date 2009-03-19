#!/usr/bin/env python

from git_fast_filter import Blob, Reset, FileChanges, Commit, FastExportFilter

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

filter = FastExportFilter(blob_callback   = drop_file_by_contents,
                          commit_callback = drop_files_by_name)
filter.run()
