#!/usr/bin/env python

import commands
import os
import sys
import tempfile
from optparse import OptionParser
from subprocess import Popen, PIPE

from git_fast_filter import Blob, Reset, FileChanges, Commit
from git_fast_filter import FastExportFilter, FastExportOutput, FastImportInput
from git_fast_filter import get_commit_count, get_total_objects

def get_syntax_string():
  return """Syntax:
  collab --help
  collab info
  collab pull-grafts
  collab push-grafts
  collab clone REPOSITORY [OPTIONS] [--] [REVISION LIMITING]

Notes:
  REPOSITORY is a path to a repository, OPTIONS is some mix of
    --exclude=PATH
    --exclude-file=FILE-WITH-PATHS
    --include=PATH
    --include-file=FILE-WITH-PATHS
  and REVISION LIMITING is options acceptable to git log to reduce the total
  list of revisions, examples of which include
    --since="2 years ago"
    master~10000..master
    master 4.10 4.8 ^4.6
  If OPTIONS is not specified, everything is included.  If REVISION LIMITING
  is not specified, --branches is the default."""

if len(sys.argv) <= 1 or sys.argv[1] == "--help":
  raise SystemExit(get_syntax_string())
subcommand = sys.argv[1]
if subcommand == "-h":
  raise SystemExit("help has four letters (and uses two dashes instead of one.")
elif subcommand not in ['info', 'pull-grafts', 'push-grafts', 'clone']:
  sys.stderr.write("Unrecognized command: %s\n" % subcommand)
  raise SystemExit(get_syntax_string())


class GraftFilter(object):
  def __init__(self, source_repo, target_repo,
                     excludes = [], includes = [], fast_export_args = []):
    self.source_repo = source_repo
    self.target_repo = target_repo
    self.excludes = excludes
    self.includes = includes
    self.fast_export_args = fast_export_args

    self.show_progress = True
    self.object_count = 0
    self.commit_count = 0
    self.total_commits = get_commit_count(source_repo, fast_export_args)
    if self.total_commits == 0:
      sys.stderr.write("There are no commits to clone.\n")
      sys.exit(0)

  def print_progress(self):
    if self.show_progress:
      print "\rRewriting commits... %d/%d  (%d objects)" \
            % (self.commit_count, self.total_commits, self.object_count),

  def do_blob(self, blob):
    self.object_count += 1
    if self.object_count % 100 == 0:
      self.print_progress()

  def do_commit(self, commit):
    if self.excludes:
      new_file_changes = [change for change in commit.file_changes
                          if change.filename not in self.excludes]
      commit.file_changes = new_file_changes
    commit.branch = commit.branch.replace('refs/heads/','refs/remotes/collab/')
    self.commit_count += 1
    self.print_progress()

  def run(self):
    (file, remotemarks) = tempfile.mkstemp()
    os.close(file)
    (file, localmarks) = tempfile.mkstemp()
    os.close(file)

    source = \
      FastExportOutput(self.source_repo,
                       ["--export-marks=%s" % remotemarks]
                       + self.fast_export_args)
    target = \
      FastImportInput( self.target_repo, ["--export-marks=%s" % localmarks])

    filter = FastExportFilter(blob_callback   = lambda b: self.do_blob(b),
                              commit_callback = lambda c: self.do_commit(c))
    filter.run(source.stdout, target.stdin)

    if self.show_progress:
      sys.stdout.write("\nWaiting for git fast-import to complete...")
      sys.stdout.flush()
    target.stdin.close()
    target.wait()
    if self.show_progress:
      sys.stdout.write("done.\n")

    target_git_dir = Popen(["git", "rev-parse", "--git-dir"],
                 stdout=PIPE, cwd=self.target_repo).communicate()[0].strip()
    for filename in [localmarks, remotemarks]:
      hash = Popen(["git", "--git-dir=.", "hash-object", "-w", filename],
                 stdout = PIPE, cwd = target_git_dir).communicate()[0]
      collabdir = os.path.join(target_git_dir, 'refs', 'collab')
      if not os.path.isdir(collabdir):
        os.mkdir(collabdir)
      subname = filename == localmarks and 'localmap' or 'remotemap'
      file = open(os.path.join(collabdir, subname), 'w')
      file.write(hash)
      file.close()

def do_info():
  pass

def do_pull_grafts():
  pass

def do_push_grafts():
  pass

def do_clone():
  # Get the arguments
  if len(sys.argv) <= 2:
    raise SystemExit(get_syntax_string())
  repository = sys.argv[2]
  if not os.path.isdir(repository):
    raise SystemExit("%s does not appear to be a git repository" % repository)
  parser = OptionParser(usage=get_syntax_string())
  parser.add_option("--exclude", action="append", default=[], type="string",
                    dest="excludes")
  (options, args) = parser.parse_args(args=sys.argv[3:])
  if not args:
    args = ['--branches']

  # Make sure the current repository is sane
  (status, gitdir) = commands.getstatusoutput("git rev-parse --git-dir")
  if status != 0:
    raise SystemExit("collab.py must be run from a valid git repository")
  (status, output) = commands.getstatusoutput(
                       "find %s/objects -type f | head -n 1 | wc -l" % gitdir)
  if output != "0":
    raise SystemExit("'collab.py clone' must be called from an empty git repo.")

  # Run the filtering
  filter = GraftFilter(repository,
                       '.',
                       excludes = options.excludes,
                       includes = [],
                       fast_export_args = args)
  filter.run()
  pass

if   subcommand == 'info':        do_info()
elif subcommand == 'pull_grafts': do_pull_grafts()
elif subcommand == 'push_grafts': do_push_grafts()
elif subcommand == 'clone':       do_clone()
else:
  raise SystemExit("Assertion failed; unknown command: '%s'" % subcommand)
