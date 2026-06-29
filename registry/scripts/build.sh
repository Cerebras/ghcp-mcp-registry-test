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
#   detail/<name-with-real-slashes>/<version>.json
#                        -- per-version detail blobs (non-spec namespace; static-friendly)
#   detail/<name-with-real-slashes>/latest.json
#                        -- latest version detail
#
# Static-hosting notes:
#   1. GitHub Pages can't expose both `/v0.1/servers` (file) AND `/v0.1/servers/<name>/...`
#      (subtree under the same path), so per-server-version detail is published under a
#      parallel `detail/` prefix. The primary `/v0.1/servers` listing is the spec-conformant
#      discovery surface; clients can dereference each entry from `detail/` if needed.
#   2. Server names contain `/` (e.g. `com.atlassian/atlassian-mcp-server`). HTTP clients
#      normalize `%2F` to `/`, so URL-encoding the slash doesn't survive a round-trip
#      through CDNs. We expose the slash as a real path separator under `detail/`.
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

servers_array="[]"
count=0

while IFS=$'\t' read -r name version; do
  enc="$(urlencode "$name")"
  # Use the server name's real slashes as filesystem path separators so URLs
  # survive CDN normalization. e.g. com.atlassian/atlassian-mcp-server -> detail/com.atlassian/atlassian-mcp-server/
  detail_dir="$OUT_DETAIL/$name"
  mkdir -p "$detail_dir"

  # Resolve the version this allowlist entry pins to
  if [ "$version" = "latest" ] || [ -z "$version" ]; then
    selected="$(curl -fsSL "$UPSTREAM/v0.1/servers/$enc/versions/latest")"
  else
    selected="$(curl -fsSL "$UPSTREAM/v0.1/servers/$enc/versions/$(urlencode "$version")")"
  fi

  # Write per-version detail blob and `latest.json` alias
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
