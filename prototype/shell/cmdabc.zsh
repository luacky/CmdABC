# CmdABC zsh integration.
# Source only inside an interactive zsh session.

if [ -z "${ZSH_VERSION:-}" ]; then
  print -u2 'cmdabc: this integration requires Zsh'
  return 2 2>/dev/null || exit 2
fi

if [[ ! -o interactive ]]; then
  print -u2 'cmdabc: source this file only in an interactive Zsh shell'
  return 2 2>/dev/null || exit 2
fi

typeset -g _CMDABC_ZSH_SOURCE=${(%):-%N}
typeset -g _CMDABC_ZSH_DIR=${_CMDABC_ZSH_SOURCE:A:h}
: ${CMDABC_BIN:=${_CMDABC_ZSH_DIR:h}/cmdabc}
: ${CMDABC_LIBRARY:=${HOME:-}/.cmdabc-data/command-library.txt}
unset _CMDABC_ZSH_SOURCE _CMDABC_ZSH_DIR

cmdabc-dot-widget() {
  local namespace selected pick_status

  zle .self-insert
  if (( CURSOR != ${#BUFFER} )); then
    return 0
  fi
  if [[ ! "$BUFFER" =~ '^/[A-Za-z0-9_-]+\.$' ]]; then
    return 0
  fi

  namespace=${BUFFER#/}
  namespace=${namespace%.}
  if selected=$(COLUMNS=${COLUMNS:-80} "$CMDABC_BIN" pick --library "$CMDABC_LIBRARY" --namespace "$namespace"); then
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
  fi
  zle -R
  return 0
}

cmdabc-accept-line-widget() {
  if [[ "$BUFFER" != /abc.* ]]; then
    zle .accept-line
    return 0
  fi

  print
  "$CMDABC_BIN" manage --library "$CMDABC_LIBRARY" --input "$BUFFER"
  BUFFER=''
  CURSOR=0
  zle .accept-line
  return 0
}

zle -N cmdabc-dot-widget
zle -N cmdabc-accept-line-widget
# `.` keeps the frozen C00 trigger. Enter only intercepts reserved /abc.* input.
bindkey '.' cmdabc-dot-widget
bindkey '^M' cmdabc-accept-line-widget
