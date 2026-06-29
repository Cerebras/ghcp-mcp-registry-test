#!/usr/bin/env bash
# Regenerate the static MCP-registry endpoints under registry/v0.1/
# from the upstream official MCP registry, filtered by allowlist.json.
#
# Usage:
#   ./registry/scripts/build.sh
#
# What it produces (relative to registry/):
#   v0.1/servers         -- spec endpoint /v0.1/servers (extensionless; aggregated list)
#   v0.1/servers.json    -- same content with .json suffix for explicit-extension consumers
#   detail/<flat-name>/<version>.json
#                        -- per-version detail blobs (non-spec namespace; static-friendly)
#   detail/<flat-name>/latest.json
#                        -- latest version detail
#
# Naming:
#   Upstream MCP server names use a `<reverse-dns>/<short>` convention with a literal `/`
#   in the identifier (e.g. `com.atlassian/atlassian-mcp-server`). This registry flattens
#   that slash into a `.` for everything we publish, so the published name and on-disk
#   layout are single path segments (e.g. `com.atlassian.atlassian-mcp-server`). The
#   allowlist still uses the upstream canonical name as the lookup key.
#
# Static-hosting note:
#   GitHub Pages can't expose both `/v0.1/servers` (file) AND `/v0.1/servers/<name>/...`
#   (subtree) at the same path, so per-server detail lives under a parallel `detail/`
#   prefix. The `/v0.1/servers` listing already contains the full server record, so
#   most consumers won't need to dereference detail blobs.
set -euo pipefail

UPSTREAM="${UPSTREAM:-https://registry.modelcontextprotocol.io}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALLOWLIST="$ROOT/allowlist.json"
OUT_V01="$ROOT/v0.1"
OUT_DETAIL="$ROOT/detail"

command -v jq   >/dev/null || { echo "jq is required"   >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

rm -rf "$OUT_V01" "$OUT_DETAIL"
mkdir -p "$OUT_V01" "$OUT_DETAIL"

urlencode() { jq -rn --arg v "$1" '$v|@uri'; }
flatten()   { printf '%s' "${1//\//.}"; }

servers_array="[]"
count=0

while IFS=$'\t' read -r name version; do
  enc="$(urlencode "$name")"
  flat="$(flatten "$name")"
  detail_dir="$OUT_DETAIL/$flat"
  mkdir -p "$detail_dir"

  # Resolve the version this allowlist entry pins to
  if [ "$version" = "latest" ] || [ -z "$version" ]; then
    raw="$(curl -fsSL "$UPSTREAM/v0.1/servers/$enc/versions/latest")"
  else
    raw="$(curl -fsSL "$UPSTREAM/v0.1/servers/$enc/versions/$(urlencode "$version")")"
  fi

  # Flatten the published server name (replace "/" with ".")
  selected="$(jq -c --arg flat "$flat" '.server.name = $flat' <<<"$raw")"

  v="$(jq -r '.server.version' <<<"$selected")"
  printf '%s\n' "$selected" > "$detail_dir/$v.json"
  printf '%s\n' "$selected" > "$detail_dir/latest.json"

  servers_array="$(jq -c --argjson e "$selected" '. + [$e]' <<<"$servers_array")"
  count=$((count + 1))
done < <(jq -r '.servers[] | [.name, (.version // "latest")] | @tsv' "$ALLOWLIST")

generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
listing="$(jq -n \
  --argjson servers "$servers_array" \
  --argjson count "$count" \
  --arg generated "$generated_at" \
  --arg upstream "$UPSTREAM" \
  '{servers: $servers, metadata: {count: $count, nextCursor: null, _curated: {by: "Cerebras corpsec", generatedAt: $generated, upstream: $upstream}}}')"

printf '%s\n' "$listing" > "$OUT_V01/servers"
printf '%s\n' "$listing" > "$OUT_V01/servers.json"

echo "Wrote $count servers to $OUT_V01 (and per-version detail to $OUT_DETAIL)"
