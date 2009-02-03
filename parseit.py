#!/usr/bin/env python

import commands
import re
import sha  # bleh...when can I assume python >= 2.5?
import sys
from pyparsing import ParserElement, Literal, Optional, Combine, Word, nums, \
                      ZeroOrMore, ParseException

from pyparsing import Token, ParseResults
class ExactData(Token):
  """Specialized pyparsing subclass for handling data dumps in git-fast-import
     exact data format"""
  def __init__( self ):
    super(ExactData,self).__init__()

    self.pattern = r"data (\d+)\n"
    self.re = re.compile(self.pattern)
    self.reString = self.pattern

    self.name = "ExactData"
    self.errmsg = "Expected " + self.name
    self.mayIndexError = False
    self.mayReturnEmpty = True

  def parseImpl( self, instring, loc, doActions=True ):
    result = self.re.match(instring,loc)
    if not result:
      exc = self.myException
      exc.loc = loc
      exc.pstr = instring
      raise exc

    num = result.group(1)
    loc = result.end()+int(num)
    data = instring[result.end():loc]
    d = result.groupdict()
    ret = ParseResults(['data', num, data])
    return loc,ret

  def __str__( self ):
    try:
      return super(ExactMath,self).__str__()
    except:
      pass

    if self.strRepr is None:
      self.strRepr = "Data:"

    return self.strRepr

newmark = 0
mark_dict = {}
def translate_mark(old_mark = None):
  if not old_mark or old_mark not in mark_dict:
    global newmark
    newmark += 1
    mark_dict[old_mark] = newmark

  return mark_dict[old_mark]

class GitElement(object):
  def __init__(self):
    self.type = None

  def dump(self):
    raise SystemExit("Unimplemented function: %s.dump()", type(self))

class Blob(GitElement):
  def __init__(self, data, mark = None):
    GitElement.__init__(self)
    self.type = 'blob'
    self.data = data
    self.mark = translate_mark(mark)

  def dump(self):
    sys.stdout.write('blob\n')
    sys.stdout.write('mark :%d\n' % self.mark)
    sys.stdout.write('data %d\n%s' % (len(self.data), self.data))

class FastExportParser(object):
  def __init__(self, 
               tag_callback = None,   commit_callback = None,
               blob_callback = None,  progress_callback = None,
               reset_callback = None, checkpoint_callback = None,
               everything_callback = None):
    self._setup_parser()
    self.tag_callback        = tag_callback
    self.blob_callback       = blob_callback
    self.reset_callback      = reset_callback
    self.commit_callback     = commit_callback
    self.progress_callback   = progress_callback
    self.checkpoint_callback = checkpoint_callback
    self.everything_callback = everything_callback

  def _make_blob(self, t):
    # Create the Blob object from the parser tokens
    mark = int(t[1][1:])
    datalen = int(t[3])
    data = t[4]
    if datalen != len(data):
      raise SystemExit('%d != len(%s)' % datalen, data)
    blob = Blob(data, mark)

    # Call any user callback to allow them to modify the blob
    if self.blob_callback:
      self.blob_callback(blob)

    # Now print the resulting blob to stdout
    blob.dump()

    # Replace data with its sha1sum to cut down on memory usage
    # (python parser stores whole resulting parse tree in memory)
    sha1sum = sha.new(blob.data).hexdigest()
    return ['blob', blob.mark, len(blob.data), sha1sum]

  def _setup_parser(self):
    # Basic setup
    ParserElement.setDefaultWhitespaceChars('')
    number = Word(nums)
    lf = Literal('\n').suppress()
    sp = Literal(' ').suppress()

    # Parsing marks
    mark_name = Combine(Literal(':') + number)
    mark = Literal('mark').suppress() - sp + mark_name + lf

    # Parsing blobs
    exact_data = ExactData() + Optional(lf)
    file_content = exact_data
    blob = Literal('blob') + lf + mark + file_content
    blob.setParseAction(lambda t: self._make_blob(t))

    # Tying it all together
    cmd = blob
    self.stream = ZeroOrMore(cmd)

  def parse(self, string):
    try:
      results = self.stream.parseString(string, parseAll = True)
    except ParseException, err:
      print err.line
      print " "*(err.column-1) + "^"
      print err
      raise SystemExit
    return results


parser = FastExportParser()
string = commands.getoutput("GIT_DIR=foo/.git git fast-export --all")
results = parser.parse(string)
print results
