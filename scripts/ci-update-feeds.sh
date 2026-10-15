#!/bin/sh
set -eu

# All feeds in this firmware are public. Do not send checkout's repository-
# scoped Authorization header when cloning a different GitHub repository.
# These overrides affect child git commands only, not global Git settings.
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=http.https://github.com/.extraheader
export GIT_CONFIG_VALUE_0=''
export GIT_CONFIG_KEY_1=http.version
export GIT_CONFIG_VALUE_1=HTTP/1.1

delay=${FEEDS_RETRY_DELAY:-5}
case "$delay" in ''|*[!0-9]*) echo 'Invalid FEEDS_RETRY_DELAY' >&2; exit 1;; esac

config=feeds.conf
[ -f "$config" ] || config=feeds.conf.default
[ -f "$config" ] || { echo 'Feeds configuration missing' >&2; exit 1; }
feeds=$(awk '$1 !~ /^#/ && NF >= 3 { print $2 }' "$config")
[ -n "$feeds" ] || { echo 'No feeds configured' >&2; exit 1; }

for feed in $feeds; do
  case "$feed" in ''|*[!a-zA-Z0-9_-]*) echo "Invalid feed name: $feed" >&2; exit 1;; esac
  attempt=1
  while ! ./scripts/feeds update "$feed"; do
    if [ "$attempt" -ge 3 ]; then
      echo "ERROR: feed '$feed' failed after $attempt attempts; refusing to build with missing dependencies" >&2
      exit 1
    fi
    echo "Feed '$feed' attempt $attempt failed; retrying" >&2
    pause=$((delay * attempt))
    if [ "$pause" -gt 0 ]; then sleep "$pause"; fi
    attempt=$((attempt + 1))
  done
  [ -d "feeds/$feed" ] || { echo "ERROR: feed '$feed' reported success but its directory is missing" >&2; exit 1; }
  echo "Feed '$feed' ready"
done
