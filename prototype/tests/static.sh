#!/usr/bin/env bash

set -eu

TEST_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
PROTOTYPE_DIR=${TEST_DIR%/tests}
CMDABC=$PROTOTYPE_DIR/cmdabc
LIBRARY=$PROTOTYPE_DIR/command-library.txt
TREE_LIBRARY=$TEST_DIR/tree-library.txt
PREVIEW_LIBRARY=$TEST_DIR/preview-library.txt
TOLERANT_LIBRARY=$TEST_DIR/tolerant-library.txt
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cmdabc-c00.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "$3 (expected <$2>, got <$1>)"
}

validation=$($CMDABC validate --library "$LIBRARY")
assert_eq "$validation" "OK: 3 command records" "fixed library validates"

tree_validation=$($CMDABC validate --library "$TREE_LIBRARY")
assert_eq "$tree_validation" "OK: 4 command records" "tree picker fixture validates"

preview_validation=$($CMDABC validate --library "$PREVIEW_LIBRARY")
assert_eq "$preview_validation" "OK: 3 command records" "preview fixture validates"

if $CMDABC validate --library "$TOLERANT_LIBRARY" >/dev/null 2>&1; then
  fail "strict validation accepted the tolerant picker fixture"
fi
tolerant_children=$($CMDABC children --library "$TOLERANT_LIBRARY" --path dome)
tolerant_expected=$(printf 'tar\tleaf\ttar -xzf archive.tar.gz\nfind\tleaf\tfind . -type f -name "*.log"\nlog\tparent\t\na\tleaf\t')
assert_eq "$tolerant_children" "$tolerant_expected" \
  "tolerant picker keeps valid records and one invalid leaf"

printf 'position.first\nposition.ok echo OK\ninvalid..path echo BAD\nposition.middle\nposition.second echo SECOND\nposition.last\n' \
  > "$TMP_DIR/tolerant-positions.txt"
position_children=$($CMDABC children --library "$TMP_DIR/tolerant-positions.txt" --path position)
position_expected=$(printf 'ok\tleaf\techo OK\nsecond\tleaf\techo SECOND\nfirst\tleaf\t\nmiddle\tleaf\t\nlast\tleaf\t')
assert_eq "$position_children" "$position_expected" \
  "multiple invalid records at file boundaries stay isolated"
if $CMDABC children --library "$TMP_DIR/tolerant-positions.txt" --path invalid >/dev/null 2>&1; then
  fail "unlocatable malformed path entered the picker tree"
fi

: > "$TMP_DIR/empty.txt"
empty_validation=$($CMDABC validate --library "$TMP_DIR/empty.txt")
assert_eq "$empty_validation" "OK: 0 command records" "empty user library is valid"

printf '# comments only\n\n' > "$TMP_DIR/comments-only.txt"
comments_validation=$($CMDABC validate --library "$TMP_DIR/comments-only.txt")
assert_eq "$comments_validation" "OK: 0 command records" "comments-only user library is valid"

mkdir -p "$TMP_DIR/home/.cmdabc-data"
: > "$TMP_DIR/home/.cmdabc-data/command-library.txt"
default_validation=$(HOME="$TMP_DIR/home" CMDABC_LIBRARY= $CMDABC validate)
assert_eq "$default_validation" "OK: 0 command records" "default user library path validates"

root_children=$($CMDABC children --library "$LIBRARY" --path test)
expected_root=$(printf 'one\tleaf\techo ONE\ngroup\tparent\t')
assert_eq "$root_children" "$expected_root" "root children use short labels"

group_children=$($CMDABC children --library "$LIBRARY" --path test.group)
expected_group=$(printf 'two\tleaf\techo TWO\nthree\tleaf\techo THREE')
assert_eq "$group_children" "$expected_group" "nested children preserve order"

printf '# comment\n\npreserve.path   echo spaced\n' > "$TMP_DIR/preserve.txt"
preserved=$($CMDABC children --library "$TMP_DIR/preserve.txt" --path preserve)
expected_preserved=$(printf 'path\tleaf\t  echo spaced')
assert_eq "$preserved" "$expected_preserved" "command bytes after first delimiter are preserved"

marker=$TMP_DIR/must-not-exist
printf 'safe.leaf touch %s\n' "$marker" > "$TMP_DIR/no-execute.txt"
$CMDABC children --library "$TMP_DIR/no-execute.txt" --path safe >/dev/null
[ ! -e "$marker" ] || fail "library command was executed"

printf 'dup.path echo A\ndup.path echo B\n' > "$TMP_DIR/duplicate.txt"
if $CMDABC validate --library "$TMP_DIR/duplicate.txt" >/dev/null 2>&1; then
  fail "duplicate path was accepted"
fi

printf 'tree.node echo A\ntree.node.child echo B\n' > "$TMP_DIR/collision.txt"
if $CMDABC validate --library "$TMP_DIR/collision.txt" >/dev/null 2>&1; then
  fail "leaf/parent collision was accepted"
fi

printf 'bad..path echo A\n' > "$TMP_DIR/empty-segment.txt"
if $CMDABC validate --library "$TMP_DIR/empty-segment.txt" >/dev/null 2>&1; then
  fail "empty path segment was accepted"
fi

if rg -n '(^|[;&|[:space:]])eval([;&|[:space:]]|$)' "$PROTOTYPE_DIR/cmdabc" "$PROTOTYPE_DIR/shell" >/dev/null; then
  fail "prototype contains eval"
fi

if rg -n '(^|[^[:alnum:]_])stty([^[:alnum:]_]|$)' "$PROTOTYPE_DIR/cmdabc" >/dev/null; then
  fail "picker contains forbidden stty dependency"
fi

if rg -n "suffix=' >'|suffix=' →'" "$PROTOTYPE_DIR/cmdabc" >/dev/null; then
  fail "picker contains forbidden legacy hierarchy marker"
fi

rg -F "suffix=' ▸'" "$PROTOTYPE_DIR/cmdabc" >/dev/null \
  || fail "picker is missing the collapsed tree marker"
rg -F "suffix=' ▾'" "$PROTOTYPE_DIR/cmdabc" >/dev/null \
  || fail "picker is missing the expanded tree marker"

printf 'PASS: static C00 checks\n'
