import os
import re
import sys
from subprocess import Popen, PIPE, call
from email.Utils import unquote
from datetime import tzinfo, timedelta, datetime

__all__ = ["Blob", "Reset", "FileChanges", "Commit",
           "get_total_commits", "record_id_rename",
           "FastExportFilter", "FastExportOuput", "FastImportInput"]

class TimeZone(tzinfo):
  """Fixed offset in minutes east from UTC."""
  def __init__(self, offset_string):
    (minus, hh, mm) = re.match(r'^(-?)(\d\d)(\d\d)$', offset_string).groups()
    sign = minus and -1 or 1
    self._offset = timedelta(minutes = sign*(60*int(hh) + int(mm)))
    self._offset_string = offset_string

  def utcoffset(self, dt):
    return self._offset

  def tzname(self, dt):
    return self._offset_string

  def dst(self, dt):
    return timedelta(0)

def timedelta_to_seconds(delta):
  offset = delta.days*86400 + delta.seconds + (delta.microseconds+0.0)/1000000
  return round(offset)

def write_date(file, date):
  epoch = datetime.fromtimestamp(0, date.tzinfo)
  file.write('%d %s' % (timedelta_to_seconds(date-epoch),
                        date.tzinfo.tzname(0)))

class IDs(object):
  def __init__(self):
    self.count = 0
    self.translation = {}
    self.reverse_translation = {}

  def new(self):
    self.count += 1
    return self.count

  def record_rename(self, old_id, new_id, handle_transitivity = False):
    if old_id != new_id:
      # old_id -> new_id
      self.translation[old_id] = new_id

      if handle_transitivity:
        # Anything that points to old_id should point to new_id
        if old_id in self.reverse_translation:
          for id in self.reverse_translation[old_id]:
            self.translation[id] = new_id

      # Record that new_id is pointed to by old_id
      if new_id not in self.reverse_translation:
        self.reverse_translation[new_id] = []
      self.reverse_translation[new_id].append(old_id)

  def translate(self, old_id):
    if old_id in self.translation:
      return self.translation[old_id]
    else:
      return old_id
ids = IDs()
extra_changes = {}  # idnum -> list of list of FileChanges
current_stream_number = 0

def record_id_rename(old_id, new_id, handle_transitivity = False):
  ids.record_rename(old_id, new_id, handle_transitivity)

class GitElement(object):
  def __init__(self):
    self.type = None
    self.dumped = 0
    self.old_id = None

  def dump(self, file):
    raise SystemExit("Unimplemented function: %s.dump()", type(self))

  def set_old_id(self, value):
    self.old_id = value

class Blob(GitElement):
  def __init__(self, data):
    GitElement.__init__(self)
    self.type = 'blob'
    self.data = data
    self.id = ids.new()

  def dump(self, file):
    self.dumped = 1

    file.write('blob\n')
    file.write('mark :%d\n' % self.id)
    file.write('data %d\n%s' % (len(self.data), self.data))
    file.write('\n')

  def skip(self):
    self.dumped = 2
    ids.record_rename(self.old_id or self.id, None)

class Reset(GitElement):
  def __init__(self, ref, from_ref = None):
    GitElement.__init__(self)
    self.type = 'reset'
    self.ref = ref
    self.from_ref = from_ref

  def dump(self, file):
    self.dumped = 1

    file.write('reset %s\n' % self.ref)
    if self.from_ref:
      file.write('from :%d\n' % self.from_ref)
      file.write('\n')

  def skip(self):
    self.dumped = 2

class FileChanges(GitElement):
  def __init__(self, type, filename, id = None, mode = None):
    GitElement.__init__(self)
    self.type = type
    self.filename = filename
    self.mode = None
    self.id = None
    if type == 'M':
      if mode is None:
        raise SystemExit("file mode and idnum needed for %s" % filename)
      self.mode = mode
      self.id = id

  def dump(self, file):
    skipped_blob = (self.type == 'M' and self.id is None)
    if skipped_blob: return
    self.dumped = 1

    if self.type == 'M':
      file.write('M %s :%d %s\n' % (self.mode, self.id, self.filename))
    elif self.type == 'D':
      file.write('D %s\n' % self.filename)
    else:
      raise SystemExit("Unhandled filechange type: %s" % self.type)

  def skip(self):
    self.dumped = 2

class Commit(GitElement):
  def __init__(self, branch,
               author_name,    author_email,    author_date,
               committer_name, committer_email, committer_date,
               message,
               file_changes,
               from_commit = None,
               merge_commits = [],
               **kwargs):
    GitElement.__init__(self)
    self.type = 'commit'
    self.branch = branch
    self.author_name  = author_name
    self.author_email = author_email
    self.author_date  = author_date
    self.committer_name  = committer_name
    self.committer_email = committer_email
    self.committer_date  = committer_date
    self.message = message
    self.file_changes = file_changes
    self.id = ids.new()
    self.from_commit = from_commit
    self.merge_commits = merge_commits
    self.stream_number = 0
    if "stream_number" in kwargs:
      self.stream_number = kwargs["stream_number"]

  def dump(self, file):
    self.dumped = 1

    # Workaround fast-import/fast-export weird handling of merges
    global extra_changes
    if self.stream_number != current_stream_number:
      extra_changes[self.id] = [[change for change in self.file_changes]]
    merge_extra_changes = []
    for parent in self.merge_commits:
      if parent in extra_changes:
        merge_extra_changes += extra_changes[parent]
    for additional_changes in merge_extra_changes:
      self.file_changes += additional_changes
    if self.stream_number == current_stream_number:
      parent_extra_changes = []
      if self.from_commit and self.from_commit in extra_changes:
        parent_extra_changes = extra_changes[self.from_commit]
      parent_extra_changes += merge_extra_changes
      extra_changes[self.id] = parent_extra_changes
    # End workaround

    file.write('commit %s\n' % self.branch)
    file.write('mark :%d\n' % self.id)
    file.write('author %s <%s> ' % (self.author_name, self.author_email))
    write_date(file, self.author_date)
    file.write('\n')
    file.write('committer %s <%s> ' % \
                     (self.committer_name, self.committer_email))
    write_date(file, self.committer_date)
    file.write('\n')
    file.write('data %d\n%s' % (len(self.message), self.message))
    if self.from_commit:
      file.write('from :%s\n' % self.from_commit)
    for ref in self.merge_commits:
      file.write('merge :%s\n' % ref)
    for change in self.file_changes:
      change.dump(file)
    file.write('\n')

  def skip(self, new_id):
    self.dumped = 2
    ids.record_rename(self.old_id or self.id, new_id)

class FastExportFilter(object):
  def __init__(self, 
               tag_callback = None,   commit_callback = None,
               blob_callback = None,  progress_callback = None,
               reset_callback = None, checkpoint_callback = None,
               everything_callback = None):
    self.tag_callback        = tag_callback
    self.blob_callback       = blob_callback
    self.reset_callback      = reset_callback
    self.commit_callback     = commit_callback
    self.progress_callback   = progress_callback
    self.checkpoint_callback = checkpoint_callback
    self.everything_callback = everything_callback

    self.input = None
    self.output = sys.stdout
    self.nextline = ''

    self.id_offset = 0

  def _advance_nextline(self):
    self.nextline = self.input.readline()

  def _parse_optional_mark(self):
    mark = None
    matches = re.match('mark :(\d+)\n$', self.nextline)
    if matches:
      mark = int(matches.group(1))+self.id_offset
      self._advance_nextline()
    return mark

  def _parse_optional_baseref(self, refname):
    baseref = None
    matches = re.match('%s :(\d+)\n' % refname, self.nextline)
    if matches:
      baseref = ids.translate( int(matches.group(1))+self.id_offset )
      self._advance_nextline()
    return baseref

  def _parse_optional_filechange(self):
    filechange = None
    if self.nextline.startswith('M '):
      (mode, idnum, path) = \
        re.match('M (\d+) :(\d+) (.*)\n$', self.nextline).groups()
      idnum = ids.translate( int(idnum)+self.id_offset )
      if idnum is not None:
        if path.startswith('"'):
          path = unquote(path)
        filechange = FileChanges('M', path, idnum, mode)
      self._advance_nextline()
    elif self.nextline.startswith('D '):
      path = self.nextline[2:-1]
      if path.startswith('"'):
        path = unquote(path)
      filechange = FileChanges('D', path)
      self._advance_nextline()
    return filechange

  def _parse_ref_line(self, refname):
    matches = re.match('%s (.*)\n$' % refname, self.nextline)
    if not matches:
      raise SystemExit("Malformed %s line: '%s'" % (refname, self.nextline))
    ref = matches.group(1)
    self._advance_nextline()
    return ref

  def _parse_user(self, usertype):
    (name, email, when) = \
      re.match('%s (.*?) <(.*?)> (.*)\n$' % usertype, self.nextline).groups()

    # Translate when into a datetime object, with corresponding timezone info
    (unix_timestamp, tz_offset) = when.split()
    datestamp = datetime.fromtimestamp(int(unix_timestamp), TimeZone(tz_offset))

    self._advance_nextline()
    return (name, email, datestamp)

  def _parse_data(self):
    size = int(re.match('data (\d+)\n$', self.nextline).group(1))
    data = self.input.read(size)
    self._advance_nextline()
    if self.nextline == '\n':
      self._advance_nextline()
    return data

  def _parse_blob(self):
    # Parse the Blob
    self._advance_nextline()
    id = self._parse_optional_mark()
    data = self._parse_data()
    if self.nextline == '\n':
      self._advance_nextline()

    # Create the blob
    blob = Blob(data)
    if id:
      blob.set_old_id(id)
      ids.record_rename(id, blob.id)

    # Call any user callback to allow them to modify the blob
    if self.blob_callback:
      self.blob_callback(blob)
    if self.everything_callback:
      self.everything_callback('blob', blob)

    # Now print the resulting blob
    if not blob.dumped:
      blob.dump(self.output)

  def _parse_reset(self):
    # Parse the Reset
    ref = self._parse_ref_line('reset')
    from_ref = self._parse_optional_baseref('from')
    if self.nextline == '\n':
      self._advance_nextline()

    # Create the reset
    reset = Reset(ref, from_ref)

    # Call any user callback to allow them to modify the reset
    if self.reset_callback:
      self.reset_callback(reset)
    if self.everything_callback:
      self.everything_callback('reset', reset)

    # Now print the resulting reset
    if not reset.dumped:
      reset.dump(self.output)

  def _parse_commit(self):
    # Parse the Commit
    branch = self._parse_ref_line('commit')
    id = self._parse_optional_mark()

    author_name = None
    if self.nextline.startswith('author'):
      (author_name, author_email, author_date) = self._parse_user('author')

    (committer_name, committer_email, committer_date) = \
      self._parse_user('committer')

    if not author_name:
      (author_name, author_email, author_date) = \
        (committer_name, committer_email, committer_date)

    commit_msg = self._parse_data()

    from_commit = self._parse_optional_baseref('from')
    merge_commits = []
    merge_ref = self._parse_optional_baseref('merge')
    while merge_ref:
      merge_commits.append(merge_ref)
      merge_ref = self._parse_optional_baseref('merge')
    
    file_changes = []
    file_change = self._parse_optional_filechange()
    while file_change:
      file_changes.append(file_change)
      file_change = self._parse_optional_filechange()
    if self.nextline == '\n':
      self._advance_nextline()

    # Okay, now we can finally create the Commit object
    commit = Commit(branch,
                    author_name,    author_email,    author_date,
                    committer_name, committer_email, committer_date,
                    commit_msg,
                    file_changes,
                    from_commit,
                    merge_commits,
                    stream_number = current_stream_number)
    if id:
      commit.set_old_id(id)
      ids.record_rename(id, commit.id)

    # Call any user callback to allow them to modify the commit
    if self.commit_callback:
      self.commit_callback(commit)
    if self.everything_callback:
      self.everything_callback('commit', commit)

    # Now print the resulting commit to stdout
    if not commit.dumped:
      commit.dump(self.output)

  def run(self, *args):
    # Sanity check arguments
    if len(args) != 0 and len(args) != 2:
      raise SystemExit("run() must be called with 0 or 2 arguments")
    for arg in args:
      if type(arg) != str and type(arg) != file:
        raise SystemExit("argumetns to run() must be filenames or files")

    # Set input
    self.input = sys.stdin
    if len(args) > 0:
      if type(args[0]) == str:
        self.input = FastExportOutput(args[0]).stdout
      else:
        self.input = args[0]

    # Set output
    self.output = sys.stdout
    output_pipe = None
    need_wait = False
    if len(args) > 1:
      if type(args[1]) == str:
        output_pipe = FastImportInput(args[1])
        self.output = output_pipe.stdin
        need_wait = True
      else:
        self.output = args[1]

    # Setup some vars
    global current_stream_number

    self.id_offset = ids.count
    current_stream_number += 1

    # Run over the input and do the filtering
    self.nextline = self.input.readline()
    while self.nextline:
      if   self.nextline.startswith('blob'):
        self._parse_blob()
      elif self.nextline.startswith('reset'):
        self._parse_reset()
      elif self.nextline.startswith('commit'):
        self._parse_commit()
      else:
        raise SystemExit("Could not parse line: '%s'" % self.nextline)

    if need_wait:
      self.output.close()
      output_pipe.wait()

def FastExportOutput(source_repo, extra_args = []):
  if not extra_args:
    extra_args = ["--all"]
  return Popen(["git", "fast-export", "--topo-order"] + extra_args,
               stdout = PIPE,
               cwd = source_repo)

def FastImportInput(target_repo, extra_args = []):
  if not os.path.isdir(target_repo):
    os.makedirs(target_repo)
    if call(["git", "init", "--bare", "--shared"], cwd = target_repo) != 0:
      raise SystemExit("git init in %s failed!" % target_repo)
  return Popen(["git", "fast-import", "--quiet"] + extra_args,
               stdin = PIPE,
               cwd = target_repo)

def get_total_commits(repo):
  p1 = Popen(["git", "rev-list", "--all"], stdout = PIPE, cwd = repo)
  p2 = Popen(["wc", "-l"], stdin = p1.stdout, stdout = PIPE)
  return int(p2.communicate()[0])

def get_total_objects(repo):
  p1 = Popen(["git", "count-objects", "-v"], stdout = PIPE, cwd = repo)
  lines = p1.stdout.read().splitlines()
  # Return unpacked objects + packed-objects
  return int(lines[0].split()[1]) + int(lines[2].split()[1])
