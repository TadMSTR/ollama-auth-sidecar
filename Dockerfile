FROM nginx:1.27-alpine

# yq for YAML parsing; gettext for envsubst used in template rendering
RUN apk add --no-cache yq gettext

# Standard config path; override via CONFIG_PATH env var
# Also pre-create nginx runtime dirs owned by the nginx user so the process
# can start without root — /var/cache/nginx is owned by root in the base image.
RUN mkdir -p /etc/ollama-auth-sidecar \
    && chown -R nginx:nginx /var/cache/nginx /var/run

COPY entrypoint.sh /entrypoint.sh
COPY templates/ /templates/

RUN chmod +x /entrypoint.sh

# nginx:alpine ships with an nginx user (uid 101); use it
USER nginx

ENTRYPOINT ["/entrypoint.sh"]
