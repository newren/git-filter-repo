#!/bin/bash

test_description='Usage of git-filter-repo with python callbacks'
. ./test-lib.sh

export PATH=$(dirname $TEST_DIRECTORY):$PATH  # Put git-filter-repo in PATH

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
		git commit -m "Brain damage" &&

                git tag v1.0 HEAD~3 &&
                git tag -a -m 'Super duper snazzy release' v2.0 HEAD~1 &&
                git branch testing master &&

		# Make it look like a fresh clone (avoid need for --force)
		git gc &&
		git remote add origin . &&
		git update-ref refs/remotes/origin/master refs/heads/master
		git update-ref refs/remotes/origin/testing refs/heads/testing
	)
}

test_expect_success '--filename-callback' '
	setup filename-callback &&
	(
		cd filename-callback &&
		git filter-repo --filename-callback "return None if filename.endswith(b\".doc\") else b\"src/\"+filename" &&
		git log --format=%n --name-only | sort | uniq | grep -v ^$ > f &&
		! grep file.doc f &&
		COMPARE=$(wc -l <f) &&
		grep src/ f >filtered_f &&
		test_line_count = $COMPARE filtered_f
	)
'

test_expect_success '--message-callback' '
	setup message-callback &&
	(
		cd message-callback &&
		git filter-repo --message-callback "return b\"TLDR: \"+message[0:5]" &&
		git log --format=%s >log-messages &&
		grep TLDR:...... log-messages >modified-messages &&
		test_line_count = 6 modified-messages
	)
'

test_expect_success '--name-callback' '
	setup name-callback &&
	(
		cd name-callback &&
		git filter-repo --name-callback "return name.replace(b\"N.\", b\"And\")" &&
		git log --format=%an >log-person-names &&
		grep Copy.And.Paste log-person-names
	)
'

test_expect_success '--email-callback' '
	setup email-callback &&
	(
		cd email-callback &&
		git filter-repo --email-callback "return email.replace(b\".com\", b\".org\")" &&
		git log --format=%ae%n%ce >log-emails &&
		! grep .com log-emails &&
		grep .org log-emails
	)
'

test_expect_success '--refname-callback' '
	setup refname-callback &&
	(
		cd refname-callback &&
		git filter-repo --refname-callback "
                    dir,path = os.path.split(refname)
                    return dir+b\"/prefix-\"+path" &&
		git show-ref | grep refs/heads/prefix-master &&
		git show-ref | grep refs/tags/prefix-v1.0 &&
		git show-ref | grep refs/tags/prefix-v2.0
	)
'

test_expect_success '--refname-callback sanity check' '
	setup refname-sanity-check &&
	(
		cd refname-sanity-check &&

		test_must_fail git filter-repo --refname-callback "return re.sub(b\"tags\", b\"other-tags\", refname)" 2>../err &&
		test_i18ngrep "fast-import requires tags to be in refs/tags/ namespace" ../err &&
		rm ../err
	)
'

test_expect_success '--blob-callback' '
	setup blob-callback &&
	(
		cd blob-callback &&
		git log --format=%n --name-only | sort | uniq | grep -v ^$ > f &&
		test_line_count = 5 f &&
		rm f &&
		git filter-repo --blob-callback "if len(blob.data) > 25: blob.skip()" &&
		git log --format=%n --name-only | sort | uniq | grep -v ^$ > f &&
		test_line_count = 2 f
	)
'

test_expect_success '--commit-callback' '
	setup commit-callback &&
	(
		cd commit-callback &&
		git filter-repo --commit-callback "
                    commit.committer_name  = commit.author_name
                    commit.committer_email = commit.author_email
                    commit.committer_date  = commit.author_date
                    for change in commit.file_changes:
                      change.mode = b\"100755\"
                    " &&
		git log --format=%ae%n%ce >log-emails &&
		! grep committer@example.com log-emails &&
		git log --raw | grep ^: >file-changes &&
		! grep 100644 file-changes &&
		grep 100755 file-changes
	)
'

test_expect_success '--tag-callback' '
	setup tag-callback &&
	(
		cd tag-callback &&
		git filter-repo --tag-callback "
                    tag.tagger_name = b\"Dr. \"+tag.tagger_name
                    tag.message = b\"Awesome sauce \"+tag.message
                    " &&
		git cat-file -p v2.0 | grep ^tagger.Dr\\. &&
		git cat-file -p v2.0 | grep ^Awesome.sauce.Super
	)
'

test_expect_success '--reset-callback' '
	setup reset-callback &&
	(
		cd reset-callback &&
		git filter-repo --reset-callback "reset.from_ref = 3" &&
		test $(git rev-parse testing) = $(git rev-parse master~3)
	)
'

test_expect_success 'callback has return statement sanity check' '
	setup callback_return_sanity &&
	(
		cd callback_return_sanity &&

		test_must_fail git filter-repo --filename-callback "filename + b\".txt\"" 2>../err&&
		test_i18ngrep "Error: --filename-callback should have a return statement" ../err &&
		rm ../err
	)
'

test_expect_success 'Callback read from a file' '
	setup name-callback-from-file &&
	(
		cd name-callback-from-file &&
		echo "return name.replace(b\"N.\", b\"And\")" >../name-func &&
		git filter-repo --name-callback ../name-func &&
		git log --format=%an >log-person-names &&
		grep Copy.And.Paste log-person-names
	)
'


test_done
