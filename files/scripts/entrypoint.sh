#!/bin/sh
set -eu

TIMEZONE="${TIMEZONE:-America/Fortaleza}"
APP_UID="${UID:-1000}"
APP_GID="${GID:-1000}"
RT_DOWNLOAD_RATE_KB="${RT_DOWNLOAD_RATE_KB:-0}"
RT_UPLOAD_RATE_KB="${RT_UPLOAD_RATE_KB:-0}"

export DEBIAN_FRONTEND=noninteractive
ln -snf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
printf '%s\n' "${TIMEZONE}" > /etc/timezone

if ! getent group rutorrent >/dev/null 2>&1; then
  addgroup --gid "${APP_GID}" rutorrent
fi

EXISTING_GROUP="$(getent group "${APP_GID}" | cut -d: -f1 || true)"
if [ -n "${EXISTING_GROUP}" ] && [ "${EXISTING_GROUP}" != "rutorrent" ]; then
  echo "GID ${APP_GID} ja esta em uso pelo grupo ${EXISTING_GROUP}" >&2
  exit 1
fi

CURRENT_GID="$(id -g rutorrent)"
if [ "${CURRENT_GID}" != "${APP_GID}" ]; then
  groupmod -o -g "${APP_GID}" rutorrent
fi

EXISTING_USER="$(getent passwd "${APP_UID}" | cut -d: -f1 || true)"
if [ -n "${EXISTING_USER}" ] && [ "${EXISTING_USER}" != "rutorrent" ]; then
  echo "UID ${APP_UID} ja esta em uso pelo usuario ${EXISTING_USER}" >&2
  exit 1
fi

CURRENT_UID="$(id -u rutorrent)"
if [ "${CURRENT_UID}" != "${APP_UID}" ]; then
  usermod -o -u "${APP_UID}" -g "${APP_GID}" rutorrent
fi

EXTERNAL_IP="$(curl -fsSL https://ipinfo.io/json | jq -r '.ip // empty' || true)"
if [ -z "${EXTERNAL_IP}" ]; then
  EXTERNAL_IP="0.0.0.0"
fi

mkdir -p \
  /data/downloads \
  /data/config/rtorrent/session \
  /data/config/rtorrent/watch \
  /data/logs/nginx \
  /data/logs/php \
  /data/logs/rtorrent \
  /run/rtorrent \
  /tmp/nginx \
  /tmp/php

for template in \
  /templates/nginx.conf.template \
  /templates/rutorrent.conf.template \
  /templates/php-fpm.conf.template \
  /templates/php-www.conf.template \
  /templates/rtorrent.rc.template \
  /templates/rutorrent-config.php.template
  do
    [ -f "$template" ] || { echo "Template ausente: $template"; exit 1; }
  done

sed -e "s|__TIMEZONE__|${TIMEZONE}|g" \
    -e "s|__UID__|${APP_UID}|g" \
    -e "s|__GID__|${APP_GID}|g" \
    -e "s|__EXTERNAL_IP__|${EXTERNAL_IP}|g" \
    -e "s|__RT_DOWNLOAD_RATE_KB__|${RT_DOWNLOAD_RATE_KB}|g" \
    -e "s|__RT_UPLOAD_RATE_KB__|${RT_UPLOAD_RATE_KB}|g" \
    /templates/nginx.conf.template > /etc/nginx/nginx.conf

sed -e "s|__TIMEZONE__|${TIMEZONE}|g" \
    -e "s|__UID__|${APP_UID}|g" \
    -e "s|__GID__|${APP_GID}|g" \
    -e "s|__EXTERNAL_IP__|${EXTERNAL_IP}|g" \
    -e "s|__RT_DOWNLOAD_RATE_KB__|${RT_DOWNLOAD_RATE_KB}|g" \
    -e "s|__RT_UPLOAD_RATE_KB__|${RT_UPLOAD_RATE_KB}|g" \
    /templates/rutorrent.conf.template > /etc/nginx/conf.d/rutorrent.conf

sed -e "s|__TIMEZONE__|${TIMEZONE}|g" \
    -e "s|__UID__|${APP_UID}|g" \
    -e "s|__GID__|${APP_GID}|g" \
    /templates/php-fpm.conf.template > /etc/php/8.3/fpm/php-fpm.conf

sed -e "s|__TIMEZONE__|${TIMEZONE}|g" \
    -e "s|__UID__|${APP_UID}|g" \
    -e "s|__GID__|${APP_GID}|g" \
    /templates/php-www.conf.template > /etc/php/8.3/fpm/pool.d/www.conf

sed -e "s|__TIMEZONE__|${TIMEZONE}|g" \
    -e "s|__UID__|${APP_UID}|g" \
    -e "s|__GID__|${APP_GID}|g" \
    -e "s|__EXTERNAL_IP__|${EXTERNAL_IP}|g" \
    -e "s|__RT_DOWNLOAD_RATE_KB__|${RT_DOWNLOAD_RATE_KB}|g" \
    -e "s|__RT_UPLOAD_RATE_KB__|${RT_UPLOAD_RATE_KB}|g" \
    /templates/rtorrent.rc.template > /etc/rtorrent/rtorrent.rc

sed -e "s|__TIMEZONE__|${TIMEZONE}|g" \
    -e "s|__UID__|${APP_UID}|g" \
    -e "s|__GID__|${APP_GID}|g" \
    -e "s|__EXTERNAL_IP__|${EXTERNAL_IP}|g" \
    /templates/rutorrent-config.php.template > /var/www/rutorrent/conf/config.php

chown -R "${APP_UID}:${APP_GID}" /data /var/www/rutorrent /run/rtorrent /tmp/nginx /tmp/php /etc/rtorrent

exec gosu rutorrent:rutorrent /usr/local/bin/start-services.sh
