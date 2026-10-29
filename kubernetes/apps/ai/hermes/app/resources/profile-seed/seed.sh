#!/usr/bin/env bash
set -euo pipefail
umask 077

data=/opt/data

# Keep writes to .env atomic and preserve unrelated profile settings.
update_env() (
  file=$1
  filter=$2
  temporary=$(mktemp "${file}.XXXXXX")
  trap 'rm -f "$temporary"' EXIT
  if [[ -f $file ]]; then
    sed "$filter" "$file" > "$temporary"
  fi
  cat >> "$temporary"
  chmod 600 "$temporary"
  mv "$temporary" "$file"
)

: "${LITELLM_API_KEY:?LITELLM_API_KEY is required}"
: "${SEARXNG_URL:?SEARXNG_URL is required}"
: "${API_SERVER_KEY:?API_SERVER_KEY is required}"

cp /seed/config.yaml "$data/config.yaml"
cp /seed/SOUL.md "$data/SOUL.md"

cat > "$data/.hermes-terminal-env.sh" <<'EOF'
# Bash sources this file through BASH_ENV for every Hermes terminal command.
for directory in /opt/data/.local/bin /opt/hermes/.venv/bin /opt/hermes/bin; do
  case ":$PATH:" in
    *":$directory:"*) ;;
    *) PATH="$directory:$PATH" ;;
  esac
done
export PATH
if [[ ${_HERMES_MISE_ACTIVATED:-} != 1 ]]; then
  _HERMES_MISE_ACTIVATED=1
  eval "$(mise activate bash)"
fi
EOF
chmod 644 "$data/.hermes-terminal-env.sh"

update_env "$data/.env" '/^LITELLM_/d; /^SEARXNG_URL=/d' <<EOF
LITELLM_API_KEY=$LITELLM_API_KEY
SEARXNG_URL=$SEARXNG_URL
EOF

for profile in "$data"/profiles/*; do
  [[ -d $profile ]] || continue
  update_env "$profile/.env" '/^LITELLM_API_KEY=/d; /^API_SERVER_KEY=/d; /^SEARXNG_URL=/d; /^HERMES_WEBUI_GATEWAY_BASE_URL=/d' <<EOF
LITELLM_API_KEY=$LITELLM_API_KEY
API_SERVER_KEY=$API_SERVER_KEY
SEARXNG_URL=$SEARXNG_URL
HERMES_WEBUI_GATEWAY_BASE_URL=http://127.0.0.1:8642/p/${profile##*/}
EOF
done

mkdir -p "$data/.local/bin"
ln -sfn /opt/mise/mise "$data/.local/bin/mise"

# memini memory-provider plugin, pinned to the memini server version. Fail-soft: without network
# the installed copy stays, and without any copy Hermes starts with no external memory.
plugin_dir="$data/plugins/memini"
if [[ $(cat "$plugin_dir/.version" 2>/dev/null) != "$MEMINI_PLUGIN_VERSION" ]]; then
  mkdir -p "$data/.cache"
  workdir=$(mktemp -d "$data/.cache/memini-plugin.XXXXXX")
  if HOME=$workdir git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$MEMINI_PLUGIN_VERSION" \
    https://github.com/eleboucher/memini "$workdir/src"; then
    mkdir -p "$data/plugins"
    rm -rf "$plugin_dir"
    mv "$workdir/src/integrations/hermes/plugin/memini" "$plugin_dir"
    echo "$MEMINI_PLUGIN_VERSION" > "$plugin_dir/.version"
  else
    echo "seed: memini plugin $MEMINI_PLUGIN_VERSION not fetched, keeping the installed copy" >&2
  fi
  rm -rf "$workdir"
fi
