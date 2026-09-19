#!/usr/bin/env bash

set -eu

TEST_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
REPO_DIR=${TEST_DIR%/tests}
CMDABC=$REPO_DIR/prototype/cmdabc
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cmdabc-manage.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT
export HOME=$TMP_DIR/home
mkdir -p "$HOME/.cmdabc-data"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "$3 (expected <$2>, got <$1>)"
}

assert_contains() {
  printf '%s\n' "$1" | grep -F "$2" >/dev/null \
    || fail "$3 (missing <$2> in <$1>)"
}

file_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    sha256sum "$1" | awk '{ print $1 }'
  fi
}

assert_unchanged_after_failure() {
  local before=$1
  shift
  cp "$LIBRARY" "$before"
  if "$@" >/dev/null 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
  cmp "$before" "$LIBRARY" || fail "failed command changed the library: $*"
}

EMPTY_LIBRARY=$HOME/.cmdabc-data/command-library.txt
: > "$EMPTY_LIBRARY"

# The system namespace is built in and exists with an empty user library.
system_children=$($CMDABC children --path abc)
expected_children=$(printf 'add\tleaf\t/abc.add.\ndel\tleaf\t/abc.del.\nhelp\tleaf\t/abc.help\nlist\tleaf\t/abc.list\nupdate\tleaf\t/abc.update.')
assert_eq "$system_children" "$expected_children" 'built-in abc picker nodes'
assert_eq "$($CMDABC manage --input /abc.list)" \
  '0 user commands' 'empty library list'

help_output=$($CMDABC manage --library "$EMPTY_LIBRARY" --input /abc.help)
assert_contains "$help_output" '/abc.list' 'help lists list command'
assert_contains "$help_output" '/abc.add.<target> <command>' 'help lists add command'
assert_contains "$help_output" '/abc.update.<target> <command>' 'help lists update command'
assert_contains "$help_output" '/abc.del.<target>' 'help lists del command'
assert_contains "$help_output" '/abc.help' 'help lists help command'

# Reserved records are rejected by validation and cannot replace system nodes.
RESERVED_LIBRARY=$TMP_DIR/reserved.txt
printf 'abc.list touch %s\nabc.foo echo FAKE\n' "$TMP_DIR/reserved-executed" > "$RESERVED_LIBRARY"
cp "$RESERVED_LIBRARY" "$TMP_DIR/reserved-before"
if reserved_error=$($CMDABC validate --library "$RESERVED_LIBRARY" 2>&1); then
  fail 'reserved namespace validation unexpectedly succeeded'
fi
assert_contains "$reserved_error" 'reserved namespace: abc' 'reserved namespace validation message'
assert_eq "$($CMDABC children --library "$RESERVED_LIBRARY" --path abc)" \
  "$expected_children" 'reserved user records cannot replace system nodes'
[ ! -e "$TMP_DIR/reserved-executed" ] || fail 'reserved payload was executed'
cmp "$TMP_DIR/reserved-before" "$RESERVED_LIBRARY" || fail 'reserved validation changed user data'

LIBRARY=$HOME/.cmdabc-data/command-library.txt
printf '# user comment\n\nbase.one echo ONE\nbase.two echo TWO\n' > "$LIBRARY"

# Add stores payload bytes, rejects duplicates/reserved targets, and never executes.
assert_eq "$($CMDABC manage --library "$LIBRARY" --input '/abc.add.git.status git status')" \
  'Added: git.status' 'add success output'
grep -Fx 'git.status git status' "$LIBRARY" >/dev/null || fail 'add did not write target record'

assert_unchanged_after_failure "$TMP_DIR/add-duplicate-before" \
  "$CMDABC" manage --library "$LIBRARY" --input '/abc.add.git.status git status --short'
assert_unchanged_after_failure "$TMP_DIR/add-reserved-before" \
  "$CMDABC" manage --library "$LIBRARY" --input '/abc.add.abc.foo echo forbidden'
assert_unchanged_after_failure "$TMP_DIR/add-empty-before" \
  "$CMDABC" manage --library "$LIBRARY" --input '/abc.add.empty.target    '

NOEXEC_MARKER=$TMP_DIR/add-must-not-execute
assert_eq "$($CMDABC manage --library "$LIBRARY" \
  --input "/abc.add.safe.noexec touch $NOEXEC_MARKER")" \
  'Added: safe.noexec' 'no-exec add output'
[ ! -e "$NOEXEC_MARKER" ] || fail 'add executed its payload'
grep -Fx "safe.noexec touch $NOEXEC_MARKER" "$LIBRARY" >/dev/null \
  || fail 'add did not preserve no-exec payload'

assert_eq "$($CMDABC manage --library "$LIBRARY" \
  --input '/abc.add.space.payload printf "%s %s" hello world')" \
  'Added: space.payload' 'space payload add output'
grep -Fx 'space.payload printf "%s %s" hello world' "$LIBRARY" >/dev/null \
  || fail 'add did not preserve a payload containing spaces'

# Shell metacharacters are opaque payload text: add stores them byte-for-byte,
# list and picker input preserve them, and none of the text is executed.
FIDELITY_ADD_PAYLOAD=$'printf \'%s\\n\' "$HOME" "$USER" | sed \'s/ /_/g\' && echo "add"; touch "$HOME/fidelity-add-executed" > "$HOME/fidelity add.out" 2>>"$HOME/fidelity-add.err"; printf \'%s\' path\\ with\\ spaces'
assert_eq "$($CMDABC manage --library "$LIBRARY" \
  --input "/abc.add.fidelity.payload $FIDELITY_ADD_PAYLOAD")" \
  'Added: fidelity.payload' 'fidelity payload add output'
[ ! -e "$HOME/fidelity-add-executed" ] || fail 'add executed the fidelity payload'
[ ! -e "$HOME/fidelity add.out" ] || fail 'add applied fidelity output redirection'
[ ! -e "$HOME/fidelity-add.err" ] || fail 'add applied fidelity error redirection'
grep -Fx "fidelity.payload $FIDELITY_ADD_PAYLOAD" "$LIBRARY" >/dev/null \
  || fail 'add did not preserve the fidelity payload'

list_output=$($CMDABC manage --library "$LIBRARY" --input /abc.list)
assert_contains "$list_output" '6 user commands' 'list count'
assert_contains "$list_output" 'base.one echo ONE' 'list base record'
assert_contains "$list_output" 'git.status git status' 'list added record'
assert_contains "$list_output" "fidelity.payload $FIDELITY_ADD_PAYLOAD" \
  'list changed the fidelity payload'
if printf '%s\n' "$list_output" | grep -F 'abc.' >/dev/null; then
  fail 'list included an internal abc command'
fi
assert_eq "$($CMDABC children --library "$LIBRARY" --path fidelity)" \
  "$(printf 'payload\tleaf\t%s' "$FIDELITY_ADD_PAYLOAD")" \
  'picker input changed the added fidelity payload'

# Update changes exactly one record and preserves comments/other records.
assert_eq "$($CMDABC manage --library "$LIBRARY" \
  --input '/abc.update.git.status git status --short')" \
  'Updated: git.status' 'update success output'
grep -Fx 'git.status git status --short' "$LIBRARY" >/dev/null \
  || fail 'update did not replace target command'
grep -Fx '# user comment' "$LIBRARY" >/dev/null || fail 'update removed comments'
grep -Fx 'base.one echo ONE' "$LIBRARY" >/dev/null || fail 'update changed another record'

FIDELITY_UPDATE_PAYLOAD=$'cat < "$HOME/input file" | tr \' \' \'_\' && printf "%s" "$SHELL"; touch "$HOME/fidelity-update-executed" 2> "$HOME/fidelity-update.err"; printf \'%s\' updated\\ value'
assert_eq "$($CMDABC manage --library "$LIBRARY" \
  --input "/abc.update.fidelity.payload $FIDELITY_UPDATE_PAYLOAD")" \
  'Updated: fidelity.payload' 'fidelity payload update output'
[ ! -e "$HOME/fidelity-update-executed" ] || fail 'update executed the fidelity payload'
[ ! -e "$HOME/fidelity-update.err" ] || fail 'update applied fidelity redirection'
grep -Fx "fidelity.payload $FIDELITY_UPDATE_PAYLOAD" "$LIBRARY" >/dev/null \
  || fail 'update did not preserve the fidelity payload'
if grep -Fx "fidelity.payload $FIDELITY_ADD_PAYLOAD" "$LIBRARY" >/dev/null; then
  fail 'update left the old fidelity payload in the library'
fi
list_output=$($CMDABC manage --library "$LIBRARY" --input /abc.list)
assert_contains "$list_output" "fidelity.payload $FIDELITY_UPDATE_PAYLOAD" \
  'list changed the updated fidelity payload'
assert_eq "$($CMDABC children --library "$LIBRARY" --path fidelity)" \
  "$(printf 'payload\tleaf\t%s' "$FIDELITY_UPDATE_PAYLOAD")" \
  'picker input changed the updated fidelity payload'
assert_unchanged_after_failure "$TMP_DIR/update-missing-before" \
  "$CMDABC" manage --library "$LIBRARY" --input '/abc.update.missing.target echo NO'
assert_unchanged_after_failure "$TMP_DIR/update-reserved-before" \
  "$CMDABC" manage --library "$LIBRARY" --input '/abc.update.abc.help echo NO'

# Delete removes exactly one record and rejects missing/reserved targets safely.
assert_eq "$($CMDABC manage --library "$LIBRARY" --input /abc.del.git.status)" \
  'Deleted: git.status' 'delete success output'
if grep -F 'git.status ' "$LIBRARY" >/dev/null; then
  fail 'delete left the target record behind'
fi
grep -Fx 'base.two echo TWO' "$LIBRARY" >/dev/null || fail 'delete changed another record'
assert_unchanged_after_failure "$TMP_DIR/delete-missing-before" \
  "$CMDABC" manage --library "$LIBRARY" --input /abc.del.missing.target
assert_unchanged_after_failure "$TMP_DIR/delete-reserved-before" \
  "$CMDABC" manage --library "$LIBRARY" --input /abc.del.abc.help

# List is read-only and tolerant: a recognizable incomplete path is reported
# without hiding valid records or changing the source file.
SINGLE_INVALID_LIBRARY=$TMP_DIR/list-single-invalid.txt
printf 'single.one echo ONE\nsingle.bad\nsingle.two echo TWO\n' > "$SINGLE_INVALID_LIBRARY"
cp "$SINGLE_INVALID_LIBRARY" "$TMP_DIR/list-single-invalid-before"
single_invalid_sha=$(file_sha256 "$SINGLE_INVALID_LIBRARY")
single_invalid_output=$($CMDABC manage --library "$SINGLE_INVALID_LIBRARY" --input /abc.list)
single_invalid_expected=$(printf '2 user commands, 1 invalid entry\nsingle.one echo ONE\nsingle.bad    ???  [invalid: missing command]\nsingle.two echo TWO')
assert_eq "$single_invalid_output" "$single_invalid_expected" \
  'list tolerates one invalid record between valid records'
cmp "$TMP_DIR/list-single-invalid-before" "$SINGLE_INVALID_LIBRARY" \
  || fail 'list changed the single-invalid library'
assert_eq "$(file_sha256 "$SINGLE_INVALID_LIBRARY")" "$single_invalid_sha" \
  'list changed the single-invalid library SHA-256'

# Multiple invalid records at the start, middle, and end remain visible. A row
# whose path cannot be trusted is identified only by its source line.
MULTI_INVALID_LIBRARY=$TMP_DIR/list-multiple-invalid.txt
printf 'multi.first\nmulti.one echo ONE\nmulti.one\nbad..path echo BAD\nmulti.two echo TWO\nmulti.middle\nmulti.three echo THREE\nmulti.last\n' \
  > "$MULTI_INVALID_LIBRARY"
cp "$MULTI_INVALID_LIBRARY" "$TMP_DIR/list-multiple-invalid-before"
multi_invalid_sha=$(file_sha256 "$MULTI_INVALID_LIBRARY")
multi_invalid_output=$($CMDABC manage --library "$MULTI_INVALID_LIBRARY" --input /abc.list)
multi_invalid_expected=$(printf '3 user commands, 5 invalid entries\nmulti.first    ???  [invalid: missing command]\nmulti.one echo ONE\nmulti.one    ???  [invalid: missing command]\nline 4    [invalid: malformed entry]\nmulti.two echo TWO\nmulti.middle    ???  [invalid: missing command]\nmulti.three echo THREE\nmulti.last    ???  [invalid: missing command]')
assert_eq "$multi_invalid_output" "$multi_invalid_expected" \
  'list preserves valid and invalid source order'
cmp "$TMP_DIR/list-multiple-invalid-before" "$MULTI_INVALID_LIBRARY" \
  || fail 'list changed the multiple-invalid library'
assert_eq "$(file_sha256 "$MULTI_INVALID_LIBRARY")" "$multi_invalid_sha" \
  'list changed the multiple-invalid library SHA-256'

# Write operations stay strict and fail closed when any malformed record exists.
LIBRARY=$MULTI_INVALID_LIBRARY
assert_unchanged_after_failure "$TMP_DIR/malformed-add-before" \
  "$CMDABC" manage --library "$LIBRARY" --input '/abc.add.multi.new echo NEW'
assert_unchanged_after_failure "$TMP_DIR/malformed-update-before" \
  "$CMDABC" manage --library "$LIBRARY" --input '/abc.update.multi.one echo CHANGED'
assert_unchanged_after_failure "$TMP_DIR/malformed-delete-before" \
  "$CMDABC" manage --library "$LIBRARY" --input /abc.del.multi.one
assert_eq "$(file_sha256 "$MULTI_INVALID_LIBRARY")" "$multi_invalid_sha" \
  'strict write failures changed the malformed library SHA-256'

# Parse failures never replace the existing database.
INVALID_LIBRARY=$TMP_DIR/invalid.txt
printf 'bad..path echo BAD\nkeep.path echo KEEP\n' > "$INVALID_LIBRARY"
LIBRARY=$INVALID_LIBRARY
assert_unchanged_after_failure "$TMP_DIR/invalid-add-before" \
  "$CMDABC" manage --library "$LIBRARY" --input '/abc.add.new.path echo NEW'

printf 'PASS: Phase 3.1 management checks\n'
