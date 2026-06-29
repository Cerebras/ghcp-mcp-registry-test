#!/usr/bin/env bash
# Regenerate the static MCP-registry endpoints under registry/v0.1/
# from the upstream official MCP registry, filtered by allowlist.json.
#
# Usage:
#   ./registry/scripts/build.sh
#
# Endpoints produced (relative to registry/, matching the GitHub Copilot MCP
# registry contract — https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-registry):
#
#   v0.1/servers/index.html
#     /v0.1/servers — aggregated server listing. Served via GitHub Pages'
#     trailing-slash redirect (/v0.1/servers → /v0.1/servers/ → index.html).
#     Body is JSON; MIME from GH Pages is text/html. Copilot tolerates this.
#
#   v0.1/servers.json
#     Same listing body, with an explicit .json extension and application/json
#     MIME, for tooling that requires a strict content type.
#
#   v0.1/servers/<name-with-slashes>/versions/latest
#   v0.1/servers/<name-with-slashes>/versions/<version>
#     Per-version detail blobs at the spec paths. The server name is preserved
#     verbatim (e.g. `com.atlassian/atlassian-mcp-server`) so it matches the
#     canonical ID Copilot enforces against. The name's `/` becomes a real
#     filesystem path separator so paths resolve whether the client sends `/`
#     or URL-encoded `%2F` (CDNs typically normalize the latter to the former).
set -euo pipefail

UPSTREAM="${UPSTREAM:-https://registry.modelcontextprotocol.io}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALLOWLIST="$ROOT/allowlist.json"
OUT_V01="$ROOT/v0.1"

command -v jq   >/dev/null || { echo "jq is required"   >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

rm -rf "$OUT_V01"
mkdir -p "$OUT_V01/servers"

urlencode() { jq -rn --arg v "$1" '$v|@uri'; }

servers_array="[]"
count=0

while IFS=$'\t' read -r name version; do
  enc="$(urlencode "$name")"
  versions_dir="$OUT_V01/servers/$name/versions"
  mkdir -p "$versions_dir"

  if [ "$version" = "latest" ] || [ -z "$version" ]; then
    selected="$(curl -fsSL "$UPSTREAM/v0.1/servers/$enc/versions/latest")"
  else
    selected="$(curl -fsSL "$UPSTREAM/v0.1/servers/$enc/versions/$(urlencode "$version")")"
  fi

  v="$(jq -r '.server.version' <<<"$selected")"
  printf '%s\n' "$selected" > "$versions_dir/$v"
  printf '%s\n' "$selected" > "$versions_dir/$v.json"
  printf '%s\n' "$selected" > "$versions_dir/latest"
  printf '%s\n' "$selected" > "$versions_dir/latest.json"

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

# /v0.1/servers/ → index.html (will be reached via GH Pages' trailing-slash redirect)
printf '%s\n' "$listing" > "$OUT_V01/servers/index.html"
# Sibling .json file for tooling that wants explicit application/json
printf '%s\n' "$listing" > "$OUT_V01/servers.json"

echo "Wrote $count servers to $OUT_V01"
