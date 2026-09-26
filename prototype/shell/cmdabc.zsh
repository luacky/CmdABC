# CmdABC zsh integration.
# Source only inside an interactive zsh session.

if [ -z "${ZSH_VERSION:-}" ]; then
  print -u2 '[error: zsh integration requires zsh]'
  return 2 2>/dev/null || exit 2
fi

if [[ ! -o interactive ]]; then
  print -u2 '[error: zsh integration requires an interactive zsh shell]'
  return 2 2>/dev/null || exit 2
fi

typeset -g _CMDABC_ZSH_SOURCE=${(%):-%N}
typeset -g _CMDABC_ZSH_DIR=${_CMDABC_ZSH_SOURCE:A:h}
: ${CMDABC_BIN:=${_CMDABC_ZSH_DIR:h}/cmdabc}
: ${CMDABC_LIBRARY:=${HOME:-}/.cmdabc-data/command-library.txt}
unset _CMDABC_ZSH_SOURCE _CMDABC_ZSH_DIR

typeset -g _CMDABC_PENDING_NOTICE=''
typeset -g _CMDABC_PENDING_MANAGE_INPUT=''

_cmdabc_notice_precmd() {
  local notice=${_CMDABC_PENDING_NOTICE:-}

  [[ -n "$notice" ]] || return 0
  _CMDABC_PENDING_NOTICE=''

  # The successful Add accepted an empty edit line. Replace that line before
  # Zsh draws the next prompt, outside the ZLE-managed editing region.
  printf '\033[1A\r\033[2K%s\n' "$notice"
}

_cmdabc_run_pending_manage() {
  local input=$_CMDABC_PENDING_MANAGE_INPUT

  _CMDABC_PENDING_MANAGE_INPUT=''
  # accept-line has already advanced below the private helper. Remove that
  # implementation-only line before printing the user-facing error.
  printf '\033[1A\r\033[2K'
  "$CMDABC_BIN" manage --library "$CMDABC_LIBRARY" --input "$input"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _cmdabc_notice_precmd

cmdabc-dot-widget() {
  local namespace selected pick_status probe_output probe_status

  zle .self-insert
  if (( CURSOR != ${#BUFFER} )); then
    return 0
  fi
  if [[ ! "$BUFFER" =~ '^/[A-Za-z0-9_-]+\.$' ]]; then
    return 0
  fi

  namespace=${BUFFER#/}
  namespace=${namespace%.}
  if probe_output=$("$CMDABC_BIN" children --library "$CMDABC_LIBRARY" \
    --path "$namespace" 2>&1 >/dev/null); then
    probe_status=0
  else
    probe_status=$?
  fi
  if (( probe_status != 0 )); then
    if (( probe_status != 3 )); then
      [[ -n "$probe_output" ]] \
        || probe_output='[error: CmdABC runtime is unavailable]'
      print
      print -r -- "$probe_output"
      zle reset-prompt
    fi
    return 0
  fi
  if selected=$(COLUMNS=${COLUMNS:-80} LINES=${LINES:-24} \
    "$CMDABC_BIN" pick --library "$CMDABC_LIBRARY" --namespace "$namespace"); then
    pick_status=0
  else
    pick_status=$?
  fi
  if (( pick_status == 0 )) && [[ -n "$selected" ]]; then
    BUFFER=$selected
    CURSOR=${#BUFFER}
  elif (( pick_status == 5 )); then
    # The picker returned a captured invalid-entry message, not a command.
    BUFFER=''
    CURSOR=0
    print
    print -r -- "$selected"
    zle reset-prompt
  elif (( pick_status == 6 )); then
    # A built-in action completed inside the current picker session.
    BUFFER=''
    CURSOR=0
    _CMDABC_PENDING_NOTICE=$selected
    zle .accept-line
    return 0
  fi
  zle -R
  return 0
}

cmdabc-accept-line-widget() {
  if [[ "$BUFFER" != /abc.* ]]; then
    zle .accept-line
    return 0
  fi

  _CMDABC_PENDING_MANAGE_INPUT=$BUFFER
  # Invalidate while the user-facing buffer is still active. Changes made
  # after this point are not repainted before accept-line exits ZLE.
  zle -I
  BUFFER='_cmdabc_run_pending_manage'
  CURSOR=${#BUFFER}
  # The private helper runs as the shell command so its status becomes the
  # shell's final status without exposing the helper as a public route.
  zle .accept-line
  return 0
}

zle -N cmdabc-dot-widget
zle -N cmdabc-accept-line-widget
# `.` keeps the frozen C00 trigger. Enter only intercepts reserved /abc.* input.
bindkey '.' cmdabc-dot-widget
bindkey '^M' cmdabc-accept-line-widget
