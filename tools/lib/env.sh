# Sourced by the tools: repo root + local settings (config/local.env, not in git - copy config/local.env.example).
#   S8PORT     repo checkout (this folder)
#   S8ROM      case-sensitive work dir in WSL / on the build server (trees, kernel, port staging), default ~/s8rom
#   BUILD_HOST user@host of the build server (tools/setup/remote.sh)
#   PHONE_PC   user@host of the PC the phone is plugged into, if not this machine (adb runs there over ssh)
#   PHONE_PC_PW / PHONE_PC_TMP   its ssh password (optional, sshpass; keys are better) / a temp dir on it for pushes
S8PORT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
[ -f "$S8PORT/config/local.env" ] && . "$S8PORT/config/local.env"
S8ROM=${S8ROM:-$HOME/s8rom}

_phone_ssh() {  # _phone_ssh <ssh|scp> args...
  local c=$1; shift
  if [ -n "$PHONE_PC_PW" ]; then sshpass -p "$PHONE_PC_PW" $c -o ConnectTimeout=15 -o LogLevel=ERROR "$@"
  else $c -o ConnectTimeout=15 -o LogLevel=ERROR "$@"; fi
}
# ph '<adb arguments as one string>'   e.g. ph 'shell getprop ro.build.id'
ph() { if [ -n "$PHONE_PC" ]; then _phone_ssh ssh "$PHONE_PC" "adb $*"; else eval adb "$*"; fi; }
# phsh <local script>   run it as root on the phone (stdin to "adb shell su")
phsh() { if [ -n "$PHONE_PC" ]; then _phone_ssh ssh "$PHONE_PC" "adb shell su" < "$1"; else adb shell su < "$1"; fi; }
# phpush <local file> <phone path>
phpush() {
  if [ -n "$PHONE_PC" ]; then
    local t=${PHONE_PC_TMP:?set PHONE_PC_TMP (a temp dir on the phone PC)}/$(basename "$1")
    _phone_ssh scp -q "$1" "$PHONE_PC:$t" && _phone_ssh ssh "$PHONE_PC" "adb push $t $2" >/dev/null
  else adb push "$1" "$2" >/dev/null; fi
}
