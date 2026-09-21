#!/usr/bin/env bash
set -euo pipefail

REMOTE="${REMOTE:-root@68.183.185.48}"
CONTAINER="${CONTAINER:-profit-monitor-db}"
LOCAL_PORT="${LOCAL_PORT:-15432}"

IP="$(ssh -o BatchMode=yes "$REMOTE" "docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' '$CONTAINER'")"
if [[ -z "$IP" ]]; then
	echo "Could not resolve $CONTAINER on $REMOTE" >&2
	exit 1
fi

echo "localhost:${LOCAL_PORT} -> ${REMOTE} ${CONTAINER} ${IP}:5432"
exec ssh -N -L "${LOCAL_PORT}:${IP}:5432" "$REMOTE"
