# A bunch of installation-related paths people can override on the command line
prefix = $(HOME)
bindir = $(prefix)/libexec/git-core
localedir = $(prefix)/share/locale
mandir = $(prefix)/share/man
htmldir = $(prefix)/share/doc/git-doc
pythondir = $(prefix)/lib64/python3.6/site-packages

default: build

build:
	@echo Nothing to do: filter-repo is a script which needs no compilation.

test:
	cd t && time ./run_coverage

# fixup_locale might matter once we actually have translations, but right now
# we don't.  It might not even matter then, because python has a fallback podir.
fixup_locale:
	sed -ie s%@@LOCALEDIR@@%$(localedir)% git-filter-repo

# People installing from tarball will already have man1/git-filter-repo.1 and
# html/git-filter-repo.html.  But let's support people installing from a git
# clone too; for them, just cheat and snag a copy of the built docs that I
# record in a different branch.
snag_docs: Documentation/man1/git-filter-repo.1 Documentation/html/git-filter-repo.html

Documentation/man1/git-filter-repo.1:
	mkdir -p man1
	git show docs:man1/git-filter-repo.1 >Documentation/man1/git-filter-repo.1

Documentation/html/git-filter-repo.html:
	mkdir -p html
	git show docs:html/git-filter-repo.html >Documentation/html/git-filter-repo.html

install: snag_docs #fixup_locale
	cp -a git-filter-repo $(bindir)/
	ln -s $(bindir)/git-filter-repo $(pythondir)/git_filter_repo.py
	cp -a Documentation/man1/git-filter-repo.1 $(mandir)/man1/git-filter-repo.1
	cp -a Documentation/html/git-filter-repo.html $(htmldir)/git-filter-repo.html
