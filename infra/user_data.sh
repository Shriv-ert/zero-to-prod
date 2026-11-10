#!/bin/bash
set -euxo pipefail
dnf install -y docker git
systemctl enable --now docker
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/download/v2.32.4/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

rm -rf /opt/src && git clone --depth 1 https://github.com/Shriv-ert/zero-to-prod.git /opt/src
mkdir -p /opt/app && cp -r /opt/src/deploy/. /opt/app/
cat > /opt/app/.env <<EOF
APP_IMAGE=${image}
GRAFANA_PASSWORD=${grafana_password}
GREETING=hello from AWS
EOF
cd /opt/app && docker compose up -d
