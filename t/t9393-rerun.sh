#!/bin/bash

test_description='filter-repo tests with reruns'

. ./test-lib.sh

export PATH=$(dirname $TEST_DIRECTORY):$PATH  # Put git-filter-repo in PATH

DATA="$TEST_DIRECTORY/t9393"
DELETED_SHA="0000000000000000000000000000000000000000" # FIXME: sha256 support

test_expect_success 'a re-run that is treated as a clean slate' '
	test_create_repo clean_slate_rerun &&
	(
		cd clean_slate_rerun &&
		git fast-import --quiet <$DATA/simple &&

		FIRST_ORPHAN=$(git rev-parse orphan-me~1) &&
		FINAL_ORPHAN=$(git rev-parse orphan-me) &&
		FILE_A_CHANGE=$(git rev-list -1 HEAD -- fileA) &&
		FILE_B_CHANGE=$(git rev-list -1 HEAD -- fileB) &&
		FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&
		FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		ORIGINAL_TAG=$(git rev-parse v1.0) &&

		git filter-repo --invert-paths --path fileB --force &&
		NEW_FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&
		NEW_FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		FINAL_TAG=$(git rev-parse v1.0) &&

		cat <<-EOF | sort >sha-expect &&
		${FIRST_ORPHAN} ${FIRST_ORPHAN}
		${FINAL_ORPHAN} ${FINAL_ORPHAN}
		${FILE_A_CHANGE} ${FILE_A_CHANGE}
		${FILE_B_CHANGE} ${DELETED_SHA}
		${FILE_C_CHANGE} ${NEW_FILE_C_CHANGE}
		${FILE_D_CHANGE} ${NEW_FILE_D_CHANGE}
		EOF
		printf "%-40s %s\n" old new >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/commit-map &&

		cat <<-EOF | sort -k 3 >sha-expect &&
		${FILE_D_CHANGE} ${NEW_FILE_D_CHANGE} $(git symbolic-ref HEAD)
		${FINAL_ORPHAN} ${FINAL_ORPHAN} refs/heads/orphan-me
		${ORIGINAL_TAG} ${FINAL_TAG} refs/tags/v1.0
		EOF
		printf "%-40s %-40s %s\n" old new ref >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/ref-map &&

		cat <<-EOF | sort >expect &&
		${FILE_B_CHANGE} ${FILE_A_CHANGE}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits &&

		touch -t 197001010000 .git/filter-repo/already_ran &&
		echo no | git filter-repo --invert-paths --path fileC --force &&
		FINAL_FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		REALLY_FINAL_TAG=$(git rev-parse v1.0) &&

		cat <<-EOF | sort >sha-expect &&
		${FIRST_ORPHAN} ${FIRST_ORPHAN}
		${FINAL_ORPHAN} ${FINAL_ORPHAN}
		${FILE_A_CHANGE} ${FILE_A_CHANGE}
		${NEW_FILE_C_CHANGE} ${DELETED_SHA}
		${NEW_FILE_D_CHANGE} ${FINAL_FILE_D_CHANGE}
		EOF
		printf "%-40s %s\n" old new >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/commit-map &&

		cat <<-EOF | sort -k 3 >sha-expect &&
		${NEW_FILE_D_CHANGE} ${FINAL_FILE_D_CHANGE} $(git symbolic-ref HEAD)
		${FINAL_ORPHAN} ${FINAL_ORPHAN} refs/heads/orphan-me
		${FINAL_TAG} ${REALLY_FINAL_TAG} refs/tags/v1.0
		EOF
		printf "%-40s %-40s %s\n" old new ref >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/ref-map &&

		cat <<-EOF | sort >expect &&
		${NEW_FILE_C_CHANGE} ${FILE_A_CHANGE}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits
	)
'

test_expect_success 'remove two files, no re-run' '
	test_create_repo simple_two_files &&
	(
		cd simple_two_files &&
		git fast-import --quiet <$DATA/simple &&

		FIRST_ORPHAN=$(git rev-parse orphan-me~1) &&
		FINAL_ORPHAN=$(git rev-parse orphan-me) &&
		FILE_A_CHANGE=$(git rev-list -1 HEAD -- fileA) &&
		FILE_B_CHANGE=$(git rev-list -1 HEAD -- fileB) &&
		FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&
		FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		ORIGINAL_TAG=$(git rev-parse v1.0) &&

		git filter-repo --invert-paths --path nuke-me --path fileC \
		                --force &&

		NEW_FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		NEW_TAG=$(git rev-parse v1.0) &&

		cat <<-EOF | sort >sha-expect &&
		${FIRST_ORPHAN} ${DELETED_SHA}
		${FINAL_ORPHAN} ${DELETED_SHA}
		${FILE_A_CHANGE} ${FILE_A_CHANGE}
		${FILE_B_CHANGE} ${FILE_B_CHANGE}
		${FILE_C_CHANGE} ${DELETED_SHA}
		${FILE_D_CHANGE} ${NEW_FILE_D_CHANGE}
		EOF
		printf "%-40s %s\n" old new >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/commit-map &&

		cat <<-EOF | sort -k 3 >sha-expect &&
		${FILE_D_CHANGE} ${NEW_FILE_D_CHANGE} $(git symbolic-ref HEAD)
		${FINAL_ORPHAN} ${DELETED_SHA} refs/heads/orphan-me
		${ORIGINAL_TAG} ${NEW_TAG} refs/tags/v1.0
		EOF
		printf "%-40s %-40s %s\n" old new ref >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/ref-map &&

		cat <<-EOF | sort >expect &&
		${FIRST_ORPHAN} ${DELETED_SHA}
		${FILE_C_CHANGE} ${FILE_B_CHANGE}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits
	)
'

test_expect_success 'remove two files, then remove a later file' '
	test_create_repo remove_two_file_then_remove_later &&
	(
		cd remove_two_file_then_remove_later &&
		git fast-import --quiet <$DATA/simple &&

		FIRST_ORPHAN=$(git rev-parse orphan-me~1) &&
		FINAL_ORPHAN=$(git rev-parse orphan-me) &&
		FILE_A_CHANGE=$(git rev-list -1 HEAD -- fileA) &&
		FILE_B_CHANGE=$(git rev-list -1 HEAD -- fileB) &&
		FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&
		FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		ORIGINAL_TAG=$(git rev-parse v1.0) &&

		git filter-repo --invert-paths --path nuke-me --path fileC \
		                --force &&

		NEW_FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		NEW_TAG=$(git rev-parse v1.0) &&

		cat <<-EOF | sort >expect &&
		${FIRST_ORPHAN} ${DELETED_SHA}
		${FILE_C_CHANGE} ${FILE_B_CHANGE}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits &&

		cat <<-EOF | sort -k 3 >sha-expect &&
		${FILE_D_CHANGE} ${NEW_FILE_D_CHANGE} $(git symbolic-ref HEAD)
		${FINAL_ORPHAN} ${DELETED_SHA} refs/heads/orphan-me
		${ORIGINAL_TAG} ${NEW_TAG} refs/tags/v1.0
		EOF
		printf "%-40s %-40s %s\n" old new ref >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/ref-map &&

		git filter-repo --invert-paths --path fileD &&

		FINAL_TAG=$(git rev-parse v1.0) &&

		cat <<-EOF | sort >expect &&
		${FIRST_ORPHAN} ${DELETED_SHA}
		${FILE_C_CHANGE} ${FILE_B_CHANGE}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits &&

		cat <<-EOF | sort >sha-expect &&
		${FIRST_ORPHAN} ${DELETED_SHA}
		${FINAL_ORPHAN} ${DELETED_SHA}
		${FILE_A_CHANGE} ${FILE_A_CHANGE}
		${FILE_B_CHANGE} ${FILE_B_CHANGE}
		${FILE_C_CHANGE} ${DELETED_SHA}
		${FILE_D_CHANGE} ${DELETED_SHA}
		EOF
		printf "%-40s %s\n" old new >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/commit-map &&

		cat <<-EOF | sort -k 3 >sha-expect &&
		${FILE_D_CHANGE} ${FILE_B_CHANGE} $(git symbolic-ref HEAD)
		${FINAL_ORPHAN} ${DELETED_SHA} refs/heads/orphan-me
		${ORIGINAL_TAG} ${FINAL_TAG} refs/tags/v1.0
		EOF
		printf "%-40s %-40s %s\n" old new ref >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/ref-map
	)
'

test_expect_success 'remove two files, then remove a later file via --refs' '
	test_create_repo remove_two_files_remove_later_via_refs &&
	(
		cd remove_two_files_remove_later_via_refs &&
		git fast-import --quiet <$DATA/simple &&

		FIRST_ORPHAN=$(git rev-parse orphan-me~1) &&
		FINAL_ORPHAN=$(git rev-parse orphan-me) &&
		FILE_A_CHANGE=$(git rev-list -1 HEAD -- fileA) &&
		FILE_B_CHANGE=$(git rev-list -1 HEAD -- fileB) &&
		FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&
		FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		ORIGINAL_TAG=$(git rev-parse v1.0) &&

		git filter-repo --invert-paths --path nuke-me --path fileB \
		                --force &&

		NEW_FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&

		cat <<-EOF | sort >expect &&
		${FIRST_ORPHAN} ${DELETED_SHA}
		${FILE_B_CHANGE} ${FILE_A_CHANGE}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits &&

		git filter-repo --invert-paths --path fileD --refs HEAD~1..HEAD &&
		FINAL_TAG=$(git rev-parse v1.0) &&

		cat <<-EOF | sort >expect &&
		${FIRST_ORPHAN} ${DELETED_SHA}
		${FILE_B_CHANGE} ${FILE_A_CHANGE}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits &&

		cat <<-EOF | sort >sha-expect &&
		${FIRST_ORPHAN} ${DELETED_SHA}
		${FINAL_ORPHAN} ${DELETED_SHA}
		${FILE_A_CHANGE} ${FILE_A_CHANGE}
		${FILE_B_CHANGE} ${DELETED_SHA}
		${FILE_C_CHANGE} ${NEW_FILE_C_CHANGE}
		${FILE_D_CHANGE} ${DELETED_SHA}
		EOF
		printf "%-40s %s\n" old new >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/commit-map &&

		cat <<-EOF | sort -k 3 >sha-expect &&
		${FILE_D_CHANGE} ${NEW_FILE_C_CHANGE} $(git symbolic-ref HEAD)
		${FINAL_ORPHAN} ${DELETED_SHA} refs/heads/orphan-me
		${ORIGINAL_TAG} ${FINAL_TAG} refs/tags/v1.0
		EOF
		printf "%-40s %-40s %s\n" old new ref >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/ref-map
	)
'

test_expect_success 'remove two files, then remove an earlier file' '
	test_create_repo remove_two_files_then_remove_earlier &&
	(
		cd remove_two_files_then_remove_earlier &&
		git fast-import --quiet <$DATA/simple &&

		FIRST_ORPHAN=$(git rev-parse orphan-me~1) &&
		FINAL_ORPHAN=$(git rev-parse orphan-me) &&
		FILE_A_CHANGE=$(git rev-list -1 HEAD -- fileA) &&
		FILE_B_CHANGE=$(git rev-list -1 HEAD -- fileB) &&
		FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&
		FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		ORIGINAL_TAG=$(git rev-parse v1.0) &&

		git filter-repo --invert-paths --path nuke-me --path fileC \
		                --force &&

		git filter-repo --invert-paths --path fileB &&

		NEW_FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		FINAL_TAG=$(git rev-parse v1.0) &&

		cat <<-EOF | sort >expect &&
		${FIRST_ORPHAN} ${DELETED_SHA}
		${FILE_B_CHANGE} ${FILE_A_CHANGE}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits &&

		cat <<-EOF | sort >sha-expect &&
		${FIRST_ORPHAN} ${DELETED_SHA}
		${FINAL_ORPHAN} ${DELETED_SHA}
		${FILE_A_CHANGE} ${FILE_A_CHANGE}
		${FILE_B_CHANGE} ${DELETED_SHA}
		${FILE_C_CHANGE} ${DELETED_SHA}
		${FILE_D_CHANGE} ${NEW_FILE_D_CHANGE}
		EOF
		printf "%-40s %s\n" old new >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/commit-map &&

		cat <<-EOF | sort -k 3 >sha-expect &&
		${FILE_D_CHANGE} ${NEW_FILE_D_CHANGE} $(git symbolic-ref HEAD)
		${FINAL_ORPHAN} ${DELETED_SHA} refs/heads/orphan-me
		${ORIGINAL_TAG} ${FINAL_TAG} refs/tags/v1.0
		EOF
		printf "%-40s %-40s %s\n" old new ref >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/ref-map
	)
'

test_expect_success 'modify a file, then remove a later file' '
	test_create_repo modify_file_later_remove &&
	(
		cd modify_file_later_remove &&
		git fast-import --quiet <$DATA/simple &&

		FIRST_ORPHAN=$(git rev-parse orphan-me~1) &&
		FINAL_ORPHAN=$(git rev-parse orphan-me) &&
		FILE_A_CHANGE=$(git rev-list -1 HEAD -- fileA) &&
		FILE_B_CHANGE=$(git rev-list -1 HEAD -- fileB) &&
		FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&
		FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		ORIGINAL_TAG=$(git rev-parse v1.0) &&

		echo "file 3 contents==>Alternate C" >changes &&
		git filter-repo --force --replace-text changes &&

		NEW_FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&

		cat <<-EOF | sort >expect &&
		${FILE_C_CHANGE} ${NEW_FILE_C_CHANGE}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits &&

		git filter-repo --invert-paths --path fileD &&

		FINAL_TAG=$(git rev-parse v1.0) &&

		cat <<-EOF | sort >expect &&
		${FILE_C_CHANGE} ${NEW_FILE_C_CHANGE}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits &&

		# Make sure the fileD commit was indeed removed
		echo $NEW_FILE_C_CHANGE >expect &&
		git rev-parse HEAD >actual &&
		test_cmp expect actual &&

		cat <<-EOF | sort >sha-expect &&
		${FIRST_ORPHAN} ${FIRST_ORPHAN}
		${FINAL_ORPHAN} ${FINAL_ORPHAN}
		${FILE_A_CHANGE} ${FILE_A_CHANGE}
		${FILE_B_CHANGE} ${FILE_B_CHANGE}
		${FILE_C_CHANGE} ${NEW_FILE_C_CHANGE}
		${FILE_D_CHANGE} ${DELETED_SHA}
		EOF
		printf "%-40s %s\n" old new >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/commit-map &&

		cat <<-EOF | sort -k 3 >sha-expect &&
		${FILE_D_CHANGE} ${NEW_FILE_C_CHANGE} $(git symbolic-ref HEAD)
		${FINAL_ORPHAN} ${FINAL_ORPHAN} refs/heads/orphan-me
		${ORIGINAL_TAG} ${FINAL_TAG} refs/tags/v1.0
		EOF
		printf "%-40s %-40s %s\n" old new ref >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/ref-map
	)
'


test_expect_success 'modify a file, then remove a later file via --refs' '
	test_create_repo modify_file_later_remove_with_refs &&
	(
		cd modify_file_later_remove_with_refs &&
		git fast-import --quiet <$DATA/simple &&

		FIRST_ORPHAN=$(git rev-parse orphan-me~1) &&
		FINAL_ORPHAN=$(git rev-parse orphan-me) &&
		FILE_A_CHANGE=$(git rev-list -1 HEAD -- fileA) &&
		FILE_B_CHANGE=$(git rev-list -1 HEAD -- fileB) &&
		FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&
		FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		ORIGINAL_TAG=$(git rev-parse v1.0) &&

		echo "file 2 contents==>Alternate B" >changes &&
		git filter-repo --force --replace-text changes &&

		NEW_FILE_B_CHANGE=$(git rev-list -1 HEAD -- fileB) &&
		NEW_FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&

		cat <<-EOF | sort >expect &&
		${FILE_B_CHANGE} ${NEW_FILE_B_CHANGE}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits &&

		git filter-repo --invert-paths --path fileD \
		                --refs HEAD~1..HEAD &&
		FINAL_TAG=$(git rev-parse v1.0) &&

		cat <<-EOF | sort >expect &&
		${FILE_B_CHANGE} ${NEW_FILE_B_CHANGE}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits &&

		# Make sure the fileD commit was indeed removed
		git rev-parse HEAD^ >expect &&
		echo ${NEW_FILE_B_CHANGE} >actual &&
		test_cmp expect actual &&

		cat <<-EOF | sort >sha-expect &&
		${FIRST_ORPHAN} ${FIRST_ORPHAN}
		${FINAL_ORPHAN} ${FINAL_ORPHAN}
		${FILE_A_CHANGE} ${FILE_A_CHANGE}
		${FILE_B_CHANGE} ${NEW_FILE_B_CHANGE}
		${FILE_C_CHANGE} ${NEW_FILE_C_CHANGE}
		${FILE_D_CHANGE} ${DELETED_SHA}
		EOF
		printf "%-40s %s\n" old new >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/commit-map &&

		cat <<-EOF | sort -k 3 >sha-expect &&
		${FILE_D_CHANGE} ${NEW_FILE_C_CHANGE} $(git symbolic-ref HEAD)
		${FINAL_ORPHAN} ${FINAL_ORPHAN} refs/heads/orphan-me
		${ORIGINAL_TAG} ${FINAL_TAG} refs/tags/v1.0
		EOF
		printf "%-40s %-40s %s\n" old new ref >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/ref-map
	)
'

test_expect_success 'modify a file, then remove an earlier file' '
	test_create_repo modify_file_earlier_remove &&
	(
		cd modify_file_earlier_remove &&
		git fast-import --quiet <$DATA/simple &&

		FIRST_ORPHAN=$(git rev-parse orphan-me~1) &&
		FINAL_ORPHAN=$(git rev-parse orphan-me) &&
		FILE_A_CHANGE=$(git rev-list -1 HEAD -- fileA) &&
		FILE_B_CHANGE=$(git rev-list -1 HEAD -- fileB) &&
		FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&
		FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		ORIGINAL_TAG=$(git rev-parse v1.0) &&

		echo "file 3 contents==>Alternate C" >changes &&
		git filter-repo --force --replace-text changes &&

		NEW_FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&

		cat <<-EOF | sort >expect &&
		${FILE_C_CHANGE} ${NEW_FILE_C_CHANGE}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits &&

		git filter-repo --invert-paths --path fileB &&

		NEW_FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&
		NEW_FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		FINAL_TAG=$(git rev-parse v1.0) &&

		cat <<-EOF | sort >expect &&
		${FILE_B_CHANGE} ${FILE_A_CHANGE}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits &&

		cat <<-EOF | sort >sha-expect &&
		${FIRST_ORPHAN} ${FIRST_ORPHAN}
		${FINAL_ORPHAN} ${FINAL_ORPHAN}
		${FILE_A_CHANGE} ${FILE_A_CHANGE}
		${FILE_B_CHANGE} ${DELETED_SHA}
		${FILE_C_CHANGE} ${NEW_FILE_C_CHANGE}
		${FILE_D_CHANGE} ${NEW_FILE_D_CHANGE}
		EOF
		printf "%-40s %s\n" old new >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/commit-map &&

		cat <<-EOF | sort -k 3 >sha-expect &&
		${FILE_D_CHANGE} ${NEW_FILE_D_CHANGE} $(git symbolic-ref HEAD)
		${FINAL_ORPHAN} ${FINAL_ORPHAN} refs/heads/orphan-me
		${ORIGINAL_TAG} ${FINAL_TAG} refs/tags/v1.0
		EOF
		printf "%-40s %-40s %s\n" old new ref >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/ref-map
	)
'

test_expect_success 'use --refs heavily with a rerun' '
	test_create_repo rerun_on_targetted_branches &&
	(
		cd rerun_on_targetted_branches &&
		git fast-import --quiet <$DATA/simple &&

		FIRST_ORPHAN=$(git rev-parse orphan-me~1) &&
		FINAL_ORPHAN=$(git rev-parse orphan-me) &&
		FILE_A_CHANGE=$(git rev-list -1 HEAD -- fileA) &&
		FILE_B_CHANGE=$(git rev-list -1 HEAD -- fileB) &&
		FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&
		FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&

		echo "Tweak it==>Modify it" >changes &&
		git filter-repo --force --refs orphan-me \
		    --replace-message changes &&

		NEW_FINAL_ORPHAN=$(git rev-list -1 orphan-me) &&

		cat <<-EOF | sort >expect &&
		${FINAL_ORPHAN} ${NEW_FINAL_ORPHAN}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits &&

		git filter-repo --refs $(git symbolic-ref HEAD) \
		    --invert-paths --path fileD &&

		cat <<-EOF | sort >expect &&
		${FINAL_ORPHAN} ${NEW_FINAL_ORPHAN}
		${FILE_D_CHANGE} ${FILE_C_CHANGE}
		EOF
		test_cmp expect .git/filter-repo/first-changed-commits &&

		cat <<-EOF | sort >sha-expect &&
		${FIRST_ORPHAN} ${FIRST_ORPHAN}
		${FINAL_ORPHAN} ${NEW_FINAL_ORPHAN}
		${FILE_A_CHANGE} ${FILE_A_CHANGE}
		${FILE_B_CHANGE} ${FILE_B_CHANGE}
		${FILE_C_CHANGE} ${FILE_C_CHANGE}
		${FILE_D_CHANGE} ${DELETED_SHA}
		EOF
		printf "%-40s %s\n" old new >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/commit-map &&

		cat <<-EOF | sort -k 3 >sha-expect &&
		${FILE_D_CHANGE} ${FILE_C_CHANGE} $(git symbolic-ref HEAD)
		${FINAL_ORPHAN} ${NEW_FINAL_ORPHAN} refs/heads/orphan-me
		EOF
		printf "%-40s %-40s %s\n" old new ref >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/ref-map
	)
'

test_done
