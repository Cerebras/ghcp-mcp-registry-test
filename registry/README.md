# registry

A statically-hosted MCP server registry for Cerebras, conforming to the [GitHub Copilot MCP registry contract](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-registry) (v0.1).

Served from the `pages` branch at:

```
https://cerebras.github.io/ghcp-mcp-registry-test/registry/
```

Configure that base URL in your enterprise/organization Copilot MCP registry settings.

## Endpoints

These three endpoints are the contract GitHub Copilot enforces against:

| Endpoint | Source file |
| --- | --- |
| `GET /v0.1/servers` | `v0.1/servers/index.html` (body is JSON; reached via GH Pages' trailing-slash redirect) |
| `GET /v0.1/servers/{serverName}/versions/latest` | `v0.1/servers/<serverName>/versions/latest` |
| `GET /v0.1/servers/{serverName}/versions/{version}` | `v0.1/servers/<serverName>/versions/<version>` |

`serverName` keeps its canonical `/` (e.g. `com.atlassian/atlassian-mcp-server`). The slash becomes a real filesystem path separator, so the URL resolves whether the client sends the `/` literally or URL-encoded as `%2F` (CDNs normalize the latter to the former).

A `v0.1/servers.json` sibling is also published with explicit `application/json` MIME, for tooling that doesn't follow the trailing-slash redirect.

## Source layout

| Path | Purpose |
| --- | --- |
| `allowlist.json` | Source of truth — which MCP servers are exposed and at what versions. Uses canonical server IDs (with `/`). |
| `local/<name>/<version>.json` | Hand-authored blobs for servers that have no upstream registry entry. Only read for allowlist entries with `"source": "local"`. |
| `scripts/build.sh` | Pulls each allowlisted server from `registry.modelcontextprotocol.io` (or `local/`) and regenerates the static endpoints. |
| `v0.1/...` | Generated. Do not edit by hand. |
| `index.html` | Human-readable landing page. |

## CORS

GitHub Pages already sends `Access-Control-Allow-Origin: *` on every response, which is enough for Copilot's simple `GET` fetches. If Copilot ever sends a preflighted request (custom headers like `Authorization`), GH Pages won't add `Access-Control-Allow-Methods` / `Access-Control-Allow-Headers`, and you'd need to front the site with a proxy (e.g. a Cloudflare Worker) that injects them.

## Why the server ID must match exactly

GitHub Copilot's MCP allowlist enforcement is name-based — see [MCP allowlist enforcement](https://docs.github.com/en/copilot/reference/mcp-allowlist-enforcement). When a user tries to use an MCP server, Copilot compares the installed server's canonical ID against the IDs in your registry; **non-matching IDs are denied.** Don't rewrite the names — keep them exactly as the upstream/manifest defines them (e.g. `com.atlassian/atlassian-mcp-server`, not `com.atlassian.atlassian-mcp-server`).

## Updating

1. Edit `allowlist.json` — add or remove entries. Use the canonical upstream name (with `/`). `versions` is an array; each element is `"latest"` or a pinned semver. A bare `"version": "..."` string is still accepted.
2. Rebuild:
   ```bash
   ./registry/scripts/build.sh
   ```
3. Commit and push to `pages`:
   ```bash
   git add registry
   git commit -m "registry: refresh"
   git push origin pages
   ```

## Publishing several versions of one server

List more than one version to keep an older release resolvable while a newer one is the default:

```json
{
  "name": "com.example/foo-mcp",
  "versions": ["latest", "1.1.2"]
}
```

(No entry uses this today — every server in the allowlist is pinned to `latest` alone — but the build still supports it.)

Every listed version is fetched and published at its own `/versions/<semver>` path, and all of them appear in `/v0.1/servers`. That matches how the upstream registry presents a server's history, so the `isLatest` flag inside each blob stays accurate and nothing has to be rewritten by hand.

Two rules the build enforces:

- Only the entry requested as `"latest"` writes the `/versions/latest` alias — a pinned version never claims it. If a server is pinned without `"latest"`, the build warns, because Copilot will fetch that path and 404.
- Listing entries are deduplicated by *resolved* version, so naming both `"latest"` and the semver it currently resolves to publishes one copy, not two.

Keep in mind that Copilot's allowlist enforcement is name-based, not version-based (see below) — publishing several versions controls what the registry offers, not which version an already-installed client is allowed to use.

## Servers with no upstream entry

The Microsoft servers are Cerebras-built and Slack hasn't published its official remote server upstream, so `build.sh` has nothing to fetch. Those entries set `"source": "local"` and keep their blob at `local/<name>/<version>.json`, in the same `{server, _meta}` shape the upstream per-version endpoint returns.

The build fails loudly if the file is missing, or if `.server.name` inside it disagrees with the allowlist key — Copilot enforces on the name in the blob.

Conventions for local entries:

- **Names** use `net.cerebras.sec` (reverse-DNS of the proxy host), not `com.slack` or `com.microsoft` — namespaces we don't control and would collide on if the vendor publishes upstream later.
- **Remotes** point at the Runlayer proxy, not the vendor, so Copilot is under the same policy and audit as Claude Code. Upstream entries like Atlassian still point at the vendor directly.
- **`_meta`** uses `net.cerebras.registry/curated` rather than `io.modelcontextprotocol.registry/official`, which would be a false claim. Both validate; revisit if Copilot turns out to read the official key.

`net.cerebras.sec/atlassian` replaced the direct `com.atlassian/atlassian-mcp-server` entry once it was validated in Copilot, so every entry now routes through Runlayer. Anyone still installed under the old ID has to reinstall — Copilot enforces on server ID and that one no longer resolves.

Runlayer has four Atlassian servers and only one is fit for interactive use. `faad5da6` and `2ccdb53c` front `v1/mcp`, whose sign-in Copilot can't complete over Remote-SSH; `1bf125a8` and `2ccdb53c` inject a static API key, so every user shares one identity in the audit log. `f06f1af5` is `v2/mcp` with per-user OAuth.

One client-side gotcha, hit when Copilot first tried the Slack entry: Runlayer enforces an OAuth redirect-URI allowlist, and an unrecognised URI stalls the flow at the authorization screen. The list is org-wide (Settings → General → OAuth redirect URIs), not per-connector, so it's a one-time fix per client, not per server.

## Finding a server's canonical ID

```bash
curl -s "https://registry.modelcontextprotocol.io/v0.1/servers?search=<term>" | jq '.servers[].server.name'
```

Add it to `allowlist.json` exactly as returned:

```json
{
  "name": "com.example/foo-mcp",
  "versions": ["latest"],
  "notes": "Optional rationale for allowing this server."
}
```

## References

- [Configure an MCP registry for your organization or enterprise](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-registry)
- [Configure MCP server access](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-server-access)
- [MCP allowlist enforcement](https://docs.github.com/en/copilot/reference/mcp-allowlist-enforcement)
- [Generic Registry API spec](https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/api/generic-registry-api.md)
- [server.json format](https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/server-json/generic-server-json.md)
