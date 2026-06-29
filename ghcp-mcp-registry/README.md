# ghcp-mcp-registry

A statically-hosted, allowlist-based mirror of the [official MCP registry](https://registry.modelcontextprotocol.io), curated for Cerebras and served from this repo's GitHub Pages branch.

Once GitHub Pages is enabled on the `pages` branch, the registry is reachable at:

```
https://cerebras.github.io/corpsec/ghcp-mcp-registry/
```

## Layout

| Path | Purpose |
| --- | --- |
| `allowlist.json` | Source of truth — which MCP servers are exposed (and at what pinned version). |
| `scripts/build.sh` | Pulls each allowlisted server from the upstream registry and regenerates the static files below. |
| `v0.1/servers` | Spec-conformant listing endpoint (no extension; matches `GET /v0.1/servers` from the Generic Registry API). |
| `v0.1/servers.json` | Same content, `.json` extension, served as `application/json` by GitHub Pages. |
| `detail/<name>/<version>.json` | Per-version detail blobs (e.g. `detail/com.atlassian/atlassian-mcp-server/1.1.2.json`). |
| `detail/<name>/latest.json` | Latest-version alias. |
| `index.html` | Human-readable landing page. |

## Why both `v0.1/servers` (extensionless) and `v0.1/servers.json`?

The MCP registry spec describes an HTTP API where path-without-extension is the canonical endpoint. GitHub Pages can serve extensionless files (so `/v0.1/servers` works), but the MIME type isn't guaranteed to be `application/json`. The `.json` sibling exists for tooling that requires a strict content type.

## Why is per-server detail under `detail/`, not `v0.1/servers/<name>/...`?

The spec puts the listing at `/v0.1/servers` and per-server detail at `/v0.1/servers/<name>/versions/<version>`. On a static filesystem you can't have both a file and a directory at the same path (`v0.1/servers`), so we publish the detail blobs under a parallel `detail/` prefix. Listing consumers don't need to walk these — every entry in `v0.1/servers.json` already contains the full server record.

The spec further URL-encodes the slash inside a server name (e.g. `com.example%2Fmy-server`). HTTP clients and CDNs normalize `%2F` to `/` before path matching, so that encoding doesn't survive a round-trip. We keep the slash as a real path separator under `detail/` instead.

## Updating

1. Edit `allowlist.json` — add or remove server entries. `version` can be `"latest"` or a pinned semver.
2. Run the build:
   ```bash
   ./ghcp-mcp-registry/scripts/build.sh
   ```
3. Commit and push to `pages`:
   ```bash
   git add ghcp-mcp-registry
   git commit -m "registry: refresh"
   git push origin pages
   ```

## Adding a new server

The upstream registry indexes servers by reverse-DNS name. To find one:

```bash
curl -s "https://registry.modelcontextprotocol.io/v0.1/servers?search=<term>" | jq '.servers[].server.name'
```

Then add an entry to `allowlist.json`:

```json
{
  "name": "com.example/foo-mcp",
  "version": "latest",
  "notes": "Optional rationale for allowing this server."
}
```

## References

- [Generic Registry API spec](https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/api/generic-registry-api.md)
- [Generic server.json format](https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/server-json/generic-server-json.md)
- [Official MCP registry](https://registry.modelcontextprotocol.io/docs)
