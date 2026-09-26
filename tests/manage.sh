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

assert_failure_surface() {
  local expected=$1
  local stdout_file=$TMP_DIR/error-stdout
  local stderr_file=$TMP_DIR/error-stderr
  local output
  shift

  if "$@" > "$stdout_file" 2> "$stderr_file"; then
    fail "command unexpectedly succeeded: $*"
  fi
  [ ! -s "$stdout_file" ] || fail "failed command wrote to stdout: $*"
  output=$(cat "$stderr_file")
  assert_eq "$output" "$expected" "error surface for $*"
}

assert_removed_management_entry() {
  local library=$1
  local input=$2
  local before=$TMP_DIR/removed-entry-before

  cp "$library" "$before"
  assert_failure_surface '[invalid: malformed entry]' \
    "$CMDABC" manage --library "$library" --input "$input"
  cmp "$before" "$library" \
    || fail "removed management syntax changed the library: $input"
}

EMPTY_LIBRARY=$HOME/.cmdabc-data/command-library.txt
: > "$EMPTY_LIBRARY"

expected_version=$(sed -n '1p' "$REPO_DIR/VERSION")
assert_eq "$($CMDABC --version)" "$expected_version" 'runtime version'
help_output=$($CMDABC --help)
assert_contains "$help_output" "CmdABC $expected_version" \
  'standard CLI help derives its version from VERSION'
assert_contains "$help_output" '/abc.' 'public help identifies the management entry'
if printf '%s\n' "$help_output" \
  | grep -E 'cmdabc (add|manage|pick|children|internal-list)|/abc\.(add|del|update|help|list)' \
    >/dev/null; then
  fail 'public help exposes an internal helper or removed management syntax'
fi

# Standalone Add is no longer a public dispatch. It must fail before opening a
# TTY editor and must not change the command library.
cp "$EMPTY_LIBRARY" "$TMP_DIR/public-add-before"
if "$CMDABC" add --library "$EMPTY_LIBRARY" \
  > "$TMP_DIR/public-add-stdout" 2> "$TMP_DIR/public-add-stderr"; then
  fail 'standalone cmdabc add unexpectedly succeeded'
fi
[ ! -s "$TMP_DIR/public-add-stdout" ] \
  || fail 'standalone cmdabc add wrote to stdout'
assert_contains "$(cat "$TMP_DIR/public-add-stderr")" \
  '[error: unknown command: add]' 'standalone cmdabc add rejection'
if grep -F 'cmdabc add' "$TMP_DIR/public-add-stderr" >/dev/null; then
  fail 'standalone cmdabc add rejection advertised the removed route'
fi
cmp "$TMP_DIR/public-add-before" "$EMPTY_LIBRARY" \
  || fail 'standalone cmdabc add changed the library'

# The guided management home is built in, ordered, and limited to three
# plain-language actions. No legacy command syntax appears in its rows.
system_children=$($CMDABC children --path abc)
expected_children=$(printf 'add\tleaf\tAdd a command\ndel\tleaf\tRemove a command\nlist\tleaf\tView commands and errors')
assert_eq "$system_children" "$expected_children" 'guided management home'
if printf '%s\n' "$system_children" | grep -E '(^|[[:space:]])(help|update)([[:space:]]|$)|/abc\.' >/dev/null; then
  fail 'management home exposes help, update, or legacy syntax'
fi

assert_eq "$($CMDABC internal-list --library "$EMPTY_LIBRARY")" \
  '0 commands, 0 invalid' 'empty library list'

# Removed developer-style management entries fail explicitly, write nothing,
# and leave the source file byte-for-byte unchanged.
for removed_input in \
  '/abc.add' \
  '/abc.add.git.status git status' \
  '/abc.del.git.status' \
  '/abc.update.git.status git status --short' \
  '/abc.help' \
  '/abc.list'; do
  assert_removed_management_entry "$EMPTY_LIBRARY" "$removed_input"
done

# Public CLI failures remain one-line stderr with non-zero status and no path
# or parser implementation details.
assert_failure_surface '[error: command library not found]' \
  "$CMDABC" internal-list --library "$TMP_DIR/does-not-exist.txt"
assert_failure_surface '[invalid: name not found]' \
  "$CMDABC" children --library "$EMPTY_LIBRARY" --path missing
assert_failure_surface '[invalid: invalid name]' \
  "$CMDABC" pick --library "$EMPTY_LIBRARY" --namespace 'bad.target'

PERMISSION_LIBRARY=$TMP_DIR/permission-library.txt
printf 'permission.target echo SAFE\n' > "$PERMISSION_LIBRARY"
chmod 000 "$PERMISSION_LIBRARY"
assert_failure_surface '[error: command library is not readable]' \
  "$CMDABC" internal-list --library "$PERMISSION_LIBRARY"
chmod 600 "$PERMISSION_LIBRARY"

# Strict validation maps record problems to the stable public taxonomy.
MISSING_LIBRARY=$TMP_DIR/missing-command.txt
printf 'demo.invalid\n' > "$MISSING_LIBRARY"
assert_failure_surface '[invalid: missing command]' \
  "$CMDABC" validate --library "$MISSING_LIBRARY"

MALFORMED_LIBRARY=$TMP_DIR/malformed.txt
printf '%s\n' '----------------' > "$MALFORMED_LIBRARY"
assert_failure_surface '[invalid: malformed entry]' \
  "$CMDABC" validate --library "$MALFORMED_LIBRARY"

RESERVED_LIBRARY=$TMP_DIR/reserved.txt
printf 'abc.list echo NO\n' > "$RESERVED_LIBRARY"
assert_failure_surface '[invalid: reserved namespace]' \
  "$CMDABC" validate --library "$RESERVED_LIBRARY"

DUPLICATE_LIBRARY=$TMP_DIR/duplicate.txt
printf 'dup.path echo ONE\ndup.path echo TWO\n' > "$DUPLICATE_LIBRARY"
assert_failure_surface '[invalid: name taken]' \
  "$CMDABC" validate --library "$DUPLICATE_LIBRARY"

EMPTY_SEGMENT_LIBRARY=$TMP_DIR/empty-segment.txt
printf 'bad..name echo NO\n' > "$EMPTY_SEGMENT_LIBRARY"
assert_failure_surface '[invalid: empty name segment]' \
  "$CMDABC" validate --library "$EMPTY_SEGMENT_LIBRARY"

UNSUPPORTED_NAME_LIBRARY=$TMP_DIR/unsupported-name.txt
printf 'bad!name echo NO\n' > "$UNSUPPORTED_NAME_LIBRARY"
assert_failure_surface '[invalid: unsupported name character]' \
  "$CMDABC" validate --library "$UNSUPPORTED_NAME_LIBRARY"

# List is the parser diagnostic surface. Comments and blanks stay invisible;
# duplicate targets invalidate every occurrence; unrelated malformed rows do
# not hide valid commands.
TOLERANT_LIBRARY=$TMP_DIR/tolerant.txt
printf '# heading\n\ngood.one echo ONE\ndemo.invalid\n   # disabled.path echo OFF\n# dup.path echo COMMENTED\ndup.path echo A\ndup.path echo B\n\nkeep.two echo TWO\n----------------\n' \
  > "$TOLERANT_LIBRARY"
cp "$TOLERANT_LIBRARY" "$TMP_DIR/tolerant-before"
list_output=$($CMDABC internal-list --library "$TOLERANT_LIBRARY")
list_expected=$(printf 'good.one echo ONE\ndemo.invalid  [invalid: missing command]\ndup.path  [invalid: name taken]\ndup.path  [invalid: name taken]\nkeep.two echo TWO\nline 11  [invalid: malformed entry]\n\n2 commands, 4 invalid')
assert_eq "$list_output" "$list_expected" 'tolerant list diagnostics'
cmp "$TMP_DIR/tolerant-before" "$TOLERANT_LIBRARY" \
  || fail 'list changed the command library'
if printf '%s\n' "$list_output" | grep -F 'disabled.path' >/dev/null; then
  fail 'list included a comment'
fi
if $CMDABC children --library "$TOLERANT_LIBRARY" --path dup >/dev/null 2>&1; then
  fail 'duplicate target entered the tree'
fi

# The three frozen leading-comment forms are ignored. Inline # remains exact
# command payload, and removing # restores the record immediately.
COMMENT_LIBRARY=$TMP_DIR/comments.txt
printf '#screen.test echo test\n# screen.test echo test\n    #screen.test echo test\nfoo.live echo hi # payload\nbroken\n' \
  > "$COMMENT_LIBRARY"
comment_list=$($CMDABC internal-list --library "$COMMENT_LIBRARY")
comment_expected=$(printf 'foo.live echo hi # payload\nline 5  [invalid: malformed entry]\n\n1 commands, 1 invalid')
assert_eq "$comment_list" "$comment_expected" \
  'leading comments and inline payload classification'
assert_eq "$($CMDABC children --library "$COMMENT_LIBRARY" --path foo)" \
  "$(printf 'live\tleaf\techo hi # payload')" \
  'inline # payload fidelity'
if $CMDABC children --library "$COMMENT_LIBRARY" --path screen >/dev/null 2>&1; then
  fail 'commented command entered the tree'
fi

printf 'screen.test echo test\n# screen.test echo test\n    #screen.test echo test\nfoo.live echo hi # payload\nbroken\n' \
  > "$COMMENT_LIBRARY"
uncommented_list=$($CMDABC internal-list --library "$COMMENT_LIBRARY")
uncommented_expected=$(printf 'screen.test echo test\nfoo.live echo hi # payload\nline 5  [invalid: malformed entry]\n\n2 commands, 1 invalid')
assert_eq "$uncommented_list" "$uncommented_expected" \
  'removing # restores command classification'

# Stored payload is opaque data: list/children return it exactly and no shell
# metacharacter is evaluated by CmdABC.
NOEXEC_MARKER=$TMP_DIR/must-not-exist
FIDELITY_PAYLOAD="printf '%s' \"\$HOME\" | cat && touch $NOEXEC_MARKER"
FIDELITY_LIBRARY=$TMP_DIR/fidelity.txt
printf 'fidelity.payload %s\n' "$FIDELITY_PAYLOAD" > "$FIDELITY_LIBRARY"
assert_contains "$($CMDABC internal-list --library "$FIDELITY_LIBRARY")" \
  "fidelity.payload $FIDELITY_PAYLOAD" 'list payload fidelity'
assert_eq "$($CMDABC children --library "$FIDELITY_LIBRARY" --path fidelity)" \
  "$(printf 'payload\tleaf\t%s' "$FIDELITY_PAYLOAD")" \
  'tree payload fidelity'
[ ! -e "$NOEXEC_MARKER" ] || fail 'payload was executed'

printf 'PASS: C02 guided management and parser checks\n'
