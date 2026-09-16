#!/usr/bin/env bash

set -u

CMDABC_MARKER_START='# >>> CmdABC >>>'
CMDABC_MARKER_END='# <<< CmdABC <<<'
CMDABC_TMP_FILE=''
CMDABC_UNINSTALL_CONFLICT=0
CMDABC_RC_PATHS=()
CMDABC_RC_KINDS=()

cmdabc_uninstall_error() {
  printf 'cmdabc uninstall: %s\n' "$*" >&2
}

cmdabc_uninstall_cleanup() {
  if [ -n "$CMDABC_TMP_FILE" ] && [ -e "$CMDABC_TMP_FILE" ]; then
    rm -f "$CMDABC_TMP_FILE"
  fi
}

trap cmdabc_uninstall_cleanup EXIT
trap 'exit 130' INT TERM HUP

cmdabc_read_file() {
  local output_name=$1
  local path=$2
  local value

  value=$(cat "$path"; printf '\001') || return 1
  value=${value%$'\001'}
  printf -v "$output_name" '%s' "$value"
}

cmdabc_count_exact_line() {
  local text=$1
  local wanted=$2
  local line count=0

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$wanted" ]; then
      count=$((count + 1))
    fi
  done <<< "$text"
  printf '%s\n' "$count"
}

cmdabc_add_rc_target() {
  local path=$1
  local kind=$2
  local index=0

  while [ "$index" -lt "${#CMDABC_RC_PATHS[@]}" ]; do
    if [ "${CMDABC_RC_PATHS[$index]}" = "$path" ]; then
      return 0
    fi
    index=$((index + 1))
  done
  CMDABC_RC_PATHS[${#CMDABC_RC_PATHS[@]}]=$path
  CMDABC_RC_KINDS[${#CMDABC_RC_KINDS[@]}]=$kind
}

cmdabc_remove_rc_block() {
  local rc_path=$1
  local shell_kind=$2
  local source_line block prefixed_block content start_count end_count source_count prefix suffix updated temporary

  [ -e "$rc_path" ] || [ -L "$rc_path" ] || return 0
  case "$shell_kind" in
    bash) source_line='source "$HOME/.cmdabc/shell/cmdabc.bash"' ;;
    zsh) source_line='source "$HOME/.cmdabc/shell/cmdabc.zsh"' ;;
  esac
  printf -v block '%s\n%s\n%s\n' "$CMDABC_MARKER_START" "$source_line" "$CMDABC_MARKER_END"
  prefixed_block=$'\n'$block

  if [ -L "$rc_path" ]; then
    content=''
    if [ -r "$rc_path" ]; then
      cmdabc_read_file content "$rc_path" || content=''
    fi
    if [[ "$content" == *"$CMDABC_MARKER_START"* ]] \
      || [[ "$content" == *"$CMDABC_MARKER_END"* ]] \
      || [[ "$content" == *"$source_line"* ]]; then
      cmdabc_uninstall_error "cannot safely modify symlink rc file containing CmdABC registration: $rc_path"
      CMDABC_UNINSTALL_CONFLICT=1
    fi
    return 0
  fi
  if [ ! -f "$rc_path" ]; then
    cmdabc_uninstall_error "cannot safely inspect non-regular rc path: $rc_path"
    CMDABC_UNINSTALL_CONFLICT=1
    return 0
  fi
  cmdabc_read_file content "$rc_path" || {
    cmdabc_uninstall_error "cannot read rc file: $rc_path"
    CMDABC_UNINSTALL_CONFLICT=1
    return 0
  }
  start_count=$(cmdabc_count_exact_line "$content" "$CMDABC_MARKER_START")
  end_count=$(cmdabc_count_exact_line "$content" "$CMDABC_MARKER_END")
  source_count=$(cmdabc_count_exact_line "$content" "$source_line")

  if [ "$start_count" -eq 0 ] && [ "$end_count" -eq 0 ]; then
    if [ "$source_count" -ne 0 ]; then
      cmdabc_uninstall_error "unmanaged CmdABC source line remains in $rc_path"
      CMDABC_UNINSTALL_CONFLICT=1
    fi
    return 0
  fi
  if [ "$start_count" -ne 1 ] || [ "$end_count" -ne 1 ] || [[ "$content" != *"$block"* ]]; then
    cmdabc_uninstall_error "incomplete, duplicate, or modified CmdABC managed block in $rc_path"
    CMDABC_UNINSTALL_CONFLICT=1
    return 0
  fi

  if [ "$content" = "$block" ]; then
    updated=''
  elif [[ "$content" == *"$prefixed_block"* ]]; then
    prefix=${content%%"$prefixed_block"*}
    suffix=${content#*"$prefixed_block"}
    if [ -n "$prefix" ] && [ -n "$suffix" ] && [[ "$prefix" != *$'\n' ]]; then
      updated=$prefix$'\n'$suffix
    else
      updated=$prefix$suffix
    fi
  else
    prefix=${content%%"$block"*}
    suffix=${content#*"$block"}
    updated=$prefix$suffix
  fi
  temporary=$rc_path.cmdabc-uninstall.$$
  CMDABC_TMP_FILE=$temporary
  rm -f "$temporary"
  cp -p "$rc_path" "$temporary" || {
    cmdabc_uninstall_error "cannot prepare rc update: $rc_path"
    CMDABC_UNINSTALL_CONFLICT=1
    return 0
  }
  printf '%s' "$updated" > "$temporary" || {
    cmdabc_uninstall_error "cannot write rc update: $rc_path"
    CMDABC_UNINSTALL_CONFLICT=1
    return 0
  }
  mv -f "$temporary" "$rc_path" || {
    cmdabc_uninstall_error "cannot replace rc file: $rc_path"
    CMDABC_UNINSTALL_CONFLICT=1
    return 0
  }
  CMDABC_TMP_FILE=''
  printf 'Removed CmdABC shell registration from %s\n' "$rc_path"
}

[ -n "${HOME:-}" ] || {
  cmdabc_uninstall_error 'HOME is not set'
  exit 1
}
case "$HOME" in
  /*) ;;
  *) cmdabc_uninstall_error 'HOME must be an absolute path'; exit 1 ;;
esac

CMDABC_INSTALL_DIR=$HOME/.cmdabc
CMDABC_DATA_DIR=$HOME/.cmdabc-data
CMDABC_LIBRARY_PATH=$CMDABC_DATA_DIR/command-library.txt

cmdabc_add_rc_target "$HOME/.bashrc" bash
cmdabc_add_rc_target "$HOME/.zshrc" zsh

if [ -n "${ZDOTDIR:-}" ]; then
  CMDABC_ZDOTDIR=$ZDOTDIR
elif command -v zsh >/dev/null 2>&1; then
  CMDABC_ZDOTDIR=$(HOME="$HOME" zsh -c 'printf "%s" "${ZDOTDIR:-$HOME}"' 2>/dev/null) || CMDABC_ZDOTDIR=''
else
  CMDABC_ZDOTDIR=''
fi
case "$CMDABC_ZDOTDIR" in
  "$HOME"|"$HOME"/*) cmdabc_add_rc_target "$CMDABC_ZDOTDIR/.zshrc" zsh ;;
  '') ;;
  *) cmdabc_uninstall_error "skipping zsh rc outside HOME: $CMDABC_ZDOTDIR" ;;
esac

CMDABC_INDEX=0
while [ "$CMDABC_INDEX" -lt "${#CMDABC_RC_PATHS[@]}" ]; do
  cmdabc_remove_rc_block \
    "${CMDABC_RC_PATHS[$CMDABC_INDEX]}" \
    "${CMDABC_RC_KINDS[$CMDABC_INDEX]}"
  CMDABC_INDEX=$((CMDABC_INDEX + 1))
done

if [ "$CMDABC_UNINSTALL_CONFLICT" -ne 0 ]; then
  cmdabc_uninstall_error 'program files were retained because shell registration could not be removed safely'
  printf 'User data was not changed: %s\n' "$CMDABC_LIBRARY_PATH"
  exit 2
fi

if [ -L "$CMDABC_INSTALL_DIR" ]; then
  cmdabc_uninstall_error "refusing to remove symlink program directory: $CMDABC_INSTALL_DIR"
  printf 'User data was not changed: %s\n' "$CMDABC_LIBRARY_PATH"
  exit 2
fi
if [ -d "$CMDABC_INSTALL_DIR" ]; then
  rm -rf "$CMDABC_INSTALL_DIR" || {
    cmdabc_uninstall_error "cannot remove program directory: $CMDABC_INSTALL_DIR"
    printf 'User data was not changed: %s\n' "$CMDABC_LIBRARY_PATH"
    exit 1
  }
  printf 'Removed CmdABC program directory: %s\n' "$CMDABC_INSTALL_DIR"
else
  printf 'CmdABC program directory is already absent: %s\n' "$CMDABC_INSTALL_DIR"
fi

printf 'CmdABC program removal complete.\n'
printf 'User data was preserved at: %s\n' "$CMDABC_LIBRARY_PATH"
