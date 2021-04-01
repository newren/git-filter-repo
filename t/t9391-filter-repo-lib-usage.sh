#!/bin/bash

test_description='Usage of git-filter-repo as a library'
. ./test-lib.sh

# for git_filter_repo.py import
case "$(uname -s)" in
MINGW*|MSYS)
	export PYTHONPATH=$(cygpath -am $TEST_DIRECTORY/..)\;$PYTHONPATH
	;;
*)
	export PYTHONPATH=$(dirname $TEST_DIRECTORY):$PYTHONPATH
	;;
esac
# Avoid writing git_filter_repo.pyc file
export PYTHONDONTWRITEBYTECODE=1
export CONTRIB_DIR=$TEST_DIRECTORY/../contrib/filter-repo-demos

setup()
{
	git init $1 &&
	(
		cd $1 &&
		echo hello > world &&
		git add world &&
		test_tick &&
		git commit -m initial &&
		printf "The launch code is 1-2-3-4." > secret &&
		git add secret &&
		test_tick &&
		git commit -m "Sssh.  Dont tell no one" &&
		echo A file that you cant trust > file.doc &&
		echo there >> world &&
		git add file.doc world &&
		test_tick &&
		printf "Random useless changes\n\nLet us be like the marketing group.  Marketing is staffed with pansies" | git commit -F - &&
		echo Do not use a preposition to end a setence with > advice &&
		git add advice &&
		test_tick &&
		GIT_AUTHOR_NAME="Copy N. Paste" git commit -m "hypocrisy is fun" &&
		echo Avoid cliches like the plague >> advice &&
		test_tick &&
		GIT_AUTHOR_EMAIL="foo@my.crp" git commit -m "it is still fun" advice &&
		echo "  \$Id: A bunch of junk$" > foobar.c &&
		git add foobar.c &&
		test_tick &&
		git commit -m "Brain damage"
	)
}

test_expect_success 'commit_info.py' '
	setup commit_info &&
	(
		cd commit_info &&
		$TEST_DIRECTORY/t9391/commit_info.py &&
		test 0e5a1029 = $(git rev-parse --short=8 --verify refs/heads/master)
	)
'

test_expect_success 'file_filter.py' '
	setup file_filter &&
	(
		cd file_filter &&
		$TEST_DIRECTORY/t9391/file_filter.py &&
		test ee59e2b4 = $(git rev-parse --short=8 --verify refs/heads/master)
	)
'

test_expect_success 'print_progress.py' '
	setup print_progress &&
	(
		cd print_progress &&
		MASTER=$(git rev-parse --verify master) &&
		$TEST_DIRECTORY/t9391/print_progress.py . new &&
		test $MASTER = $(git rev-parse --verify refs/heads/master)
	)
'

test_expect_success 'rename-master-to-develop.py' '
	setup rename_master_to_develop &&
	(
		cd rename_master_to_develop &&
		MASTER=$(git rev-parse --verify master) &&
		$TEST_DIRECTORY/t9391/rename-master-to-develop.py &&
		test $MASTER = $(git rev-parse --verify refs/heads/develop)
	)
'

test_expect_success 'strip-cvs-keywords.py' '
	setup strip_cvs_keywords &&
	(
		cd strip_cvs_keywords &&
		$TEST_DIRECTORY/t9391/strip-cvs-keywords.py
		test 2306fc7c = $(git rev-parse --short=8 --verify refs/heads/master)
	)
'

test_expect_success 'setup two extra repositories' '
	mkdir repo1 &&
	cd repo1 &&
	git init &&
	echo hello > world &&
	git add world &&
	test_tick &&
	git commit -m "Commit A" &&
	echo goodbye > world &&
	git add world &&
	test_tick &&
	git commit -m "Commit C" &&
	cd .. &&
	mkdir repo2 &&
	cd repo2 &&
	git init &&
	echo foo > bar &&
	git add bar &&
	test_tick &&
	git commit -m "Commit B" &&
	echo fooey > bar &&
	git add bar &&
	test_tick &&
	git commit -m "Commit D" &&
	cd ..
'

test_expect_success 'splice_repos.py' '
	git init splice_repos &&
	$TEST_DIRECTORY/t9391/splice_repos.py repo1 repo2 splice_repos &&
	test 4 = $(git -C splice_repos rev-list master | wc -l)
'

test_expect_success 'create_fast_export_output.py' '
	git init create_fast_export_output &&
	(cd create_fast_export_output &&
		$TEST_DIRECTORY/t9391/create_fast_export_output.py &&
		test e5e0569b = $(git rev-parse --short=8 --verify refs/heads/master) &&
		test 122ead00 = $(git rev-parse --short=8 --verify refs/heads/devel) &&
		test f36143f9 = $(git rev-parse --short=8 --verify refs/tags/v1.0))
'

test_expect_success 'unusual.py' '
	setup unusual &&
	(
		cd unusual &&
		cat $TEST_DIRECTORY/t9390/unusual | \
			$TEST_DIRECTORY/t9391/unusual.py >output &&

		grep "Decipher this: .oy ,tropmi eht gnitrats ma I" output &&
		grep "Found 2 blobs/commits and 4 other objects" output
	)
'

test_expect_success 'erroneous.py' '
	setup erroneous &&
	(
		cd erroneous &&
		test_must_fail $TEST_DIRECTORY/t9391/erroneous.py 2>../err &&

		test_i18ngrep "Error: Cannot pass a tag_callback to RepoFilter AND pass --tag-callback" ../err
	)
'

test_expect_success 'other error cases' '
	GIT_CEILING_DIRECTORIES=$(pwd) &&
	export GIT_CEILING_DIRECTORIES &&
	(
		mkdir other &&
		cd other &&

		! python3 -c "import git_filter_repo as fr; fr.GitUtils.get_commit_count(b\".\", [\"HEAD\"])" 2>err &&
		test_i18ngrep "\. does not appear to be a valid git repository" err
	)
'

test_lazy_prereq DOS2UNIX '
	dos2unix -h
	test $? -ne 127
'

test_expect_success 'lint-history' '
	test_create_repo lint-history &&
	(
		cd lint-history &&
		git config core.autocrlf false &&
		echo initial >content &&
		git add content &&
		git commit -m "initial" &&

		printf "CRLF is stupid\r\n" >content &&
		git add content &&
		git commit -m "make a statement" &&

		printf "CRLF is stupid\n" >content &&
		git add content &&
		git commit -m "oops, that was embarassing" &&

		if test_have_prereq DOS2UNIX
		then
			$CONTRIB_DIR/lint-history --filenames-important dos2unix &&
			echo 2 >expect &&
			git rev-list --count HEAD >actual &&
			test_cmp expect actual
		fi
	)
'

test_done
