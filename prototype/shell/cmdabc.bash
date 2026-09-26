# CmdABC Bash integration.
# Source only inside an interactive Bash session.

if [ -z "${BASH_VERSION:-}" ]; then
  printf '[error: Bash integration requires Bash]\n' >&2
  return 2 2>/dev/null || exit 2
fi

if [[ $- != *i* ]]; then
  printf '[error: Bash integration requires an interactive Bash shell]\n' >&2
  return 2 2>/dev/null || exit 2
fi

_cmdabc_bash_source=${BASH_SOURCE[0]}
_cmdabc_bash_dir=$(cd "${_cmdabc_bash_source%/*}" && pwd)
: "${CMDABC_BIN:=${_cmdabc_bash_dir%/shell}/cmdabc}"
: "${CMDABC_LIBRARY:=${HOME:-}/.cmdabc-data/command-library.txt}"
unset _cmdabc_bash_source _cmdabc_bash_dir

_CMDABC_PENDING_NOTICE=''
_CMDABC_PENDING_MANAGE_INPUT=''

__cmdabc_notice_prompt() {
  local notice=${_CMDABC_PENDING_NOTICE:-}

  [ -n "$notice" ] || return 0
  _CMDABC_PENDING_NOTICE=''

  # The successful Add accepted an empty edit line. Replace that line before
  # Bash draws the next prompt, outside the Readline-managed editing region.
  printf '\033[1A\r\033[2K%s\n' "$notice"
}

__cmdabc_run_pending_manage() {
  local input=$_CMDABC_PENDING_MANAGE_INPUT

  _CMDABC_PENDING_MANAGE_INPUT=''
  printf '\033[1A\r\033[2K'
  "$CMDABC_BIN" manage --library "$CMDABC_LIBRARY" --input "$input"
}

_cmdabc_prompt_decl=$(declare -p PROMPT_COMMAND 2>/dev/null || :)
case "$_cmdabc_prompt_decl" in
  'declare -a '*)
    _cmdabc_hook_present=0
    for _cmdabc_hook in "${PROMPT_COMMAND[@]}"; do
      [ "$_cmdabc_hook" = '__cmdabc_notice_prompt' ] && _cmdabc_hook_present=1
    done
    [ "$_cmdabc_hook_present" -eq 1 ] || PROMPT_COMMAND+=(__cmdabc_notice_prompt)
    ;;
  *)
    case ";${PROMPT_COMMAND:-};" in
      *';__cmdabc_notice_prompt;'*) ;;
      *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }__cmdabc_notice_prompt" ;;
    esac
    ;;
esac
unset _cmdabc_prompt_decl _cmdabc_hook_present _cmdabc_hook

__cmdabc_dot_widget() {
  local before after namespace selected pick_status probe_output probe_status

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
  if probe_output=$("$CMDABC_BIN" children --library "$CMDABC_LIBRARY" \
    --path "$namespace" 2>&1 >/dev/null); then
    probe_status=0
  else
    probe_status=$?
  fi
  if [ "$probe_status" -ne 0 ]; then
    if [ "$probe_status" -ne 3 ]; then
      [ -n "$probe_output" ] \
        || probe_output='[error: CmdABC runtime is unavailable]'
      printf '\n%s\n' "$probe_output"
    fi
    return 0
  fi
  if selected=$(COLUMNS=${COLUMNS:-80} LINES=${LINES:-24} \
    "$CMDABC_BIN" pick --library "$CMDABC_LIBRARY" --namespace "$namespace"); then
    pick_status=0
  else
    pick_status=$?
  fi
  if [ "$pick_status" -eq 0 ] && [ -n "$selected" ]; then
    READLINE_LINE=$selected
    READLINE_POINT=${#READLINE_LINE}
  elif [ "$pick_status" -eq 5 ]; then
    # The picker returned a captured invalid-entry message, not a command.
    READLINE_LINE=''
    READLINE_POINT=0
    printf '\n%s\n' "$selected"
  elif [ "$pick_status" -eq 6 ]; then
    # A built-in action completed inside the current picker session.
    READLINE_LINE=''
    READLINE_POINT=0
    printf '\r\033[2K%s\n' "$selected"
  fi
  return 0
}

__cmdabc_enter_widget() {
  case "$READLINE_LINE" in
    /abc.*) ;;
    *) return 0 ;;
  esac

  printf '\n'
  _CMDABC_PENDING_MANAGE_INPUT=$READLINE_LINE
  READLINE_LINE='__cmdabc_run_pending_manage'
  READLINE_POINT=${#READLINE_LINE}
  return 0
}

# `.` keeps the frozen C00 trigger. Enter runs the narrow /abc.* handler first,
# then Readline's ordinary accept-line binding through a reserved key.
bind -x '".":__cmdabc_dot_widget'
bind '"\C-x\C-z":accept-line'
bind -x '"\C-x\C-a":__cmdabc_enter_widget'
bind '"\C-m":"\C-x\C-a\C-x\C-z"'
