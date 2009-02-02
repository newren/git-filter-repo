#!/usr/bin/env python

import commands
import re
from pyparsing import ParserElement, Literal, Optional, Combine, Word, nums

from pyparsing import Token, ParseResults
class ExactData(Token):
    """Token for matching data dumps in git-fast-import format"""
    def __init__( self ):
        super(ExactData,self).__init__()

        self.pattern = r"data (\d+)\n"
        self.re = re.compile(self.pattern)
        self.reString = self.pattern

        self.name = "ExactData"
        self.errmsg = "Expected " + self.name
        #self.myException.msg = self.errmsg
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


string = commands.getoutput("GIT_DIR=foo/.git git fast-export --all")

ParserElement.setDefaultWhitespaceChars('')
number = Word(nums)
lf = Literal('\n').suppress()
sp = Literal(' ').suppress()
mark_name = Combine(Literal(':') + number)
mark = Literal('mark').suppress() - sp + mark_name + lf
#exact_data = Literal('data') + sp + number + lf
exact_data = ExactData()
file_content = exact_data
blob = Literal('blob') + lf + mark + file_content

results = blob.parseString(string, parseAll = False)
print results
