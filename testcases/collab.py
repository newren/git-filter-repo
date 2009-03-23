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

def record_content(git_dir, filename, content):
  p = Popen(["git", "--git-dir=.", "hash-object", "-w", "--stdin"],
            stdin = PIPE, stdout = PIPE, cwd = git_dir)
  hash = p.communicate(content)[0]
  file = open(filename, 'w')
  file.write(hash)
  file.close()

def read_content(git_dir, refname):
  p = Popen(["git", "--git-dir=.", "cat-file", "-p", refname],
            stdout=PIPE, cwd = git_dir)
  return p.communicate()[0]

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

  def set_paths(self, excludes = [], includes = ['']):
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
    new_file_changes = []
    for change in commit.file_changes:
      include_it = None
      for include in self.includes:
        if change.filename.startswith(include):
          include_it = True
          break
      for exclude in self.excludes:
        if change.filename.startswith(exclude):
          include_it = False
          break
      if include_it is None:
        raise SystemExit("File '%s' is not in the include or exclude list." %
                         change.filename)
      if include_it:
        new_file_changes.append(change)
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

  def _get_maps(self, filename):
    lines = open(filename,'r').read().strip().splitlines()
    mark_and_sha = lambda t: (int(t[0][1:]), t[1])
    return dict([mark_and_sha(line.split()) for line in lines])

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
      mapname = self._get_map_name(self.sourcemarks, include_git_dir=False)
      os.write(file, read_content(self.collab_git_dir, mapname))
      os.close(file)

      (file, self.targetmarks) = tempfile.mkstemp()
      mapname = self._get_map_name(self.targetmarks, include_git_dir=False)
      os.write(file, read_content(self.collab_git_dir, mapname))
      os.close(file)

      # Get the excludes and includes, unless overridden
      if self.excludes is None:
        self.excludes = \
          read_content(self.collab_git_dir, "refs/collab/excludes").split()
      if self.includes is None:
        self.includes = \
          read_content(self.collab_git_dir, "refs/collab/includes").split()
        if not self.includes:
          self.includes = ['']

      # Get the remote repository if not specified
      if self.source_repo is None and self.target_repo is None:
        raise SystemExit("You are using code written by a moron.")
      orig_repo = \
        read_content(self.collab_git_dir, "refs/collab/orig_repo").strip()
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

    # Record the sourcemarks and targetmarks -- 2 steps

    # Step 1: Make sure the source and target marks have the same mark numbers.
    # Not doing this would allow one end of the grafting to reuse a number
    # that would then be misconnected on the other side.
    sourcemaps = self._get_maps(self.sourcemarks)
    targetmaps = self._get_maps(self.targetmarks)
    for key in sourcemaps.keys():
      if key not in targetmaps:
        del sourcemaps[key]
    for key in targetmaps.keys():
      if key not in sourcemaps:
        del targetmaps[key]
    # Step 2: Record the data
    for set in [(sourcemaps, self.sourcemarks), (targetmaps, self.targetmarks)]:
      mapname = self._get_map_name(set[1])
      if not os.path.isdir(os.path.dirname(mapname)):
        os.mkdir(os.path.dirname(mapname))
      content = ''.join([":%d %s\n" % (k, v) for k,v in set[0].iteritems()])
      record_content(self.collab_git_dir, mapname, content)

    if self.target_repo == '.':
      # Record the excludes and includes so they can be reused next time
      for set in [(self.excludes, 'excludes'), (self.includes, 'includes')]:
        filename = os.path.join(self.collab_git_dir, 'refs', 'collab', set[1])
        record_content(self.collab_git_dir, filename, '\n'.join(set[0])+'\n')

      # Record source_repo as the original repository
      filename = os.path.join(self.collab_git_dir, 'refs', 'collab', 'orig_repo')
      record_content(self.collab_git_dir, filename, self.source_repo+'\n')

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
  parser.add_option("--include", action="append", default=[], type="string",
                    dest="includes")
  (options, args) = parser.parse_args(args=sys.argv[3:])
  if not options.includes:
    options.includes=['']

  # Run the filtering
  filter = GraftFilter(repository, '.', fast_export_args = args)
  filter.set_paths(excludes = options.excludes, includes = options.includes)
  filter.run()

if   subcommand == 'info':        do_info()
elif subcommand == 'pull-grafts': do_pull_grafts()
elif subcommand == 'push-grafts': do_push_grafts()
elif subcommand == 'clone':       do_clone()
else:
  raise SystemExit("Assertion failed; unknown command: '%s'" % subcommand)
