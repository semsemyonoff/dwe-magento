#!/bin/sh
# Runs inside a throwaway curlimages/curl container attached to the compose
# project network. Talks to redis-insight:5540 by service hostname — the
# host-published port hits the SPA router and returns 404 for /api/*.
#
# Idempotent: the PATCH on settings is a no-op once accepted; the DB POSTs are
# gated on the database list being empty, so re-running on every `dwe run` is safe.
set -eu

base="http://redis-insight:5540"

# Redis Insight has no compose healthcheck — poll its API instead.
for _ in $(seq 1 30); do
  curl -fsS -o /dev/null "$base/api/settings" && break
  sleep 1
done

curl -fsS -X PATCH "$base/api/settings" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{"agreements":{"analytics":false,"notifications":false,"encryption":false,"eula":true}}' \
  >/dev/null

if [ "$(curl -fsS "$base/api/databases" | tr -d '[:space:]')" = "[]" ]; then
  echo "Registering Magento Valkey (cache + session) with Redis Insight..."
  curl -fsS -X POST "$base/api/databases" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d '{"host":"valkey","name":"Magento (Cache)","port":6379,"tls":false,"db":0}' \
    >/dev/null
  curl -fsS -X POST "$base/api/databases" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d '{"host":"valkey","name":"Magento (Session)","port":6379,"tls":false,"db":2}' \
    >/dev/null
else
  echo "Redis Insight already has databases registered. Skipping."
fi
