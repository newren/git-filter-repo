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

if len(sys.argv) != 3:
  raise SystemExit("Syntax:\n  %s SOURCE_REPO TARGET_REPO")
source_repo = sys.argv[1]
target_repo = sys.argv[2]

total_objects = repo_filter.GitUtils.get_total_objects(source_repo) # blobs+trees
total_commits = repo_filter.GitUtils.get_commit_count(source_repo)
object_count = 0
commit_count = 0

def print_progress():
  global object_count, commit_count, total_objects, total_commits
  print "\rRewriting commits... %d/%d  (%d objects)" \
        % (commit_count, total_commits, object_count),

def my_blob_callback(blob):
  global object_count
  object_count += 1
  print_progress()
  
def my_commit_callback(commit):
  global commit_count
  commit_count += 1
  print_progress()

args = repo_filter.FilteringOptions.parse_args(['--force', '--quiet'])
repo_filter.RepoFilter.run(args,
                           blob_callback   = my_blob_callback,
                           commit_callback = my_commit_callback)
