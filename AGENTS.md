# ollama-auth-sidecar

Shell-script-based Docker sidecar that generates an nginx reverse proxy config from a YAML service config file. Provides per-client API key authentication for Ollama and other HTTP services.

## What it does

Reads `config.yaml` at container startup, expands env vars, validates all inputs, generates `nginx.conf` from a template, and starts nginx. Any validation failure calls `die()` rather than starting with an insecure config.

## Structure

```
entrypoint.sh              Main script — reads config.yaml, expands env vars,
                           generates nginx.conf, starts nginx
templates/
  nginx.conf.template      nginx config template with ${VAR} placeholders
compose.mode-a.yml         Docker Compose: sidecar + Ollama in same network
compose.mode-b.yml         Docker Compose: sidecar in front of external Ollama
config.example.yaml        Reference config with placeholder values
tests/                     Shell/Python tests
Dockerfile                 Alpine + nginx + bash
```

## Architecture decisions

- **`expand_vars()` uses bash parameter substitution, not sed** — prevents injection via `$`, `/`, `\`, and `&` characters in env var values. Do not replace this with a sed-based approach without equivalent escaping.
- **`escape_header_value()` rejects newlines** — nginx header injection via newlines is explicitly blocked. The check uses a POSIX sh literal newline variable. Do not remove or weaken this check.
- **Port validation enforces 1024–65535** — system ports are rejected at config parse time.
- **URL validation enforces `http://` or `https://`** — bare hostnames and other schemes are rejected. The upstream target must be a full URL.
- **All validation runs before nginx starts** — `is_valid_url`, `is_valid_port`, `escape_header_value` are all called at config parse time. A bad config causes `die()` immediately.

## Testing

See `tests/` for test runner instructions.

## Git workflow

Branch before editing — do not commit directly to `main`.
