#!/usr/bin/env bash

set -eu

TEST_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
PROTOTYPE_DIR=${TEST_DIR%/tests}
EXPECT_SCRIPT=$TEST_DIR/widget.expect
DEL_EXPECT_SCRIPT=$TEST_DIR/del.expect
ESCAPE_EXPECT_SCRIPT=$TEST_DIR/escape-latency.expect
SUCCESS_SCREEN_EXPECT_SCRIPT=$TEST_DIR/success-screen.expect
TREE_EXPECT_SCRIPT=$TEST_DIR/tree-picker.expect
TREE_LIBRARY=$TEST_DIR/tree-library.txt
PREVIEW_EXPECT_SCRIPT=$TEST_DIR/preview.expect
PREVIEW_LIBRARY=$TEST_DIR/preview-library.txt
INVALID_EXPECT_SCRIPT=$TEST_DIR/invalid-entry.expect
LIST_COLOR_EXPECT_SCRIPT=$TEST_DIR/list-color.expect
TOLERANT_LIBRARY=$TEST_DIR/tolerant-library.txt
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cmdabc-interactive.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT
ZSH_LIBRARY=$TMP_DIR/zsh-library.txt
BASH_LIBRARY=$TMP_DIR/bash-library.txt
ZSH_SUCCESS_LIBRARY=$TMP_DIR/zsh-success-library.txt
BASH_SUCCESS_LIBRARY=$TMP_DIR/bash-success-library.txt
ZSH_DEL_LIBRARY=$TMP_DIR/zsh-del-library.txt
BASH_DEL_LIBRARY=$TMP_DIR/bash-del-library.txt
ZSH_NOEXEC_MARKER=$TMP_DIR/zsh-must-not-exist
BASH_NOEXEC_MARKER=$TMP_DIR/bash-must-not-exist
PICKER_FIDELITY_PAYLOAD=$'printf \'%s\' "$HOME" | cat && :; : >x\\ y'
LIST_HOME=$TMP_DIR/list-home
LIST_COLOR_LIBRARY=$LIST_HOME/.cmdabc-data/command-library.txt
cp "$PROTOTYPE_DIR/command-library.txt" "$ZSH_LIBRARY"
cp "$PROTOTYPE_DIR/command-library.txt" "$BASH_LIBRARY"
cp "$PROTOTYPE_DIR/command-library.txt" "$ZSH_SUCCESS_LIBRARY"
cp "$PROTOTYPE_DIR/command-library.txt" "$BASH_SUCCESS_LIBRARY"
printf '    #screen.test echo test\n' >> "$ZSH_LIBRARY"
printf '    #screen.test echo test\n' >> "$BASH_LIBRARY"
printf 'fidelity.payload %s\n' "$PICKER_FIDELITY_PAYLOAD" >> "$ZSH_LIBRARY"
printf 'fidelity.payload %s\n' "$PICKER_FIDELITY_PAYLOAD" >> "$BASH_LIBRARY"
mkdir -p "$LIST_HOME/.cmdabc-data"
printf '# hidden\nvalid.one echo ONE\nbad.record\ndup.target echo A\ndup.target echo B\ninline.payload echo hello # payload\nvalid.two echo TWO\nvalid.three echo THREE\nvalid.four echo FOUR\n' \
  > "$LIST_COLOR_LIBRARY"
printf '# keep comment\n\naa.aa echo AA\naa.aaa echo AAA\ndemo.invalid\ndup.target echo ONE\ndup.target echo TWO\nkeep.inline echo hello # payload\n' \
  > "$ZSH_DEL_LIBRARY"
cp "$ZSH_DEL_LIBRARY" "$BASH_DEL_LIBRARY"

command -v expect >/dev/null 2>&1 || {
  printf 'SKIP: expect is not installed\n'
  exit 0
}

assert_add_library_clean() {
  local library=$1
  local marker=$2
  local shell_name=$3

  grep -Fx "manage.enter touch $marker" "$library" >/dev/null || {
    printf 'FAIL: %s Add payload was not stored exactly\n' "$shell_name" >&2
    exit 1
  }
  if LC_ALL=C grep -q $'\033' "$library" \
    || grep -F '00~' "$library" >/dev/null \
    || grep -F '01~' "$library" >/dev/null; then
    printf 'FAIL: %s library contains bracketed-paste control bytes\n' "$shell_name" >&2
    exit 1
  fi
  if grep -F 'bad.one' "$library" >/dev/null \
    || grep -F 'bad.two' "$library" >/dev/null; then
    printf 'FAIL: %s multiline paste reached the library\n' "$shell_name" >&2
    exit 1
  fi
}

assert_del_library_exact() {
  local library=$1
  local shell_name=$2
  local expected=$TMP_DIR/del-expected.txt

  printf '# keep comment\n\naa.aa echo AA\ndemo.invalid\ndup.target echo ONE\ndup.target echo TWO\nkeep.inline echo hello # payload\n# concurrent change\n' \
    > "$expected"
  cmp "$expected" "$library" || {
    printf 'FAIL: %s Del changed unrelated library bytes\n' "$shell_name" >&2
    exit 1
  }
}

printf 'Running leaf-preview rendering acceptance...\n'
expect "$PREVIEW_EXPECT_SCRIPT" "$PROTOTYPE_DIR/cmdabc" "$PREVIEW_LIBRARY"

printf 'Running zsh 5.9 final success-screen acceptance...\n'
expect "$SUCCESS_SCREEN_EXPECT_SCRIPT" zsh "$(command -v zsh)" "$PROTOTYPE_DIR" "$ZSH_SUCCESS_LIBRARY"
printf 'Running zsh 5.9 in-place List and scrolling acceptance...\n'
expect "$LIST_COLOR_EXPECT_SCRIPT" zsh "$(command -v zsh)" "$PROTOTYPE_DIR" "$LIST_COLOR_LIBRARY" "$LIST_HOME"
printf 'Running zsh 5.9 interactive acceptance...\n'
expect "$EXPECT_SCRIPT" zsh "$(command -v zsh)" "$PROTOTYPE_DIR" "$ZSH_LIBRARY" "$ZSH_NOEXEC_MARKER" "$PICKER_FIDELITY_PAYLOAD"
assert_add_library_clean "$ZSH_LIBRARY" "$ZSH_NOEXEC_MARKER" 'zsh 5.9'
printf 'Running zsh 5.9 interactive Del acceptance...\n'
expect "$DEL_EXPECT_SCRIPT" zsh "$(command -v zsh)" "$PROTOTYPE_DIR" "$ZSH_DEL_LIBRARY"
assert_del_library_exact "$ZSH_DEL_LIBRARY" 'zsh 5.9'
printf 'Running zsh 5.9 Esc latency acceptance...\n'
expect "$ESCAPE_EXPECT_SCRIPT" zsh "$(command -v zsh)" "$PROTOTYPE_DIR" "$PROTOTYPE_DIR/command-library.txt"
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

printf 'Running Bash 5.2 final success-screen acceptance...\n'
expect "$SUCCESS_SCREEN_EXPECT_SCRIPT" bash "$BASH_BIN" "$PROTOTYPE_DIR" "$BASH_SUCCESS_LIBRARY"
printf 'Running Bash 5.2 in-place List and scrolling acceptance...\n'
expect "$LIST_COLOR_EXPECT_SCRIPT" bash "$BASH_BIN" "$PROTOTYPE_DIR" "$LIST_COLOR_LIBRARY" "$LIST_HOME"
printf 'Running Bash 5.2 interactive acceptance with: %s\n' "$BASH_VERSION_LINE"
expect "$EXPECT_SCRIPT" bash "$BASH_BIN" "$PROTOTYPE_DIR" "$BASH_LIBRARY" "$BASH_NOEXEC_MARKER" "$PICKER_FIDELITY_PAYLOAD"
assert_add_library_clean "$BASH_LIBRARY" "$BASH_NOEXEC_MARKER" 'Bash 5.2'
printf 'Running Bash 5.2 interactive Del acceptance...\n'
expect "$DEL_EXPECT_SCRIPT" bash "$BASH_BIN" "$PROTOTYPE_DIR" "$BASH_DEL_LIBRARY"
assert_del_library_exact "$BASH_DEL_LIBRARY" 'Bash 5.2'
printf 'Running Bash 5.2 Esc latency acceptance...\n'
expect "$ESCAPE_EXPECT_SCRIPT" bash "$BASH_BIN" "$PROTOTYPE_DIR" "$PROTOTYPE_DIR/command-library.txt"
[ ! -e "$BASH_NOEXEC_MARKER" ] || {
  printf 'FAIL: Bash management payload was executed\n' >&2
  exit 1
}
printf 'Running Bash 5.2 invalid-entry recovery acceptance...\n'
expect "$INVALID_EXPECT_SCRIPT" bash "$BASH_BIN" "$PROTOTYPE_DIR" "$TOLERANT_LIBRARY"
printf 'Running Bash 5.2 multi-level tree-picker acceptance...\n'
expect "$TREE_EXPECT_SCRIPT" "$BASH_BIN" "$PROTOTYPE_DIR" "$TREE_LIBRARY"
printf 'PASS: Bash 5.2 target and zsh 5.9 interactive checks\n'
