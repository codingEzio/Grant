# Grant's opt-in route for local interactive zsh. Scripts and command sudo keep
# the native path. No pre-authentication, retry, timestamp reset or stdin read.
_grant_sudo_eligible() {
  local arg flags char
  integer needs_command=0 action_mode=0
  (( $# )) || return 1
  while (( $# )); do
    arg=$1; shift
    case $arg in
      --) (( $# )) && return 0; return 1 ;;
      --askpass|--stdin|--non-interactive|--help|--version|--remove-timestamp) return 1 ;;
      --user|--group|--host|--prompt|--close-from|--chdir|--chroot|--role|--type|--command-timeout|--other-user)
        (( $# )) || return 1; shift ;;
      --user=*|--group=*|--host=*|--prompt=*|--close-from=*|--chdir=*|--chroot=*|--role=*|--type=*|--command-timeout=*|--other-user=*|--preserve-env=*) ;;
      --reset-timestamp) needs_command=1 ;;
      --login|--list|--shell|--validate) action_mode=1 ;;
      --background|--preserve-env|--edit|--set-home|--preserve-groups) ;;
      --*) return 1 ;;
      -?*)
        flags=${arg#-}
        while [[ -n $flags ]]; do
          char=${flags[1]}; flags=${flags[2,-1]}
          case $char in
            A|S|n|K|V|h) return 1 ;;
            u|g|p|C|D|R|r|t|T|U)
              if [[ -z $flags ]]; then (( $# )) || return 1; shift; fi
              flags='' ;;
            k) needs_command=1 ;;
            i|l|s|v) action_mode=1 ;;
            b|E|e|H|P) ;;
            *) return 1 ;;
          esac
        done ;;
      -*|*=*) return 1 ;;
      *) return 0 ;;
    esac
  done
  (( ! needs_command || action_mode ))
}

if [[ -o interactive ]]; then
  sudo() {
    local grant_helper="$HOME/Applications/Grant.app/Contents/Resources/GrantAskpass"
    local grant_preferences='/Library/Application Support/Grant/Preferences/settings.json'
    [[ -f $grant_preferences ]] || grant_preferences="$HOME/Library/Application Support/Grant/settings.json"
    if [[ -t 0 && -t 1 && -z ${SSH_CONNECTION-}${SSH_CLIENT-}${SSH_TTY-}${TMUX-}${STY-}${SUDO_ASKPASS-} && -x $grant_helper ]] &&
      _grant_sudo_eligible "$@" &&
      [[ $(/usr/bin/plutil -extract terminalSudo raw -o - "$grant_preferences" 2>/dev/null) == true ]]; then
      SUDO_ASKPASS="$grant_helper" /usr/bin/sudo -A "$@"
    else
      /usr/bin/sudo "$@"
    fi
  }
fi
