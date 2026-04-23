FROM nginx:1.27-alpine

# yq for YAML parsing; gettext for envsubst used in template rendering
RUN apk add --no-cache yq gettext

# Standard config path; override via CONFIG_PATH env var
RUN mkdir -p /etc/ollama-auth-sidecar

COPY entrypoint.sh /entrypoint.sh
COPY templates/ /templates/

RUN chmod +x /entrypoint.sh

# nginx:alpine ships with an nginx user (uid 101); use it
USER nginx

ENTRYPOINT ["/entrypoint.sh"]
