# syntax=docker/dockerfile:1

FROM node:22-alpine AS builder

WORKDIR /app

COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci

COPY frontend/ ./
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.30-alpine

USER root

# The upstream image lags Alpine security releases; pull in the patched
# OS packages so the weekly vulnerability scan tracks the Alpine repos.
RUN apk upgrade --no-cache

COPY --from=builder --chown=101:101 /app/dist /usr/share/nginx/html

# The server block and its security-header snippet live in the repository so
# the Content-Security-Policy is reviewable as nginx source instead of an
# escaped printf string. nginx -t fails the build on a malformed policy.
COPY frontend/nginx/security-headers.conf /etc/nginx/rentivo-security-headers.conf
COPY frontend/nginx/default.conf /etc/nginx/conf.d/default.conf

# nginx -t runs as root (this RUN executes before "USER 101" below) and, as a
# side effect, creates /tmp/nginx.pid owned by root:root with mode 644. If
# that file were left in the image layer, the unprivileged nginx user could
# never open it for writing at startup and the container would fail to boot
# entirely. Clear /tmp so nginx creates its runtime pid file and temp
# directories fresh, owned by the user that actually runs the process.
RUN nginx -t && rm -rf /tmp/*

USER 101

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD wget -q -O /dev/null http://localhost:8080/

ENTRYPOINT ["nginx", "-g", "daemon off;"]
