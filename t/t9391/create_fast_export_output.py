#!/usr/bin/env python

import git_filter_repo as fr
from git_filter_repo import Blob, Reset, FileChanges, Commit, Tag, FixedTimeZone
from git_filter_repo import Progress, Checkpoint

from datetime import datetime, timedelta

args = fr.FilteringOptions.default_options()
out = fr.RepoFilter(args)
out.importer_only()

output = out._output

world = Blob("Hello")
world.dump(output)

bar = Blob("foo\n")
bar.dump(output)

master = Reset("refs/heads/master")
master.dump(output)

changes = [FileChanges('M', 'world', world.id, mode="100644"),
           FileChanges('M', 'bar',   bar.id,   mode="100644")]
when = datetime(year=2005, month=4, day=7,
                hour=15, minute=16, second=10,
                tzinfo=FixedTimeZone("-0700"))
when_string = fr.date_to_string(when)
commit1 = Commit("refs/heads/master",
                 "A U Thor", "au@thor.email", when_string,
                 "Com M. Iter", "comm@iter.email", when_string,
                 "My first commit!  Wooot!\n\nLonger description",
                 changes,
                 from_commit = None,
                 merge_commits = [])
commit1.dump(output)

world = Blob("Hello\nHi")
world.dump(output)
world_link = Blob("world")
world_link.dump(output)

changes = [FileChanges('M', 'world',  world.id,      mode="100644"),
           FileChanges('M', 'planet', world_link.id, mode="120000")]
when += timedelta(days=3, hours=4, minutes=6)
when_string = fr.date_to_string(when)
commit2 = Commit("refs/heads/master",
                 "A U Thor", "au@thor.email", when_string,
                 "Com M. Iter", "comm@iter.email", when_string,
                 "Make a symlink to world called planet, modify world",
                 changes,
                 from_commit = commit1.id,
                 merge_commits = [])
commit2.dump(output)

script = Blob("#!/bin/sh\n\necho Hello")
script.dump(output)
changes = [FileChanges('M', 'runme', script.id, mode="100755"),
           FileChanges('D', 'bar')]
when_string = "1234567890 -0700"
commit3 = Commit("refs/heads/master",
                 "A U Thor", "au@thor.email", when_string,
                 "Com M. Iter", "comm@iter.email", when_string,
                 "Add runme script, remove bar",
                 changes,
                 from_commit = commit2.id,
                 merge_commits = [])
commit3.dump(output)

progress = Progress("Done with the master branch now...")
progress.dump(output)
checkpoint = Checkpoint()
checkpoint.dump(output)

devel = Reset("refs/heads/devel", commit1.id)
devel.dump(output)

world = Blob("Hello\nGoodbye")
world.dump(output)

changes = [FileChanges('M', 'world', world.id, mode="100644")]
when = datetime(2006, 8, 17, tzinfo=FixedTimeZone("+0200"))
when_string = fr.date_to_string(when)
commit4 = Commit("refs/heads/devel",
                 "A U Thor", "au@thor.email", when_string,
                 "Com M. Iter", "comm@iter.email", when_string,
                 "Modify world",
                 changes,
                 from_commit = commit1.id,
                 merge_commits = [])
commit4.dump(output)

world = Blob("Hello\nHi\nGoodbye")
world.dump(output)
when = fr.string_to_date(commit3.author_date) + timedelta(days=47)
when_string = fr.date_to_string(when)
# git fast-import requires file changes to be listed in terms of differences
# to the first parent.  Thus, despite the fact that runme and planet have
# not changed and bar was not modified in the devel side, we have to list them
# all anyway.
changes = [FileChanges('M', 'world', world.id, mode="100644"),
           FileChanges('D', 'bar'),
           FileChanges('M', 'runme', script.id, mode="100755"),
           FileChanges('M', 'planet', world_link.id, mode="120000")]

commit5 = Commit("refs/heads/devel",
                 "A U Thor", "au@thor.email", when_string,
                 "Com M. Iter", "comm@iter.email", when_string,
                 "Merge branch 'master'\n",
                 changes,
                 from_commit = commit4.id,
                 merge_commits = [commit3.id])
commit5.dump(output)


mytag = Tag("refs/tags/v1.0", commit5.id,
            "His R. Highness", "royalty@my.kingdom", when_string,
            "I bequeath to my peons this royal software")
mytag.dump(output)
out.finish()
