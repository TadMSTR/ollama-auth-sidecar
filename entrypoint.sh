#!/bin/sh
set -eu

CONFIG_PATH="${CONFIG_PATH:-/etc/ollama-auth-sidecar/config.yaml}"
NGINX_BIND="${NGINX_BIND:-127.0.0.1}"
TEMPLATE_DIR="${TEMPLATE_DIR:-/templates}"
NGINX_CONF="/tmp/nginx.conf"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# Expand ${VAR_NAME} tokens in a string using only strict POSIX env var names.
# Uses bash parameter substitution to avoid sed injection with /, \, &, newlines.
# Any pattern outside ${[A-Z_][A-Z0-9_]*} is left literal.
expand_vars() {
    local value="$1"
    local result="$value"

    # Extract all ${VAR} tokens from the value
    local tokens
    tokens=$(printf '%s' "$value" | grep -oE '\$\{[A-Z_][A-Z0-9_]*\}' || true)

    for token in $tokens; do
        # Strip ${ and }
        local varname="${token#\$\{}"
        varname="${varname%\}}"

        # Look up the variable; fail fast if unset or empty
        eval "local varval=\"\${${varname}:-}\""
        if [ -z "$varval" ]; then
            die "Env var '${varname}' is referenced in config but is unset or empty (service context: ${SERVICE_CTX:-unknown})"
        fi

        # Bash string substitution treats replacement as literal — no sed injection
        result="${result//"${token}"/"${varval}"}"
    done

    printf '%s' "$result"
}

# Validate that a value is a valid URL (basic check)
is_valid_url() {
    case "$1" in
        http://*|https://*) return 0 ;;
        *) return 1 ;;
    esac
}

# Validate that a port is in the allowed range
is_valid_port() {
    local port="$1"
    case "$port" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$port" -ge 1024 ] && [ "$port" -le 65535 ]
}

# Escape a value so it is safe inside an nginx double-quoted string.
# Rejects characters that cannot be safely represented.
# Note: uses POSIX sh compatible constructs (ash-safe; no bash $'\n' escapes).
escape_header_value() {
    local val="$1"

    # Reject newlines — these cannot appear in an nginx header directive.
    # Use printf to produce a literal newline for the comparison (ash-safe).
    local newline
    newline=$(printf '\n')
    case "$val" in
        *"$newline"*) die "Header value for service '${SERVICE_CTX:-unknown}' contains a newline, which is not allowed in nginx directives" ;;
    esac

    # Null bytes cannot appear in shell environment variables (OS strips them),
    # so no explicit check is needed here.

    # Escape backslash and double-quote for embedding inside nginx double-quotes
    val=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')

    # Reject bare $ remaining after env-var expansion — all ${VAR} tokens were
    # already resolved; a leftover $ indicates an unterminated reference.
    case "$val" in
        *\$*)
            die "Header value for service '${SERVICE_CTX:-unknown}' contains a bare '\$' after env-var expansion. Check config for unterminated variable references."
            ;;
    esac
    printf '%s' "$val"
}

main() {
    [ -f "$CONFIG_PATH" ] || die "Config file not found: $CONFIG_PATH"

    # Verify yq is available and can parse the file
    yq e '.' "$CONFIG_PATH" > /dev/null 2>&1 || die "Config file is not valid YAML: $CONFIG_PATH"

    local service_count
    service_count=$(yq e '.services | length' "$CONFIG_PATH")
    [ "$service_count" -gt 0 ] || die "No services defined in config"

    local seen_ports=""
    local seen_names=""
    local server_blocks=""

    i=0
    while [ "$i" -lt "$service_count" ]; do
        local svc_name svc_listen svc_upstream svc_timeout

        svc_name=$(yq e ".services[$i].name" "$CONFIG_PATH")
        svc_listen=$(yq e ".services[$i].listen" "$CONFIG_PATH")
        svc_upstream=$(yq e ".services[$i].upstream" "$CONFIG_PATH")
        svc_timeout=$(yq e ".services[$i].timeout // \"120s\"" "$CONFIG_PATH")

        [ -z "$svc_name" ] || [ "$svc_name" = "null" ] && die "Service[$i]: missing required field 'name'"
        [ -z "$svc_listen" ] || [ "$svc_listen" = "null" ] && die "Service[$i]: missing required field 'listen'"
        [ -z "$svc_upstream" ] || [ "$svc_upstream" = "null" ] && die "Service[$i]: missing required field 'upstream'"

        # Validate port
        is_valid_port "$svc_listen" || die "Service '$svc_name': listen port '$svc_listen' is not in range 1024–65535"

        # Check for duplicate ports
        case "$seen_ports" in
            *" $svc_listen "*) die "Service '$svc_name': port $svc_listen is already used by another service" ;;
        esac
        seen_ports="$seen_ports $svc_listen "

        # Check for duplicate names
        case "$seen_names" in
            *" $svc_name "*) die "Duplicate service name: '$svc_name'" ;;
        esac
        seen_names="$seen_names $svc_name "

        # Validate upstream URL
        is_valid_url "$svc_upstream" || die "Service '$svc_name': upstream '$svc_upstream' is not a valid http/https URL"

        # Build proxy_set_header directives from headers map
        local header_count
        header_count=$(yq e ".services[$i].headers | length" "$CONFIG_PATH")
        local header_directives=""
        SERVICE_CTX="$svc_name"

        j=0
        while [ "$j" -lt "$header_count" ]; do
            local hdr_name hdr_raw hdr_expanded hdr_safe

            hdr_name=$(yq e ".services[$i].headers | keys | .[$j]" "$CONFIG_PATH")
            hdr_raw=$(yq e ".services[$i].headers[\"$hdr_name\"]" "$CONFIG_PATH")

            # Expand ${VAR} tokens; fails fast on unresolved refs
            hdr_expanded=$(expand_vars "$hdr_raw")

            # Escape for nginx directive
            hdr_safe=$(escape_header_value "$hdr_expanded")

            header_directives="${header_directives}    proxy_set_header ${hdr_name} \"${hdr_safe}\";
"
            j=$((j + 1))
        done

        # Render server block from template
        local block
        block=$(BIND="$NGINX_BIND" \
                PORT="$svc_listen" \
                UPSTREAM="$svc_upstream" \
                TIMEOUT="$svc_timeout" \
                SERVICE_NAME="$svc_name" \
                HEADER_DIRECTIVES="$header_directives" \
                envsubst '${BIND} ${PORT} ${UPSTREAM} ${TIMEOUT} ${SERVICE_NAME} ${HEADER_DIRECTIVES}' \
                < "${TEMPLATE_DIR}/server-block.conf.tmpl")

        server_blocks="${server_blocks}
${block}
"
        i=$((i + 1))
    done

    # Write final nginx.conf
    # Note: no 'user' directive — container already runs as the nginx user (uid 101)
    # via USER in Dockerfile. The 'user' directive requires root to take effect.
    cat > "$NGINX_CONF" <<NGINX_HEADER
worker_processes auto;
error_log /dev/stderr warn;
pid /tmp/nginx.pid;

events {
    worker_connections 1024;
}

http {
    log_format json_combined escape=json
        '{'
        '"time":"\$time_iso8601",'
        '"remote_addr":"\$remote_addr",'
        '"request_method":"\$request_method",'
        '"request_uri":"\$request_uri",'
        '"status":\$status,'
        '"request_time":\$request_time,'
        '"upstream_response_time":"\$upstream_response_time",'
        '"upstream_addr":"\$upstream_addr"'
        '}';

${server_blocks}
}
NGINX_HEADER

    # Validate the rendered config
    nginx -t -c "$NGINX_CONF" || die "nginx config validation failed — see errors above"

    exec nginx -c "$NGINX_CONF" -g 'daemon off;'
}

main "$@"
