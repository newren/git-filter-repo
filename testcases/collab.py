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
  def __init__(self, source_repo, target_repo, fast_export_args = []):
    self.source_repo = source_repo
    self.target_repo = target_repo
    self.fast_export_args = fast_export_args
    if not self.fast_export_args:
      self.fast_export_args = ['--branches']
    self.sourcemarks = None
    self.targetmarks = None
    self.excludes = None
    self.includes = None
    self.collab_git_dir = None

    self.show_progress = True
    self.object_count = 0
    self.commit_count = 0
    self.total_commits = get_commit_count(source_repo, self.fast_export_args)
    if self.total_commits == 0:
      sys.stderr.write("There are no commits to clone.\n")
      sys.exit(0)

  def set_paths(self, excludes = [], includes = []):
    self.excludes = excludes
    self.includes = includes

  def _print_progress(self):
    if self.show_progress:
      print "\rRewriting commits... %d/%d  (%d objects)" \
            % (self.commit_count, self.total_commits, self.object_count),

  def _do_blob(self, blob):
    self.object_count += 1
    if self.object_count % 100 == 0:
      self._print_progress()

  def _do_commit(self, commit):
    if self.excludes:
      new_file_changes = [change for change in commit.file_changes
                          if change.filename not in self.excludes]
      commit.file_changes = new_file_changes
    commit.branch = commit.branch.replace('refs/heads/','refs/remotes/collab/')
    self.commit_count += 1
    self._print_progress()

  def _get_map_name(self, filename, include_git_dir = True):
    if include_git_dir:
      collabdir = os.path.join(self.collab_git_dir, 'refs', 'collab')
    else:
      collabdir = os.path.join('refs', 'collab')
    if (filename == self.sourcemarks and self.source_repo == '.') or \
       (filename == self.targetmarks and self.target_repo == '.'):
      subname = 'localmap'
    else:
      subname = 'remotemap'
    return os.path.join(collabdir, subname)

  def _setup_files_and_excludes(self):
    if self.source_repo != '.' and self.target_repo != '.':
      raise SystemExit("Must be run from collab-created repo location.")
    (status, self.collab_git_dir) = \
      commands.getstatusoutput("git rev-parse --git-dir")
    if status != 0:
      raise SystemExit("collab.py must be run from a valid git repository")

    self.first_time = True
    if os.path.isdir(os.path.join(self.collab_git_dir, 'refs', 'collab')):
      self.first_time = False

    if self.first_time:
      if self.excludes is None or self.includes is None:
        raise SystemExit("Assertion failed: called set_paths() == True")

      # Make sure the current repository is sane
      if self.target_repo != '.':
        raise SystemExit("Assertion failed: Program written correctly == True")
      (status, output) = \
        commands.getstatusoutput(
          "find %s/objects -type f | head -n 1 | wc -l" % self.collab_git_dir)
      if output != "0":
        raise SystemExit("collab clone must be called from an empty git repo.")

      # Create the sourcemarks and targetmarks empty files, get their names
      (file, self.sourcemarks) = tempfile.mkstemp()
      os.close(file)
      (file, self.targetmarks) = tempfile.mkstemp()
      os.close(file)
    else:
      # Get the souremarks and targetmarks
      (file, self.sourcemarks) = tempfile.mkstemp()
      Popen(["git", "--git-dir=.", "cat-file", "-p",
             self._get_map_name(self.sourcemarks, include_git_dir=False)],
            stdout=file, cwd = self.collab_git_dir).wait()
      os.close(file)

      (file, self.targetmarks) = tempfile.mkstemp()
      Popen(["git", "--git-dir=.", "cat-file", "-p",
             self._get_map_name(self.targetmarks, include_git_dir=False)],
            stdout=file, cwd = self.collab_git_dir).wait()
      os.close(file)

      # Get the excludes and includes, unless overridden
      if self.excludes is None:
        p = Popen(["git", "--git-dir=.", "cat-file", "-p",
                   "refs/collab/excludes"],
                  stdout=PIPE, cwd = self.collab_git_dir)
        self.excludes = p.communicate()[0].split()
      if self.includes is None:
        p = Popen(["git", "--git-dir=.", "cat-file", "-p",
                   "refs/collab/includes"],
                  stdout=PIPE, cwd = self.collab_git_dir)
        self.includes = p.communicate()[0].split()

      # Get the remote repository if not specified
      if self.source_repo is None and self.target_repo is None:
        raise SystemExit("You are using code written by a moron.")
      p = Popen(["git", "--git-dir=.", "cat-file", "-p",
                "refs/collab/orig_repo"],
                stdout=PIPE, cwd = self.collab_git_dir)
      orig_repo = p.communicate()[0].strip()
      if self.source_repo is None:
        self.source_repo = orig_repo
      if self.target_repo is None:
        self.target_repo = orig_repo

  def run(self):
    self._setup_files_and_excludes()

    source = \
      FastExportOutput(self.source_repo,
                       ["--export-marks=%s" % self.sourcemarks,
                        "--import-marks=%s" % self.sourcemarks]
                       + self.fast_export_args)
    target = \
      FastImportInput( self.target_repo,
                       ["--export-marks=%s" % self.targetmarks,
                        "--import-marks=%s" % self.targetmarks])

    filter = FastExportFilter(blob_callback   = lambda b: self._do_blob(b),
                              commit_callback = lambda c: self._do_commit(c))
    filter.run(source.stdout, target.stdin)

    if self.show_progress:
      sys.stdout.write("\nWaiting for git fast-import to complete...")
      sys.stdout.flush()
    target.stdin.close()
    target.wait()
    if self.show_progress:
      sys.stdout.write("done.\n")

    # Record the sourcemarks and targetmarks
    for filename in [self.sourcemarks, self.targetmarks]:
      hash = Popen(["git", "--git-dir=.", "hash-object", "-w", filename],
                   stdout = PIPE, cwd = self.collab_git_dir).communicate()[0]
      mapname = self._get_map_name(filename)
      if not os.path.isdir(os.path.dirname(mapname)):
        os.mkdir(os.path.dirname(mapname))
      file = open(mapname, 'w')
      file.write(hash)
      file.close()

    if self.target_repo == '.':
      # Record the excludes and includes so they can be reused next time
      for set in [(self.excludes, 'excludes'), (self.includes, 'includes')]:
        p = Popen(["git", "--git-dir=.", "hash-object", "-w", "--stdin"],
                  stdin = PIPE, stdout = PIPE, cwd = self.collab_git_dir)
        hash = p.communicate('\n'.join(set[0])+'\n')[0]
        filename = os.path.join(self.collab_git_dir, 'refs', 'collab', set[1])
        file = open(filename, 'w')
        file.write(hash)
        file.close()

      # Record source_repo as the original repository
      p = Popen(["git", "--git-dir=.", "hash-object", "-w", "--stdin"],
                stdin=PIPE, stdout=PIPE, cwd=self.collab_git_dir)
      hash = p.communicate(self.source_repo+'\n')[0].strip()
      filename = os.path.join(self.collab_git_dir, 'refs', 'collab', 'orig_repo')
      file = open(filename, 'w')
      file.write(hash)
      file.close()

def do_info():
  pass

def do_pull_grafts():
  filter = GraftFilter(None, '.')
  filter.run()

def do_push_grafts():
  filter = GraftFilter('.', None)
  filter.run()

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

  # Run the filtering
  filter = GraftFilter(repository, '.', fast_export_args = args)
  filter.set_paths(excludes = options.excludes, includes = [])
  filter.run()

if   subcommand == 'info':        do_info()
elif subcommand == 'pull-grafts': do_pull_grafts()
elif subcommand == 'push-grafts': do_push_grafts()
elif subcommand == 'clone':       do_clone()
else:
  raise SystemExit("Assertion failed; unknown command: '%s'" % subcommand)
