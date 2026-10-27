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
#
# A server may be allowlisted at several versions at once, via a `versions`
# array (`"versions": ["latest", "1.1.2"]`). Each one is fetched and published
# at its own path, and all of them appear in the listing — which is what the
# upstream registry does too, so `isLatest` in each blob stays accurate without
# us rewriting anything. The legacy single `"version": "..."` form still works.
#
# Only the entry requested as "latest" writes the `latest` alias; pinned
# versions never claim it. Listing entries are deduplicated by resolved
# version, so naming both "latest" and the semver it currently resolves to
# publishes one copy rather than two.
#
# An entry may instead set `"source": "local"`, in which case the blob is read
# from `local/<name>/<version>.json` rather than fetched upstream. That covers
# servers with no entry in registry.modelcontextprotocol.io — Cerebras-built
# servers, and vendor servers the vendor has not published upstream. The file
# is the same shape the upstream per-version endpoint returns ({server, _meta}),
# and the published version still comes from `.server.version` inside it, so a
# local `latest.json` carrying version 1.0.0 lands at both /versions/1.0.0 and
# /versions/latest exactly as an upstream fetch would.
set -euo pipefail

UPSTREAM="${UPSTREAM:-https://registry.modelcontextprotocol.io}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALLOWLIST="$ROOT/allowlist.json"
LOCAL="$ROOT/local"
OUT_V01="$ROOT/v0.1"

command -v jq   >/dev/null || { echo "jq is required"   >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

rm -rf "$OUT_V01"
mkdir -p "$OUT_V01/servers"

urlencode() { jq -rn --arg v "$1" '$v|@uri'; }

servers_array="[]"
count=0
published=""     # |name@resolved-version| already in the listing
has_latest=""    # |name| that published a latest alias

while IFS=$'\t' read -r name spec source; do
  enc="$(urlencode "$name")"
  versions_dir="$OUT_V01/servers/$name/versions"
  mkdir -p "$versions_dir"

  if [ "$source" = "local" ]; then
    src="$LOCAL/$name/${spec:-latest}.json"
    [ -f "$src" ] || { echo "error: $name declares source \"local\" but $src is missing" >&2; exit 1; }
    selected="$(jq -c . "$src")"
    # The blob is hand-maintained, so the name inside it can drift from the
    # allowlist key that decides where it gets published. Copilot enforces on
    # the name in the blob, so a mismatch silently publishes an unusable entry.
    blob_name="$(jq -r '.server.name' <<<"$selected")"
    [ "$blob_name" = "$name" ] || { echo "error: $src declares server.name \"$blob_name\", expected \"$name\"" >&2; exit 1; }
  elif [ "$spec" = "latest" ] || [ -z "$spec" ]; then
    selected="$(curl -fsSL "$UPSTREAM/v0.1/servers/$enc/versions/latest")"
  else
    selected="$(curl -fsSL "$UPSTREAM/v0.1/servers/$enc/versions/$(urlencode "$spec")")"
  fi

  v="$(jq -r '.server.version' <<<"$selected")"
  printf '%s\n' "$selected" > "$versions_dir/$v"
  printf '%s\n' "$selected" > "$versions_dir/$v.json"

  if [ "$spec" = "latest" ] || [ -z "$spec" ]; then
    printf '%s\n' "$selected" > "$versions_dir/latest"
    printf '%s\n' "$selected" > "$versions_dir/latest.json"
    has_latest="$has_latest|$name|"
  fi

  case "$published" in
    *"|$name@$v|"*) continue ;;
  esac
  published="$published|$name@$v|"

  servers_array="$(jq -c --argjson e "$selected" '. + [$e]' <<<"$servers_array")"
  count=$((count + 1))
done < <(jq -r '
  .servers[]
  | . as $s
  | ($s.versions // [$s.version // "latest"])[]
  | [$s.name, ., ($s.source // "upstream")] | @tsv
' "$ALLOWLIST")

# A server pinned only to explicit versions has no /versions/latest, which
# Copilot will fetch and 404 on. Flag it rather than shipping a hole.
while IFS= read -r n; do
  case "$has_latest" in
    *"|$n|"*) ;;
    *) echo "warning: $n has no \"latest\" in its versions — /versions/latest will 404" >&2 ;;
  esac
done < <(jq -r '.servers[].name' "$ALLOWLIST" | sort -u)

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
