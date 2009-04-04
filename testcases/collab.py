#!/usr/bin/env python

"""
An executable for creating a filtered clone and grafting
commits between the filtered and unfiltered repositories. See USAGE.
"""

import commands, os, sys, tempfile

from optparse import OptionParser
from subprocess import Popen, PIPE

from git_fast_filter import FastExportFilter, fast_export_output, \
                            fast_import_input, get_commit_count

USAGE = \
"""
Syntax:
  collab --help

  collab info
    Report the path to the original repo, the excludes and includes they
    had used, whether there were commits on collab/master that weren't
    on master, etc.

  collab pull-grafts
    Take commits from the original repository and add them
    to the collab/<branch> branches of the filtered repository

  collab push-grafts
    Take commits from this repository and place them in
    collab/<branch> branches of the original repository

  collab clone REPOSITORY [OPTIONS] [--] [REVISION LIMITING]
    Create a [filtered] clone of a repository.
Notes:
  REPOSITORY is a path to a repository, OPTIONS is some mix of
    --exclude=PATH
    --exclude-file=FILE-WITH-PATHS
    --include=PATH
    --include-file=FILE-WITH-PATHS
  and REVISION LIMITING is options acceptable to git log to reduce the total
  list of revisions, examples of which include
    --since='2 years ago'
    master~10000..master
    master 4.10 4.8 ^4.6

  If OPTIONS is not specified, everything is included.  If REVISION LIMITING
  is not specified, --branches is the default.

  Once the clone has completed, you'll need to run 'git merge collab/<branch>'
  in order to populate your working tree.
"""

###############################################################################
def record_content(git_dir, filename, content):
###############################################################################
  """
  Takes a string, calculates its hash, and stores the result in $filename.
  This will also record the string as a blob in git.
  """
  p = Popen(["git", "--git-dir=.", "hash-object", "-w", "--stdin"],
            stdin = PIPE, stdout = PIPE, cwd = git_dir)
  hash_value = p.communicate(content)[0]
  hash_file = open(filename, 'w')
  hash_file.write(hash_value)
  hash_file.close()

###############################################################################
def read_content(git_dir, refname):
###############################################################################
  """
  Takes a valid git ref (e.g. refs/collab/foo) and returns the content of
  the corresponding object as a string.
  """
  p = Popen(["git", "--git-dir=.", "cat-file", "-p", refname],
            stdout=PIPE, cwd = git_dir)
  return p.communicate()[0]

###############################################################################
###############################################################################
class GraftFilter(object):
###############################################################################
###############################################################################
  """
  This class implements the functionality that the tool provides.

  Some key implementation details:
  All of the data that needs to persist from one execution of the tool
  to another is recorded as a ref in git under refs/collab/DATA with
  DATA being one of:

  excludes  : The original excludes given to collab in the cloning
  includes  : The original includes given to collab in the cloning
  orig_repo : The handle to the repository collab cloned from
  localmap  : The commit-map from the POV of the local repository
  remotemap : The commit-map from the POV of the remote repository

  Important concept: commit-map. These maps map a mark* to a commit id
  (hash). The raw commit-ids will not necessarily be meaningful to
  both source and target repositories due to the presence of includes,
  excludes, and history chopping (since any of these will change the
  contents of certain commits). These keys allow us to refer to
  correlated commits in both repositories.

  *The notion of a mark is an important concept. Fast-export uses a simple
  int that is incremented once per exported object to identify the object
  without having to use it's sha1 hash. This is an ideal way for us to
  refer to commits in a portable way (has proper meaning in both source
  and target repo).
  """

  #############################################################################
  def __init__(self, source_repo, target_repo, fast_export_args = None):
  #############################################################################
    """
    Initialization
    """
    # The location of the original repo
    self._source_repo = source_repo

    # The location of the filtered-clone repo
    self._target_repo = target_repo

    # Extra args that need to be passed along to git
    self._fast_export_args = fast_export_args
    if not self._fast_export_args:
      self._fast_export_args = ['--branches']

    # Temporary file used to store source commit-maps in ascii. We use this
    # to grab the marks created by fast-exporting the source.
    self._sourcemarks = None

    # Temporary file used to store target commit-maps in ascii. We use this
    # to grab the marks created by fast-importing the target.
    self._targetmarks = None

    # The path prefixs that the user wants to exclude
    self._excludes = None

    # The path prefixs that the user wants to include
    self._includes = None

    # The path to the .git directory of the repository from which collab was
    # executed
    self._collab_git_dir = None

    # Flag that tells us to print text showing the progress of the operation
    self._show_progress = True

    # Number of objects processed; used only for showing progress
    self._object_count = 0

    # Number of commits processed; used only for showing progress
    self._commit_count = 0

    # Total number of commits in source repo; used only for showing progress
    self._total_commits = get_commit_count(source_repo,
                                           self._fast_export_args)

    # If no commits to clone, we're done
    if self._total_commits == 0:
      sys.stderr.write("There are no commits to clone.\n")
      sys.exit(0)

  #############################################################################
  def set_paths(self, excludes = None, includes = None):
  #############################################################################
    """
    Sets the exclude/include paths.
    """
    self._excludes = excludes
    if (self._excludes is None):
      self._excludes = []

    self._includes = includes
    if (self._includes is None):
      self._includes = ['']

  #############################################################################
  def _print_progress(self):
  #############################################################################
    """
    Print a quick message describing the progress of the operation.
    """
    if self._show_progress:
      print "\rRewriting commits... %d/%d  (%d objects)" \
            % (self._commit_count, self._total_commits, self._object_count),

  #############################################################################
  def _do_blob(self, blob):
  #############################################################################
    """
    The callback to be invoked when fast-export encounters a blob. We don't
    do anything important here, just maintain and print progress.
    """
    self._object_count += 1
    if self._object_count % 100 == 0:
      self._print_progress()

  #############################################################################
  def _do_commit(self, commit):
  #############################################################################
    """
    The callback to be invoked when fast-export encounters a commit object.
    We have to analyze the commit to find changes in the files we included.
    Note that, if all file changes are excluded, then FastExportFilter is
    smart enough to skip it all together.
    """
    # list to hold all changes we care about
    new_file_changes = []

    # Iterate over file_changes associated with this commit
    for change in commit.file_changes:
      include_it = None

      # See if change involved an included file
      for include in self._includes:
        if change.filename.startswith(include):
          include_it = True
          break

      # See if change involved an excluded file (overrides included status!).
      for exclude in self._excludes:
        if change.filename.startswith(exclude):
          include_it = False
          break

      # If file was in neither included or excluded, we have an error
      if include_it is None:
        raise SystemExit("File '%s' is not in the include or exclude list." %
                         change.filename)

      # Add change if it affected included file
      if include_it:
        new_file_changes.append(change)

    # Overwrite commit's file changes so that it only has changes associated
    # with included files.
    commit.file_changes = new_file_changes

    # Rename the affected branch
    commit.branch = commit.branch.replace('refs/heads/','refs/remotes/collab/')

    # Maintain and print progress info
    self._commit_count += 1
    self._print_progress()

  #############################################################################
  def _get_map_name(self, filename, include_git_dir = True):
  #############################################################################
    """
    Gets a handle to the data containing the map. This method will return
    either a raw filename or a handle that git will understand depending
    upon the value of include_git_dir.
    """
    if include_git_dir:
      collabdir = os.path.join(self._collab_git_dir, 'refs', 'collab')
    else:
      collabdir = os.path.join('refs', 'collab')

    if ( (filename == self._sourcemarks and self._source_repo == '.') or
         (filename == self._targetmarks and self._target_repo == '.') ):
      subname = 'localmap'
    else:
      subname = 'remotemap'

    return os.path.join(collabdir, subname)

  #############################################################################
  def _get_maps(self, filename):
  #############################################################################
    """
    Based on contents of file, create the key->commit-id map.
    """
    lines = open(filename,'r').read().strip().splitlines()

    mark_and_sha = lambda t: (int(t[0][1:]), t[1])

    return dict([mark_and_sha(line.split()) for line in lines])

  #############################################################################
  def _setup_files_and_excludes(self):
  #############################################################################
    """
    Setup _sourcemarks, _targetmarks, _collab_git_dir, _includes, _excludes,
    and _source_repo. If collab has been run on this directory before,
    much of this data will come from objects left behind from the previous
    run.
    """
    # Either the source or the target repo should be "."
    if self._source_repo != '.' and self._target_repo != '.':
      raise SystemExit("Must be run from collab-created repo location.")

    # Get the location of the .git directory for this repo
    (status, self._collab_git_dir) = \
      commands.getstatusoutput("git rev-parse --git-dir")
    if status != 0:
      raise SystemExit("collab.py must be run from a valid git repository")

    # If .git/refs/collab exists, this is not the first time we've used the
    # collab tool on this repository
    self._first_time = True
    if os.path.isdir(os.path.join(self._collab_git_dir, 'refs', 'collab')):
      self._first_time = False

    if self._first_time:
      # Check that excludes, includes have been set
      assert self._excludes is not None and self._includes is not None, \
             "set_paths() was not called"

      # Make sure the current repository is sane. The target needs to be
      # the cwd. Also, the target repo should not have any git objects.
      assert self._target_repo == '.', "Target should be the current directory"
      (status, output) = \
        commands.getstatusoutput(
          "find %s/objects -type f | head -n 1 | wc -l"
          % self._collab_git_dir)
      if output != "0":
        raise SystemExit("collab clone must be called from an empty git repo.")

      # Create the sourcemarks and targetmarks empty files, get their names
      (file_obj, self._sourcemarks) = tempfile.mkstemp()
      os.close(file_obj)
      (file_obj, self._targetmarks) = tempfile.mkstemp()
      os.close(file_obj)
    else:
      # Get the souremarks and targetmarks temp files. Write the map contents
      # to them.
      (file_obj, self._sourcemarks) = tempfile.mkstemp()
      mapname = self._get_map_name(self._sourcemarks, include_git_dir=False)
      os.write(file_obj, read_content(self._collab_git_dir, mapname))
      os.close(file_obj)

      (file_obj, self._targetmarks) = tempfile.mkstemp()
      mapname = self._get_map_name(self._targetmarks, include_git_dir=False)
      os.write(file_obj, read_content(self._collab_git_dir, mapname))
      os.close(file_obj)

      # Get the excludes and includes, unless overridden
      if self._excludes is None:
        self._excludes = \
          read_content(self._collab_git_dir, "refs/collab/excludes").split()
      if self._includes is None:
        self._includes = \
          read_content(self._collab_git_dir, "refs/collab/includes").split()
        if not self._includes:
          self._includes = ['']

      # Get the remote repository if not specified
      if self._source_repo is None and self._target_repo is None:
        raise SystemExit("You are using code written by a moron.")
      orig_repo = \
        read_content(self._collab_git_dir, "refs/collab/orig_repo").strip()
      if self._source_repo is None:
        self._source_repo = orig_repo
      if self._target_repo is None:
        self._target_repo = orig_repo

  #############################################################################
  def run(self):
  #############################################################################
    # Set members based on data from previous runs
    self._setup_files_and_excludes()

    # Setup the source and target processes. The source process will produce
    # fast-export output for the source repo, this output will be passed
    # through FastExportFilter which will manipulate the output using our
    # callbacks, finally, the manipulated output will be given to the
    # fast-import process and used to create the target repo.
    # (This should update sourcemarks and targetmarks)
    source = \
      fast_export_output(self._source_repo,
                       ["--export-marks=%s" % self._sourcemarks,
                        "--import-marks=%s" % self._sourcemarks]
                       + self._fast_export_args)
    target = \
      fast_import_input( self._target_repo,
                       ["--export-marks=%s" % self._targetmarks,
                        "--import-marks=%s" % self._targetmarks])

    filt = FastExportFilter(blob_callback   = lambda b: self._do_blob(b),
                            commit_callback = lambda c: self._do_commit(c))
    filt.run(source.stdout, target.stdin)

    # Show progress
    if self._show_progress:
      sys.stdout.write("\nWaiting for git fast-import to complete...")
      sys.stdout.flush()
    target.stdin.close()
    target.wait() # need to wait for fast-import process to finish
    if self._show_progress:
      sys.stdout.write("done.\n")

    # Record the sourcemarks and targetmarks -- 2 steps

    # Step 1: Make sure the source and target marks have the same mark numbers.
    # Not doing this would allow one end of the grafting to reuse a number
    # that would then be misconnected on the other side.
    sourcemaps = self._get_maps(self._sourcemarks)
    targetmaps = self._get_maps(self._targetmarks)
    for key in sourcemaps.keys():
      if key not in targetmaps:
        del sourcemaps[key]
    for key in targetmaps.keys():
      if key not in sourcemaps:
        del targetmaps[key]

    # Step 2: Record the data
    for set_obj in [(sourcemaps, self._sourcemarks),
                    (targetmaps, self._targetmarks)]:
      # get raw filename for source/target
      mapname = self._get_map_name(set_obj[1])

      # create refs/collab if it's not there
      if not os.path.isdir(os.path.dirname(mapname)):
        os.mkdir(os.path.dirname(mapname))

      # compute string content of commit-map
      content = ''.join([":%d %s\n" % (k,v) for k,v in set_obj[0].iteritems()])

      # record content in the object database
      record_content(self._collab_git_dir, mapname, content)

    # Check if we are running from the target
    if self._target_repo == '.':
      # Record the excludes and includes so they can be reused next time
      for set_obj in [(self._excludes, 'excludes'),
                      (self._includes, 'includes')]:
        filename = os.path.join(self._collab_git_dir, 'refs',
                                'collab', set_obj[1])
        record_content(self._collab_git_dir, filename,
                       '\n'.join(set_obj[0]) + '\n')

      # Record source_repo as the original repository
      filename = os.path.join(self._collab_git_dir, 'refs',
                              'collab', 'orig_repo')
      record_content(self._collab_git_dir, filename, self._source_repo+'\n')

###############################################################################
def _main_func():
###############################################################################
  parser = OptionParser(usage=USAGE)

  parser.add_option("--exclude", action="append", default=[], type="string",
                    dest="excludes")
  parser.add_option("--include", action="append", default=[], type="string",
                    dest="includes")
  (options, args) = parser.parse_args()

  if (not args):
    raise SystemExit("Missing command\n\n" + USAGE)
  if (not options.includes):
    options.includes.append("")

  subcommand = args[0]
  if (subcommand not in ['info', 'pull-grafts', 'push-grafts', 'clone']):
    raise SystemExit("Unrecognized command: %s\n\n%s" % (subcommand, USAGE))

  if (subcommand == "info"):
    #JGF TODO
    pass
  elif (subcommand == "pull-grafts"):
    graft_filter = GraftFilter(None, '.')
    graft_filter.run()
  elif (subcommand == "push-grafts"):
    graft_filter = GraftFilter('.', None)
    graft_filter.run()
  elif (subcommand == "clone"):
    # Get the arguments
    if len(args) < 2:
      raise SystemExit("Missing repository\n\n" + USAGE)
    repository = args[1]

    if (not os.path.isdir(repository)):
      raise SystemExit("%s does not appear to be a git repository"
                       % repository)

    # Run the filtering
    graft_filter = GraftFilter(repository, '.', fast_export_args = args[2:])
    graft_filter.set_paths(excludes = options.excludes,
                           includes = options.includes)
    graft_filter.run()
  else:
    assert False, "Unhandled command: " + subcommand

  sys.exit(0)

###############################################################################
if (__name__ == "__main__"):
###############################################################################
  _main_func()
