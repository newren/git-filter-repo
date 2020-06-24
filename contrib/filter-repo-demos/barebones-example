#!/usr/bin/env python3

"""
This is a simple program that behaves identically to git-filter-repo.  Its
entire purpose is just to show what to import and run to get the normal
git-filter-repo behavior, to serve as a starting point for you to figure
out what you want to modify.
"""

"""
Please see the
  ***** API BACKWARD COMPATIBILITY CAVEAT *****
near the top of git-filter-repo.
"""

import sys

try:
  import git_filter_repo as fr
except ImportError:
  raise SystemExit("Error: Couldn't find git_filter_repo.py.  Did you forget to make a symlink to git-filter-repo named git_filter_repo.py or did you forget to put the latter in your PYTHONPATH?")

args = fr.FilteringOptions.parse_args(sys.argv[1:])
if args.analyze:
  fr.RepoAnalyze.run(args)
else:
  filter = fr.RepoFilter(args)
  filter.run()
