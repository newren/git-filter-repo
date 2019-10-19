#!/usr/bin/env python3

"""
Please see the
  ***** API BACKWARD COMPATIBILITY CAVEAT *****
near the top of git-filter-repo
"""

import sys
import git_filter_repo as fr

if len(sys.argv) != 3:
  raise SystemExit("Syntax:\n  %s SOURCE_REPO TARGET_REPO")
source_repo = sys.argv[1].encode()
target_repo = sys.argv[2].encode()

total_objects = fr.GitUtils.get_total_objects(source_repo) # blobs+trees
total_commits = fr.GitUtils.get_commit_count(source_repo)
object_count = 0
commit_count = 0

def print_progress():
  global object_count, commit_count, total_objects, total_commits
  print("\rRewriting commits... %d/%d  (%d objects)"
        % (commit_count, total_commits, object_count), end='')

def my_blob_callback(blob, metadata):
  global object_count
  object_count += 1
  print_progress()

def my_commit_callback(commit, metadata):
  global commit_count
  commit_count += 1
  print_progress()

args = fr.FilteringOptions.parse_args(['--force', '--quiet'])
filter = fr.RepoFilter(args,
                       blob_callback   = my_blob_callback,
                       commit_callback = my_commit_callback)
filter.run()
