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
  "name": "com.atlassian/atlassian-mcp-server",
  "versions": ["latest", "1.1.2"]
}
```

Every listed version is fetched and published at its own `/versions/<semver>` path, and all of them appear in `/v0.1/servers`. That matches how the upstream registry presents a server's history, so the `isLatest` flag inside each blob stays accurate and nothing has to be rewritten by hand.

Two rules the build enforces:

- Only the entry requested as `"latest"` writes the `/versions/latest` alias — a pinned version never claims it. If a server is pinned without `"latest"`, the build warns, because Copilot will fetch that path and 404.
- Listing entries are deduplicated by *resolved* version, so naming both `"latest"` and the semver it currently resolves to publishes one copy, not two.

Keep in mind that Copilot's allowlist enforcement is name-based, not version-based (see below) — publishing several versions controls what the registry offers, not which version an already-installed client is allowed to use.

## Servers with no upstream entry

Most of what we expose through Runlayer isn't in `registry.modelcontextprotocol.io` — the Microsoft Outlook/SharePoint/Teams servers are Cerebras-built, and Slack hasn't published its official remote server upstream. `build.sh` can't fetch what isn't there, so those entries set `"source": "local"`:

```json
{
  "name": "net.cerebras.sec/microsoft-sharepoint",
  "versions": ["latest"],
  "source": "local",
  "notes": "Cerebras-built SharePoint MCP server, Runlayer proxy 5305ba03."
}
```

and the blob lives at `local/net.cerebras.sec/microsoft-sharepoint/latest.json`, in the same `{server, _meta}` shape the upstream per-version endpoint returns. The published version still comes from `.server.version` inside the blob, so a `latest.json` carrying `1.0.0` lands at both `/versions/1.0.0` and `/versions/latest`, exactly as an upstream fetch would.

Two things the build checks, because a hand-maintained blob can drift in ways an upstream fetch can't:

- The file must exist — a missing `local/<name>/<version>.json` is a hard error, not a silently skipped server.
- `.server.name` inside the blob must equal the allowlist key. Copilot enforces on the name in the blob, so a mismatch would publish an entry nobody can use.

### Naming

Local entries use the `net.cerebras.sec` namespace (reverse-DNS of `sec.cerebras.net`, where the Runlayer proxies live). Deliberately *not* `com.slack` or `com.microsoft` — we don't control those namespaces, and squatting them would collide if the vendor later publishes upstream for real. The trade-off is that the ID a Copilot user sees is Cerebras-flavoured rather than vendor-flavoured.

### Remote URLs

Local entries point at the Runlayer proxy (`https://runlayer.sec.cerebras.net/api/v1/proxy/<uuid>/mcp`), not the vendor's own endpoint, so Copilot traffic is subject to the same policy and audit as Claude Code's. Note this differs from the Atlassian entry, which comes from upstream and therefore points straight at `mcp.atlassian.com`.

### `_meta`

Upstream blobs carry `_meta["io.modelcontextprotocol.registry/official"]`. Local blobs use `_meta["net.cerebras.registry/curated"]` instead — asserting the official namespace for a server the official registry has never seen would be false. The schema treats `_meta` as free-form extension data, so both validate; if Copilot turns out to read the official key specifically, this is the thing to revisit.

### Staged but not published

`local/` currently also holds four validated blobs that are **not** in `allowlist.json`:

| Server | Runlayer proxy |
| --- | --- |
| `net.cerebras.sec/microsoft-outlook-email` | `eeb341c6` |
| `net.cerebras.sec/microsoft-outlook-calendar` | `c128228b` |
| `net.cerebras.sec/microsoft-sharepoint` | `5305ba03` |
| `net.cerebras.sec/microsoft-teams` | `27ff6109` |

They're held back because the local-source path carries two assumptions that nothing has yet tested against Copilot itself:

1. Copilot accepts a server entry whose `_meta` lacks the `io.modelcontextprotocol.registry/official` key.
2. Copilot's MCP client can reach `runlayer.sec.cerebras.net` — an internal-only host — from wherever it runs. This is not a given: it connects from the client side, which for Remote-SSH users is the remote host, not the laptop. Every upstream entry in this registry points at a public hostname, so nothing here has exercised an internal one.

`net.cerebras.sec/slack` is published first as the canary. Both assumptions are identical across all five, so if Slack installs and authenticates in Copilot, add the four entries above with `"source": "local"` and rebuild. If it fails, the fix applies to all five at once and nothing else has to be rolled back.

Auth itself is the lower risk of the two: Runlayer's proxy presents the same OAuth flow as `mcp.atlassian.com/v2/mcp`, which is known to work in Copilot — `401` with `WWW-Authenticate: ... resource_metadata=`, `/.well-known/oauth-protected-resource`, an authorization server advertising a DCR `registration_endpoint`, and `authorization_code` with PKCE `S256`. The Atlassian `/v1/mcp` remote that Copilot *couldn't* sign into used the older method, which is why `latest` moved to v2.

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
