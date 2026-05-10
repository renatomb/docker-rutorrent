FROM ubuntu:24.04
LABEL org.opencontainers.image.title="ruTorrent" \
      org.opencontainers.image.description="ruTorrent (Ubuntu) with RTorrent" \
      org.opencontainers.image.url="https://hub.docker.com/r/renatomb/rutorrent" \
      org.opencontainers.image.source="https://github.com/renatomb/rutorrent" \
      org.opencontainers.image.authors="Renato Monteiro Batista <https://github.com/renatomb>" \
      org.opencontainers.image.licenses="MIT"

ARG DEBIAN_FRONTEND=noninteractive
ARG RUTORRENT_REPO=https://github.com/Novik/ruTorrent.git
ARG RUTORRENT_REF=master

RUN if getent passwd ubuntu >/dev/null 2>&1; then userdel --remove ubuntu || userdel ubuntu; fi && \
    if getent group ubuntu >/dev/null 2>&1; then groupdel ubuntu; fi

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gosu \
    jq \
    nginx \
    php8.3-cli \
    php8.3-curl \
    php8.3-fpm \
    php8.3-mbstring \
    php8.3-xml \
    php8.3-zip \
    rtorrent \
    tmux \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system rutorrent && \
    useradd --system --home-dir /home/rutorrent --create-home --shell /bin/bash --gid rutorrent rutorrent

RUN mkdir -p /var/www/rutorrent \
    /etc/rtorrent \
    /etc/nginx/conf.d \
    /data/downloads \
    /data/config/rtorrent/session \
    /data/config/rtorrent/watch \
    /data/logs \
    /run/rtorrent \
    /tmp/nginx \
    /tmp/php

RUN git clone --depth 1 --branch ${RUTORRENT_REF} ${RUTORRENT_REPO} /var/www/rutorrent

COPY files/nginx/nginx.conf.template /templates/nginx.conf.template
COPY files/nginx/conf.d/rutorrent.conf.template /templates/rutorrent.conf.template
COPY files/php-fpm/php-fpm.conf.template /templates/php-fpm.conf.template
COPY files/php-fpm/pool.d/www.conf.template /templates/php-www.conf.template
COPY files/rtorrent/rtorrent.rc.template /templates/rtorrent.rc.template
COPY files/rutorrent/conf/config.php.template /templates/rutorrent-config.php.template
COPY files/scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY files/scripts/start-services.sh /usr/local/bin/start-services.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/start-services.sh && \
    chown -R rutorrent:rutorrent /var/www/rutorrent /data /run/rtorrent /tmp/nginx /tmp/php

EXPOSE 8666 51413 51413/udp 51414

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
