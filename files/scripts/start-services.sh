#!/bin/sh
set -eu

RT_LOG="/data/logs/rtorrent/rtorrent.log"
PHP_LOG="/data/logs/php/php-fpm.log"
RT_SESSION_DIR="/data/config/rtorrent/session"
RT_SOCKET="/run/rtorrent/rpc.socket"
PHP_SOCKET="/tmp/php/php-fpm.sock"

mkdir -p /data/logs/rtorrent /data/logs/php /data/logs/nginx /run/rtorrent /tmp/php "${RT_SESSION_DIR}"

# Limpa artefatos stale deixados por encerramentos abruptos anteriores.
rm -f "${RT_SOCKET}" "${RT_SESSION_DIR}/rtorrent.lock" "${PHP_SOCKET}"

tmux new-session -d -s rtorrent "exec rtorrent -n -o import=/etc/rtorrent/rtorrent.rc >> ${RT_LOG} 2>&1"

php-fpm8.3 -y /etc/php/8.3/fpm/php-fpm.conf -F >> "${PHP_LOG}" 2>&1 &
PHP_PID="$!"

wait_for_php_socket() {
  socket_path="$1"
  pid="$2"
  i=0
  while [ "$i" -lt 50 ]; do
    if [ -S "${socket_path}" ]; then
      return 0
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      echo "php-fpm encerrou antes de criar o socket ${socket_path}" >&2
      return 1
    fi
    i=$((i + 1))
    sleep 0.2
  done
  echo "Timeout aguardando o socket ${socket_path} de php-fpm" >&2
  return 1
}

wait_for_rtorrent() {
  i=0
  while [ "$i" -lt 50 ]; do
    if [ -S "${RT_SOCKET}" ]; then
      return 0
    fi
    if ! tmux has-session -t rtorrent 2>/dev/null; then
      echo "rtorrent encerrou antes de criar o socket ${RT_SOCKET}" >&2
      return 1
    fi
    i=$((i + 1))
    sleep 0.2
  done
  echo "Timeout aguardando o socket ${RT_SOCKET} de rtorrent" >&2
  return 1
}

wait_for_rtorrent
wait_for_php_socket "${PHP_SOCKET}" "${PHP_PID}"

cleanup() {
  if tmux has-session -t rtorrent 2>/dev/null; then
    tmux kill-session -t rtorrent || true
  fi
  if kill -0 "${PHP_PID}" 2>/dev/null; then
    kill "${PHP_PID}" || true
  fi
}

trap cleanup EXIT INT TERM

# nginx no primeiro plano para manter container vivo.
exec nginx -c /etc/nginx/nginx.conf -g 'daemon off;'
