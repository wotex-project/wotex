#!/bin/sh
# Entry point of the Linux container of the native checks
# (Wotex.Workspace.NativeContainer): fetches the Mix dependencies of the root
# project and of package $1, then runs `mix wotex.native.suite --package $1`
# with the remaining arguments. bin/mix keeps every project's dependencies and
# build output below $WOTEX_MIX_STATE; their output is shown only on failure.
set -eu
package=$1
shift

quietly() {
  if ! log=$("$@" 2>&1); then
    printf '%s\n' "$log" >&2
    exit 1
  fi
}

(
  cd "$WOTEX_ROOT/packages/$package"
  WOTEX_PATH_DEPS=1
  export WOTEX_PATH_DEPS
  quietly mix deps.get --check-locked
)
cd "$WOTEX_ROOT"
quietly mix deps.get --check-locked
quietly mix compile
exec mix wotex.native.suite --package "$package" "$@"
