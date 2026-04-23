# Changelog

## [0.1.1] — 2026-04-23

### Security
- Replace `$request_uri` with `$uri` in nginx log format — prevents query strings from appearing in container stdout (relevant if upstream uses query-string API keys)
- Add test coverage for newline-in-header-value rejection (`header-special-chars.yaml` fixture now exercised in CI)
- Pin all GitHub Actions `uses:` references to commit SHAs in `ci.yml` and `release.yml`

## [0.1.0] — 2026-04-23

### Added
- Initial release: nginx-based auth sidecar for Ollama
- Per-client listen ports with `Authorization: Bearer` injection
- Config-driven multi-service support via `config.yaml`
- Strict `${ENV_VAR}` expansion in header values (fail-fast on unresolved refs)
- Mode A (host networking) and Mode B (shared bridge network) deployment options
- `/health` endpoint on each listen port (does not proxy to upstream)
- JSON access logs with header redaction for `Authorization`, `Cookie`, and related fields
- Integration test suite: header injection, streaming, timeouts, health, config validation, log redaction
- Docker hardening defaults in both compose examples (`cap_drop: ALL`, `read_only: true`, tmpfs)
- Multi-arch image published to `ghcr.io/tadmstr/ollama-auth-sidecar` (`linux/amd64`, `linux/arm64`)
- Security policy in `SECURITY.md` including trust model and key-handling guidance
