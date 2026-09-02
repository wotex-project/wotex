#!/bin/sh
set -eu

for root in "$(printf '/%s/' Users)" "$(printf '/%s/' home)"; do
  if find . -type f \
    ! -path './.git/*' \
    ! -path './_build/*' \
    ! -path './cover/*' \
    ! -path './deps/*' \
    ! -path './doc/*' \
    -print0 | xargs -0 grep -IlF "$root" | grep -q .; then
    echo "organization-internal path detected" >&2
    exit 1
  fi
done

if grep -RIlE \
  '(def start\(|use GenServer|use Supervisor|Application\.(get|fetch)_env|Ecto\.Repo|use Phoenix|use Oban)' \
  lib | grep -q .; then
  echo "forbidden runtime or framework boundary detected" >&2
  exit 1
fi

echo "public boundary checks passed"
