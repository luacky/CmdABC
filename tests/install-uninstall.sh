#!/usr/bin/env bash

set -eu

TEST_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
REPO_DIR=${TEST_DIR%/tests}
INSTALLER=$REPO_DIR/install.sh
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cmdabc-c01.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
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

assert_eq() {
  [ "$1" = "$2" ] || fail "$3 (expected <$2>, got <$1>)"
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "$3 (missing <$2>)" ;;
  esac
}

install_bash() {
  HOME=$1 SHELL=/bin/bash CMDABC_SHELL=bash "$INSTALLER" >/dev/null
}

uninstall_bash() {
  HOME=$1 SHELL=/bin/bash CMDABC_SHELL=bash "$1/.cmdabc/uninstall.sh" >/dev/null
}

block_count() {
  awk '$0 == "# >>> CmdABC >>>" { count += 1 } END { print count + 0 }' "$1"
}

created_marker_count() {
  awk '$0 == "# CmdABC-RC-CREATED-BY-INSTALLER" { count += 1 } END { print count + 0 }' "$1"
}

install_for_shell() {
  local kind=$1
  local home=$2
  local rc_parent=$3

  if [ "$kind" = bash ]; then
    HOME="$home" SHELL=/bin/bash CMDABC_SHELL=bash "$INSTALLER" >/dev/null
  else
    HOME="$home" SHELL=$(command -v zsh) CMDABC_SHELL=zsh ZDOTDIR="$rc_parent" \
      "$INSTALLER" >/dev/null
  fi
}

uninstall_for_shell() {
  local kind=$1
  local home=$2
  local rc_parent=$3

  if [ "$kind" = bash ]; then
    HOME="$home" SHELL=/bin/bash CMDABC_SHELL=bash "$home/.cmdabc/uninstall.sh" >/dev/null
  else
    HOME="$home" SHELL=$(command -v zsh) CMDABC_SHELL=zsh ZDOTDIR="$rc_parent" \
      "$home/.cmdabc/uninstall.sh" >/dev/null
  fi
}

run_rc_ownership_checks() {
  local kind=$1
  local case_home rc_parent rc_path before changed

  case_home=$TMP_DIR/$kind-absent-rc-home
  if [ "$kind" = bash ]; then
    rc_parent=$case_home
    rc_path=$case_home/.bashrc
  else
    rc_parent=$case_home/config/zsh
    rc_path=$rc_parent/.zshrc
  fi
  mkdir -p "$rc_parent"
  assert_not_exists "$rc_path"
  install_for_shell "$kind" "$case_home" "$rc_parent"
  assert_eq "$(block_count "$rc_path")" 1 "$kind absent rc block count"
  assert_eq "$(created_marker_count "$rc_path")" 1 "$kind absent rc created marker count"
  install_for_shell "$kind" "$case_home" "$rc_parent"
  assert_eq "$(block_count "$rc_path")" 1 "$kind repeated install block count"
  assert_eq "$(created_marker_count "$rc_path")" 1 "$kind repeated install created marker count"
  uninstall_for_shell "$kind" "$case_home" "$rc_parent"
  assert_not_exists "$rc_path"
  assert_file "$case_home/.cmdabc-data/command-library.txt"

  case_home=$TMP_DIR/$kind-empty-rc-home
  if [ "$kind" = bash ]; then
    rc_parent=$case_home
    rc_path=$case_home/.bashrc
  else
    rc_parent=$case_home/config/zsh
    rc_path=$rc_parent/.zshrc
  fi
  mkdir -p "$rc_parent"
  : > "$rc_path"
  install_for_shell "$kind" "$case_home" "$rc_parent"
  assert_eq "$(created_marker_count "$rc_path")" 0 "$kind empty pre-existing rc marker count"
  uninstall_for_shell "$kind" "$case_home" "$rc_parent"
  assert_file "$rc_path"
  [ ! -s "$rc_path" ] || fail "$kind empty pre-existing rc was not restored"

  case_home=$TMP_DIR/$kind-content-rc-home
  before=$TMP_DIR/$kind-content-rc-before
  if [ "$kind" = bash ]; then
    rc_parent=$case_home
    rc_path=$case_home/.bashrc
  else
    rc_parent=$case_home/config/zsh
    rc_path=$rc_parent/.zshrc
  fi
  mkdir -p "$rc_parent"
  printf 'export CMDABC_%s_SENTINEL=yes' "$kind" > "$rc_path"
  cp "$rc_path" "$before"
  install_for_shell "$kind" "$case_home" "$rc_parent"
  install_for_shell "$kind" "$case_home" "$rc_parent"
  assert_eq "$(block_count "$rc_path")" 1 "$kind ordinary repeated install block count"
  assert_eq "$(created_marker_count "$rc_path")" 0 "$kind ordinary repeated install marker count"
  uninstall_for_shell "$kind" "$case_home" "$rc_parent"
  cmp "$before" "$rc_path" || fail "$kind pre-existing rc was not restored byte-for-byte"

  case_home=$TMP_DIR/$kind-later-content-home
  if [ "$kind" = bash ]; then
    rc_parent=$case_home
    rc_path=$case_home/.bashrc
  else
    rc_parent=$case_home/config/zsh
    rc_path=$rc_parent/.zshrc
  fi
  mkdir -p "$rc_parent"
  install_for_shell "$kind" "$case_home" "$rc_parent"
  printf 'export CMDABC_%s_AFTER_INSTALL=yes\n' "$kind" >> "$rc_path"
  uninstall_for_shell "$kind" "$case_home" "$rc_parent"
  assert_file "$rc_path"
  assert_eq "$(cat "$rc_path")" "export CMDABC_${kind}_AFTER_INSTALL=yes" \
    "$kind user content added after install"
  assert_eq "$(block_count "$rc_path")" 0 "$kind block removal with later content"
  assert_eq "$(created_marker_count "$rc_path")" 0 "$kind marker removal with later content"

  case_home=$TMP_DIR/$kind-modified-created-marker-home
  changed=$TMP_DIR/$kind-modified-created-marker-before
  if [ "$kind" = bash ]; then
    rc_parent=$case_home
    rc_path=$case_home/.bashrc
  else
    rc_parent=$case_home/config/zsh
    rc_path=$rc_parent/.zshrc
  fi
  mkdir -p "$rc_parent"
  install_for_shell "$kind" "$case_home" "$rc_parent"
  sed 's/^# CmdABC-RC-CREATED-BY-INSTALLER$/# CmdABC-RC-CREATED-BY-INSTALLER-EDITED/' \
    "$rc_path" > "$rc_path.changed"
  mv "$rc_path.changed" "$rc_path"
  cp "$rc_path" "$changed"
  if uninstall_for_shell "$kind" "$case_home" "$rc_parent" 2>/dev/null; then
    fail "$kind uninstaller accepted a modified created marker"
  fi
  cmp "$changed" "$rc_path" || fail "$kind failed uninstall changed user rc content"
  assert_dir "$case_home/.cmdabc"
  assert_file "$case_home/.cmdabc-data/command-library.txt"
}

run_rc_ownership_checks bash
if command -v zsh >/dev/null 2>&1; then
  run_rc_ownership_checks zsh
fi

# Fresh install: create the program, empty data file, and exactly one block.
FRESH_HOME=$TMP_DIR/fresh-home
mkdir -p "$FRESH_HOME"
printf 'export CMDABC_USER_SENTINEL=fresh\n' > "$FRESH_HOME/.bashrc"
cp "$FRESH_HOME/.bashrc" "$TMP_DIR/fresh-rc-before"
FRESH_INSTALL_OUTPUT=$(HOME="$FRESH_HOME" SHELL=/bin/bash CMDABC_SHELL=bash "$INSTALLER")

assert_contains "$FRESH_INSTALL_OUTPUT" \
  'Existing bash sessions keep any previously loaded CmdABC shell functions.' \
  'fresh install warns about already-running shell sessions'
assert_contains "$FRESH_INSTALL_OUTPUT" \
  'Open a new bash shell, or activate this install in the current shell with:' \
  'fresh install gives activation choices'
assert_contains "$FRESH_INSTALL_OUTPUT" \
  'source "$HOME/.cmdabc/shell/cmdabc.bash"' \
  'fresh install prints the current-shell reload command'

assert_file "$FRESH_HOME/.cmdabc/cmdabc"
assert_file "$FRESH_HOME/.cmdabc/uninstall.sh"
assert_file "$FRESH_HOME/.cmdabc/shell/cmdabc.bash"
assert_file "$FRESH_HOME/.cmdabc/shell/cmdabc.zsh"
assert_file "$FRESH_HOME/.cmdabc/VERSION"
assert_dir "$FRESH_HOME/.cmdabc-data"
assert_file "$FRESH_HOME/.cmdabc-data/command-library.txt"
cmp "$REPO_DIR/prototype/cmdabc" "$FRESH_HOME/.cmdabc/cmdabc" \
  || fail 'installed runtime differs from repository payload'
cmp "$REPO_DIR/prototype/shell/cmdabc.bash" "$FRESH_HOME/.cmdabc/shell/cmdabc.bash" \
  || fail 'installed Bash integration differs from repository payload'
cmp "$REPO_DIR/prototype/shell/cmdabc.zsh" "$FRESH_HOME/.cmdabc/shell/cmdabc.zsh" \
  || fail 'installed zsh integration differs from repository payload'
[ ! -s "$FRESH_HOME/.cmdabc-data/command-library.txt" ] || fail 'fresh command library is not empty'
assert_eq "$(block_count "$FRESH_HOME/.bashrc")" 1 'fresh install block count'
assert_eq "$(HOME="$FRESH_HOME" "$FRESH_HOME/.cmdabc/cmdabc" --version)" 0.1.0 'installed runtime version'
assert_eq "$(sed -n '1p' "$FRESH_HOME/.cmdabc/VERSION")" 0.1.0 'installed VERSION'
assert_eq "$(HOME="$FRESH_HOME" CMDABC_LIBRARY= "$FRESH_HOME/.cmdabc/cmdabc" validate)" \
  'OK: 0 command records' 'empty default library validates'

# Reinstall overwrites broken program files, but preserves user data byte-for-byte.
printf 'user.real echo PRESERVE ME\n# bytes after this line matter\n' \
  > "$FRESH_HOME/.cmdabc-data/command-library.txt"
cp "$FRESH_HOME/.cmdabc-data/command-library.txt" "$TMP_DIR/fresh-library-before"
printf 'BROKEN RUNTIME\n' > "$FRESH_HOME/.cmdabc/cmdabc"
rm -f "$FRESH_HOME/.cmdabc/shell/cmdabc.zsh"
install_bash "$FRESH_HOME"
cmp "$TMP_DIR/fresh-library-before" "$FRESH_HOME/.cmdabc-data/command-library.txt" \
  || fail 'reinstall changed user data'
assert_eq "$(block_count "$FRESH_HOME/.bashrc")" 1 'reinstall block count'
assert_eq "$(HOME="$FRESH_HOME" "$FRESH_HOME/.cmdabc/cmdabc" --version)" 0.1.0 'reinstalled runtime version'
assert_file "$FRESH_HOME/.cmdabc/shell/cmdabc.zsh"

# Uninstall removes only the managed block/program and preserves rc/user data.
uninstall_bash "$FRESH_HOME"
assert_not_exists "$FRESH_HOME/.cmdabc"
assert_dir "$FRESH_HOME/.cmdabc-data"
cmp "$TMP_DIR/fresh-library-before" "$FRESH_HOME/.cmdabc-data/command-library.txt" \
  || fail 'uninstall changed user data'
cmp "$TMP_DIR/fresh-rc-before" "$FRESH_HOME/.bashrc" \
  || fail 'uninstall changed rc content outside the managed block'

# Reinstall after uninstall reuses the exact existing data.
install_bash "$FRESH_HOME"
cmp "$TMP_DIR/fresh-library-before" "$FRESH_HOME/.cmdabc-data/command-library.txt" \
  || fail 'install after uninstall changed user data'
assert_eq "$(block_count "$FRESH_HOME/.bashrc")" 1 'install-after-uninstall block count'

# User rc content added after installation survives precise block removal.
printf 'export CMDABC_USER_AFTER_INSTALL=yes\n' >> "$FRESH_HOME/.bashrc"
cp "$TMP_DIR/fresh-rc-before" "$TMP_DIR/fresh-rc-with-later-content"
printf 'export CMDABC_USER_AFTER_INSTALL=yes\n' >> "$TMP_DIR/fresh-rc-with-later-content"
uninstall_bash "$FRESH_HOME"
cmp "$TMP_DIR/fresh-rc-with-later-content" "$FRESH_HOME/.bashrc" \
  || fail 'uninstall changed user rc content added after installation'
cmp "$TMP_DIR/fresh-library-before" "$FRESH_HOME/.cmdabc-data/command-library.txt" \
  || fail 'second uninstall changed user data'

# A pre-existing database is adopted without any byte changes.
EXISTING_HOME=$TMP_DIR/existing-data-home
mkdir -p "$EXISTING_HOME/.cmdabc-data"
printf 'existing.path printf "EXISTING  DATA"\n\n# keep trailing bytes' \
  > "$EXISTING_HOME/.cmdabc-data/command-library.txt"
cp "$EXISTING_HOME/.cmdabc-data/command-library.txt" "$TMP_DIR/existing-library-before"
install_bash "$EXISTING_HOME"
cmp "$TMP_DIR/existing-library-before" "$EXISTING_HOME/.cmdabc-data/command-library.txt" \
  || fail 'install changed pre-existing user data'
uninstall_bash "$EXISTING_HOME"
cmp "$TMP_DIR/existing-library-before" "$EXISTING_HOME/.cmdabc-data/command-library.txt" \
  || fail 'uninstall changed pre-existing user data'

# A pre-existing rc without a trailing newline is restored byte-for-byte.
NO_NEWLINE_HOME=$TMP_DIR/no-newline-home
mkdir -p "$NO_NEWLINE_HOME"
printf 'export CMDABC_NO_NEWLINE=yes' > "$NO_NEWLINE_HOME/.bashrc"
cp "$NO_NEWLINE_HOME/.bashrc" "$TMP_DIR/no-newline-rc-before"
install_bash "$NO_NEWLINE_HOME"
uninstall_bash "$NO_NEWLINE_HOME"
cmp "$TMP_DIR/no-newline-rc-before" "$NO_NEWLINE_HOME/.bashrc" \
  || fail 'uninstall changed an rc file without a trailing newline'

# An interrupted/partial program directory is repaired by reinstall.
PARTIAL_HOME=$TMP_DIR/partial-home
mkdir -p "$PARTIAL_HOME/.cmdabc/shell" "$PARTIAL_HOME/.cmdabc-data"
printf 'partial user data\n' > "$PARTIAL_HOME/.cmdabc-data/command-library.txt"
cp "$PARTIAL_HOME/.cmdabc-data/command-library.txt" "$TMP_DIR/partial-library-before"
printf 'partial\n' > "$PARTIAL_HOME/.cmdabc/cmdabc"
install_bash "$PARTIAL_HOME"
assert_eq "$(HOME="$PARTIAL_HOME" "$PARTIAL_HOME/.cmdabc/cmdabc" --version)" 0.1.0 'partial install recovery version'
assert_file "$PARTIAL_HOME/.cmdabc/uninstall.sh"
assert_file "$PARTIAL_HOME/.cmdabc/shell/cmdabc.bash"
assert_file "$PARTIAL_HOME/.cmdabc/shell/cmdabc.zsh"
cmp "$TMP_DIR/partial-library-before" "$PARTIAL_HOME/.cmdabc-data/command-library.txt" \
  || fail 'partial install recovery changed user data'

# Explicit CMDABC_LIBRARY continues to override the default data path.
assert_eq "$(HOME="$PARTIAL_HOME" CMDABC_LIBRARY="$REPO_DIR/prototype/command-library.txt" \
  "$PARTIAL_HOME/.cmdabc/cmdabc" validate)" \
  'OK: 3 command records' 'explicit CMDABC_LIBRARY override'

# The installer also works from the future release-package root layout.
PACKAGE_DIR=$TMP_DIR/CmdABC
PACKAGE_HOME=$TMP_DIR/package-home
mkdir -p "$PACKAGE_DIR/shell" "$PACKAGE_HOME"
cp "$REPO_DIR/prototype/cmdabc" "$PACKAGE_DIR/cmdabc"
cp "$REPO_DIR/prototype/shell/cmdabc.bash" "$PACKAGE_DIR/shell/cmdabc.bash"
cp "$REPO_DIR/prototype/shell/cmdabc.zsh" "$PACKAGE_DIR/shell/cmdabc.zsh"
cp "$REPO_DIR/install.sh" "$PACKAGE_DIR/install.sh"
cp "$REPO_DIR/uninstall.sh" "$PACKAGE_DIR/uninstall.sh"
cp "$REPO_DIR/VERSION" "$PACKAGE_DIR/VERSION"
chmod 755 "$PACKAGE_DIR/cmdabc" "$PACKAGE_DIR/install.sh" "$PACKAGE_DIR/uninstall.sh"
HOME="$PACKAGE_HOME" SHELL=/bin/bash CMDABC_SHELL=bash "$PACKAGE_DIR/install.sh" >/dev/null
assert_eq "$(HOME="$PACKAGE_HOME" "$PACKAGE_HOME/.cmdabc/cmdabc" --version)" \
  0.1.0 'release-layout installed version'
uninstall_bash "$PACKAGE_HOME"
assert_dir "$PACKAGE_HOME/.cmdabc-data"
assert_not_exists "$PACKAGE_HOME/.bashrc"

# zsh registration honors an explicit custom ZDOTDIR under HOME.
if command -v zsh >/dev/null 2>&1; then
  ZSH_HOME=$TMP_DIR/zsh-home
  ZSH_DOT=$ZSH_HOME/config/zsh
  mkdir -p "$ZSH_DOT"
  printf 'typeset -g CMDABC_ZSH_SENTINEL=yes\n' > "$ZSH_DOT/.zshrc"
  cp "$ZSH_DOT/.zshrc" "$TMP_DIR/zsh-rc-before"
  ZSH_INSTALL_OUTPUT=$(HOME="$ZSH_HOME" SHELL=$(command -v zsh) CMDABC_SHELL=zsh \
    ZDOTDIR="$ZSH_DOT" "$INSTALLER")
  assert_contains "$ZSH_INSTALL_OUTPUT" \
    'Existing zsh sessions keep any previously loaded CmdABC shell functions.' \
    'zsh install warns about already-running shell sessions'
  assert_contains "$ZSH_INSTALL_OUTPUT" \
    'source "$HOME/.cmdabc/shell/cmdabc.zsh"' \
    'zsh install prints the current-shell reload command'
  assert_eq "$(block_count "$ZSH_DOT/.zshrc")" 1 'custom ZDOTDIR block count'
  HOME="$ZSH_HOME" SHELL=$(command -v zsh) ZDOTDIR="$ZSH_DOT" \
    "$ZSH_HOME/.cmdabc/uninstall.sh" >/dev/null
  cmp "$TMP_DIR/zsh-rc-before" "$ZSH_DOT/.zshrc" \
    || fail 'zsh uninstall changed rc outside the managed block'
  assert_dir "$ZSH_HOME/.cmdabc-data"
fi

# Malformed markers fail closed and do not create a duplicate block.
CONFLICT_HOME=$TMP_DIR/conflict-home
mkdir -p "$CONFLICT_HOME"
printf '# user content\n# >>> CmdABC >>>\n' > "$CONFLICT_HOME/.bashrc"
if install_bash "$CONFLICT_HOME" 2>/dev/null; then
  fail 'installer accepted an incomplete managed block'
fi
assert_eq "$(block_count "$CONFLICT_HOME/.bashrc")" 1 'conflict marker count'

# A modified managed block makes uninstall fail closed; program and data remain.
UNINSTALL_CONFLICT_HOME=$TMP_DIR/uninstall-conflict-home
mkdir -p "$UNINSTALL_CONFLICT_HOME"
install_bash "$UNINSTALL_CONFLICT_HOME"
printf 'conflict.data echo SAFE\n' > "$UNINSTALL_CONFLICT_HOME/.cmdabc-data/command-library.txt"
cp "$UNINSTALL_CONFLICT_HOME/.cmdabc-data/command-library.txt" "$TMP_DIR/uninstall-conflict-library-before"
sed 's|source "$HOME/.cmdabc/shell/cmdabc.bash"|source "$HOME/.cmdabc/shell/cmdabc.bash" # user edit|' \
  "$UNINSTALL_CONFLICT_HOME/.bashrc" > "$UNINSTALL_CONFLICT_HOME/.bashrc.changed"
mv "$UNINSTALL_CONFLICT_HOME/.bashrc.changed" "$UNINSTALL_CONFLICT_HOME/.bashrc"
if uninstall_bash "$UNINSTALL_CONFLICT_HOME" 2>/dev/null; then
  fail 'uninstaller accepted a modified managed block'
fi
assert_dir "$UNINSTALL_CONFLICT_HOME/.cmdabc"
cmp "$TMP_DIR/uninstall-conflict-library-before" \
  "$UNINSTALL_CONFLICT_HOME/.cmdabc-data/command-library.txt" \
  || fail 'failed uninstall changed user data'

printf 'PASS: C01 isolated install/uninstall checks\n'
