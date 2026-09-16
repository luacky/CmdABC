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

__cmdabc_enter_widget() {
  case "$READLINE_LINE" in
    /abc.*) ;;
    *) return 0 ;;
  esac

  printf '\n'
  "$CMDABC_BIN" manage --library "$CMDABC_LIBRARY" --input "$READLINE_LINE"
  READLINE_LINE=''
  READLINE_POINT=0
  return 0
}

# `.` keeps the frozen C00 trigger. Enter runs the narrow /abc.* handler first,
# then Readline's ordinary accept-line binding through Ctrl-J.
bind -x '".":__cmdabc_dot_widget'
bind -x '"\C-x\C-a":__cmdabc_enter_widget'
bind '"\C-m":"\C-x\C-a\C-j"'
