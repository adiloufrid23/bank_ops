FROM nginx:1.25-alpine

LABEL maintainer="bankops-team"

COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80 443

HEALTHCHECK --interval=15s --timeout=5s --retries=3 \
    CMD wget -qO- http://localhost/nginx-health || exit 1
