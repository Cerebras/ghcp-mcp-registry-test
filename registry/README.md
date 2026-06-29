# registry

A statically-hosted MCP server registry for Cerebras, conforming to the [GitHub Copilot MCP registry contract](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-registry) (v0.1).

Served from the `pages` branch at:

```
https://cerebras.github.io/ghcp-mcp-registry/registry/
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
| `allowlist.json` | Source of truth — which MCP servers are exposed and at what pinned version. Uses canonical server IDs (with `/`). |
| `scripts/build.sh` | Pulls each allowlisted server from `registry.modelcontextprotocol.io` and regenerates the static endpoints. |
| `v0.1/...` | Generated. Do not edit by hand. |
| `index.html` | Human-readable landing page. |

## CORS

GitHub Pages already sends `Access-Control-Allow-Origin: *` on every response, which is enough for Copilot's simple `GET` fetches. If Copilot ever sends a preflighted request (custom headers like `Authorization`), GH Pages won't add `Access-Control-Allow-Methods` / `Access-Control-Allow-Headers`, and you'd need to front the site with a proxy (e.g. a Cloudflare Worker) that injects them.

## Why the server ID must match exactly

GitHub Copilot's MCP allowlist enforcement is name-based — see [MCP allowlist enforcement](https://docs.github.com/en/copilot/reference/mcp-allowlist-enforcement). When a user tries to use an MCP server, Copilot compares the installed server's canonical ID against the IDs in your registry; **non-matching IDs are denied.** Don't rewrite the names — keep them exactly as the upstream/manifest defines them (e.g. `com.atlassian/atlassian-mcp-server`, not `com.atlassian.atlassian-mcp-server`).

## Updating

1. Edit `allowlist.json` — add or remove entries. Use the canonical upstream name (with `/`). `version` can be `"latest"` or a pinned semver.
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

## Finding a server's canonical ID

```bash
curl -s "https://registry.modelcontextprotocol.io/v0.1/servers?search=<term>" | jq '.servers[].server.name'
```

Add it to `allowlist.json` exactly as returned:

```json
{
  "name": "com.example/foo-mcp",
  "version": "latest",
  "notes": "Optional rationale for allowing this server."
}
```

## References

- [Configure an MCP registry for your organization or enterprise](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-registry)
- [Configure MCP server access](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-mcp-usage/configure-mcp-server-access)
- [MCP allowlist enforcement](https://docs.github.com/en/copilot/reference/mcp-allowlist-enforcement)
- [Generic Registry API spec](https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/api/generic-registry-api.md)
- [server.json format](https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/server-json/generic-server-json.md)
