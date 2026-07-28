# TurboClaude in a minimal Alpine container.
#
# No systemd here on purpose: install.sh already falls back to cron when
# systemctl isn't available, so dcron (a lightweight cron daemon) is enough.
# Don't build/run this image directly for a new account: use
# ./docker-new-account.sh <name> on the host, it scaffolds the per-account
# volumes and the docker-compose.yml service (see README's Docker section).
FROM alpine:3.20

RUN apk add --no-cache bash coreutils dcron tzdata nodejs npm ca-certificates tini jq

RUN npm install -g @anthropic-ai/claude-code

WORKDIR /opt/turbo-claude
COPY . .
RUN chmod +x *.sh

ENV HOME=/root
ENV XDG_CONFIG_HOME=/root/.config
ENV XDG_DATA_HOME=/root/.local/share
ENV XDG_BIN_HOME=/root/.local/bin

# Guided-install defaults, overridable at `docker run -e ...`.
ENV PROMPT="Oi"
ENV TIMES="05:00,10:00,15:00"
ENV DAYS="*"
ENV LOG_RESPONSE="true"
# Without this, cron schedules and log timestamps are UTC, which almost
# never matches what you typed in the guided install. docker-new-account.sh
# sets this per-account from the host's own timezone.
ENV TZ="UTC"

ENTRYPOINT ["/sbin/tini", "--", "/opt/turbo-claude/docker-entrypoint.sh"]
