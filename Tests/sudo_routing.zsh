#!/bin/zsh -f
# Only a pure argv classifier is exercised. No sudo process or credentials.
set -eu
source "${0:A:h:h}/Resources/grant_shell.zsh"
integer cases=0
check() {
  local expected=$1; shift
  local actual=0
  _grant_sudo_eligible "$@" || actual=$?
  [[ $actual == $expected ]] || { print -u2 -- "routing mismatch: ${(q)@}"; exit 1; }
  (( ++cases ))
}
check 0 ls
check 0 -u root -- /usr/bin/true
check 0 -uASn ls
check 0 -pASn ls
check 0 -Hp 'hello %p' true
check 0 --prompt='hello %p' true
check 0 -- /bin/echo -A -S -n
check 0 /bin/echo '中文 space $(literal)'
check 0 -v
check 0 -k true
check 0 -kv
check 0 -kl
check 0 -ki
check 0 -ks
check 0 --reset-timestamp --validate
check 1 -A true
check 1 -Hn true
check 1 -Su root true
check 1 --stdin true
check 1 --non-interactive true
check 1 --askpass true
check 1 --ask true
check 1 --unknown true
check 1 -x true
check 1 -u
check 1 -k
check 1 -K
check 1 -V
check 1 -h
check 1 --help
check 1
print -- "PASS $cases sudo argv routing cases; no authorization requested"
