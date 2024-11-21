#!/bin/bash

test_description='Basic filter-repo tests'

. ./test-lib.sh

export PATH=$(dirname $TEST_DIRECTORY):$PATH  # Put git-filter-repo in PATH

DATA="$TEST_DIRECTORY/t9390"
SQ="'"

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
		rm -rf .git/filter-repo/ &&

		# Run the example
		cat $DATA/$INPUT | git filter-repo --stdin --quiet --force --replace-refs delete-no-add "${REST[@]}" &&

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
filter_testcase basic basic-message  --replace-message ../t9390/sample-message
filter_testcase empty empty-keepme   --path keepme
filter_testcase empty more-empty-keepme --path keepme --prune-empty=always \
		                                   --prune-degenerate=always
filter_testcase empty less-empty-keepme --path keepme --prune-empty=never \
		                                   --prune-degenerate=never
filter_testcase degenerate degenerate-keepme   --path moduleA/keepme
filter_testcase degenerate degenerate-moduleA  --path moduleA
filter_testcase degenerate degenerate-globme   --path-glob *me
filter_testcase degenerate degenerate-keepme-noff --path moduleA/keepme --no-ff
filter_testcase unusual unusual-filtered --path ''
filter_testcase unusual unusual-mailmap  --mailmap ../t9390/sample-mailmap

setup_path_rename() {
	test -d path_rename && return
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
}

test_expect_success '--path-rename sequences/tiny:sequences/small' '
	setup_path_rename &&
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
	setup_path_rename &&
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
	setup_path_rename &&
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
	setup_path_rename &&
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
	setup_path_rename &&
	(
		git clone file://"$(pwd)"/path_rename path_rename_bad_squash &&
		cd path_rename_bad_squash &&
		test_must_fail git filter-repo \
			--path-rename values/large:values/big \
			--path-rename values/huge:values/big 2>../err &&
		test_i18ngrep "File renaming caused colliding pathnames" ../err
	)
'

test_expect_success '--paths-from-file' '
	setup_path_rename &&
	(
		git clone file://"$(pwd)"/path_rename paths_from_file &&
		cd paths_from_file &&

		cat >../path_changes <<-EOF &&
		literal:values/huge
		values/huge==>values/gargantuan
		glob:*rge

		# Comments and blank lines are ignored
		regex:.*med.*
		regex:^([^/]*)/(.*)ge$==>\2/\1/ge
		EOF

		git filter-repo --paths-from-file ../path_changes &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		# intermediate, medium, two larges, gargantuan, and a blank line
		test_line_count = 6 filenames &&
		! grep sequences/tiny filenames &&
		grep sequences/intermediate filenames &&
		grep lar/sequences/ge filenames &&
		grep lar/values/ge filenames &&
		grep values/gargantuan filenames &&
		! grep sequences/small filenames &&
		grep sequences/medium filenames &&

		rm ../path_changes
	)
'

test_expect_success '--paths does not mean --paths-from-file' '
	setup_path_rename &&
	(
		git clone file://"$(pwd)"/path_rename paths_misuse &&
		cd paths_misuse &&

		test_must_fail git filter-repo --paths values/large 2>../err &&

		grep "Error: Option.*--paths.*unrecognized; did you" ../err &&
		rm ../err
	)
'

create_path_filtering_and_renaming() {
	test -d path_filtering_and_renaming && return

	test_create_repo path_filtering_and_renaming &&
	(
		cd path_filtering_and_renaming &&

		>.gitignore &&
		mkdir -p src/main/java/com/org/{foo,bar} &&
		mkdir -p src/main/resources &&
		test_seq  1 10 >src/main/java/com/org/foo/uptoten &&
		test_seq 11 20 >src/main/java/com/org/bar/uptotwenty &&
		test_seq  1  7 >src/main/java/com/org/uptoseven &&
		test_seq  1  5 >src/main/resources/uptofive &&
		git add . &&
		git commit -m Initial
	)
}

test_expect_success 'Mixing filtering and renaming paths, not enough filters' '
	create_path_filtering_and_renaming &&
	git clone --no-local path_filtering_and_renaming \
			     path_filtering_and_renaming_1 &&
	(
		cd path_filtering_and_renaming_1 &&

		git filter-repo --path .gitignore \
				--path src/main/resources \
				--path-rename src/main/java/com/org/foo/:src/main/java/com/org/ &&

		cat <<-EOF >expect &&
		.gitignore
		src/main/resources/uptofive
		EOF
		git ls-files >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'Mixing filtering and renaming paths, enough filters' '
	create_path_filtering_and_renaming &&
	git clone --no-local path_filtering_and_renaming \
			     path_filtering_and_renaming_2 &&
	(
		cd path_filtering_and_renaming_2 &&

		git filter-repo --path .gitignore \
				--path src/main/resources \
				--path src/main/java/com/org/foo/ \
				--path-rename src/main/java/com/org/foo/:src/main/java/com/org/ &&

		cat <<-EOF >expect &&
		.gitignore
		src/main/java/com/org/uptoten
		src/main/resources/uptofive
		EOF
		git ls-files >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'Mixing filtering and to-subdirectory-filter' '
	create_path_filtering_and_renaming &&
	git clone --no-local path_filtering_and_renaming \
			     path_filtering_and_renaming_3 &&
	(
		cd path_filtering_and_renaming_3 &&

		git filter-repo --path src/main/resources \
				--to-subdirectory-filter my-module &&

		cat <<-EOF >expect &&
		my-module/src/main/resources/uptofive
		EOF
		git ls-files >actual &&
		test_cmp expect actual
	)
'

setup_commit_message_rewriting() {
	test -d commit_msg && return
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
}

test_expect_success 'commit message rewrite' '
	setup_commit_message_rewriting &&
	(
		git clone file://"$(pwd)"/commit_msg commit_msg_clone &&
		cd commit_msg_clone &&

		git filter-repo --invert-paths --path bar &&

		git log --oneline >changes &&
		test_line_count = 204 changes &&

		# If a commit we reference is rewritten, we expect the
		# reference to be rewritten.
		name=$(git rev-parse HEAD~203) &&
		echo "Commit referencing ${name:0:8}" >expect &&
		git log --no-walk --format=%s HEAD~202 >actual &&
		test_cmp expect actual &&

		# If a commit we reference was pruned, then the reference
		# has nothing to be rewritten to.  Verify that the commit
		# ID it points to does not exist.
		latest=$(git log --no-walk | grep reverts | awk "{print \$4}" | tr -d '.') &&
		test -n "$latest" &&
		test_must_fail git cat-file -e "$latest"
	)
'

test_expect_success 'commit hash unchanged if requested' '
	setup_commit_message_rewriting &&
	(
		git clone file://"$(pwd)"/commit_msg commit_msg_clone_2 &&
		cd commit_msg_clone_2 &&

		name=$(git rev-parse HEAD~204) &&
		git filter-repo --invert-paths --path bar --preserve-commit-hashes &&

		git log --oneline >changes &&
		test_line_count = 204 changes &&

		echo "Commit referencing ${name:0:8}" >expect &&
		git log --no-walk --format=%s HEAD~202 >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'commit message encoding preserved if requested' '
	(
		git init commit_message_encoding &&
		cd commit_message_encoding &&

		cat >input <<-\EOF &&
		feature done
		commit refs/heads/develop
		mark :1
		original-oid deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
		author Just Me <just@here.org> 1234567890 -0200
		committer Just Me <just@here.org> 1234567890 -0200
		encoding iso-8859-7
		data 5
		EOF

		printf "Pi: \360\n\ndone\n" >>input &&

		cat input | git fast-import --quiet &&
		git rev-parse develop >expect &&

		git filter-repo --preserve-commit-encoding --force &&
		git rev-parse develop >actual &&
		test_cmp expect actual
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

test_expect_success '--refs and --replace-text' '
	# This test exists to make sure we do not assume that parents in
	# filter-repo code are always represented by integers (or marks);
	# they sometimes are represented as hashes.
	setup_path_rename &&
	(
		git clone file://"$(pwd)"/path_rename refs_and_replace_text &&
		cd refs_and_replace_text &&
		git rev-parse --short=10 HEAD~1 >myparent &&
		echo "10==>TEN" >input &&
		git filter-repo --force --replace-text input --refs $(cat myparent)..master &&
		cat <<-EOF >expect &&
		TEN11
		EOF
		test_cmp expect sequences/medium &&
		git rev-list --count HEAD >actual &&
		echo 4 >expect &&
		test_cmp expect actual &&
		git rev-parse --short=10 HEAD~1 >actual &&
		test_cmp myparent actual
	)
'

test_expect_success 'reset to specific refs' '
	test_create_repo reset_to_specific_refs &&
	(
		cd reset_to_specific_refs &&

		git commit --allow-empty -m initial &&
		INITIAL=$(git rev-parse HEAD) &&
		echo "$INITIAL refs/heads/develop" >expect &&

		cat >input <<-INPUT_END &&
		reset refs/heads/develop
		from $INITIAL

		reset refs/heads/master
		from 0000000000000000000000000000000000000000
		INPUT_END

		cat input | git filter-repo --force --stdin &&
		git show-ref >actual &&
		test_cmp expect actual
	)
'

setup_handle_funny_characters() {
	test -d funny_chars && return
	test_create_repo funny_chars &&
	(
		cd funny_chars &&

		git symbolic-ref HEAD refs/heads/españa &&

		printf "بتتكلم بالهندي؟\n" >señor &&
		printf "Αυτά μου φαίνονται αλαμπουρνέζικα.\n" >>señor &&
		printf "זה סינית בשבילי\n" >>señor &&
		printf "ちんぷんかんぷん\n" >>señor &&
		printf "За мене тоа е шпанско село\n" >>señor &&
		printf "看起来像天书。\n" >>señor &&
		printf "انگار ژاپنی حرف می زنه\n" >>señor &&
		printf "Это для меня китайская грамота.\n" >>señor &&
		printf "To mi je španska vas\n" >>señor &&
		printf "Konuya Fransız kaldım\n" >>señor &&
		printf "עס איז די שפּראַך פון גיבבעריש\n" >>señor &&
		printf "Not even UTF-8:\xe0\x80\x80\x00\n" >>señor &&

		cp señor señora &&
		cp señor señorita &&
		git add . &&

		export GIT_AUTHOR_NAME="Nguyễn Arnfjörð Gábor" &&
		export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME &&
		export GIT_AUTHOR_EMAIL="emails@are.ascii" &&
		export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL" &&
		git commit -m "€$£₽₪" &&

		git tag -a -m "₪₽£€$" סְפָרַד
	)
}

test_expect_success 'handle funny characters' '
	setup_handle_funny_characters &&
	(
		git clone file://"$(pwd)"/funny_chars funny_chars_checks &&
		cd funny_chars_checks &&

		file_sha=$(git rev-parse :0:señor) &&
		former_head_sha=$(git rev-parse HEAD) &&
		git filter-repo --replace-refs old-default --to-subdirectory-filter títulos &&

		cat <<-EOF >expect &&
		100644 $file_sha 0	"t\303\255tulos/se\303\261or"
		100644 $file_sha 0	"t\303\255tulos/se\303\261ora"
		100644 $file_sha 0	"t\303\255tulos/se\303\261orita"
		EOF

		git ls-files -s >actual &&
		test_cmp expect actual &&

		commit_sha=$(git rev-parse HEAD) &&
		tag_sha=$(git rev-parse סְפָרַד) &&
		cat <<-EOF >expect &&
		$commit_sha refs/heads/españa
		$commit_sha refs/replace/$former_head_sha
		$tag_sha refs/tags/סְפָרַד
		EOF

		git show-ref >actual &&
		test_cmp expect actual &&

		echo "€$£₽₪" >expect &&
		git cat-file -p HEAD | tail -n 1 >actual &&

		echo "₪₽£€$" >expect &&
		git cat-file -p סְפָרַד | tail -n 1 >actual
        )
'

test_expect_success '--state-branch with changing renames' '
	test_create_repo state_branch_renames_export
	test_create_repo state_branch_renames &&
	(
		cd state_branch_renames &&
		git fast-import --quiet <$DATA/basic-numbers &&
		git branch -d A &&
		git branch -d B &&
		git tag -d v1.0 &&

		ORIG=$(git rev-parse master) &&
		git reset --hard master~1 &&
		git filter-repo --path-rename ten:zehn \
                                --state-branch state_info \
                                --target ../state_branch_renames_export &&

		cd ../state_branch_renames_export &&
		git log --format=%s --name-status >actual &&
		cat <<-EOF >expect &&
			Merge branch ${SQ}A${SQ} into B
			add twenty

			M	twenty
			add ten

			M	zehn
			Initial

			A	twenty
			A	zehn
			EOF
		test_cmp expect actual &&

		cd ../state_branch_renames &&

		git reset --hard $ORIG &&
		git filter-repo --path-rename twenty:veinte \
                                --state-branch state_info \
                                --target ../state_branch_renames_export &&

		cd ../state_branch_renames_export &&
		git log --format=%s --name-status >actual &&
		cat <<-EOF >expect &&
			whatever

			A	ten
			A	veinte
			Merge branch ${SQ}A${SQ} into B
			add twenty

			M	twenty
			add ten

			M	zehn
			Initial

			A	twenty
			A	zehn
			EOF
		test_cmp expect actual
	)
'

test_expect_success '--state-branch with expanding paths and refs' '
	test_create_repo state_branch_more_paths_export
	test_create_repo state_branch_more_paths &&
	(
		cd state_branch_more_paths &&
		git fast-import --quiet <$DATA/basic-numbers &&

		git reset --hard master~1 &&
		git filter-repo --path ten --state-branch state_info \
                                --target ../state_branch_more_paths_export \
                                --refs master &&

		cd ../state_branch_more_paths_export &&
		echo 2 >expect &&
		git rev-list --count master >actual &&
		test_cmp expect actual &&
		test_must_fail git rev-parse master~1:twenty &&
		test_must_fail git rev-parse master:twenty &&

		cd ../state_branch_more_paths &&

		git reset --hard v1.0 &&
		git filter-repo --path ten --path twenty \
                                --state-branch state_info \
                                --target ../state_branch_more_paths_export &&

		cd ../state_branch_more_paths_export &&
		echo 3 >expect &&
		git rev-list --count master >actual &&
		test_cmp expect actual &&
		test_must_fail git rev-parse master~2:twenty &&
		git rev-parse master:twenty
	)
'

test_expect_success FUNNYNAMES 'degenerate merge with non-matching filenames' '
	test_create_repo degenerate_merge_differing_filenames &&
	(
		cd degenerate_merge_differing_filenames &&

		touch "foo \"quote\" bar" &&
		git add "foo \"quote\" bar" &&
		git commit -m "Add foo \"quote\" bar"
		git branch A &&

		git checkout --orphan B &&
		git reset --hard &&
		mkdir -p pkg/list &&
		test_commit pkg/list/whatever &&
		test_commit unwanted_file &&

		git checkout A &&
		git merge --allow-unrelated-histories --no-commit B &&
		>pkg/list/wanted &&
		git add pkg/list/wanted &&
		git rm -f pkg/list/whatever.t &&
		git commit &&

		git filter-repo --force --path pkg/list &&
		! test_path_is_file pkg/list/whatever.t &&
		git ls-files >actual &&
		echo pkg/list/wanted >expect &&
		test_cmp expect actual
	)
'

test_expect_success 'degenerate merge with typechange' '
	test_create_repo degenerate_merge_with_typechange &&
	(
		cd degenerate_merge_with_typechange &&

		touch irrelevant_file &&
		git add irrelevant_file &&
		git commit -m "Irrelevant, unwanted file"
		git branch A &&

		git checkout --orphan B &&
		git reset --hard &&
		echo hello >world &&
		git add world &&
		git commit -m "greeting" &&
		echo goodbye >planet &&
		git add planet &&
		git commit -m "farewell" &&

		git checkout A &&
		git merge --allow-unrelated-histories --no-commit B &&
		rm world &&
		ln -s planet world &&
		git add world &&
		git commit &&

		git filter-repo --force --path world &&
		test_path_is_missing irrelevant_file &&
		test_path_is_missing planet &&
		echo world >expect &&
		git ls-files >actual &&
		test_cmp expect actual &&

		git log --oneline HEAD >input &&
		test_line_count = 2 input
	)
'

test_expect_success 'degenerate evil merge' '
	test_create_repo degenerate_evil_merge &&
	(
		cd degenerate_evil_merge &&

		cat $DATA/degenerate-evil-merge | git fast-import --quiet &&
		git filter-repo --force --subdirectory-filter module-of-interest &&
		test_path_is_missing module-of-interest &&
		test_path_is_missing other-module &&
		test_path_is_missing irrelevant &&
		test_path_is_file file1 &&
		test_path_is_file file2 &&
		test_path_is_file file3
	)
'

test_lazy_prereq IN_FILTER_REPO_CLONE '
	git -C ../../ rev-parse HEAD:git-filter-repo &&
	grep @@LOCALEDIR@@ ../../../git-filter-repo &&
	head -n 1 ../../../git-filter-repo | grep "/usr/bin/env python3$"
'

# Next test depends on git-filter-repo coming from the git-filter-repo
# not having been modified by e.g. normal installation.  Skip the test
# if we're in some kind of installation of filter-repo rather than in a
# simple clone of the original repository.
test_expect_success IN_FILTER_REPO_CLONE '--version' '
	git filter-repo --version >actual &&
	git hash-object ../../git-filter-repo | cut -c 1-12 >expect &&
	test_cmp expect actual
'

test_expect_success 'empty author ident' '
	test_create_repo empty_author_ident &&
	(
		cd empty_author_ident &&

		git init &&
		cat <<-EOF | git fast-import --quiet &&
			feature done
			blob
			mark :1
			data 8
			initial

			reset refs/heads/develop
			commit refs/heads/develop
			mark :2
			author <empty@ident.ity> 1535228562 -0700
			committer Full Name <email@add.ress> 1535228562 -0700
			data 8
			Initial
			M 100644 :1 filename

			done
			EOF

		git filter-repo --force --path-rename filename:stuff &&

		git log --format=%an develop >actual &&
		echo >expect &&
		test_cmp expect actual
	)
'

test_expect_success 'rewrite stash' '
	test_create_repo rewrite_stash &&
	(
		cd rewrite_stash &&

		git init &&
		test_write_lines 1 2 3 4 5 6 7 8 9 10 >numbers &&
		git add numbers &&
		git commit -qm initial &&

		echo 11 >>numbers &&
		git stash push -m "add eleven" &&
		echo foobar >>numbers &&
		git stash push -m "add foobar" &&

		git filter-repo --force --path-rename numbers:values &&

		git stash list >output &&
		test 2 -eq $(cat output | wc -l)
	)
'

test_expect_success 'rewrite stash and drop relevant entries' '
	test_create_repo rewrite_stash_drop_entries &&
	(
		cd rewrite_stash_drop_entries &&

		git init &&
		test_write_lines 1 2 3 4 5 6 7 8 9 10 >numbers &&
		git add numbers &&
		git commit -qm numbers &&

		echo 11 >>numbers &&
		git stash push -m "add eleven" &&

		test_write_lines a b c d e f g h i j >letters &&
		test_write_lines hello hi welcome >greetings &&
		git add letters greetings &&
		git commit -qm "letters and greetings" &&

		echo k >>letters &&
		git stash push -m "add k" &&
		echo hey >>greetings &&
		git stash push -m "add hey" &&
		echo 12 >>numbers &&
		git stash push -m "add twelve" &&

		test_line_count = 4 .git/logs/refs/stash &&

		git filter-repo --force --path letters --path greetings &&

		test_line_count = 3 .git/logs/refs/stash &&
		! grep add.eleven .git/logs/refs/stash &&
		grep add.k .git/logs/refs/stash &&
		grep add.hey .git/logs/refs/stash &&
		grep add.twelve .git/logs/refs/stash
	)
'

test_expect_success POSIXPERM 'failure to run cleanup' '
	test_create_repo fail_to_cleanup &&
	(
		cd fail_to_cleanup &&

		git init &&
		test_write_lines 1 2 3 4 5 6 7 8 9 10 >numbers &&
		git add numbers &&
		git commit -qm initial &&

		chmod u-w .git/logs &&
		test_must_fail git filter-repo --force \
		                       --path-rename numbers:values 2> ../err &&
		chmod u+w .git/logs &&
		grep fatal.*git.reflog.expire.*failed ../err
	)
'

test_expect_success 'origin refs without origin remote does not die' '
	test_create_repo origin_refs_with_origin_remote &&
	(
		cd origin_refs_with_origin_remote &&

		test_commit numbers &&
		git update-ref refs/remotes/origin/svnhead master &&

		git filter-repo --force --path-rename numbers.t:values.t &&

		git show svnhead:values.t >actual &&
		echo numbers >expect &&
		test_cmp expect actual
	)
'

test_done
