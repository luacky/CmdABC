#!/usr/bin/env bash

set -u

CMDABC_MARKER_START='# >>> CmdABC >>>'
CMDABC_MARKER_END='# <<< CmdABC <<<'
CMDABC_TMP_FILE=''

cmdabc_install_error() {
  printf 'cmdabc install: %s\n' "$*" >&2
}

cmdabc_install_fail() {
  cmdabc_install_error "$*"
  exit 1
}

cmdabc_install_cleanup() {
  if [ -n "$CMDABC_TMP_FILE" ] && [ -e "$CMDABC_TMP_FILE" ]; then
    rm -f "$CMDABC_TMP_FILE"
  fi
}

trap cmdabc_install_cleanup EXIT
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

cmdabc_copy_program_file() {
  local source=$1
  local destination=$2
  local mode=$3
  local temporary=$destination.cmdabc-install.$$

  CMDABC_TMP_FILE=$temporary
  rm -f "$temporary"
  cp "$source" "$temporary" || cmdabc_install_fail "cannot copy $source"
  chmod "$mode" "$temporary" || cmdabc_install_fail "cannot set mode on $destination"
  mv -f "$temporary" "$destination" || cmdabc_install_fail "cannot replace $destination"
  CMDABC_TMP_FILE=''
}

cmdabc_register_shell() {
  local rc_path=$1
  local source_line=$2
  local rc_parent content start_count end_count source_count block temporary

  rc_parent=${rc_path%/*}
  [ -d "$rc_parent" ] || cmdabc_install_fail "rc parent directory does not exist: $rc_parent"
  [ -w "$rc_parent" ] || cmdabc_install_fail "rc parent directory is not writable: $rc_parent"
  if [ -L "$rc_path" ]; then
    cmdabc_install_fail "refusing to modify symlink rc file: $rc_path"
  fi
  if [ -e "$rc_path" ] && [ ! -f "$rc_path" ]; then
    cmdabc_install_fail "rc path is not a regular file: $rc_path"
  fi
  if [ -e "$rc_path" ] && [ ! -r "$rc_path" ]; then
    cmdabc_install_fail "rc file is not readable: $rc_path"
  fi
  if [ -e "$rc_path" ] && [ ! -w "$rc_path" ]; then
    cmdabc_install_fail "rc file is not writable: $rc_path"
  fi
  if [ -e "$rc_path" ] && LC_ALL=C grep -q $'\r' "$rc_path"; then
    cmdabc_install_fail "refusing to normalize CRLF rc file: $rc_path"
  fi

  content=''
  if [ -e "$rc_path" ]; then
    cmdabc_read_file content "$rc_path" || cmdabc_install_fail "cannot read rc file: $rc_path"
  fi
  start_count=$(cmdabc_count_exact_line "$content" "$CMDABC_MARKER_START")
  end_count=$(cmdabc_count_exact_line "$content" "$CMDABC_MARKER_END")
  source_count=$(cmdabc_count_exact_line "$content" "$source_line")
  printf -v block '%s\n%s\n%s\n' "$CMDABC_MARKER_START" "$source_line" "$CMDABC_MARKER_END"

  if [ "$start_count" -eq 1 ] && [ "$end_count" -eq 1 ] && [[ "$content" == *"$block"* ]]; then
    printf 'CmdABC shell registration already present: %s\n' "$rc_path"
    return 0
  fi
  if [ "$start_count" -ne 0 ] || [ "$end_count" -ne 0 ]; then
    cmdabc_install_fail "incomplete, duplicate, or modified CmdABC managed block in $rc_path"
  fi
  if [ "$source_count" -ne 0 ]; then
    cmdabc_install_fail "unmanaged CmdABC source line already exists in $rc_path"
  fi

  temporary=$rc_path.cmdabc-install.$$
  CMDABC_TMP_FILE=$temporary
  rm -f "$temporary"
  if [ -e "$rc_path" ]; then
    cp -p "$rc_path" "$temporary" || cmdabc_install_fail "cannot prepare rc update: $rc_path"
  else
    (umask 077; : > "$temporary") || cmdabc_install_fail "cannot create rc file: $rc_path"
  fi
  if [ -n "$content" ]; then
    printf '\n' >> "$temporary" || cmdabc_install_fail "cannot separate managed block: $rc_path"
  fi
  printf '%s' "$block" >> "$temporary" || cmdabc_install_fail "cannot append managed block: $rc_path"
  mv -f "$temporary" "$rc_path" || cmdabc_install_fail "cannot replace rc file: $rc_path"
  CMDABC_TMP_FILE=''
  printf 'Registered CmdABC in %s\n' "$rc_path"
}

[ -n "${HOME:-}" ] || cmdabc_install_fail 'HOME is not set'
case "$HOME" in
  /*) ;;
  *) cmdabc_install_fail 'HOME must be an absolute path' ;;
esac

CMDABC_PACKAGE_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd) \
  || cmdabc_install_fail 'cannot resolve package directory'

if [ -x "$CMDABC_PACKAGE_DIR/cmdabc" ] \
  && [ -f "$CMDABC_PACKAGE_DIR/shell/cmdabc.bash" ] \
  && [ -f "$CMDABC_PACKAGE_DIR/shell/cmdabc.zsh" ]; then
  CMDABC_PAYLOAD_DIR=$CMDABC_PACKAGE_DIR
elif [ -x "$CMDABC_PACKAGE_DIR/prototype/cmdabc" ] \
  && [ -f "$CMDABC_PACKAGE_DIR/prototype/shell/cmdabc.bash" ] \
  && [ -f "$CMDABC_PACKAGE_DIR/prototype/shell/cmdabc.zsh" ]; then
  CMDABC_PAYLOAD_DIR=$CMDABC_PACKAGE_DIR/prototype
else
  cmdabc_install_fail 'package runtime payload is incomplete'
fi

[ -f "$CMDABC_PACKAGE_DIR/VERSION" ] || cmdabc_install_fail 'VERSION is missing'
IFS= read -r CMDABC_PACKAGE_VERSION < "$CMDABC_PACKAGE_DIR/VERSION" \
  || cmdabc_install_fail 'cannot read VERSION'
[ -n "$CMDABC_PACKAGE_VERSION" ] || cmdabc_install_fail 'VERSION is empty'
CMDABC_RUNTIME_VERSION=$("$CMDABC_PAYLOAD_DIR/cmdabc" --version) \
  || cmdabc_install_fail 'cannot read runtime version'
[ "$CMDABC_RUNTIME_VERSION" = "$CMDABC_PACKAGE_VERSION" ] \
  || cmdabc_install_fail 'VERSION and cmdabc --version do not match'

CMDABC_SHELL_KIND=${CMDABC_SHELL:-}
if [ -z "$CMDABC_SHELL_KIND" ]; then
  CMDABC_SHELL_KIND=${SHELL##*/}
fi
case "$CMDABC_SHELL_KIND" in
  bash|zsh) ;;
  *) cmdabc_install_fail "unsupported shell: ${CMDABC_SHELL_KIND:-unknown}; use Bash or zsh" ;;
esac
command -v "$CMDABC_SHELL_KIND" >/dev/null 2>&1 \
  || cmdabc_install_fail "supported shell executable not found: $CMDABC_SHELL_KIND"

case "$CMDABC_SHELL_KIND" in
  bash)
    CMDABC_RC_PATH=$HOME/.bashrc
    CMDABC_SOURCE_LINE='source "$HOME/.cmdabc/shell/cmdabc.bash"'
    ;;
  zsh)
    if [ -n "${ZDOTDIR:-}" ]; then
      CMDABC_ZDOTDIR=$ZDOTDIR
    else
      CMDABC_ZDOTDIR=$(HOME="$HOME" zsh -c 'printf "%s" "${ZDOTDIR:-$HOME}"' 2>/dev/null) \
        || cmdabc_install_fail 'cannot determine zsh ZDOTDIR'
    fi
    case "$CMDABC_ZDOTDIR" in
      "$HOME"|"$HOME"/*) ;;
      *) cmdabc_install_fail "zsh rc directory is outside HOME: $CMDABC_ZDOTDIR" ;;
    esac
    CMDABC_RC_PATH=$CMDABC_ZDOTDIR/.zshrc
    CMDABC_SOURCE_LINE='source "$HOME/.cmdabc/shell/cmdabc.zsh"'
    ;;
esac

CMDABC_INSTALL_DIR=$HOME/.cmdabc
CMDABC_DATA_DIR=$HOME/.cmdabc-data
CMDABC_LIBRARY_PATH=$CMDABC_DATA_DIR/command-library.txt

if [ -L "$CMDABC_INSTALL_DIR" ]; then
  cmdabc_install_fail "refusing to install through symlink: $CMDABC_INSTALL_DIR"
fi
if [ -e "$CMDABC_INSTALL_DIR" ] && [ ! -d "$CMDABC_INSTALL_DIR" ]; then
  cmdabc_install_fail "program path is not a directory: $CMDABC_INSTALL_DIR"
fi
if [ -L "$CMDABC_DATA_DIR" ]; then
  cmdabc_install_fail "refusing to use symlink data directory: $CMDABC_DATA_DIR"
fi
if [ -e "$CMDABC_DATA_DIR" ] && [ ! -d "$CMDABC_DATA_DIR" ]; then
  cmdabc_install_fail "data path is not a directory: $CMDABC_DATA_DIR"
fi

mkdir -p "$CMDABC_INSTALL_DIR/shell" || cmdabc_install_fail 'cannot create program directory'
chmod 700 "$CMDABC_INSTALL_DIR" "$CMDABC_INSTALL_DIR/shell" \
  || cmdabc_install_fail 'cannot set program directory permissions'

cmdabc_copy_program_file "$CMDABC_PAYLOAD_DIR/cmdabc" "$CMDABC_INSTALL_DIR/cmdabc" 755
cmdabc_copy_program_file "$CMDABC_PAYLOAD_DIR/shell/cmdabc.bash" "$CMDABC_INSTALL_DIR/shell/cmdabc.bash" 644
cmdabc_copy_program_file "$CMDABC_PAYLOAD_DIR/shell/cmdabc.zsh" "$CMDABC_INSTALL_DIR/shell/cmdabc.zsh" 644
cmdabc_copy_program_file "$CMDABC_PACKAGE_DIR/uninstall.sh" "$CMDABC_INSTALL_DIR/uninstall.sh" 755

CMDABC_TMP_FILE=$CMDABC_INSTALL_DIR/VERSION.cmdabc-install.$$
printf '%s\n' "$CMDABC_PACKAGE_VERSION" > "$CMDABC_TMP_FILE" \
  || cmdabc_install_fail 'cannot write installed VERSION'
chmod 644 "$CMDABC_TMP_FILE" || cmdabc_install_fail 'cannot set VERSION mode'
mv -f "$CMDABC_TMP_FILE" "$CMDABC_INSTALL_DIR/VERSION" \
  || cmdabc_install_fail 'cannot replace installed VERSION'
CMDABC_TMP_FILE=''

if [ ! -e "$CMDABC_DATA_DIR" ]; then
  (umask 077; mkdir "$CMDABC_DATA_DIR") || cmdabc_install_fail 'cannot create user data directory'
  chmod 700 "$CMDABC_DATA_DIR" || cmdabc_install_fail 'cannot set user data directory permissions'
fi
if [ ! -e "$CMDABC_LIBRARY_PATH" ] && [ ! -L "$CMDABC_LIBRARY_PATH" ]; then
  if (umask 077; set -C; : > "$CMDABC_LIBRARY_PATH") 2>/dev/null; then
    printf 'Created empty user command library: %s\n' "$CMDABC_LIBRARY_PATH"
  elif [ -e "$CMDABC_LIBRARY_PATH" ] || [ -L "$CMDABC_LIBRARY_PATH" ]; then
    printf 'Preserved concurrently created user command library unchanged: %s\n' "$CMDABC_LIBRARY_PATH"
  else
    cmdabc_install_fail 'cannot create command-library.txt'
  fi
else
  printf 'Preserved existing user command library unchanged: %s\n' "$CMDABC_LIBRARY_PATH"
fi

cmdabc_register_shell "$CMDABC_RC_PATH" "$CMDABC_SOURCE_LINE"

printf 'CmdABC %s installed in %s\n' "$CMDABC_PACKAGE_VERSION" "$CMDABC_INSTALL_DIR"
printf 'User data: %s\n' "$CMDABC_LIBRARY_PATH"
printf 'Open a new %s shell for the registration to take effect.\n' "$CMDABC_SHELL_KIND"
