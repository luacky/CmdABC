#!/usr/bin/env bash

set -euo pipefail

TEST_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
REPO_DIR=${TEST_DIR%/tests}
PACKAGE_SCRIPT=$REPO_DIR/scripts/package.sh
ARCHIVE=$REPO_DIR/artifacts/CmdABC-0.3.0.tar.gz
CHECKSUM=$ARCHIVE.sha256
WIDGET_EXPECT=$REPO_DIR/prototype/tests/widget.expect
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cmdabc-release-test.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "$3 (expected <$2>, got <$1>)"
}

assert_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

assert_dir() {
  [ -d "$1" ] || fail "missing directory: $1"
}

assert_not_exists() {
  [ ! -e "$1" ] && [ ! -L "$1" ] || fail "unexpected path: $1"
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    fail 'neither shasum nor sha256sum is available'
  fi
}

file_mode() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

block_count() {
  awk '$0 == "# >>> CmdABC >>>" { count += 1 } END { print count + 0 }' "$1"
}

created_marker_count() {
  awk '$0 == "# CmdABC-RC-CREATED-BY-INSTALLER" { count += 1 } END { print count + 0 }' "$1"
}

assert_rejected_management_route() {
  local input=$1
  local result

  cp "$LIBRARY" "$TMP_DIR/rejected-route-before"
  if HOME="$RELEASE_HOME" "$RUNTIME" manage --library "$LIBRARY" \
    --input "$input" > "$TMP_DIR/rejected-route-stdout" \
    2> "$TMP_DIR/rejected-route-stderr"; then
    fail "removed management route succeeded: $input"
  else
    result=$?
  fi
  assert_eq "$result" 2 "removed management route status: $input"
  [ ! -s "$TMP_DIR/rejected-route-stdout" ] \
    || fail "removed management route wrote to stdout: $input"
  assert_eq "$(cat "$TMP_DIR/rejected-route-stderr")" \
    '[invalid: malformed entry]' "removed management route error: $input"
  cmp "$TMP_DIR/rejected-route-before" "$LIBRARY" \
    || fail "removed management route changed user data: $input"
}

find_bash52() {
  local candidate version

  if [ -n "${CMDABC_BASH52_BIN:-}" ]; then
    candidate=$CMDABC_BASH52_BIN
    [ -x "$candidate" ] || fail "CMDABC_BASH52_BIN is not executable: $candidate"
    version=$($candidate --version | sed -n '1p')
    case "$version" in
      *'version 5.2.'*) printf '%s\n' "$candidate"; return 0 ;;
      *) fail "CMDABC_BASH52_BIN is not Bash 5.2: $version" ;;
    esac
  fi

  for candidate in "$(command -v bash 2>/dev/null || true)" /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [ -n "$candidate" ] || continue
    [ -x "$candidate" ] || continue
    version=$($candidate --version | sed -n '1p')
    case "$version" in
      *'version 5.2.'*) printf '%s\n' "$candidate"; return 0 ;;
    esac
  done
  fail 'Bash 5.2 is required for release-package PTY acceptance'
}

command -v expect >/dev/null 2>&1 || fail 'expect is required'
command -v zsh >/dev/null 2>&1 || fail 'zsh is required'
case "$(zsh --version)" in
  'zsh 5.9'*) ;;
  *) fail "zsh 5.9 is required, found: $(zsh --version)" ;;
esac
BASH52_BIN=$(find_bash52)

# Two clean builds must produce byte-identical archives and checksum files.
"$PACKAGE_SCRIPT" >/dev/null
assert_file "$ARCHIVE"
assert_file "$CHECKSUM"
cp "$ARCHIVE" "$TMP_DIR/first.tar.gz"
cp "$CHECKSUM" "$TMP_DIR/first.tar.gz.sha256"
FIRST_BUILD_SHA=$(sha256_file "$TMP_DIR/first.tar.gz")
"$PACKAGE_SCRIPT" >/dev/null
cmp "$TMP_DIR/first.tar.gz" "$ARCHIVE" || fail 'repeated build changed archive bytes'
cmp "$TMP_DIR/first.tar.gz.sha256" "$CHECKSUM" || fail 'repeated build changed checksum file'
SECOND_BUILD_SHA=$(sha256_file "$ARCHIVE")
assert_eq "$SECOND_BUILD_SHA" "$FIRST_BUILD_SHA" 'repeated build SHA-256'

EXPECTED_SHA=$(awk 'NR == 1 { print $1 }' "$CHECKSUM")
EXPECTED_NAME=$(awk 'NR == 1 { print $2 }' "$CHECKSUM")
assert_eq "$EXPECTED_NAME" 'CmdABC-0.3.0.tar.gz' 'checksum filename'
assert_eq "$(sha256_file "$ARCHIVE")" "$EXPECTED_SHA" 'archive SHA-256'

EXPECTED_LIST=$(printf '%s\n' \
  'CmdABC-0.3.0/' \
  'CmdABC-0.3.0/cmdabc' \
  'CmdABC-0.3.0/install.sh' \
  'CmdABC-0.3.0/uninstall.sh' \
  'CmdABC-0.3.0/VERSION' \
  'CmdABC-0.3.0/README.md' \
  'CmdABC-0.3.0/README.zh-CN.md' \
  'CmdABC-0.3.0/LICENSE' \
  'CmdABC-0.3.0/docs/' \
  'CmdABC-0.3.0/docs/images/' \
  'CmdABC-0.3.0/docs/images/cmdabc-01-command-tree.png' \
  'CmdABC-0.3.0/docs/images/cmdabc-02-management.png' \
  'CmdABC-0.3.0/docs/images/cmdabc-03-command-fill.png' \
  'CmdABC-0.3.0/docs/images/cmdabc-04-list.png' \
  'CmdABC-0.3.0/docs/images/cmdabc-05-add.png' \
  'CmdABC-0.3.0/shell/' \
  'CmdABC-0.3.0/shell/cmdabc.bash' \
  'CmdABC-0.3.0/shell/cmdabc.zsh')
assert_eq "$(tar -tzf "$ARCHIVE")" "$EXPECTED_LIST" 'archive allowlist'

if tar -tzf "$ARCHIVE" | grep -E '(^|/)(\.DS_Store|\._|command-library\.txt$)' >/dev/null; then
  fail 'archive contains macOS metadata or user command data'
fi
if tar --version 2>/dev/null | grep -qi bsdtar; then
  tar -tvvvf "$ARCHIVE" | grep -F 'Archive Format: POSIX ustar format' >/dev/null \
    || fail 'archive is not POSIX ustar'
fi

# Extraction happens outside the repository; every product action below uses
# only the extracted package and the isolated HOME.
EXTRACT_DIR=$TMP_DIR/extracted
mkdir -p "$EXTRACT_DIR"
if ! EXTRACT_OUTPUT=$(COPYFILE_DISABLE=1 tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR" 2>&1); then
  fail "archive extraction failed: $EXTRACT_OUTPUT"
fi
[ -z "$EXTRACT_OUTPUT" ] || fail "archive extraction emitted diagnostics: $EXTRACT_OUTPUT"
PACKAGE_ROOT=$EXTRACT_DIR/CmdABC-0.3.0

assert_dir "$PACKAGE_ROOT"
assert_dir "$PACKAGE_ROOT/shell"
assert_dir "$PACKAGE_ROOT/docs"
assert_dir "$PACKAGE_ROOT/docs/images"
assert_eq "$(file_mode "$PACKAGE_ROOT")" 755 'package root mode'
assert_eq "$(file_mode "$PACKAGE_ROOT/shell")" 755 'shell directory mode'
assert_eq "$(file_mode "$PACKAGE_ROOT/docs")" 755 'docs directory mode'
assert_eq "$(file_mode "$PACKAGE_ROOT/docs/images")" 755 'docs/images directory mode'
for path in cmdabc install.sh uninstall.sh; do
  assert_eq "$(file_mode "$PACKAGE_ROOT/$path")" 755 "$path mode"
done
for path in VERSION README.md README.zh-CN.md LICENSE \
  shell/cmdabc.bash shell/cmdabc.zsh \
  docs/images/cmdabc-01-command-tree.png \
  docs/images/cmdabc-02-management.png \
  docs/images/cmdabc-03-command-fill.png \
  docs/images/cmdabc-04-list.png \
  docs/images/cmdabc-05-add.png; do
  assert_file "$PACKAGE_ROOT/$path"
  assert_eq "$(file_mode "$PACKAGE_ROOT/$path")" 644 "$path mode"
done
if find "$PACKAGE_ROOT" -type l -print | grep -q .; then
  fail 'extracted package contains a symlink'
fi
if grep -R -E '/Users/[^/[:space:]]+' "$PACKAGE_ROOT" >/dev/null; then
  fail 'package contains a personal home path'
fi
assert_eq "$(sed -n '1p' "$PACKAGE_ROOT/VERSION")" 0.3.0 'package VERSION'
assert_eq "$(HOME="$TMP_DIR/version-home" "$PACKAGE_ROOT/cmdabc" --version)" \
  0.3.0 'package runtime version'

# The extracted package must restore an absent rc to absent for both supported
# shells, including after a repeated install, without changing user data.
for kind in bash zsh; do
  ABSENT_HOME=$TMP_DIR/package-absent-$kind-home
  if [ "$kind" = bash ]; then
    RC_PARENT=$ABSENT_HOME
    RC_PATH=$ABSENT_HOME/.bashrc
    SHELL_BIN=/bin/bash
  else
    RC_PARENT=$ABSENT_HOME/config/zsh
    RC_PATH=$RC_PARENT/.zshrc
    SHELL_BIN=$(command -v zsh)
  fi
  mkdir -p "$RC_PARENT"
  if [ "$kind" = bash ]; then
    HOME="$ABSENT_HOME" SHELL="$SHELL_BIN" CMDABC_SHELL="$kind" \
      "$PACKAGE_ROOT/install.sh" >/dev/null
  else
    HOME="$ABSENT_HOME" SHELL="$SHELL_BIN" CMDABC_SHELL="$kind" ZDOTDIR="$RC_PARENT" \
      "$PACKAGE_ROOT/install.sh" >/dev/null
  fi
  printf 'package.%s echo PRESERVE\n' "$kind" \
    > "$ABSENT_HOME/.cmdabc-data/command-library.txt"
  cp "$ABSENT_HOME/.cmdabc-data/command-library.txt" "$TMP_DIR/package-$kind-library-before"
  if [ "$kind" = bash ]; then
    HOME="$ABSENT_HOME" SHELL="$SHELL_BIN" CMDABC_SHELL="$kind" \
      "$PACKAGE_ROOT/install.sh" >/dev/null
  else
    HOME="$ABSENT_HOME" SHELL="$SHELL_BIN" CMDABC_SHELL="$kind" ZDOTDIR="$RC_PARENT" \
      "$PACKAGE_ROOT/install.sh" >/dev/null
  fi
  assert_eq "$(block_count "$RC_PATH")" 1 "$kind absent rc package block count"
  assert_eq "$(created_marker_count "$RC_PATH")" 1 \
    "$kind absent rc package created marker count"
  if [ "$kind" = bash ]; then
    HOME="$ABSENT_HOME" SHELL="$SHELL_BIN" CMDABC_SHELL="$kind" \
      "$ABSENT_HOME/.cmdabc/uninstall.sh" >/dev/null
  else
    HOME="$ABSENT_HOME" SHELL="$SHELL_BIN" CMDABC_SHELL="$kind" ZDOTDIR="$RC_PARENT" \
      "$ABSENT_HOME/.cmdabc/uninstall.sh" >/dev/null
  fi
  assert_not_exists "$RC_PATH"
  assert_dir "$ABSENT_HOME/.cmdabc-data"
  cmp "$TMP_DIR/package-$kind-library-before" \
    "$ABSENT_HOME/.cmdabc-data/command-library.txt" \
    || fail "$kind absent rc package cycle changed user data"
done

RELEASE_HOME=$TMP_DIR/release-home
mkdir -p "$RELEASE_HOME"
printf 'export CMDABC_RELEASE_SENTINEL=yes\n' > "$RELEASE_HOME/.bashrc"
cp "$RELEASE_HOME/.bashrc" "$TMP_DIR/bashrc-before"
HOME="$RELEASE_HOME" SHELL=/bin/bash CMDABC_SHELL=bash "$PACKAGE_ROOT/install.sh" >/dev/null

assert_file "$RELEASE_HOME/.cmdabc/cmdabc"
assert_file "$RELEASE_HOME/.cmdabc/uninstall.sh"
assert_file "$RELEASE_HOME/.cmdabc/shell/cmdabc.bash"
assert_file "$RELEASE_HOME/.cmdabc/shell/cmdabc.zsh"
assert_file "$RELEASE_HOME/.cmdabc/VERSION"
assert_dir "$RELEASE_HOME/.cmdabc-data"
assert_file "$RELEASE_HOME/.cmdabc-data/command-library.txt"
[ ! -s "$RELEASE_HOME/.cmdabc-data/command-library.txt" ] \
  || fail 'release install did not create an empty command library'
assert_eq "$(block_count "$RELEASE_HOME/.bashrc")" 1 'release install rc block count'
assert_eq "$(HOME="$RELEASE_HOME" "$RELEASE_HOME/.cmdabc/cmdabc" --version)" \
  0.3.0 'installed release runtime version'

RUNTIME=$RELEASE_HOME/.cmdabc/cmdabc
LIBRARY=$RELEASE_HOME/.cmdabc-data/command-library.txt
HELP_OUTPUT=$(HOME="$RELEASE_HOME" "$RUNTIME" --help)
printf '%s\n' "$HELP_OUTPUT" | grep -F '/abc.' >/dev/null \
  || fail 'release help omits the guided management entry'
if printf '%s\n' "$HELP_OUTPUT" \
  | grep -E 'cmdabc (add|manage|pick|children|internal-list)|/abc\.(add|del|update|help|list)' \
    >/dev/null; then
  fail 'release help exposes a removed route or internal helper'
fi
assert_eq "$(HOME="$RELEASE_HOME" "$RUNTIME" internal-list --library "$LIBRARY")" \
  '0 commands, 0 invalid' 'empty installed command library list'

for removed_input in \
  '/abc.add' \
  '/abc.add.release.payload echo NO' \
  '/abc.del.release.payload' \
  '/abc.update.release.payload echo NO' \
  '/abc.help' \
  '/abc.list'; do
  assert_rejected_management_route "$removed_input"
done

cp "$LIBRARY" "$TMP_DIR/public-add-before"
if HOME="$RELEASE_HOME" "$RUNTIME" add --library "$LIBRARY" \
  > "$TMP_DIR/public-add-stdout" 2> "$TMP_DIR/public-add-stderr"; then
  fail 'standalone cmdabc add succeeded in the release'
else
  public_add_status=$?
fi
assert_eq "$public_add_status" 2 'standalone cmdabc add status'
[ ! -s "$TMP_DIR/public-add-stdout" ] \
  || fail 'standalone cmdabc add wrote to stdout'
assert_eq "$(sed -n '1p' "$TMP_DIR/public-add-stderr")" \
  '[error: unknown command: add]' 'standalone cmdabc add rejection'
if grep -E 'cmdabc (add|manage|pick|children|internal-list)|/abc\.(add|del|update|help|list)' \
  "$TMP_DIR/public-add-stderr" >/dev/null; then
  fail 'standalone cmdabc add error advertised a removed route or internal helper'
fi
cmp "$TMP_DIR/public-add-before" "$LIBRARY" \
  || fail 'standalone cmdabc add changed user data'

# Run the real shell widgets from the installed release, with isolated fixtures.
PICKER_PAYLOAD=$'printf \'%s\' "$HOME" | cat && :; : >x\\ y'
for kind in zsh bash; do
  PICKER_LIBRARY=$TMP_DIR/$kind-picker-library.txt
  PICKER_MARKER=$TMP_DIR/$kind-picker-must-not-exist
  printf 'test.one echo ONE\ntest.group.two echo TWO\ntest.group.three echo THREE\nfidelity.payload %s\n' \
    "$PICKER_PAYLOAD" > "$PICKER_LIBRARY"
  if [ "$kind" = zsh ]; then
    SHELL_BIN=$(command -v zsh)
  else
    SHELL_BIN=$BASH52_BIN
  fi
  expect "$WIDGET_EXPECT" "$kind" "$SHELL_BIN" "$RELEASE_HOME/.cmdabc" \
    "$PICKER_LIBRARY" "$PICKER_MARKER" "$PICKER_PAYLOAD" >/dev/null
  [ ! -e "$PICKER_MARKER" ] || fail "$kind release picker executed a payload"
done

# Uninstall removes only the program/managed block. Reinstall must adopt the
# exact surviving database bytes.
printf 'persistent.keep printf "KEEP  BYTES"\n\n# trailing data' > "$LIBRARY"
cp "$LIBRARY" "$TMP_DIR/library-before-uninstall"
HOME="$RELEASE_HOME" SHELL=/bin/bash CMDABC_SHELL=bash \
  "$RELEASE_HOME/.cmdabc/uninstall.sh" >/dev/null
assert_not_exists "$RELEASE_HOME/.cmdabc"
assert_dir "$RELEASE_HOME/.cmdabc-data"
cmp "$TMP_DIR/library-before-uninstall" "$LIBRARY" \
  || fail 'release uninstall changed user data'
cmp "$TMP_DIR/bashrc-before" "$RELEASE_HOME/.bashrc" \
  || fail 'release uninstall changed rc content outside its managed block'

HOME="$RELEASE_HOME" SHELL=/bin/bash CMDABC_SHELL=bash "$PACKAGE_ROOT/install.sh" >/dev/null
cmp "$TMP_DIR/library-before-uninstall" "$LIBRARY" \
  || fail 'release reinstall changed existing user data'
assert_eq "$(block_count "$RELEASE_HOME/.bashrc")" 1 'release reinstall rc block count'
assert_eq "$(HOME="$RELEASE_HOME" "$RELEASE_HOME/.cmdabc/cmdabc" internal-list --library "$LIBRARY")" \
  $'persistent.keep printf "KEEP  BYTES"\n\n1 commands, 0 invalid' \
  'release reinstall did not reuse user data'

printf 'PASS: CmdABC 0.3.0 release archive checks\n'
printf 'Build 1 SHA-256: %s\nBuild 2 SHA-256: %s\n' \
  "$FIRST_BUILD_SHA" "$SECOND_BUILD_SHA"
