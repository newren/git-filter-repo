#!/usr/bin/env python3

import argparse
import os
import subprocess
import datetime
import sys
try:
  import git_filter_repo as fr
except ImportError:
  raise SystemExit("Error: Couldn't find git_filter_repo.py.  Did you forget to make a symlink to git-filter-repo named git_filter_repo.py or did you forget to put the latter in your PYTHONPATH?")

parser = argparse.ArgumentParser(
          description='Offset a set of or all commits by n seconds, can be used to timeshift a repository')
parser.add_argument('--offset', type=int,
        help=("Offset in seconds"))
parser.add_argument('--from-commit', type=str,
        help=("Commit to start from"))
parser.add_argument('--to-commit', type=str,
        help=("Commit to finish at"))
args = parser.parse_args()

print(args)

shouldOffset = args.from_commit is None

def offsetDate(timestampAndUtcOffset):
  timestampAndUtcOffset = timestampAndUtcOffset.decode('utf-8')
  split = timestampAndUtcOffset.split(' ')
  timestamp = int(split[0])
  timestamp = timestamp + args.offset
  result = str(timestamp) + ' ' + split[1];
  result = result.encode()
  return result

def fixup_commits(commit, metadata):
  global shouldOffset
  commitId = commit.original_id.decode('utf-8')
  if shouldOffset == False:
    shouldOffset = args.from_commit == commitId
  
  if shouldOffset == True:
    print('Offsetting commit ' + commitId)
    commit.author_date = offsetDate(commit.author_date)
    commit.committer_date = offsetDate(commit.committer_date)

    if not args.to_commit is None:
      shouldOffset = args.to_commit != commitId

  else:
    print('Skipping commit ' + commitId)

fr_args = fr.FilteringOptions.parse_args(['--force'])
filter = fr.RepoFilter(fr_args, commit_callback=fixup_commits)
filter.run()