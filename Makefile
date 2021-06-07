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
	time t/run_coverage

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
	mkdir -p Documentation/man1
	git show origin/docs:man1/git-filter-repo.1 >Documentation/man1/git-filter-repo.1

Documentation/html/git-filter-repo.html:
	mkdir -p Documentation/html
	git show origin/docs:html/git-filter-repo.html >Documentation/html/git-filter-repo.html

install: snag_docs #fixup_locale
	cp -a git-filter-repo "$(bindir)/"
	ln -sf "$(bindir)/git-filter-repo" "$(pythondir)/git_filter_repo.py"
	cp -a Documentation/man1/git-filter-repo.1 "$(mandir)/man1/git-filter-repo.1"
	cp -a Documentation/html/git-filter-repo.html "$(htmldir)/git-filter-repo.html"


#
# The remainder of the targets are meant for tasks for the maintainer; if they
# don't work for you, I don't care.  These tasks modify branches and upload
# releases and whatnot, and presume a directory layout I have locally.
#
update_docs: export GIT_WORK_TREE=$(shell mktemp -d)
update_docs: export GIT_INDEX_FILE=$(shell mktemp)
update_docs: export COMMIT=$(shell git rev-parse HEAD)
update_docs:
	# Sanity check; we'll build docs in a clone of a git repo
	test -d ../git
	# Sanity check; docs == origin/docs
	test -z "$(git rev-parse docs origin/docs | uniq -u)"
	# Avoid spurious errors by forcing index to be well formatted, if empty
	git read-tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904 # empty tree
	# Symlink git-filter-repo.txt documentation into git and build it
	ln -sf ../../git-filter-repo/Documentation/git-filter-repo.txt ../git/Documentation/
	make -C ../git/Documentation -j4 man html
	# Take the built documentation and lay it out nicely
	mkdir $$GIT_WORK_TREE/html
	mkdir $$GIT_WORK_TREE/man1
	cp -a ../git/Documentation/*.html $$GIT_WORK_TREE/html/
	cp -a ../git/Documentation/git-filter-repo.1 $$GIT_WORK_TREE/man1/
	dos2unix $$GIT_WORK_TREE/html/*
	# Add new version of the documentation as a commit, if it differs
	git --work-tree $$GIT_WORK_TREE add .
	git diff --quiet docs || git write-tree \
		| xargs git commit-tree -p docs -m "Update docs to $$COMMIT" \
		| xargs git update-ref refs/heads/docs
	# Remove temporary files
	rm -rf $$GIT_WORK_TREE
	rm $$GIT_INDEX_FILE
	# Push the new documentation upstream
	git push origin docs
	# Notify of completion
	@echo
	@echo === filter-repo docs branch updated ===

# Call like this:
#   make GITHUB_COM_TOKEN=$KEY TAGNAME=v2.23.0 release
release: github_release pypi_release

# Call like this:
#   make GITHUB_COM_TOKEN=$KEY TAGNAME=v2.23.0 github_release
github_release: export FILEBASE=git-filter-repo-$(shell echo $(TAGNAME) | tail -c +2)
github_release: export GIT_INDEX_FILE=$(shell mktemp)
github_release: export COMMIT=$(shell git rev-parse HEAD)
github_release: update_docs
	test -n "$(GITHUB_COM_TOKEN)"
	test -n "$(TAGNAME)"
	test -n "$$COMMIT"
	# Make sure 'jq' is installed
	type -p jq
	# Tag the release, push it to GitHub
	git tag -a -m "filter-repo $(TAGNAME)" $(TAGNAME) $$COMMIT
	git push origin $(TAGNAME)
	# Create the tarball
	git read-tree $$COMMIT
	git ls-tree -r docs | grep filter-repo    \
		| sed -e 's%\t%\tDocumentation/%' \
		| git update-index --index-info
	git write-tree                                    \
		| xargs git archive --prefix=$(FILEBASE)/ \
		| xz -c >$(FILEBASE).tar.xz
	rm $$GIT_INDEX_FILE
	# Make GitHub mark our new tag as an official release
	curl -s -H "Authorization: token $(GITHUB_COM_TOKEN)" -X POST \
		https://api.github.com/repos/newren/git-filter-repo/releases \
		--data "{                                  \
		  \"tag_name\": \"$(TAGNAME)\",            \
		  \"target_commitish\": \"$$COMMIT\",      \
		  \"name\": \"$(TAGNAME)\",                \
		  \"body\": \"filter-repo $(TAGNAME)\"     \
		}" | jq -r .id >asset_id
	# Upload our tarball
	cat asset_id | xargs -I ASSET_ID curl -s -H "Authorization: token $(GITHUB_COM_TOKEN)" -H "Content-Type: application/octet-stream" --data-binary @$(FILEBASE).tar.xz https://uploads.github.com/repos/newren/git-filter-repo/releases/ASSET_ID/assets?name=$(FILEBASE).tar.xz
	# Remove temporary file(s)
	rm asset_id
	# Notify of completion
	@echo
	@echo === filter-repo $(TAGNAME) created and uploaded to GitHub ===

pypi_release: # Has an implicit dependency on github_release because...
	# Upload to PyPI, automatically picking tag created by github_release
	cd release && python3 -m venv venv
	cd release && venv/bin/pip3 install --upgrade setuptools pip
	cd release && venv/bin/pip3 install twine wheel
	cd release && venv/bin/python3 setup.py sdist bdist_wheel
	# Note: hope you remember password for pypi, but username is 'newren'
	cd release && venv/bin/twine upload dist/*
	# Remove temporary file(s)
	cd release && rm -f README.md git-filter-repo git_filter_repo.py
	cd release && rm -rf .eggs/ build/ venv/ git_filter_repo.egg-info/

# NOTE TO FUTURE SELF: If you accidentally push a bad release, you can remove
# all but the git-filter-repo-$VERSION.tar.xz asset with
#    git push --delete origin $TAGNAME
# To remove the git-filter-repo-$VERSION.tar.xz asset as well:
#    curl -s -H "Authorization: token $GITHUB_COM_TOKEN" -X GET \
#        https://api.github.com/repos/newren/git-filter-repo/releases
# and look for the "id", then run
#    curl -s -H "Authorization: token $GITHUB_COM_TOKEN" -X DELETE \
#        https://api.github.com/repos/newren/git-filter-repo/releases/$ID
