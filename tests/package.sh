#!/usr/bin/env bash

set -euo pipefail

TEST_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
REPO_DIR=${TEST_DIR%/tests}
PACKAGE_SCRIPT=$REPO_DIR/scripts/package.sh
ARCHIVE=$REPO_DIR/artifacts/CmdABC-0.1.0.tar.gz
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
"$PACKAGE_SCRIPT" >/dev/null
cmp "$TMP_DIR/first.tar.gz" "$ARCHIVE" || fail 'repeated build changed archive bytes'
cmp "$TMP_DIR/first.tar.gz.sha256" "$CHECKSUM" || fail 'repeated build changed checksum file'

EXPECTED_SHA=$(awk 'NR == 1 { print $1 }' "$CHECKSUM")
EXPECTED_NAME=$(awk 'NR == 1 { print $2 }' "$CHECKSUM")
assert_eq "$EXPECTED_NAME" 'CmdABC-0.1.0.tar.gz' 'checksum filename'
assert_eq "$(sha256_file "$ARCHIVE")" "$EXPECTED_SHA" 'archive SHA-256'

EXPECTED_LIST=$(printf '%s\n' \
  'CmdABC-0.1.0/' \
  'CmdABC-0.1.0/cmdabc' \
  'CmdABC-0.1.0/install.sh' \
  'CmdABC-0.1.0/uninstall.sh' \
  'CmdABC-0.1.0/VERSION' \
  'CmdABC-0.1.0/README.md' \
  'CmdABC-0.1.0/shell/' \
  'CmdABC-0.1.0/shell/cmdabc.bash' \
  'CmdABC-0.1.0/shell/cmdabc.zsh')
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
COPYFILE_DISABLE=1 tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"
PACKAGE_ROOT=$EXTRACT_DIR/CmdABC-0.1.0

assert_dir "$PACKAGE_ROOT"
assert_dir "$PACKAGE_ROOT/shell"
assert_eq "$(file_mode "$PACKAGE_ROOT")" 755 'package root mode'
assert_eq "$(file_mode "$PACKAGE_ROOT/shell")" 755 'shell directory mode'
for path in cmdabc install.sh uninstall.sh; do
  assert_eq "$(file_mode "$PACKAGE_ROOT/$path")" 755 "$path mode"
done
for path in VERSION README.md shell/cmdabc.bash shell/cmdabc.zsh; do
  assert_eq "$(file_mode "$PACKAGE_ROOT/$path")" 644 "$path mode"
done
if find "$PACKAGE_ROOT" -type l -print | grep -q .; then
  fail 'extracted package contains a symlink'
fi
if grep -R -F '/Users/sweetcolin/LocalCodex/CmdABC' "$PACKAGE_ROOT" >/dev/null; then
  fail 'package contains the development repository absolute path'
fi
assert_eq "$(sed -n '1p' "$PACKAGE_ROOT/VERSION")" 0.1.0 'package VERSION'
assert_eq "$(HOME="$TMP_DIR/version-home" "$PACKAGE_ROOT/cmdabc" --version)" \
  0.1.0 'package runtime version'

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
  0.1.0 'installed release runtime version'

RUNTIME=$RELEASE_HOME/.cmdabc/cmdabc
LIBRARY=$RELEASE_HOME/.cmdabc-data/command-library.txt
HELP_OUTPUT=$(HOME="$RELEASE_HOME" "$RUNTIME" manage --input /abc.help)
printf '%s\n' "$HELP_OUTPUT" | grep -F '/abc.add.<target> <command>' >/dev/null \
  || fail 'release /abc.help is incomplete'

NOEXEC_MARKER=$RELEASE_HOME/release-payload-must-not-exist
ADD_PAYLOAD="printf '%s' \"\$HOME\" | cat && touch \"$NOEXEC_MARKER\"; printf '%s' value\\ with\\ spaces"
assert_eq "$(HOME="$RELEASE_HOME" "$RUNTIME" manage \
  --input "/abc.add.release.payload $ADD_PAYLOAD")" \
  'Added: release.payload' 'release /abc.add'
[ ! -e "$NOEXEC_MARKER" ] || fail 'release /abc.add executed its payload'
grep -Fx "release.payload $ADD_PAYLOAD" "$LIBRARY" >/dev/null \
  || fail 'release /abc.add changed payload text'
LIST_OUTPUT=$(HOME="$RELEASE_HOME" "$RUNTIME" manage --input /abc.list)
printf '%s\n' "$LIST_OUTPUT" | grep -Fx "release.payload $ADD_PAYLOAD" >/dev/null \
  || fail 'release /abc.list changed payload text'

UPDATE_PAYLOAD="echo \"\$USER\" | cat && touch \"$NOEXEC_MARKER\"; : >value\\ two"
assert_eq "$(HOME="$RELEASE_HOME" "$RUNTIME" manage \
  --input "/abc.update.release.payload $UPDATE_PAYLOAD")" \
  'Updated: release.payload' 'release /abc.update'
[ ! -e "$NOEXEC_MARKER" ] || fail 'release /abc.update executed its payload'
grep -Fx "release.payload $UPDATE_PAYLOAD" "$LIBRARY" >/dev/null \
  || fail 'release /abc.update changed payload text'
assert_eq "$(HOME="$RELEASE_HOME" "$RUNTIME" manage --input /abc.del.release.payload)" \
  'Deleted: release.payload' 'release /abc.del'
[ ! -s "$LIBRARY" ] || fail 'release /abc.del did not remove its target'

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
assert_eq "$(HOME="$RELEASE_HOME" "$RELEASE_HOME/.cmdabc/cmdabc" manage --input /abc.list)" \
  $'1 user commands\npersistent.keep printf "KEEP  BYTES"' \
  'release reinstall did not reuse user data'

printf 'PASS: CmdABC 0.1.0 release archive checks\n'
