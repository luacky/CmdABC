#!/usr/bin/env bash

set -eu

TEST_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
PROTOTYPE_DIR=${TEST_DIR%/tests}
CMDABC=$PROTOTYPE_DIR/cmdabc
LIBRARY=$PROTOTYPE_DIR/command-library.txt
TREE_LIBRARY=$TEST_DIR/tree-library.txt
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
