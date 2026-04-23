# Security Policy

## Reporting a Vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

To report a vulnerability, use one of these channels:

- **GitHub private disclosure:** Use the [Security tab](https://github.com/TadMSTR/ollama-auth-sidecar/security/advisories/new) to submit a private advisory.
- **Email:** Send a description to `security.i9v75@8alias.com` with the subject line `[ollama-auth-sidecar] Security Report`.

Include as much detail as possible: the affected component, steps to reproduce, and potential impact.

## Scope

**In scope:**

- The sidecar Docker image and its entrypoint logic
- Config file parsing, env-var expansion, and validation
- Header injection logic and nginx config rendering
- Log redaction — sensitive header values appearing in access or error logs

**Out of scope:**

- Vulnerabilities in upstream Ollama or other services the sidecar proxies to
- Issues in consumer applications that point at the sidecar's listen ports
- The host system, Docker daemon, or network infrastructure
- Vulnerabilities that require attacker control of `config.yaml`
  (that is an operator-controlled trust boundary, not an input attack surface)

## Secrets Handling

**Never commit `config.yaml` with literal secret values.**

The config file uses `${ENV_VAR}` references — this is intentional. Inlining a literal
key (e.g. `Authorization: "Bearer sk-abc123"`) exposes it permanently in git history,
even if the file is later modified or deleted. Store keys in environment variables or
a secrets manager; reference them in config by name only.

If you accidentally committed a secret, rotate the key immediately and treat the old
value as compromised. A `git rebase` or `git filter-repo` to scrub the history does not
protect you — assume the value was already logged or cached.

## Trust Model

The sidecar's listen ports have **no authentication of their own** — any process or
container that can reach a configured port will have its requests forwarded with the
configured upstream credentials injected. This is by design; the sidecar assumes it
runs in a trusted boundary.

**Never bind `NGINX_BIND` to a non-loopback address on an untrusted network.** Doing so
exposes upstream credentials (API keys, Bearer tokens) to any host that can reach the
port. The default (`127.0.0.1`) is safe for host-local consumers. For containerized
consumers, use a dedicated named Docker network (Mode B) and ensure unrelated containers
do not join it.

## Response Expectations

| Stage | Timeline |
|-------|----------|
| Acknowledgement | Within 3 business days |
| Initial assessment | Within 7 business days |
| Fix or remediation plan | Within 30 days (critical/high); 60 days (medium/low) |

This is a personal project maintained by one developer. Response times are best-effort.
If you haven't heard back within 3 business days, a follow-up email is welcome.

## Disclosure

Coordinated disclosure is preferred. Please allow time for a fix to be released before
public disclosure. The CHANGELOG documents remediated findings at an appropriate level
of detail after each release.
