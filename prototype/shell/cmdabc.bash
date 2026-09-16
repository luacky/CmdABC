# CmdABC Bash integration.
# Source only inside an interactive Bash session.

if [ -z "${BASH_VERSION:-}" ]; then
  printf 'cmdabc: this integration requires Bash\n' >&2
  return 2 2>/dev/null || exit 2
fi

if [[ $- != *i* ]]; then
  printf 'cmdabc: source this file only in an interactive Bash shell\n' >&2
  return 2 2>/dev/null || exit 2
fi

_cmdabc_bash_source=${BASH_SOURCE[0]}
_cmdabc_bash_dir=$(cd "${_cmdabc_bash_source%/*}" && pwd)
: "${CMDABC_BIN:=${_cmdabc_bash_dir%/shell}/cmdabc}"
: "${CMDABC_LIBRARY:=${HOME:-}/.cmdabc-data/command-library.txt}"
unset _cmdabc_bash_source _cmdabc_bash_dir

__cmdabc_dot_widget() {
  local before after namespace selected pick_status

  before=${READLINE_LINE:0:READLINE_POINT}
  after=${READLINE_LINE:READLINE_POINT}
  READLINE_LINE="${before}.${after}"
  READLINE_POINT=$((READLINE_POINT + 1))

  if [ "$READLINE_POINT" -ne "${#READLINE_LINE}" ]; then
    return 0
  fi
  if [[ ! "$READLINE_LINE" =~ ^/[A-Za-z0-9_-]+\.$ ]]; then
    return 0
  fi

  namespace=${READLINE_LINE#/}
  namespace=${namespace%.}
  selected=$("$CMDABC_BIN" pick --library "$CMDABC_LIBRARY" --namespace "$namespace")
  pick_status=$?
  if [ "$pick_status" -eq 0 ] && [ -n "$selected" ]; then
    READLINE_LINE=$selected
    READLINE_POINT=${#READLINE_LINE}
  fi
  return 0
}

# C00 intentionally changes only this isolated shell's current Readline keymap.
bind -x '".":__cmdabc_dot_widget'
