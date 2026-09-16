#!/usr/bin/env bash

set -eu

TEST_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
PROTOTYPE_DIR=${TEST_DIR%/tests}
EXPECT_SCRIPT=$TEST_DIR/widget.expect
TREE_EXPECT_SCRIPT=$TEST_DIR/tree-picker.expect
TREE_LIBRARY=$TEST_DIR/tree-library.txt

command -v expect >/dev/null 2>&1 || {
  printf 'SKIP: expect is not installed\n'
  exit 0
}

printf 'Running zsh 5.9 interactive acceptance...\n'
expect "$EXPECT_SCRIPT" zsh "$(command -v zsh)" "$PROTOTYPE_DIR"

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
expect "$EXPECT_SCRIPT" bash "$BASH_BIN" "$PROTOTYPE_DIR"
printf 'Running Bash 5.2 multi-level tree-picker acceptance...\n'
expect "$TREE_EXPECT_SCRIPT" "$BASH_BIN" "$PROTOTYPE_DIR" "$TREE_LIBRARY"
printf 'PASS: Bash 5.2 target and zsh 5.9 interactive checks\n'
