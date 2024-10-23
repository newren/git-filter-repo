#!/bin/bash

test_description='Basic filter-repo tests'

. ./test-lib.sh

export PATH=$(dirname $TEST_DIRECTORY):$PATH  # Put git-filter-repo in PATH

DATA="$TEST_DIRECTORY/t9394"

setup_metasyntactic_repo() {
	test -d metasyntactic && return
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
}

test_expect_success FUNNYNAMES '--tag-rename' '
	setup_metasyntactic_repo &&
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

test_expect_success 'tag of tag before relevant portion of history' '
	test_create_repo filtered_tag_of_tag &&
	(
		cd filtered_tag_of_tag &&
		echo contents >file &&
		git add file &&
		git commit -m "Initial" &&

		git tag -a -m "Inner Tag" inner_tag HEAD &&
		git tag -a -m "Outer Tag" outer_tag inner_tag &&

		mkdir subdir &&
		echo stuff >subdir/whatever &&
		git add subdir &&
		git commit -m "Add file in subdir" &&

		git filter-repo --force --subdirectory-filter subdir &&

		git show-ref >refs &&
		! grep refs/tags refs &&
		git log --all --oneline >commits &&
		test_line_count = 1 commits
	)
'

test_expect_success FUNNYNAMES '--subdirectory-filter' '
	setup_metasyntactic_repo &&
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

test_expect_success FUNNYNAMES '--subdirectory-filter with trailing slash' '
	setup_metasyntactic_repo &&
	(
		git clone file://"$(pwd)"/metasyntactic subdir_filter_2 &&
		cd subdir_filter_2 &&
		git filter-repo \
			--subdirectory-filter words/ &&
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

test_expect_success FUNNYNAMES '--to-subdirectory-filter' '
	setup_metasyntactic_repo &&
	(
		git clone file://"$(pwd)"/metasyntactic to_subdir_filter &&
		cd to_subdir_filter &&
		git filter-repo \
			--to-subdirectory-filter mysubdir/ &&
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

test_expect_success FUNNYNAMES '--use-base-name' '
	setup_metasyntactic_repo &&
	(
		git clone file://"$(pwd)"/metasyntactic use_base_name &&
		cd use_base_name &&
		git filter-repo --path small --path important --use-base-name &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 10 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 3 filenames &&
		grep ^numbers/small$ filenames &&
		grep ^words/important$ filenames &&
		test $(git cat-file -t v1.0) = commit &&
		test $(git cat-file -t v1.1) = tag &&
		test $(git cat-file -t v2.0) = commit &&
		test $(git cat-file -t v3.0) = tag
	)
'

test_expect_success FUNNYNAMES 'refs/replace/ to skip a parent' '
	setup_metasyntactic_repo &&
	(
		git clone file://"$(pwd)"/metasyntactic replace_skip_ref &&
		cd replace_skip_ref &&

		git tag -d v2.0 &&
		git replace HEAD~1 HEAD~2 &&

		git filter-repo --proceed &&
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

test_expect_success FUNNYNAMES 'refs/replace/ to add more initial history' '
	setup_metasyntactic_repo &&
	(
		git clone file://"$(pwd)"/metasyntactic replace_add_refs &&
		cd replace_add_refs &&

		git checkout --orphan new_root &&
		rm .git/index &&
		git add numbers/small &&
		git clean -fd &&
		git commit -m new.root &&
		NEW_ROOT=$(git rev-parse HEAD) &&
		git checkout master &&

		# Make it look like a fresh clone...
		git gc &&
		git reflog expire --expire=now HEAD &&
		git branch -D new_root &&

		# ...but add a replace object to give us a new root commit
		git replace --graft master~2 $NEW_ROOT &&

		git --no-replace-objects cat-file -p master~2 >grandparent &&
		! grep parent grandparent &&
		rm grandparent &&

		git filter-repo --proceed &&

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

test_expect_success FUNNYNAMES 'creation/deletion/updating of replace refs' '
	setup_metasyntactic_repo &&
	(
		git clone file://"$(pwd)"/metasyntactic replace_handling &&

		# Same setup as "refs/replace/ to skip a parent", so we
		# do not have to check that replacement refs were used
		# correctly in the rewrite, just that replacement refs were
		# deleted, added, or updated correctly.
		cd replace_handling &&
		git tag -d v2.0 &&
		master=$(git rev-parse master) &&
		master_1=$(git rev-parse master~1) &&
		master_2=$(git rev-parse master~2) &&
		git replace HEAD~1 HEAD~2 &&
		cd .. &&

		mkdir -p test_replace_refs &&
		cd test_replace_refs &&

		rsync -a --delete ../replace_handling/ ./ &&
		git filter-repo --replace-refs delete-no-add --path-rename numbers:counting &&
		git show-ref >output &&
		! grep refs/replace/ output &&

		rsync -a --delete ../replace_handling/ ./ &&
		git filter-repo --replace-refs delete-and-add --path-rename numbers:counting &&
		echo "$(git rev-parse master) refs/replace/$master" >out &&
		echo "$(git rev-parse master~1) refs/replace/$master_1" >>out &&
		echo "$(git rev-parse master~1) refs/replace/$master_2" >>out &&
		sort -k 2 out >expect &&
		git show-ref | grep refs/replace/ >output &&
		test_cmp output expect &&

		rsync -a --delete ../replace_handling/ ./ &&
		git filter-repo --replace-refs update-no-add --path-rename numbers:counting &&
		echo "$(git rev-parse master~1) refs/replace/$master_1" >expect &&
		git show-ref | grep refs/replace/ >output &&
		test_cmp output expect &&

		rsync -a --delete ../replace_handling/ ./ &&
		git filter-repo --replace-refs update-or-add --path-rename numbers:counting &&
		echo "$(git rev-parse master) refs/replace/$master" >>out &&
		echo "$(git rev-parse master~1) refs/replace/$master_1" >>out &&
		sort -k 2 out >expect &&
		git show-ref | grep refs/replace/ >output &&
		test_cmp output expect &&

		rsync -a --delete ../replace_handling/ ./ &&
		git filter-repo --replace-refs update-and-add --path-rename numbers:counting &&
		echo "$(git rev-parse master) refs/replace/$master" >>out &&
		echo "$(git rev-parse master~1) refs/replace/$master_1" >>out &&
		echo "$(git rev-parse master~1) refs/replace/$master_2" >>out &&
		sort -k 2 out >expect &&
		git show-ref | grep refs/replace/ >output &&
		test_cmp output expect &&

		rsync -a --delete ../replace_handling/ ./ &&
		git filter-repo --replace-refs old-default --path-rename numbers:counting &&
		echo "$(git rev-parse master) refs/replace/$master" >>out &&
		echo "$(git rev-parse master~1) refs/replace/$master_1" >>out &&
		echo "$(git rev-parse master~1) refs/replace/$master_2" >>out &&
		sort -k 2 out >expect &&
		git show-ref | grep refs/replace/ >output &&
		test_cmp output expect &&

		rsync -a --delete ../replace_handling/ ./ &&
		git filter-repo --replace-refs update-no-add --path-rename numbers:counting &&
		echo "$(git rev-parse master~1) refs/replace/$master_1" >expect &&
		git show-ref | grep refs/replace/ >output &&
		test_cmp output expect
	)
'

test_expect_success FUNNYNAMES '--debug' '
	setup_metasyntactic_repo &&
	(
		git clone file://"$(pwd)"/metasyntactic debug &&
		cd debug &&

		git filter-repo --path words --debug &&

		test $(git rev-list --count HEAD) = 2 &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 12 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 6 filenames &&

		test_path_is_file .git/filter-repo/fast-export.original &&
		grep "^commit " .git/filter-repo/fast-export.original >out &&
		test_line_count = 3 out &&
		test_path_is_file .git/filter-repo/fast-export.filtered &&
		grep "^commit " .git/filter-repo/fast-export.filtered >out &&
		test_line_count = 2 out
	)
'

test_expect_success FUNNYNAMES '--dry-run' '
	setup_metasyntactic_repo &&
	(
		git clone file://"$(pwd)"/metasyntactic dry_run &&
		cd dry_run &&

		git filter-repo --path words --dry-run &&

		git show-ref | grep master >out &&
		test_line_count = 2 out &&
		awk "{print \$1}" out | uniq >out2 &&
		test_line_count = 1 out2 &&

		test $(git rev-list --count HEAD) = 3 &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 19 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 9 filenames &&

		test_path_is_file .git/filter-repo/fast-export.original &&
		grep "^commit " .git/filter-repo/fast-export.original >out &&
		test_line_count = 3 out &&
		test_path_is_file .git/filter-repo/fast-export.filtered &&
		grep "^commit " .git/filter-repo/fast-export.filtered >out &&
		test_line_count = 2 out
	)
'

test_expect_success FUNNYNAMES '--dry-run --debug' '
	setup_metasyntactic_repo &&
	(
		git clone file://"$(pwd)"/metasyntactic dry_run_debug &&
		cd dry_run_debug &&

		git filter-repo --path words --dry-run --debug &&

		git show-ref | grep master >out &&
		test_line_count = 2 out &&
		awk "{print \$1}" out | uniq >out2 &&
		test_line_count = 1 out2 &&

		test $(git rev-list --count HEAD) = 3 &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 19 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 9 filenames &&

		test_path_is_file .git/filter-repo/fast-export.original &&
		grep "^commit " .git/filter-repo/fast-export.original >out &&
		test_line_count = 3 out &&
		test_path_is_file .git/filter-repo/fast-export.filtered &&
		grep "^commit " .git/filter-repo/fast-export.filtered >out &&
		test_line_count = 2 out
	)
'

test_expect_success FUNNYNAMES '--dry-run --stdin' '
	setup_metasyntactic_repo &&
	(
		git clone file://"$(pwd)"/metasyntactic dry_run_stdin &&
		cd dry_run_stdin &&

		git fast-export --all | git filter-repo --path words --dry-run --stdin &&

		git show-ref | grep master >out &&
		test_line_count = 2 out &&
		awk "{print \$1}" out | uniq >out2 &&
		test_line_count = 1 out2 &&

		test $(git rev-list --count HEAD) = 3 &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 19 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 9 filenames &&

		test_path_is_missing .git/filter-repo/fast-export.original &&
		test_path_is_file .git/filter-repo/fast-export.filtered &&
		grep "^commit " .git/filter-repo/fast-export.filtered >out &&
		test_line_count = 2 out
	)
'

setup_analyze_me() {
	test -d analyze_me && return
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

		git branch modify-fickle &&
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

		git checkout modify-fickle &&
		echo "more stuff" >>fickle &&
		test_tick &&
		git commit -am "another more stuff commit" &&

		git checkout modify-fickle &&
		echo "more stuff" >>fickle &&
		test_tick &&
		git commit -am "another more stuff commit" &&

		test_tick &&
		git commit --allow-empty -m "Final commit, empty" &&

		git checkout master &&

		# Add a random extra unreferenced object
		echo foobar | git hash-object --stdin -w
	)
}

test_expect_success C_LOCALE_OUTPUT '--analyze' '
	setup_analyze_me &&
	(
		cd analyze_me &&

		# Detect whether zlib or zlib-ng are in use; they give
		# slightly different compression
		echo e80fdf8cd5fb645649c14f41656a076dedc4e12a >expect &&
		python3 -c "print(\"test\\t\" * 1000, end=\"\")" | git hash-object -w --stdin >actual &&
		test_cmp expect actual &&
		compressed_size=$(python3 -c "import os; print(os.path.getsize(\".git/objects/e8/0fdf8cd5fb645649c14f41656a076dedc4e12a\"))") &&
		zlibng=$((72-${compressed_size})) &&
		test $zlibng -eq "0" -o $zlibng -eq "2" &&

		# Now do the analysis
		git filter-repo --analyze &&

		# It should not work again without a --force
		test_must_fail git filter-repo --analyze &&

		# With a --force, another run should succeed
		git filter-repo --analyze --force &&

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
		== Overall Statistics ==
		  Number of commits: 12
		  Number of filenames: 10
		  Number of directories: 4
		  Number of file extensions: 2

		  Total unpacked size (bytes): 206
		  Total packed size (bytes): $((387+${zlibng}))

		EOF
		head -n 9 README >actual &&
		test_cmp expect actual &&

		cat >expect <<-EOF &&
		=== Files by sha and associated pathnames in reverse size ===
		Format: sha, unpacked size, packed size, filename(s) object stored as
		  a89c82a2d4b713a125a4323d25adda062cc0013d         44         $((48+${zlibng})) numbers/medium.num
		  c58ae2ffaf8352bd9860bf4bbb6ea78238dca846         35         41 fickle
		  ccff62141ec7bae42e01a3dcb7615b38aa9fa5b3         24         40 fickle
		  f00c965d8307308469e537302baa73048488f162         21         37 numbers/small.num
		  2aa69a2a708eed00cb390e30f6bcc3eed773f390         20         36 whatever
		  51b95456de9274c9a95f756742808dfd480b9b35         13         29 [capricious, fickle, mercurial]
		  732c85a1b3d7ce40ec8f78fd9ffea32e9f45fae0          5         20 [sequence/know, words/know]
		  34b6a0c9d02cb6ef7f409f248c0c1224ce9dd373          5         20 [sequence/to, words/to]
		  7ecb56eb3fa3fa6f19dd48bca9f971950b119ede          3         18 words/know
		EOF
		test_cmp expect blob-shas-and-paths.txt &&

		cat >expect <<-EOF &&
		=== All directories by reverse size ===
		Format: unpacked size, packed size, date deleted, directory name
		         206        $((387+${zlibng})) <present>  <toplevel>
		          65         $((85+${zlibng})) 2005-04-07 numbers
		          13         58 <present>  words
		          10         40 <present>  sequence
		EOF
		test_cmp expect directories-all-sizes.txt &&

		cat >expect <<-EOF &&
		=== Deleted directories by reverse size ===
		Format: unpacked size, packed size, date deleted, directory name
		          65         $((85+${zlibng})) 2005-04-07 numbers
		EOF
		test_cmp expect directories-deleted-sizes.txt &&

		cat >expect <<-EOF &&
		=== All extensions by reverse size ===
		Format: unpacked size, packed size, date deleted, extension name
		         141        302 <present>  <no extension>
		          65         $((85+${zlibng})) 2005-04-07 .num
		EOF
		test_cmp expect extensions-all-sizes.txt &&

		cat >expect <<-EOF &&
		=== Deleted extensions by reverse size ===
		Format: unpacked size, packed size, date deleted, extension name
		          65         $((85+${zlibng})) 2005-04-07 .num
		EOF
		test_cmp expect extensions-deleted-sizes.txt &&

		cat >expect <<-EOF &&
		=== All paths by reverse accumulated size ===
		Format: unpacked size, packed size, date deleted, path name
		          72        110 <present>  fickle
		          44         $((48+${zlibng})) 2005-04-07 numbers/medium.num
		           8         38 <present>  words/know
		          21         37 2005-04-07 numbers/small.num
		          20         36 <present>  whatever
		          13         29 <present>  mercurial
		          13         29 <present>  capricious
		           5         20 <present>  words/to
		           5         20 <present>  sequence/to
		           5         20 <present>  sequence/know
		EOF
		test_cmp expect path-all-sizes.txt &&

		cat >expect <<-EOF &&
		=== Deleted paths by reverse accumulated size ===
		Format: unpacked size, packed size, date deleted, path name(s)
		          44         $((48+${zlibng})) 2005-04-07 numbers/medium.num
		          21         37 2005-04-07 numbers/small.num
		EOF
		test_cmp expect path-deleted-sizes.txt
	)
'

test_expect_success C_LOCALE_OUTPUT '--analyze --report-dir' '
	setup_analyze_me &&
	(
		cd analyze_me &&

		rm -rf .git/filter-repo &&
		git filter-repo --analyze --report-dir foobar &&

		# It should not work again without a --force
		test_must_fail git filter-repo --analyze --report-dir foobar &&

		# With a --force, though, it should overwrite
		git filter-repo --analyze --report-dir foobar --force &&

		test ! -d .git/filter-repo/analysis &&
		test -d foobar &&

		cd foobar &&

		# Very simple tests because already tested above.
		test_path_is_file renames.txt &&
		test_path_is_file README &&
		test_path_is_file blob-shas-and-paths.txt &&
		test_path_is_file directories-all-sizes.txt &&
		test_path_is_file directories-deleted-sizes.txt &&
		test_path_is_file extensions-all-sizes.txt &&
		test_path_is_file extensions-deleted-sizes.txt &&
		test_path_is_file path-all-sizes.txt &&
		test_path_is_file path-deleted-sizes.txt
	)
'

test_expect_success '--replace-text all options' '
	setup_analyze_me &&
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

test_expect_success '--replace-text binary zero_byte-0_char' '
	(
		set -e
		set -u
		REPO=replace-text-detect-binary
		FILE=mangle.bin
		OLD_STR=replace-from
		NEW_STR=replace-with
		# used with printf, contains a zero byte and a "0" character, binary
		OLD_CONTENT_FORMAT="${OLD_STR}\\0${OLD_STR}\\n0\\n"
		# expect content unchanged due to binary
		NEW_CONTENT_FORMAT="${OLD_CONTENT_FORMAT}"

		rm -rf "${REPO}"
		git init "${REPO}"
		cd "${REPO}"
		echo "${OLD_STR}==>${NEW_STR}" >../replace-rules
		printf "${NEW_CONTENT_FORMAT}" > ../expect
		printf "${OLD_CONTENT_FORMAT}" > "${FILE}"
		git add "${FILE}"
		git commit -m 'test'
		git filter-repo --force --replace-text ../replace-rules

		test_cmp ../expect "${FILE}"
	)
'

test_expect_success '--replace-text binary zero_byte-no_0_char' '
	(
		set -e
		set -u
		REPO=replace-text-detect-binary
		FILE=mangle.bin
		OLD_STR=replace-from
		NEW_STR=replace-with
		# used with printf, contains a zero byte but no "0" character, binary
		OLD_CONTENT_FORMAT="${OLD_STR}\\0${OLD_STR}\\n"
		# expect content unchanged due to binary
		NEW_CONTENT_FORMAT="${OLD_CONTENT_FORMAT}"

		rm -rf "${REPO}"
		git init "${REPO}"
		cd "${REPO}"
		echo "${OLD_STR}==>${NEW_STR}" >../replace-rules
		printf "${NEW_CONTENT_FORMAT}" > ../expect
		printf "${OLD_CONTENT_FORMAT}" > "${FILE}"
		git add "${FILE}"
		git commit -m 'test'
		git filter-repo --force --replace-text ../replace-rules

		test_cmp ../expect "${FILE}"
	)
'

test_expect_success '--replace-text text-file no_zero_byte-zero_char' '
	(
		set -e
		set -u
		REPO=replace-text-detect-binary
		FILE=mangle.bin
		OLD_STR=replace-from
		NEW_STR=replace-with
		# used with printf, contains no zero byte but contains a "0" character, text
		OLD_CONTENT_FORMAT="${OLD_STR}0\\n0${OLD_STR}\\n0\\n"
		# expect content changed due to text
		NEW_CONTENT_FORMAT="${NEW_STR}0\\n0${NEW_STR}\\n0\\n"

		rm -rf "${REPO}"
		git init "${REPO}"
		cd "${REPO}"
		echo "${OLD_STR}==>${NEW_STR}" >../replace-rules
		printf "${NEW_CONTENT_FORMAT}" > ../expect
		printf "${OLD_CONTENT_FORMAT}" > "${FILE}"
		git add "${FILE}"
		git commit -m 'test'
		git filter-repo --force --replace-text ../replace-rules

		test_cmp ../expect "${FILE}"
	)
'

test_expect_success '--strip-blobs-bigger-than' '
	setup_analyze_me &&
	(
		git clone file://"$(pwd)"/analyze_me strip_big_blobs &&
		cd strip_big_blobs &&

		# Verify certain files are present initially
		git log --format=%n --name-only | sort | uniq >../filenames &&
		test_line_count = 11 ../filenames &&
		git rev-parse HEAD~7:numbers/medium.num &&
		git rev-parse HEAD~7:numbers/small.num &&
		git rev-parse HEAD~4:mercurial &&
		test -f mercurial &&

		# Make one of the current files be "really big"
		test_seq 1 1000 >mercurial &&
		git add mercurial &&
		git commit --amend &&

		# Strip "really big" files
		git filter-repo --force --strip-blobs-bigger-than 3K --prune-empty never &&

		git log --format=%n --name-only | sort | uniq >../filenames &&
		test_line_count = 11 ../filenames &&
		# The "mercurial" file should still be around...
		git rev-parse HEAD~4:mercurial &&
		git rev-parse HEAD:mercurial &&
		# ...but only with its old, smaller contents
		test_line_count = 1 mercurial &&

		# Strip files that are too big, verify they are gone
		git filter-repo --strip-blobs-bigger-than 40 &&

		git log --format=%n --name-only | sort | uniq >../filenames &&
		test_line_count = 10 ../filenames &&
		test_must_fail git rev-parse HEAD~7:numbers/medium.num &&

		# Do it again, this time with --replace-text since that means
		# we are operating without --no-data and have to go through
		# a different codepath.  (The search/replace terms are bogus)
		cat >../replace-rules <<-\EOF &&
		not found==>was found
		EOF
		git filter-repo --strip-blobs-bigger-than 20 --replace-text ../replace-rules &&

		git log --format=%n --name-only | sort | uniq >../filenames &&
		test_line_count = 9 ../filenames &&
		test_must_fail git rev-parse HEAD~7:numbers/medium.num &&
		test_must_fail git rev-parse HEAD~7:numbers/small.num &&

		# Remove the temporary auxiliary files
		rm ../replace-rules &&
		rm ../filenames
	)
'

test_expect_success '--strip-blobs-with-ids' '
	setup_analyze_me &&
	(
		git clone file://"$(pwd)"/analyze_me strip_blobs_with_ids &&
		cd strip_blobs_with_ids &&

		# Verify certain files are present initially
		git log --format=%n --name-only | sort | uniq >../filenames &&
		test_line_count = 11 ../filenames &&
		grep fake_submodule ../filenames &&

		# Strip "a certain file" files
		echo deadbeefdeadbeefdeadbeefdeadbeefdeadbeef >../input &&
		git filter-repo --strip-blobs-with-ids ../input &&

		git log --format=%n --name-only | sort | uniq >../filenames &&
		test_line_count = 10 ../filenames &&
		# Make sure fake_submodule was removed
		! grep fake_submodule ../filenames &&

		# Do it again, this time with --replace-text since that means
		# we are operating without --no-data and have to go through
		# a different codepath.  (The search/replace terms are bogus)
		cat >../bad-ids <<-\EOF &&
		34b6a0c9d02cb6ef7f409f248c0c1224ce9dd373
		51b95456de9274c9a95f756742808dfd480b9b35
		EOF
		cat >../replace-rules <<-\EOF &&
		not found==>was found
		EOF
		git filter-repo --strip-blobs-with-ids ../bad-ids --replace-text ../replace-rules &&

		git log --format=%n --name-only | sort | uniq >../filenames &&
		test_line_count = 6 ../filenames &&
		! grep sequence/to ../filenames &&
		! grep words/to ../filenames &&
		! grep capricious ../filenames &&
		! grep fickle ../filenames &&
		! grep mercurial ../filenames &&

		# Remove the temporary auxiliary files
		rm ../bad-ids &&
		rm ../replace-rules &&
		rm ../filenames
	)
'

test_expect_success 'startup sanity checks' '
	setup_analyze_me &&
	(
		git clone file://"$(pwd)"/analyze_me startup_sanity_checks &&
		cd startup_sanity_checks &&

		echo foobar | git hash-object -w --stdin &&
		git count-objects -v &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "expected freshly packed repo" ../err &&
		git prune &&

		git remote add another_remote /dev/null &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "expected one remote, origin" ../err &&
		git remote rm another_remote &&

		git remote rename origin another_remote &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "expected one remote, origin" ../err &&
		git remote rename another_remote origin &&

		cd words &&
		test_must_fail git filter-repo --path numbers 2>../../err &&
		test_i18ngrep "GIT_DIR must be .git" ../../err &&
		rm ../../err &&
		cd .. &&

		git config core.bare true &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "GIT_DIR must be ." ../err &&
		git config core.bare false &&

		git update-ref -m "Just Testing" refs/heads/master HEAD &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "expected at most one entry in the reflog" ../err &&
		git reflog expire --expire=now &&

		echo yes >>words/know &&
		git stash save random change &&
		rm -rf .git/logs/ &&
		git gc &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "has stashed changes" ../err &&
		git update-ref -d refs/stash &&

		echo yes >>words/know &&
		git add words/know &&
		git gc --prune=now &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "you have uncommitted changes" ../err &&
		git checkout HEAD words/know &&

		echo yes >>words/know &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "you have unstaged changes" ../err &&
		git checkout -- words/know &&

		>untracked &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "you have untracked changes" ../err &&
		rm ../err &&
		rm untracked &&

		git worktree add ../other-worktree HEAD &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "you have multiple worktrees" ../err &&
		rm -rf ../err &&
		git worktree remove ../other-worktree &&

		git update-ref -d refs/remotes/origin/master &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "refs/heads/master exists, but refs/remotes/origin/master not found" ../err &&
		git update-ref -m restoring refs/remotes/origin/master refs/heads/master &&
		rm ../err &&

		rm .git/logs/refs/remotes/origin/master &&
		git update-ref -m funsies refs/remotes/origin/master refs/heads/master~1 &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "refs/heads/master does not match refs/remotes/origin/master" ../err &&
		rm ../err &&

		cd ../ &&
		git -C analyze_me gc &&
		echo foobar | git -C analyze_me hash-object -w --stdin &&
		git clone analyze_me startup_sanity_checks2 &&
		cd startup_sanity_checks2 &&

		echo foobar | git hash-object -w --stdin &&
		test_must_fail git filter-repo --path numbers 2>../err &&
		test_i18ngrep "expected freshly packed repo" ../err &&
		test_i18ngrep "when cloning local repositories" ../err &&
		rm ../err &&

		cd ../startup_sanity_checks &&
		git config core.ignoreCase true &&
		rev=$(git rev-parse refs/remotes/origin/other) &&
		echo "$rev refs/remotes/origin/zcase" >>.git/packed-refs &&
		echo "$rev refs/remotes/origin/zCASE" >>.git/packed-refs &&
		test_must_fail git filter-repo --path numbers 2>../err
		test_i18ngrep "Cannot rewrite history on a case insensitive" ../err &&
		git update-ref -d refs/remotes/origin/zCASE &&
		git config --unset core.ignoreCase &&

		git config core.precomposeUnicode true &&
		rev=$(git rev-parse refs/heads/master) &&
		echo "$rev refs/remotes/origin/zlamé" >>.git/packed-refs &&
		echo "$rev refs/remotes/origin/zlamé" >>.git/packed-refs &&
		test_must_fail git filter-repo --path numbers 2>../err
		test_i18ngrep "Cannot rewrite history on a character normalizing" ../err &&
		git update-ref -d refs/remotes/origin/zlamé &&
		git config --unset core.precomposeUnicode &&
		cd ..
	)
'

test_expect_success 'other startup error cases and requests for help' '
	(
		# prevent MSYS2 (Git for Windows) from converting the colon to
		# a semicolon when encountering parameters that look like
		# Unix-style, colon-separated path lists (such as `foo:.`)
		MSYS_NO_PATHCONV=1 &&
		export MSYS_NO_PATHCONV

		git init startup_errors &&
		cd startup_errors &&

		git filter-repo -h >out &&
		test_i18ngrep "filter-repo destructively rewrites history" out &&

		test_must_fail git filter-repo 2>err &&
		test_i18ngrep "No arguments specified." err &&

		test_must_fail git filter-repo --analyze 2>err &&
		test_i18ngrep "Nothing to analyze; repository is empty" err &&

		(
			GIT_CEILING_DIRECTORIES=$(pwd) &&
			export GIT_CEILING_DIRECTORIES &&
			mkdir not_a_repo &&
			cd not_a_repo &&
			test_must_fail git filter-repo --dry-run 2>err &&
			test_i18ngrep "returned non-zero exit status" err &&
			rm err &&
			cd .. &&
			rmdir not_a_repo
		) &&

		test_must_fail git filter-repo --analyze --path foobar 2>err &&
		test_i18ngrep ": --analyze is incompatible with --path" err &&

		test_must_fail git filter-repo --analyze --stdin 2>err &&
		test_i18ngrep ": --analyze is incompatible with --stdin" err &&

		test_must_fail git filter-repo --path-rename foo:bar --use-base-name 2>err &&
		test_i18ngrep ": --use-base-name and --path-rename are incompatible" err &&

		test_must_fail git filter-repo --file-info-callback "None" --stdin 2>err &&
		test_i18ngrep ": --file-info-callback is incompatible with" err &&

		test_must_fail git filter-repo --file-info-callback "None" --blob-callback "None" 2>err &&
		test_i18ngrep ": --file-info-callback is incompatible with" err &&

		test_must_fail git filter-repo --file-info-callback "None" --filename-callback "None" 2>err &&
		test_i18ngrep ": --file-info-callback is incompatible with" err &&

		test_must_fail git filter-repo --path-rename foo:bar/ 2>err &&
		test_i18ngrep "either ends with a slash then both must." err &&

		echo "foo==>bar/" >input &&
		test_must_fail git filter-repo --paths-from-file input 2>err &&
		test_i18ngrep "either ends with a slash then both must." err &&

		echo "glob:*.py==>newname" >input &&
		test_must_fail git filter-repo --paths-from-file input 2>err &&
		test_i18ngrep "renaming globs makes no sense" err &&

		test_must_fail git filter-repo --strip-blobs-bigger-than 3GiB 2>err &&
		test_i18ngrep "could not parse.*3GiB" err &&

		test_must_fail git filter-repo --path-rename foo/bar:. 2>err &&
		test_i18ngrep "Invalid path component .\.. found in .foo/bar:\." err &&

		test_must_fail git filter-repo --path /foo/bar 2>err &&
		test_i18ngrep "Pathnames cannot begin with a ./" err &&

		test_must_fail git filter-repo --path-rename foo:/bar 2>err &&
		test_i18ngrep "Pathnames cannot begin with a ./" err &&

		test_must_fail git filter-repo --path-rename /foo:bar 2>err &&
		test_i18ngrep "Pathnames cannot begin with a ./" err &&

		test_must_fail git filter-repo --path-rename foo 2>err &&
		test_i18ngrep "Error: --path-rename expects one colon in its argument" err &&

		test_must_fail git filter-repo --subdirectory-filter /foo 2>err &&
		test_i18ngrep "Pathnames cannot begin with a ./" err &&

		test_must_fail git filter-repo --subdirectory-filter /foo 2>err &&
		test_i18ngrep "Pathnames cannot begin with a ./" err
	)
'

test_expect_success 'invalid fast-import directives' '
	(
		git init invalid_directives &&
		cd invalid_directives &&

		echo "get-mark :15" | \
			test_must_fail git filter-repo --stdin --force 2>err &&
		test_i18ngrep "Unsupported command" err &&

		echo "invalid-directive" | \
			test_must_fail git filter-repo --stdin --force 2>err &&
		test_i18ngrep "Could not parse line" err
	)
'

test_expect_success 'mailmap sanity checks' '
	setup_analyze_me &&
	(
		git clone file://"$(pwd)"/analyze_me mailmap_sanity_checks &&
		cd mailmap_sanity_checks &&

		fake=$(pwd)/fake &&
		test_must_fail git filter-repo --mailmap "$fake"/path 2>../err &&
		test_i18ngrep "Cannot read $fake/path" ../err &&

		echo "Total Bogus" >../whoopsies &&
		test_must_fail git filter-repo --mailmap ../whoopsies 2>../err &&
		test_i18ngrep "Unparseable mailmap file" ../err &&
		rm ../err &&
		rm ../whoopsies &&

		echo "Me <me@site.com> Myself <yo@email.com> Extraneous" >../whoopsies &&
		test_must_fail git filter-repo --mailmap ../whoopsies 2>../err &&
		test_i18ngrep "Unparseable mailmap file" ../err &&
		rm ../err &&
		rm ../whoopsies
	)
'

test_expect_success 'incremental import' '
	setup_analyze_me &&
	(
		git clone file://"$(pwd)"/analyze_me incremental &&
		cd incremental &&

		original=$(git rev-parse master) &&
		git fast-export --reference-excluded-parents master~2..master \
			| git filter-repo --stdin --refname-callback "return b\"develop\"" &&
		test "$(git rev-parse develop)" = "$original"
	)
'

test_expect_success '--target' '
	setup_analyze_me &&
	git init target &&
	(
		cd target &&
		git checkout -b other &&
		echo hello >world &&
		git add world &&
		git commit -m init &&
		git checkout -b unique
	) &&
	git -C target rev-parse unique >target/expect &&
	git filter-repo --source analyze_me --target target --path fake_submodule --force --debug &&
	test 2 = $(git -C target rev-list --count master) &&
	test_must_fail git -C target rev-parse other &&
	git -C target rev-parse unique >target/actual &&
	test_cmp target/expect target/actual
'

test_expect_success '--date-order' '
	test_create_repo date_order &&
	(
		cd date_order &&
		git fast-import --quiet <$DATA/date-order &&
		# First, verify that without date-order, C is before B
		cat <<-EOF >expect-normal &&
		Initial
		A
		C
		B
		D
		merge
		EOF
		git filter-repo --force --message-callback "
			with open(\"messages.txt\", \"ab\") as f:
				f.write(message)
			return message
			" &&
		test_cmp expect-normal messages.txt &&

		# Next, verify that with date-order, C and B are reversed
		rm messages.txt &&
		cat <<-EOF >expect &&
		Initial
		A
		B
		C
		D
		merge
		EOF
		git filter-repo --date-order --force --message-callback "
			with open(\"messages.txt\", \"ab\") as f:
				f.write(message)
			return message
			" &&
		test_cmp expect messages.txt
	)
'

test_expect_success '--refs' '
	setup_analyze_me &&
	git init refs &&
	(
		cd refs &&
		git checkout -b other &&
		echo hello >world &&
		git add world &&
		git commit -m init
	) &&
	git -C refs rev-parse other >refs/expect &&
	git -C analyze_me rev-parse master >refs/expect &&
	git filter-repo --source analyze_me --target refs --refs master --force &&
	git -C refs rev-parse other >refs/actual &&
	git -C refs rev-parse master >refs/actual &&
	test_cmp refs/expect refs/actual
'

test_done
