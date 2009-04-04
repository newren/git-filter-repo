"""
We provide a class (FastExportFilter) for parsing and handling the output
from fast-export. This class allows the user to register callbacks when
various types of data are encountered in the export output. The basic idea
is that FastExportFilter takes fast-export output, creates the various
objects as it encounters them, the user gets to use/modify these objects
via callbacks, and finally FastExportFilter writes these objects in
fast-export form (presumably so they can be used to create a new repo).
"""

import os, re, sys

from subprocess import Popen, PIPE, call
from email.Utils import unquote
from datetime import tzinfo, timedelta, datetime

__all__ = ["Blob", "Reset", "FileChanges", "Commit", "Tag", "Progress",
           "Checkpoint", "FastExportFilter",
           "fast_export_output", "fast_import_input", "get_commit_count",
           "get_total_objects", "record_id_rename"]

###############################################################################
def _timedelta_to_seconds(delta):
###############################################################################
  """
  Converts timedelta to seconds
  """
  offset = delta.days*86400 + delta.seconds + (delta.microseconds+0.0)/1000000
  return round(offset)

###############################################################################
def _write_date(file_, date):
###############################################################################
  """
  Writes a date to a file. The file should already be open. The date is
  written as seconds-since-epoch followed by the name of the timezone.
  """
  epoch = datetime.fromtimestamp(0, date.tzinfo)
  file_.write('%d %s' % (_timedelta_to_seconds(date - epoch),
                         date.tzinfo.tzname(0)))

###############################################################################
###############################################################################
class _TimeZone(tzinfo):
###############################################################################
###############################################################################
  """
  Fixed offset in minutes east from UTC.
  """

  #############################################################################
  def __init__(self, offset_string):
  #############################################################################
    tzinfo.__init__(self)
    minus, hh, mm = re.match(r'^([-+]?)(\d\d)(\d\d)$', offset_string).groups()
    sign = minus and -1 or 1
    self._offset = timedelta(minutes = sign*(60*int(hh) + int(mm)))
    self._offset_string = offset_string

  def utcoffset(self, dt):
    return self._offset

  def tzname(self, dt):
    return self._offset_string

  def dst(self, dt):
    return timedelta(0)

###############################################################################
###############################################################################
class _IDs(object):
###############################################################################
###############################################################################
  """
  A class that maintains the 'name domain' of all the 'marks' (short int
  id for a blob/commit git object). The reason this mechanism is necessary
  is because the text of fast-export may refer to an object using a different
  mark than the mark that was assigned to that object using IDS.new(). This
  class allows you to translate the fast-export marks (old) to the marks
  assigned from IDS.new() (new).

  Note that there are two reasons why the marks may differ: (1) The
  user manually creates Blob or Commit objects (for insertion into the
  stream) (2) We're reading the data from two different repositories
  and trying to combine the data (git fast-export will number ids from
  1...n, and having two 1's, two 2's, two 3's, causes issues).
  """

  #############################################################################
  def __init__(self):
  #############################################################################
    """
    Init
    """
    # The id for the next created blob/commit object
    self._next_id = 1

    # A map of old-ids to new-ids (1:1 map)
    self._translation = {}

    # A map of new-ids to every old-id that points to the new-id (1:N map)
    self._reverse_translation = {}

  #############################################################################
  def new(self):
  #############################################################################
    """
    Should be called whenever a new blob or commit object is created. The
    returned value should be used as the id/mark for that object.
    """
    rv = self._next_id
    self._next_id += 1
    return rv

  #############################################################################
  def record_rename(self, old_id, new_id, handle_transitivity = False):
  #############################################################################
    """
    Record that old_id is being renamed to new_id.
    """
    if old_id != new_id:
      # old_id -> new_id
      self._translation[old_id] = new_id

      # Transitivity will be needed if new commits are being inserted mid-way
      # through a branch.
      if handle_transitivity:
        # Anything that points to old_id should point to new_id
        if old_id in self._reverse_translation:
          for id_ in self._reverse_translation[old_id]:
            self._translation[id_] = new_id

      # Record that new_id is pointed to by old_id
      if new_id not in self._reverse_translation:
        self._reverse_translation[new_id] = []
      self._reverse_translation[new_id].append(old_id)

  #############################################################################
  def translate(self, old_id):
  #############################################################################
    """
    If old_id has been mapped to an alternate id, return the alternate id.
    """
    if old_id in self._translation:
      return self._translation[old_id]
    else:
      return old_id

  #############################################################################
  def __str__(self):
  #############################################################################
    """
    Convert IDs to string; used for debugging
    """
    rv = "Current count: %d\nTranslation:\n" % self._next_id
    for k in sorted(self._translation):
      rv += "  %d -> %d\n" % (k, self._translation[k])

    rv += "Reverse translation:\n"
    for k in sorted(self._reverse_translation):
      rv += "  " + str(k) + " -> " + str(self._reverse_translation[k]) + "\n"

    return rv

  #############################################################################
  def _avoid_ids_below(skip_value, self):
  #############################################################################
    """
    Make sure that git_fast_filter doesn't use ids <= skip_value
    """
    self._next_id = max(self._next_id, skip_value + 1)

###############################################################################
###############################################################################
class _GitElement(object):
###############################################################################
###############################################################################
  """
  The base class for all git elements that we create.
  """

  #############################################################################
  def __init__(self):
  #############################################################################
    # A string that describes what type of Git element this is
    self.type = None

    # A flag telling us if this Git element has been dumped
    # (i.e. printed) or skipped.  Typically elements that have been
    # dumped or skipped will not be dumped again.
    self.dumped = 0

  #############################################################################
  def dump(self, file_):
  #############################################################################
    """
    This version should never be called. Derived classes need to
    override! We should note that subclasses should implement this
    method such that the output would match the format produced by
    fast-export.
    """
    raise SystemExit("Unimplemented function: %s.dump()" % type(self).__name__)

  #############################################################################
  def skip(self, new_id=None):
  #############################################################################
    """
    Ensures this element will not be written to output
    """
    self.dumped = 2

###############################################################################
###############################################################################
class _GitElementWithId(_GitElement):
###############################################################################
###############################################################################
  """
  The base class for Git elements that have IDs (commits and blobs)
  """

  #############################################################################
  def __init__(self):
  #############################################################################
    _GitElement.__init__(self)

    # The mark (short, portable id) for this element
    self.id = _IDS.new()

    # The previous mark for this element
    self.old_id = None

  #############################################################################
  def skip(self, new_id=None):
  #############################################################################
    """
    This element will no longer be automatically written to output. When a
    commit gets skipped, it's ID will need to be translated to that of its
    parent.
    """
    self.dumped = 2

    _IDS.record_rename(self.old_id or self.id, new_id)

###############################################################################
###############################################################################
class Blob(_GitElementWithId):
###############################################################################
###############################################################################
  """
  This class defines our representation of git blob elements (i.e. our
  way of representing file contents).
  """

  #############################################################################
  def __init__(self, data):
  #############################################################################
    _GitElementWithId.__init__(self)

    # Denote that this is a blob
    self.type = 'blob'

    # Stores the blob's data
    self.data = data

  #############################################################################
  def dump(self, file_):
  #############################################################################
    """
    Write this blob element to a file.
    """
    self.dumped = 1

    file_.write('blob\n')
    file_.write('mark :%d\n' % self.id)
    file_.write('data %d\n%s' % (len(self.data), self.data))
    file_.write('\n')


###############################################################################
###############################################################################
class Reset(_GitElement):
###############################################################################
###############################################################################
  """
  This class defines our representation of git reset elements.  A reset
  event is the creation (or recreation) of a named branch, optionally
  starting from a specific revision).
  """

  #############################################################################
  def __init__(self, ref, from_ref = None):
  #############################################################################
    _GitElement.__init__(self)

    # Denote that this is a reset
    self.type = 'reset'

    # The name of the branch being (re)created
    self.ref = ref

    # Some reference to the branch/commit we are resetting from
    self.from_ref = from_ref

  #############################################################################
  def dump(self, file_):
  #############################################################################
    """
    Write this reset element to a file
    """
    self.dumped = 1

    file_.write('reset %s\n' % self.ref)
    if self.from_ref:
      file_.write('from :%d\n' % self.from_ref)
      file_.write('\n')

###############################################################################
###############################################################################
class FileChanges(_GitElement):
###############################################################################
###############################################################################
  """
  This class defines our representation of file change elements. File change
  elements are components within a Commit element.
  """

  #############################################################################
  def __init__(self, type_, filename, id_ = None, mode = None):
  #############################################################################
    _GitElement.__init__(self)

    # Denote the type of file-change (M for modify, D for delete, etc)
    self.type = type_

    # Record the name of the file being changed
    self.filename = filename

    # Record the mode (mode describes type of file entry (non-executable,
    # executable, or symlink)).
    self.mode = None

    # blob_id is the id (mark) of the affected blob
    self.blob_id = None

    # For 'M' file changes (modify), expect to have id and mode
    if type_ == 'M':
      if mode is None:
        raise SystemExit("file mode and idnum needed for %s" % filename)
      self.mode = mode
      self.blob_id = id_

  #############################################################################
  def dump(self, file_):
  #############################################################################
    """
    Write this file-change element to a file
    """
    skipped_blob = (self.type == 'M' and self.blob_id is None)
    if skipped_blob: return
    self.dumped = 1

    if self.type == 'M':
      file_.write('M %s :%d %s\n' % (self.mode, self.blob_id, self.filename))
    elif self.type == 'D':
      file_.write('D %s\n' % self.filename)
    else:
      raise SystemExit("Unhandled filechange type: %s" % self.type)

###############################################################################
###############################################################################
class Commit(_GitElementWithId):
###############################################################################
###############################################################################
  """
  This class defines our representation of commit elements. Commit elements
  contain all the information associated with a commit.
  """

  #############################################################################
  def __init__(self, branch,
               author_name,    author_email,    author_date,
               committer_name, committer_email, committer_date,
               message,
               file_changes,
               from_commit = None,
               merge_commits = [],
               **kwargs):
  #############################################################################
    _GitElementWithId.__init__(self)

    # Denote that this is a commit element
    self.type = 'commit'

    # Record the affected branch
    self.branch = branch

    # Record author's name
    self.author_name  = author_name

    # Record author's email
    self.author_email = author_email

    # Record date of authoring
    self.author_date  = author_date

    # Record committer's name
    self.committer_name  = committer_name

    # Record committer's email
    self.committer_email = committer_email

    # Record date the commit was made
    self.committer_date  = committer_date

    # Record commit message
    self.message = message

    # List of file-changes associated with this commit. Note that file-changes
    # are also represented as git elements
    self.file_changes = file_changes

    # Record the commit to initialize this branch from. This revision will be
    # the first parent of the new commit
    self.from_commit = from_commit

    # Record additional parent commits
    self.merge_commits = merge_commits

    # Member below is necessary for workaround fast-import's/fast-export's
    # weird handling of merges.
    self.stream_number = 0
    if "stream_number" in kwargs:
      self.stream_number = kwargs["stream_number"]

  #############################################################################
  def dump(self, file_):
  #############################################################################
    """
    Write this commit element to a file.
    """
    self.dumped = 1

    # Workaround fast-import/fast-export weird handling of merges
    if self.stream_number != _CURRENT_STREAM_NUMBER:
      _EXTRA_CHANGES[self.id] = [[change for change in self.file_changes]]

    merge_extra_changes = []
    for parent in self.merge_commits:
      if parent in _EXTRA_CHANGES:
        merge_extra_changes += _EXTRA_CHANGES[parent]

    for additional_changes in merge_extra_changes:
      self.file_changes += additional_changes

    if self.stream_number == _CURRENT_STREAM_NUMBER:
      parent_extra_changes = []
      if self.from_commit and self.from_commit in _EXTRA_CHANGES:
        parent_extra_changes = _EXTRA_CHANGES[self.from_commit]
      parent_extra_changes += merge_extra_changes
      _EXTRA_CHANGES[self.id] = parent_extra_changes
    # End workaround

    file_.write('commit %s\n' % self.branch)
    file_.write('mark :%d\n' % self.id)
    file_.write('author %s <%s> ' % (self.author_name, self.author_email))
    _write_date(file_, self.author_date)
    file_.write('\n')
    file_.write('committer %s <%s> ' % \
                     (self.committer_name, self.committer_email))
    _write_date(file_, self.committer_date)
    file_.write('\n')
    file_.write('data %d\n%s' % (len(self.message), self.message))
    if self.from_commit:
      file_.write('from :%s\n' % self.from_commit)
    for ref in self.merge_commits:
      file_.write('merge :%s\n' % ref)
    for change in self.file_changes:
      change.dump(file_)
    file_.write('\n')

  #############################################################################
  def get_parents(self):
  #############################################################################
    """
    Return all parent commits
    """
    my_parents = []
    if self.from_commit:
      my_parents.append(self.from_commit)
    my_parents += self.merge_commits
    return my_parents

  #############################################################################
  def first_parent(self):
  #############################################################################
    """
    Return first parent commit
    """
    my_parents = self.get_parents()
    if my_parents:
      return my_parents[0]
    return None

###############################################################################
###############################################################################
class Tag(_GitElement):
###############################################################################
###############################################################################
  """
  This class defines our representation of annotated tag elements.
  """

  #############################################################################
  def __init__(self, ref, from_ref,
               tagger_name, tagger_email, tagger_date, tag_msg):
  #############################################################################
    _GitElement.__init__(self)

    # Denote that this is a tag element
    self.type = 'tag'

    # Store the name of the tag
    self.ref = ref

    # Store the entity being tagged (this should be a commit)
    self.from_ref = from_ref

    # Store the name of the tagger
    self.tagger_name  = tagger_name

    # Store the email of the tagger
    self.tagger_email = tagger_email

    # Store the date
    self.tagger_date  = tagger_date

    # Store the tag message
    self.tag_message = tag_msg

  #############################################################################
  def dump(self, file_):
  #############################################################################
    """
    Write this tag element to a file
    """

    self.dumped = 1

    file_.write('tag %s\n' % self.ref)
    file_.write('from :%d\n' % self.from_ref)
    file_.write('tagger %s <%s> ' % (self.tagger_name, self.tagger_email))
    _write_date(file, self.tagger_date)
    file_.write('\n')
    file_.write('data %d\n%s' % (len(self.tag_message), self.tag_message))
    file_.write('\n')

###############################################################################
###############################################################################
class Progress(_GitElement):
###############################################################################
###############################################################################
  """
  This class defines our representation of progress elements. The progress
  element only contains a progress message, which is printed by fast-import
  when it processes the progress output.
  """

  #############################################################################
  def __init__(self, message):
  #############################################################################
    _GitElement.__init__(self)

    # Denote that this is a progress element
    self.type = 'progress'

    # Store the progress message
    self.message = message

  #############################################################################
  def dump(self, file_):
  #############################################################################
    """
    Write this progress element to a file
    """
    self.dumped = 1

    file_.write('progress %s\n' % self.message)
    #file_.write('\n')

###############################################################################
###############################################################################
class Checkpoint(_GitElement):
###############################################################################
###############################################################################
  """
  This class defines our representation of checkpoint elements.  These
  elements represent events which force fast-import to close the current
  packfile, start a new one, and to save out all current branch refs, tags
  and marks.
  """

  #############################################################################
  def __init__(self, message):
  #############################################################################
    _GitElement.__init__(self)

    # Denote that this is a checkpoint element
    self.type = 'checkpoint'

  #############################################################################
  def dump(self, file_):
  #############################################################################
    """
    Write this checkpoint element to a file
    """
    self.dumped = 1

    file_.write('checkpoint\n')
    file_.write('\n')

###############################################################################
###############################################################################
class FastExportFilter(object):
###############################################################################
###############################################################################
  """
  A class for parsing and handling the output from fast-export. This
  class allows the user to register callbacks when various types of
  data are encountered in the fast-export output. The basic idea is that,
  FastExportFilter takes fast-export output, creates the various objects
  as it encounters them, the user gets to use/modify these objects via
  callbacks, and finally FastExportFilter outputs the modified objects
  in fast-import format (presumably so they can be used to create a new
  repo).
  """

  #############################################################################
  def __init__(self, 
               tag_callback = None,   commit_callback = None,
               blob_callback = None,  progress_callback = None,
               reset_callback = None, checkpoint_callback = None,
               everything_callback = None):
  #############################################################################
    # Members below simply store callback functions for the various git
    # elements
    self._tag_callback        = tag_callback
    self._blob_callback       = blob_callback
    self._reset_callback      = reset_callback
    self._commit_callback     = commit_callback
    self._progress_callback   = progress_callback
    self._checkpoint_callback = checkpoint_callback
    self._everything_callback = everything_callback

    # A handle to the input source for the fast-export data
    self._input = None

    # A handle to the output file for the output we generate (we call dump
    # on many of the git elements we create).
    self._output = None

    # Stores the contents of the current line of input being parsed
    self._currentline = ''

    # Stores a translation of ids, useful when reading the output of a second
    # or third (or etc.) git fast-export output stream
    self._id_offset = 0

  #############################################################################
  def _advance_currentline(self):
  #############################################################################
    """
    Grab the next line of input
    """
    self._currentline = self._input.readline()

  #############################################################################
  def _parse_optional_mark(self):
  #############################################################################
    """
    If the current line contains a mark, parse it and advance to the
    next line; return None otherwise
    """
    mark = None
    matches = re.match('mark :(\d+)\n$', self._currentline)
    if matches:
      mark = int(matches.group(1))+self._id_offset
      self._advance_currentline()
    return mark

  #############################################################################
  def _parse_optional_parent_ref(self, refname):
  #############################################################################
    """
    If the current line contains a reference to a parent commit, then
    parse it and advance the current line; otherwise return None. Note
    that the name of the reference ('from', 'merge') must match the
    refname arg.
    """
    baseref = None
    matches = re.match('%s :(\d+)\n' % refname, self._currentline)
    if matches:
      # We translate the parent commit mark to what it needs to be in
      # our mark namespace
      baseref = _IDS.translate( int(matches.group(1))+self._id_offset )
      self._advance_currentline()
    return baseref

  #############################################################################
  def _parse_optional_filechange(self):
  #############################################################################
    """
    If the current line contains a file-change object, then parse it
    and advance the current line; otherwise return None. We only care
    about file changes of type 'M' and 'D' (these are the only types
    of file-changes that fast-export will provide).
    """
    filechange = None
    if self._currentline.startswith('M '):
      (mode, idnum, path) = \
        re.match('M (\d+) :(\d+) (.*)\n$', self._currentline).groups()
      # We translate the idnum to our id system
      idnum = _IDS.translate( int(idnum)+self._id_offset )
      if idnum is not None:
        if path.startswith('"'):
          path = unquote(path)
        filechange = FileChanges('M', path, idnum, mode)
      else:
        filechange = 'skipped'
      self._advance_currentline()
    elif self._currentline.startswith('D '):
      path = self._currentline[2:-1]
      if path.startswith('"'):
        path = unquote(path)
      filechange = FileChanges('D', path)
      self._advance_currentline()
    return filechange

  #############################################################################
  def _parse_ref_line(self, refname):
  #############################################################################
    """
    Parses string data (often a branch name) from current-line. The name of
    the string data must match the refname arg. The program will crash if
    current-line does not match, so current-line will always be advanced if
    this method returns.
    """
    matches = re.match('%s (.*)\n$' % refname, self._currentline)
    if not matches:
      raise SystemExit("Malformed %s line: '%s'" %
                       (refname, self._currentline))
    ref = matches.group(1)
    self._advance_currentline()
    return ref

  #############################################################################
  def _parse_user(self, usertype):
  #############################################################################
    """
    Get user name, email, datestamp from current-line. Current-line will
    be advanced.
    """
    (name, email, when) = \
      re.match('%s (.*?) <(.*?)> (.*)\n$' %
               usertype, self._currentline).groups()

    # Translate when into a datetime object, with corresponding timezone info
    (unix_timestamp, tz_offset) = when.split()
    datestamp = datetime.fromtimestamp(int(unix_timestamp),
                                       _TimeZone(tz_offset))

    self._advance_currentline()
    return (name, email, datestamp)

  #############################################################################
  def _parse_data(self):
  #############################################################################
    """
    Reads data from _input. Current-line will be advanced until it is beyond
    the data.
    """
    size = int(re.match('data (\d+)\n$', self._currentline).group(1))
    data = self._input.read(size)
    self._advance_currentline()
    if self._currentline == '\n':
      self._advance_currentline()
    return data

  #############################################################################
  def _parse_blob(self):
  #############################################################################
    """
    Parse input data into a Blob object. Once the Blob has been created, it
    will be handed off to the appropriate callbacks. Current-line will be
    advanced until it is beyond this blob's data. The Blob will be dumped
    to _output once everything else is done (unless it has been skipped by
    the callback).
    """
    # Parse the Blob
    self._advance_currentline()
    id_ = self._parse_optional_mark()
    data = self._parse_data()
    if self._currentline == '\n':
      self._advance_currentline()

    # Create the blob
    blob = Blob(data)

    # If fast-export text had a mark for this blob, need to make sure this
    # mark translates to the blob's true id.
    if id_:
      blob.old_id = id_
      _IDS.record_rename(id_, blob.id)

    # Call any user callback to allow them to use/modify the blob
    if self._blob_callback:
      self._blob_callback(blob)
    if self._everything_callback:
      self._everything_callback('blob', blob)

    # Now print the resulting blob
    if not blob.dumped:
      blob.dump(self._output)

  #############################################################################
  def _parse_reset(self):
  #############################################################################
    """
    Parse input data into a Reset object. Once the Reset has been created,
    it will be handed off to the appropriate callbacks. Current-line will
    be advanced until it is beyond the reset data. The Reset will be dumped
    to _output once everything else is done (unless it has been skipped by
    the callback).
    """
    # Parse the Reset
    ref = self._parse_ref_line('reset')
    from_ref = self._parse_optional_parent_ref('from')
    if self._currentline == '\n':
      self._advance_currentline()

    # Create the reset
    reset = Reset(ref, from_ref)

    # Call any user callback to allow them to modify the reset
    if self._reset_callback:
      self._reset_callback(reset)
    if self._everything_callback:
      self._everything_callback('reset', reset)

    # Now print the resulting reset
    if not reset.dumped:
      reset.dump(self._output)

  #############################################################################
  def _parse_commit(self):
  #############################################################################
    """
    Parse input data into a Commit object. Once the Commit has been created,
    it will be handed off to the appropriate callbacks. Current-line will
    be advanced until it is beyond the commit data. The Commit will be dumped
    to _output once everything else is done (unless it has been skipped by
    the callback OR the callback has removed all file-changes from the commit).
    """
    # Parse the Commit. This may look involved, but it's pretty simple; it only
    # looks bad because a commit object contains many pieces of data.
    branch = self._parse_ref_line('commit')
    id_ = self._parse_optional_mark()

    author_name = None
    if self._currentline.startswith('author'):
      (author_name, author_email, author_date) = self._parse_user('author')

    (committer_name, committer_email, committer_date) = \
      self._parse_user('committer')

    if not author_name:
      (author_name, author_email, author_date) = \
        (committer_name, committer_email, committer_date)

    commit_msg = self._parse_data()

    from_commit = self._parse_optional_parent_ref('from')
    merge_commits = []
    merge_ref = self._parse_optional_parent_ref('merge')
    while merge_ref:
      merge_commits.append(merge_ref)
      merge_ref = self._parse_optional_parent_ref('merge')
    
    file_changes = []
    file_change = self._parse_optional_filechange()
    had_file_changes = file_change is not None
    while file_change:
      if not (type(file_change) == str and file_change == 'skipped'):
        file_changes.append(file_change)
      file_change = self._parse_optional_filechange()
    if self._currentline == '\n':
      self._advance_currentline()

    # Okay, now we can finally create the Commit object
    commit = Commit(branch,
                    author_name,    author_email,    author_date,
                    committer_name, committer_email, committer_date,
                    commit_msg,
                    file_changes,
                    from_commit,
                    merge_commits,
                    stream_number = _CURRENT_STREAM_NUMBER)

    # If fast-export text had a mark for this commit, need to make sure this
    # mark translates to the commit's true id.
    if id_:
      commit.old_id = id_
      _IDS.record_rename(id_, commit.id)

    # Call any user callback to allow them to modify the commit
    if self._commit_callback:
      self._commit_callback(commit)
    if self._everything_callback:
      self._everything_callback('commit', commit)

    # Now print the resulting commit, unless all its changes were dropped and
    # it was a non-merge commit
    merge_commit = len(commit.get_parents()) > 1
    if not commit.dumped:
      if merge_commit or not had_file_changes or commit.file_changes:
        commit.dump(self._output)
      else:
        commit.skip(commit.first_parent())

  #############################################################################
  def _parse_tag(self):
  #############################################################################
    """
    Parse input data into a Tag object. Once the Tag has been created,
    it will be handed off to the appropriate callbacks. Current-line will
    be advanced until it is beyond the tag data. The Tag will be dumped
    to _output once everything else is done (unless it has been skipped by
    the callback).
    """
    # Parse the Tag
    tag = self._parse_ref_line('tag')
    from_ref = self._parse_optional_parent_ref('from')
    if from_ref is None:
      raise SystemExit("Expected 'from' line while parsing tag %s" % tag)
    (tagger_name, tagger_email, tagger_date) = self._parse_user('tagger')
    tag_msg = self._parse_data()
    if self._currentline == '\n':
      self._advance_currentline()

    # Create the tag
    tag = Tag(tag, from_ref, tagger_name, tagger_email, tagger_date, tag_msg)

    # Call any user callback to allow them to modify the tag
    if self._tag_callback:
      self._tag_callback(tag)
    if self._everything_callback:
      self._everything_callback('tag', tag)

    # Now print the resulting reset
    if not tag.dumped:
      tag.dump(self._output)

  #############################################################################
  def _parse_progress(self):
  #############################################################################
    """
    Parse input data into a Progress object. Once the Progress has
    been created, it will be handed off to the appropriate
    callbacks. Current-line will be advanced until it is beyond the
    progress data. The Progress will be dumped to _output once
    everything else is done (unless it has been skipped by the callback).
    """
    # Parse the Progress
    message = self._parse_ref_line('progress')
    if self._currentline == '\n':
      self._advance_currentline()

    # Create the progress message
    progress = Progress(message)

    # Call any user callback to allow them to modify the progress messsage
    if self._progress_callback:
      self._progress_callback(progress)
    if self._everything_callback:
      self._everything_callback('progress', progress)

    # Now print the resulting progress message
    if not progress.dumped:
      progress.dump(self._output)

  #############################################################################
  def _parse_checkpoint(self):
  #############################################################################
    """
    Parse input data into a Checkpoint object. Once the Checkpoint has
    been created, it will be handed off to the appropriate
    callbacks. Current-line will be advanced until it is beyond the
    checkpoint data. The Checkpoint will be dumped to _output once
    everything else is done (unless it has been skipped by the callback).
    """
    # Parse the Checkpoint
    self._advance_currentline()
    if self._currentline == '\n':
      self._advance_currentline()

    # Create the checkpoint
    checkpoint = Checkpoint()

    # Call any user callback to allow them to drop the checkpoint
    if self._checkpoint_callback:
      self._checkpoint_callback(checkpoint)
    if self._everything_callback:
      self._everything_callback('checkpoint', checkpoint)

    # Now print the resulting checkpoint
    if not checkpoint.dumped:
      checkpoint.dump(self._output)

  #############################################################################
  def run(self, *args):
  #############################################################################
    """
    This method performs the filter. The method optionally takes two arguments.
    The first represents the source repository (either a file object
    containing git-fast-export output, or a string containing the path to the
    source repository where we can run git-fast-export), and the second
    argument represents the target repository (again either a file object into
    which we write git-fast-import input, or a string containing the path to
    the source repository where we can run git-fast-import).
    """
    # Sanity check arguments
    if len(args) != 0 and len(args) != 2:
      raise SystemExit("run() must be called with 0 or 2 arguments")
    for arg in args:
      if type(arg) != str and type(arg) != file:
        raise SystemExit("argumetns to run() must be filenames or files")

    # Set input. If no args provided, use stdin.
    self._input = sys.stdin
    if len(args) > 0:
      if type(args[0]) == str:
        # If repo-name provided, set up fast_export process pipe as input
        self._input = fast_export_output(args[0]).stdout
      else:
        # If file-obj provided, just use that
        self._input = args[0]

    # Set output. If no args provided, use stdout.
    self._output = sys.stdout
    output_pipe = None
    need_wait = False
    if len(args) > 1:
      if type(args[1]) == str:
        # If repo-name provided, output to fast_import process pipe
        output_pipe = fast_import_input(args[1])
        self._output = output_pipe.stdin
        need_wait = True
      else:
        # If file-obj provided, just use that
        self._output = args[1]

    # Setup some vars
    global _CURRENT_STREAM_NUMBER

    _CURRENT_STREAM_NUMBER += 1
    if _CURRENT_STREAM_NUMBER > 1:
      self._id_offset = _IDS._next_id-1

    # Run over the input and do the filtering
    self._advance_currentline()
    while self._currentline:
      if   self._currentline.startswith('blob'):
        self._parse_blob()
      elif self._currentline.startswith('reset'):
        self._parse_reset()
      elif self._currentline.startswith('commit'):
        self._parse_commit()
      elif self._currentline.startswith('tag'):
        self._parse_tag()
      elif self._currentline.startswith('progress'):
        self._parse_progress()
      elif self._currentline.startswith('checkpoint'):
        self._parse_checkpoint()
      else:
        raise SystemExit("Could not parse line: '%s'" % self._currentline)

    # If we created fast_import process, close pipe and wait for it to finish
    if need_wait:
      self._output.close()
      output_pipe.wait()

###############################################################################
def fast_export_output(source_repo, extra_args = None):
###############################################################################
  """
  Given a source-repo location, setup a Popen process that runs fast-export
  on that repo. The Popen object is returned (we do NOT wait for it to
  finish).
  """
  if not extra_args:
    extra_args = ["--all"]

  # If the client specified an import-marks file, we find the biggest mark
  # within that file and make sure that _IDS generates new marks that are
  # at least higher than that.
  for arg in extra_args:
    if arg.startswith("--import-marks"):
      filename = arg[len("--import-marks="):]
      lines = open(filename,'r').read().strip().splitlines()
      if lines:
        biggest_mark = max([int(line.split()[0][1:]) for line in lines])
        _IDS._avoid_ids_below(biggest_mark)

  # Create and return the git process
  return Popen(["git", "fast-export", "--topo-order"] + extra_args,
               stdout = PIPE,
               cwd = source_repo)

###############################################################################
def fast_import_input(target_repo, extra_args = None):
###############################################################################
  """
  Given a target-repo location, setup a Popen process that runs fast-import
  on that repo. The Popen object is returned (we do NOT wait for it to
  finish).
  """
  if extra_args is None:
    extra_args = []

  # If target-repo directory does not exist, create it and initialize it
  if not os.path.isdir(target_repo):
    os.makedirs(target_repo)
    if call(["git", "init", "--bare", "--shared"], cwd = target_repo) != 0:
      raise SystemExit("git init in %s failed!" % target_repo)

  # Create and return the git process
  return Popen(["git", "fast-import", "--quiet"] + extra_args,
               stdin = PIPE,
               cwd = target_repo)

###############################################################################
def get_commit_count(repo, *args):
###############################################################################
  """
  Return the number of commits that have been made on repo.
  """
  if not args:
    args = ['--all']
  if len(args) == 1 and isinstance(args[0], list):
    args = args[0]
  p1 = Popen(["git", "rev-list"] + args,
             stdout=PIPE, stderr=PIPE, cwd=repo)
  p2 = Popen(["wc", "-l"], stdin = p1.stdout, stdout = PIPE)
  count = int(p2.communicate()[0])
  if p1.poll() != 0:
    raise SystemExit("%s does not appear to be a valid git repository" % repo)
  return count

###############################################################################
def get_total_objects(repo):
###############################################################################
  """
  Return the number of objects (both packed and unpacked)
  """
  p1 = Popen(["git", "count-objects", "-v"], stdout = PIPE, cwd = repo)
  lines = p1.stdout.read().splitlines()
  # Return unpacked objects + packed-objects
  return int(lines[0].split()[1]) + int(lines[2].split()[1])

###############################################################################
def record_id_rename(old_id, new_id, handle_transitivity = False):
###############################################################################
  """
  Register a new translation
  """
  _IDS.record_rename(old_id, new_id, handle_transitivity)

# Internal globals
_IDS = _IDs()
_EXTRA_CHANGES = {}  # idnum -> list of list of FileChanges
_CURRENT_STREAM_NUMBER = 0

