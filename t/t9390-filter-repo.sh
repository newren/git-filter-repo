#!/bin/bash

test_description='Basic filter-repo tests'

. ./test-lib.sh

export PATH=$(dirname $TEST_DIRECTORY):$PATH  # Put git-filter-repo in PATH

DATA="$TEST_DIRECTORY/t9390"

filter_testcase() {
	INPUT=$1
	OUTPUT=$2
	shift 2
	REST=("$@")


	NAME="check: $INPUT -> $OUTPUT using '${REST[@]}'"
	test_expect_success "$NAME" '
		# Clean up from previous run
		git pack-refs --all &&
		rm .git/packed-refs &&

		# Run the example
		cat $DATA/$INPUT | git filter-repo --stdin --quiet --force "${REST[@]}" &&

		# Compare the resulting repo to expected value
		git fast-export --use-done-feature --all >compare &&
		test_cmp $DATA/$OUTPUT compare
	'
}

filter_testcase basic basic-filename --path filename
filter_testcase basic basic-twenty   --path twenty
filter_testcase basic basic-ten      --path ten
filter_testcase basic basic-numbers  --path ten --path twenty
filter_testcase basic basic-filename --invert-paths --path-glob 't*en*'
filter_testcase basic basic-numbers  --invert-paths --path-regex 'f.*e.*e'
filter_testcase basic basic-mailmap  --mailmap ../t9390/sample-mailmap
filter_testcase basic basic-replace  --replace-text ../t9390/sample-replace
filter_testcase empty empty-keepme   --path keepme
filter_testcase degenerate degenerate-keepme   --path moduleA/keepme
filter_testcase degenerate degenerate-moduleA  --path moduleA
filter_testcase degenerate degenerate-globme   --path-glob *me

test_expect_success 'setup path_rename' '
	test_create_repo path_rename &&
	(
		cd path_rename &&
		mkdir sequences values &&
		test_seq 1 10 >sequences/tiny &&
		test_seq 100 110 >sequences/intermediate &&
		test_seq 1000 1010 >sequences/large &&
		test_seq 1000 1010 >values/large &&
		test_seq 10000 10010 >values/huge &&
		git add sequences values &&
		git commit -m initial &&

		git mv sequences/tiny sequences/small &&
		cp sequences/intermediate sequences/medium &&
		echo 10011 >values/huge &&
		git add sequences values &&
		git commit -m updates &&

		git rm sequences/intermediate &&
		echo 11 >sequences/small &&
		git add sequences/small &&
		git commit -m changes &&

		echo 1011 >sequences/medium &&
		git add sequences/medium &&
		git commit -m final
	)
'

test_expect_success '--path-rename sequences/tiny:sequences/small' '
	(
		git clone file://"$(pwd)"/path_rename path_rename_single &&
		cd path_rename_single &&
		git filter-repo --path-rename sequences/tiny:sequences/small &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 7 filenames &&
		! grep sequences/tiny filenames &&
		git rev-parse HEAD~3:sequences/small
	)
'

test_expect_success '--path-rename sequences:numbers' '
	(
		git clone file://"$(pwd)"/path_rename path_rename_dir &&
		cd path_rename_dir &&
		git filter-repo --path-rename sequences:numbers &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 8 filenames &&
		! grep sequences/ filenames &&
		grep numbers/ filenames &&
		grep values/ filenames
	)
'

test_expect_success '--path-rename-prefix values:numbers' '
	(
		git clone file://"$(pwd)"/path_rename path_rename_dir_2 &&
		cd path_rename_dir_2 &&
		git filter-repo --path-rename values/:numbers/ &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 8 filenames &&
		! grep values/ filenames &&
		grep sequences/ filenames &&
		grep numbers/ filenames
	)
'

test_expect_success '--path-rename squashing' '
	(
		git clone file://"$(pwd)"/path_rename path_rename_squash &&
		cd path_rename_squash &&
		git filter-repo \
			--path-rename sequences/tiny:sequences/small \
			--path-rename sequences:numbers \
			--path-rename values:numbers \
			--path-rename numbers/intermediate:numbers/medium &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		# Just small, medium, large, huge, and a blank line...
		test_line_count = 5 filenames &&
		! grep sequences/ filenames &&
		! grep values/ filenames &&
		grep numbers/ filenames
	)
'

test_expect_success '--path-rename inability to squash' '
	(
		git clone file://"$(pwd)"/path_rename path_rename_bad_squash &&
		cd path_rename_bad_squash &&
		test_must_fail git filter-repo \
			--path-rename values/large:values/big \
			--path-rename values/huge:values/big 2>../err &&
		test_i18ngrep "File renaming caused colliding pathnames" ../err
	)
'

test_expect_success 'more setup' '
	test_create_repo metasyntactic &&
	(
		cd metasyntactic &&
		weird_name=$(printf "file\tna\nme") &&
		echo "funny" >"$weird_name" &&
		mkdir numbers &&
		test_seq 1 10 >numbers/small &&
		test_seq 100 110 >numbers/medium &&
		git add "$weird_name" numbers &&
		git commit -m initial &&
		git tag v1.0 &&
		git tag -a -m v1.1 v1.1 &&

		mkdir words &&
		echo foo >words/important &&
		echo bar >words/whimsical &&
		echo baz >words/sequences &&
		git add words &&
		git commit -m some.words &&
		git branch another_branch &&
		git tag v2.0 &&

		echo spam >words/to &&
		echo eggs >words/know &&
		git add words
		git rm "$weird_name" &&
		git commit -m more.words &&
		git tag -a -m "Look, ma, I made a tag" v3.0
	)
'

test_expect_success '--tag-rename' '
	(
		git clone file://"$(pwd)"/metasyntactic tag_rename &&
		cd tag_rename &&
		git filter-repo \
			--tag-rename "":"myrepo-" \
			--path words &&
		test_must_fail git cat-file -t v1.0 &&
		test_must_fail git cat-file -t v1.1 &&
		test_must_fail git cat-file -t v2.0 &&
		test_must_fail git cat-file -t v3.0 &&
		test_must_fail git cat-file -t myrepo-v1.0 &&
		test_must_fail git cat-file -t myrepo-v1.1 &&
		test $(git cat-file -t myrepo-v2.0) = commit &&
		test $(git cat-file -t myrepo-v3.0) = tag
	)
'

test_expect_success '--subdirectory-filter' '
	(
		git clone file://"$(pwd)"/metasyntactic subdir_filter &&
		cd subdir_filter &&
		git filter-repo \
			--subdirectory-filter words &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 10 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 6 filenames &&
		grep ^important$ filenames &&
		test_must_fail git cat-file -t v1.0 &&
		test_must_fail git cat-file -t v1.1 &&
		test $(git cat-file -t v2.0) = commit &&
		test $(git cat-file -t v3.0) = tag
	)
'

test_expect_success '--to-subdirectory-filter' '
	(
		git clone file://"$(pwd)"/metasyntactic to_subdir_filter &&
		cd to_subdir_filter &&
		git filter-repo \
			--to-subdirectory-filter mysubdir &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 22 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 9 filenames &&
		grep "^\"mysubdir/file\\\\tna\\\\nme\"$" filenames &&
		grep ^mysubdir/words/important$ filenames &&
		test $(git cat-file -t v1.0) = commit &&
		test $(git cat-file -t v1.1) = tag &&
		test $(git cat-file -t v2.0) = commit &&
		test $(git cat-file -t v3.0) = tag
	)
'

test_expect_success 'refs/replace/ to skip a parent' '
	(
		git clone file://"$(pwd)"/metasyntactic replace_skip_ref &&
		cd replace_skip_ref &&

		git tag -d v2.0 &&
		git replace HEAD~1 HEAD~2 &&

		git filter-repo --path "" --force &&
		test $(git rev-list --count HEAD) = 2 &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 16 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 9 filenames &&
		test $(git cat-file -t v1.0) = commit &&
		test $(git cat-file -t v1.1) = tag &&
		test_must_fail git cat-file -t v2.0 &&
		test $(git cat-file -t v3.0) = tag
	)
'

test_expect_success 'refs/replace/ to add more initial history' '
	(
		git clone file://"$(pwd)"/metasyntactic replace_add_refs &&
		cd replace_add_refs &&

		git checkout --orphan new_root &&
		rm .git/index &&
		git add numbers/small &&
		git clean -fd &&
		git commit -m new.root &&

		git replace --graft master~2 new_root &&
		git checkout master &&

		git --no-replace-objects cat-file -p master~2 >grandparent &&
		! grep parent grandparent &&

		git filter-repo --path "" --force &&

		git --no-replace-objects cat-file -p master~2 >new-grandparent &&
		grep parent new-grandparent &&

		test $(git rev-list --count HEAD) = 4 &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 22 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 9 filenames &&
		test $(git cat-file -t v1.0) = commit &&
		test $(git cat-file -t v1.1) = tag &&
		test $(git cat-file -t v2.0) = commit &&
		test $(git cat-file -t v3.0) = tag
	)
'

test_expect_success 'setup analyze_me' '
	test_create_repo analyze_me &&
	(
		cd analyze_me &&
		mkdir numbers words &&
		test_seq 1 10 >numbers/small.num &&
		test_seq 100 110 >numbers/medium.num &&
		echo spam >words/to &&
		echo eggs >words/know &&
		echo rename a lot >fickle &&
		git add numbers words fickle &&
		test_tick &&
		git commit -m initial &&

		git branch other &&
		git mv fickle capricious &&
		test_tick &&
		git commit -m "rename on main branch" &&

		git checkout other &&
		echo random other change >whatever &&
		git add whatever &&
		git mv fickle capricious &&
		test_tick &&
		git commit -m "rename on other branch" &&

		git checkout master &&
		git merge --no-commit other &&
		git mv capricious mercurial &&
		test_tick &&
		git commit &&

		git mv words sequence &&
		test_tick &&
		git commit -m now.sequence &&

		git rm -rf numbers &&
		test_tick &&
		git commit -m remove.words &&

		mkdir words &&
		echo no >words/know &&
		git add words/know &&
		test_tick &&
		git commit -m "Recreated file previously renamed" &&

		echo "160000 deadbeefdeadbeefdeadbeefdeadbeefdeadbeefQfake_submodule" | q_to_tab | git update-index --index-info &&
		test_tick &&
		git commit -m "Add a fake submodule" &&

		test_tick &&
		git commit --allow-empty -m "Final commit, empty" &&

		# Add a random extra unreferenced object
		echo foobar | git hash-object --stdin -w
	)
'

test_expect_success '--analyze' '
	(
		cd analyze_me &&

		git filter-repo --analyze &&

		# It should work and overwrite report if run again
		git filter-repo --analyze &&

		test -d .git/filter-repo/analysis &&
		cd .git/filter-repo/analysis &&

		cat >expect <<-EOF &&
		fickle ->
		    capricious
		    mercurial
		words/to ->
		    sequence/to
		EOF
		test_cmp expect renames.txt &&

		cat >expect <<-EOF &&
		== Overal Statistics ==
		  Number of commits:         9
		  Number of filenames:       10
		  Number of directories:     4
		  Number of file extensions: 2

		  Total unpacked size (bytes):        147
		  Total packed size (bytes):          306

		EOF
		head -n 9 README >actual &&
		test_cmp expect actual &&

		cat | tr Q "\047" >expect <<-\EOF &&
		== Files by sha and associated pathnames in reverse size ==
		Format: sha, unpacked size, packed size, filename(s) object stored as
		  a89c82a2d4b713a125a4323d25adda062cc0013d         44         48 numbers/medium.num
		  f00c965d8307308469e537302baa73048488f162         21         37 numbers/small.num
		  2aa69a2a708eed00cb390e30f6bcc3eed773f390         20         36 whatever
		  51b95456de9274c9a95f756742808dfd480b9b35         13         29 [QcapriciousQ, QfickleQ, QmercurialQ]
		  34b6a0c9d02cb6ef7f409f248c0c1224ce9dd373          5         20 [Qsequence/toQ, Qwords/toQ]
		  732c85a1b3d7ce40ec8f78fd9ffea32e9f45fae0          5         20 [Qsequence/knowQ, Qwords/knowQ]
		  7ecb56eb3fa3fa6f19dd48bca9f971950b119ede          3         18 words/know
		EOF
		test_cmp expect blob-shas-and-paths.txt &&

		cat >expect <<-EOF &&
		=== All directories by reverse size ===
		Format: unpacked size, packed size, date deleted, directory name
		         147        306 <present>  <toplevel>
		          65         85 2005-04-07 numbers
		          13         58 <present>  words
		          10         40 <present>  sequence
		EOF
		test_cmp expect directories-all-sizes.txt &&

		cat >expect <<-EOF &&
		=== Deleted directories by reverse size ===
		Format: unpacked size, packed size, date deleted, directory name
		          65         85 2005-04-07 numbers
		EOF
		test_cmp expect directories-deleted-sizes.txt &&

		cat >expect <<-EOF &&
		=== All extensions by reverse size ===
		Format: unpacked size, packed size, date deleted, extension name
		          82        221 <present>  <no extension>
		          65         85 2005-04-07 .num
		EOF
		test_cmp expect extensions-all-sizes.txt &&

		cat >expect <<-EOF &&
		=== Deleted extensions by reverse size ===
		Format: unpacked size, packed size, date deleted, extension name
		          65         85 2005-04-07 .num
		EOF
		test_cmp expect extensions-deleted-sizes.txt &&

		cat >expect <<-EOF &&
		=== All paths by reverse accumulated size ===
		Format: unpacked size, packed size, date deleted, pathectory name
		          44         48 2005-04-07 numbers/medium.num
		           8         38 <present>  words/know
		          21         37 2005-04-07 numbers/small.num
		          20         36 <present>  whatever
		          13         29 <present>  fickle
		          13         29 <present>  mercurial
		          13         29 <present>  capricious
		           5         20 <present>  words/to
		           5         20 <present>  sequence/know
		           5         20 <present>  sequence/to
		EOF
		test_cmp expect path-all-sizes.txt &&

		cat >expect <<-EOF &&
		=== Deleted paths by reverse accumulated size ===
		Format: unpacked size, packed size, date deleted, path name(s)
		          44         48 2005-04-07 numbers/medium.num
		          21         37 2005-04-07 numbers/small.num
		EOF
		test_cmp expect path-deleted-sizes.txt
	)
'

test_expect_success '--replace-text all options' '
	(
		git clone file://"$(pwd)"/analyze_me replace_text &&
		cd replace_text &&

		cat >../replace-rules <<-\EOF &&
		other
		change==>variation

		literal:spam==>foodstuff
		glob:ran*m==>haphazard
		regex:1(.[0-9])==>2\1
		EOF
		git filter-repo --replace-text ../replace-rules &&

		test_seq 200 210 >expect &&
		git show HEAD~4:numbers/medium.num >actual &&
		test_cmp expect actual &&

		echo "haphazard ***REMOVED*** variation" >expect &&
		test_cmp expect whatever
	)
'

test_expect_success 'setup commit message rewriting' '
	test_create_repo commit_msg &&
	(
		cd commit_msg &&
		echo two guys walking into a >bar &&
		git add bar &&
		git commit -m initial &&

		test_commit another &&

		name=$(git rev-parse HEAD) &&
		echo hello >world &&
		git add world &&
		git commit -m "Commit referencing ${name:0:8}" &&

		git revert HEAD &&

		for i in $(test_seq 1 200)
		do
			git commit --allow-empty -m "another commit"
		done &&

		echo foo >bar &&
		git add bar &&
		git commit -m bar &&

		git revert --no-commit HEAD &&
		echo foo >baz &&
		git add baz &&
		git commit
	)
'

test_expect_success 'commit message rewrite' '
	(
		git clone file://"$(pwd)"/commit_msg commit_msg_clone &&
		cd commit_msg_clone &&

		git filter-repo --invert-paths --path bar &&

		git log --oneline >changes &&
		test_line_count = 204 changes &&

		name=$(git rev-parse HEAD~203) &&
		echo "Commit referencing ${name:0:8}" >expect &&
		git log --no-walk --format=%s HEAD~202 >actual &&
		test_cmp expect actual &&

		latest=$(git log --no-walk | grep reverts | awk "{print \$4}" | tr -d '.') &&
		test -n "$latest" &&
		test_must_fail git cat-file -e "$latest"
	)
'

test_expect_success 'commit message rewrite unsuccessful' '
	(
		git init commit_msg_not_found &&
		cd commit_msg_not_found &&

		cat >input <<-\EOF &&
		feature done
		commit refs/heads/develop
		mark :1
		original-oid deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
		author Just Me <just@here.org> 1234567890 -0200
		committer Just Me <just@here.org> 1234567890 -0200
		data 2
		A

		commit refs/heads/develop
		mark :2
		original-oid deadbeefcafedeadbeefcafedeadbeefcafecafe
		author Just Me <just@here.org> 1234567890 -0200
		committer Just Me <just@here.org> 1234567890 -0200
		data 2
		B

		commit refs/heads/develop
		mark :3
		original-oid 0000000000000000000000000000000000000004
		author Just Me <just@here.org> 3980014290 -0200
		committer Just Me <just@here.org> 3980014290 -0200
		data 93
		Four score and seven years ago, commit deadbeef ("B",
		2009-02-13) messed up.  This fixes it.
		done
		EOF

		cat input | git filter-repo --stdin --path salutation --force &&

		git log --oneline develop >changes &&
		test_line_count = 3 changes &&

		git log develop >out &&
		grep deadbeef out
	)
'

test_done
