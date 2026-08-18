#!/bin/sh
set -eu

TIMEZONE="${TIMEZONE:-America/Fortaleza}"
APP_UID="${UID:-1000}"
APP_GID="${GID:-1000}"
RT_DOWNLOAD_RATE_KB="${RT_DOWNLOAD_RATE_KB:-0}"
RT_UPLOAD_RATE_KB="${RT_UPLOAD_RATE_KB:-0}"

export DEBIAN_FRONTEND=noninteractive

# --- Timezone ---
ln -snf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
printf '%s\n' "${TIMEZONE}" > /etc/timezone
export TZ="${TIMEZONE}"

# Forca a timezone no PHP (FPM e CLI), pois o PHP ignora /etc/localtime
printf 'date.timezone = %s\n' "${TIMEZONE}" > /etc/php/8.3/fpm/conf.d/99-timezone.ini
printf 'date.timezone = %s\n' "${TIMEZONE}" > /etc/php/8.3/cli/conf.d/99-timezone.ini

# --- Grupo ---
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

# --- Usuario ---
EXISTING_USER="$(getent passwd "${APP_UID}" | cut -d: -f1 || true)"
if [ -n "${EXISTING_USER}" ] && [ "${EXISTING_USER}" != "rutorrent" ]; then
  echo "UID ${APP_UID} ja esta em uso pelo usuario ${EXISTING_USER}" >&2
  exit 1
fi
CURRENT_UID="$(id -u rutorrent)"
if [ "${CURRENT_UID}" != "${APP_UID}" ]; then
  usermod -o -u "${APP_UID}" -g "${APP_GID}" rutorrent
fi

# --- IP externo ---
EXTERNAL_IP="$(curl -fsSL https://ipinfo.io/json | jq -r '.ip // empty' || true)"
if [ -z "${EXTERNAL_IP}" ]; then
  EXTERNAL_IP="0.0.0.0"
fi

# --- Diretorios persistentes ---
mkdir -p \
  /data/downloads \
  /data/config/rtorrent/session \
  /data/config/rtorrent/watch \
  /data/config/rutorrent/share \
  /data/logs/nginx \
  /data/logs/php \
  /data/logs/rtorrent \
  /run/rtorrent \
  /tmp/nginx \
  /tmp/php

# --- Verificacao de templates ---
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

# --- Configs efemeras (sempre regeradas a cada boot) ---
# nginx, php-fpm e config.php do ruTorrent sao infra/deploy e nao guardam
# estado de uso, entao podem ser reescritos sem problema.
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
    /templates/rutorrent-config.php.template > /var/www/rutorrent/conf/config.php

# >>> rtorrent.rc PERSISTENTE (env como SEED, so no primeiro boot) <<<
# O arquivo de verdade vive no volume: /data/config/rtorrent/rtorrent.rc
# - 1o boot (ou arquivo ausente): gera a partir do template usando os envs.
# - Boots seguintes: preserva o que estiver no volume (inclusive ajustes
#   feitos pelo usuario), a menos que RT_FORCE_RC=1 seja passado.
RTORRENT_RC_PERSIST="/data/config/rtorrent/rtorrent.rc"
RT_FORCE_RC="${RT_FORCE_RC:-0}"

if [ ! -f "${RTORRENT_RC_PERSIST}" ] || [ "${RT_FORCE_RC}" = "1" ]; then
  echo "Gerando rtorrent.rc a partir do template (seed via env)..."
  sed -e "s|__TIMEZONE__|${TIMEZONE}|g" \
      -e "s|__UID__|${APP_UID}|g" \
      -e "s|__GID__|${APP_GID}|g" \
      -e "s|__EXTERNAL_IP__|${EXTERNAL_IP}|g" \
      -e "s|__RT_DOWNLOAD_RATE_KB__|${RT_DOWNLOAD_RATE_KB}|g" \
      -e "s|__RT_UPLOAD_RATE_KB__|${RT_UPLOAD_RATE_KB}|g" \
      /templates/rtorrent.rc.template > "${RTORRENT_RC_PERSIST}"
else
  echo "Mantendo rtorrent.rc existente do volume (nao sobrescrito)."
fi

# O IP externo muda entre reinicios, entao mantemos essa unica linha sempre
# atualizada no arquivo persistente, sem tocar no resto das preferencias.
if grep -q '^network.local_address.set' "${RTORRENT_RC_PERSIST}"; then
  sed -i "s|^network.local_address.set.*|network.local_address.set = ${EXTERNAL_IP}|" \
      "${RTORRENT_RC_PERSIST}"
fi

# rTorrent le de /etc/rtorrent/rtorrent.rc -> aponta pro arquivo do volume.
ln -snf "${RTORRENT_RC_PERSIST}" /etc/rtorrent/rtorrent.rc

# Popular o share persistente preservando a estrutura de fabrica.
# Copia apenas o que estiver faltando (nao sobrescreve dados do usuario).
if [ ! -d /var/www/rutorrent/share/torrents ]; then
  cp -a -n /var/www/rutorrent/share.skel/. /var/www/rutorrent/share/ 2>/dev/null || true
fi

mkdir -p /var/www/rutorrent/share/settings \
         /var/www/rutorrent/share/torrents \
         /var/www/rutorrent/share/users
# <<< fim do bloco persistente >>>

# --- Permissoes ---
chown -R "${APP_UID}:${APP_GID}" \
  /data /var/www/rutorrent /run/rtorrent /tmp/nginx /tmp/php /etc/rtorrent

exec gosu rutorrent:rutorrent /usr/local/bin/start-services.sh