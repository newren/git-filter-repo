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

test_expect_success '--file-info-callback acting like --filename-callback' '
	setup fileinfo-as-filename-callback &&
	(
		cd fileinfo-as-filename-callback &&
		git filter-repo --file-info-callback "return (None if filename.endswith(b\".doc\") else b\"src/\"+filename, mode, blob_id)" &&
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

test_expect_success '--file-info-callback acting like --blob-callback' '
	setup fileinfo-as-blob-callback &&
	(
		cd fileinfo-as-blob-callback &&
		git log --format=%n --name-only | sort | uniq | grep -v ^$ > f &&
		test_line_count = 5 f &&
		rm f &&
		git filter-repo --file-info-callback "
		    size = value.get_size_by_identifier(blob_id)
		    return (None if size > 25 else filename, mode, blob_id)" &&
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

test_expect_success 'Filtering a blob to make it match previous version' '
	test_create_repo remove_unique_bits_of_blob &&
	(
		cd remove_unique_bits_of_blob &&

		test_write_lines foo baz >metasyntactic_names &&
		git add metasyntactic_names &&
		git commit -m init &&

		test_write_lines foo bar baz >metasyntactic_names &&
		git add metasyntactic_names &&
		git commit -m second &&

		git filter-repo --force --blob-callback "blob.data = blob.data.replace(b\"\\nbar\", b\"\")"

		echo 1 >expect &&
		git rev-list --count HEAD >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'tweaking just a tag' '
	test_create_repo tweaking_just_a_tag &&
	(
		cd tweaking_just_a_tag &&

		test_commit foo &&
		git tag -a -m "Here is a tag" mytag &&

		git filter-repo --force --refs mytag ^mytag^{commit} --name-callback "return name.replace(b\"Mitter\", b\"L D\")" &&

		git cat-file -p mytag | grep C.O.L.D
	)
'

test_expect_success '--file-info-callback messing with history' '
	setup messing_with_files &&
	(
		cd messing_with_files &&

		echo "1-2-3-4==>1-2-3-4-5" >replacement &&
		# Trying to count the levels of backslash escaping is not fun.
		echo "regex:\\\$[^\$]*\\\$==>cvs is lame" >>replacement &&
		git filter-repo --force --file-info-callback "
		    size = value.get_size_by_identifier(blob_id)
		    contents = value.get_contents_by_identifier(blob_id)
		    if not value.is_binary(contents):
		      contents = value.apply_replace_text(contents)
		    if contents[-1] != 10:
		      contents += bytes([10])
		    blob_id = value.insert_file_with_contents(contents)
		    newname = bytes(reversed(filename))
		    if size == 27 and len(contents) == 27:
		      newname = None
		    return (newname, mode, blob_id)
                    " --replace-text replacement &&

		cat <<-EOF >expect &&
		c.raboof
		dlrow
		ecivda
		terces
		EOF

		git ls-files >actual &&
		test_cmp expect actual &&

		echo "The launch code is 1-2-3-4-5." >expect &&
		test_cmp expect terces &&

		echo "  cvs is lame" >expect &&
		test_cmp expect c.raboof
	)
'

test_expect_success '--file-info-callback and deletes and drops' '
	setup file_info_deletes_drops &&
	(
		cd file_info_deletes_drops &&

		git rm file.doc &&
		git commit -m "Nuke doc file" &&

		git filter-repo --force --file-info-callback "
		    size = value.get_size_by_identifier(blob_id)
		    (newname, newmode) = (filename, mode)
		    if filename == b\"world\" and size == 12:
		      newname = None
		    if filename == b\"advice\" and size == 77:
		      newmode = None
		    return (newname, newmode, blob_id)
                    "

		cat <<-EOF >expect &&
		foobar.c
		secret
		world
		EOF

		echo 1 >expect &&
		git rev-list --count HEAD -- world >actual &&
		test_cmp expect actual &&

		echo 2 >expect &&
		git rev-list --count HEAD -- advice >actual &&
		test_cmp expect actual &&

		echo hello >expect &&
		test_cmp expect world
	)
'

test_lazy_prereq UNIX2DOS '
        unix2dos -h
        test $? -ne 127
'

test_expect_success UNIX2DOS '--file-info-callback acting like lint-history' '
	setup lint_history_replacement &&
	(
		cd lint_history_replacement &&
		git ls-files -s | grep -v file.doc >expect &&

		git filter-repo --force --file-info-callback "
		    if not filename.endswith(b\".doc\"):
		      return (filename, mode, blob_id)

		    if blob_id in value.data:
		      return (filename, mode, value.data[blob_id])

		    contents = value.get_contents_by_identifier(blob_id)
		    tmpfile = os.path.basename(filename)
		    with open(tmpfile, \"wb\") as f:
		      f.write(contents)
		    subprocess.check_call([\"unix2dos\", filename])
		    with open(filename, \"rb\") as f:
		      contents = f.read()
		    new_blob_id = value.insert_file_with_contents(contents)

		    value.data[blob_id] = new_blob_id
		    return (filename, mode, new_blob_id)
                    " &&

		git ls-files -s | grep -v file.doc >actual &&
		test_cmp expect actual &&

		printf "A file that you cant trust\r\n" >expect &&
		test_cmp expect file.doc
	)
'

test_done
