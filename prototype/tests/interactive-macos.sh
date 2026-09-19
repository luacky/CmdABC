#!/usr/bin/env bash

set -eu

TEST_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
PROTOTYPE_DIR=${TEST_DIR%/tests}
EXPECT_SCRIPT=$TEST_DIR/widget.expect
TREE_EXPECT_SCRIPT=$TEST_DIR/tree-picker.expect
TREE_LIBRARY=$TEST_DIR/tree-library.txt
PREVIEW_EXPECT_SCRIPT=$TEST_DIR/preview.expect
PREVIEW_LIBRARY=$TEST_DIR/preview-library.txt
INVALID_EXPECT_SCRIPT=$TEST_DIR/invalid-entry.expect
TOLERANT_LIBRARY=$TEST_DIR/tolerant-library.txt
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cmdabc-interactive.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT
ZSH_LIBRARY=$TMP_DIR/zsh-library.txt
BASH_LIBRARY=$TMP_DIR/bash-library.txt
ZSH_NOEXEC_MARKER=$TMP_DIR/zsh-must-not-exist
BASH_NOEXEC_MARKER=$TMP_DIR/bash-must-not-exist
PICKER_FIDELITY_PAYLOAD=$'printf \'%s\' "$HOME" | cat && :; : >x\\ y'
cp "$PROTOTYPE_DIR/command-library.txt" "$ZSH_LIBRARY"
cp "$PROTOTYPE_DIR/command-library.txt" "$BASH_LIBRARY"
printf 'fidelity.payload %s\n' "$PICKER_FIDELITY_PAYLOAD" >> "$ZSH_LIBRARY"
printf 'fidelity.payload %s\n' "$PICKER_FIDELITY_PAYLOAD" >> "$BASH_LIBRARY"

command -v expect >/dev/null 2>&1 || {
  printf 'SKIP: expect is not installed\n'
  exit 0
}

printf 'Running leaf-preview rendering acceptance...\n'
expect "$PREVIEW_EXPECT_SCRIPT" "$PROTOTYPE_DIR/cmdabc" "$PREVIEW_LIBRARY"

printf 'Running zsh 5.9 interactive acceptance...\n'
expect "$EXPECT_SCRIPT" zsh "$(command -v zsh)" "$PROTOTYPE_DIR" "$ZSH_LIBRARY" "$ZSH_NOEXEC_MARKER" "$PICKER_FIDELITY_PAYLOAD"
[ ! -e "$ZSH_NOEXEC_MARKER" ] || {
  printf 'FAIL: zsh management payload was executed\n' >&2
  exit 1
}
printf 'Running zsh 5.9 invalid-entry recovery acceptance...\n'
expect "$INVALID_EXPECT_SCRIPT" zsh "$(command -v zsh)" "$PROTOTYPE_DIR" "$TOLERANT_LIBRARY"

BASH_BIN=${CMDABC_BASH52_BIN:-}
if [ -z "$BASH_BIN" ]; then
  for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [ -x "$candidate" ] && "$candidate" --version | sed -n '1p' | grep -F 'version 5.2.' >/dev/null; then
      BASH_BIN=$candidate
      break
    fi
  done
fi

if [ -z "$BASH_BIN" ]; then
  printf 'PASS: zsh 5.9 interactive check\n'
  printf 'SKIP: Bash 5.2 not found; set CMDABC_BASH52_BIN to run target acceptance\n'
  exit 0
fi

[ -x "$BASH_BIN" ] || {
  printf 'FAIL: CMDABC_BASH52_BIN is not executable: %s\n' "$BASH_BIN" >&2
  exit 1
}
BASH_VERSION_LINE=$($BASH_BIN --version | sed -n '1p')
case "$BASH_VERSION_LINE" in
  *'version 5.2.'*) ;;
  *)
    printf 'FAIL: target acceptance requires Bash 5.2.x, got: %s\n' "$BASH_VERSION_LINE" >&2
    exit 1
    ;;
esac

printf 'Running Bash 5.2 interactive acceptance with: %s\n' "$BASH_VERSION_LINE"
expect "$EXPECT_SCRIPT" bash "$BASH_BIN" "$PROTOTYPE_DIR" "$BASH_LIBRARY" "$BASH_NOEXEC_MARKER" "$PICKER_FIDELITY_PAYLOAD"
[ ! -e "$BASH_NOEXEC_MARKER" ] || {
  printf 'FAIL: Bash management payload was executed\n' >&2
  exit 1
}
printf 'Running Bash 5.2 invalid-entry recovery acceptance...\n'
expect "$INVALID_EXPECT_SCRIPT" bash "$BASH_BIN" "$PROTOTYPE_DIR" "$TOLERANT_LIBRARY"
printf 'Running Bash 5.2 multi-level tree-picker acceptance...\n'
expect "$TREE_EXPECT_SCRIPT" "$BASH_BIN" "$PROTOTYPE_DIR" "$TREE_LIBRARY"
printf 'PASS: Bash 5.2 target and zsh 5.9 interactive checks\n'
