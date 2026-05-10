# ruTorrent Docker (Ubuntu)

![Docker Pulls](https://img.shields.io/docker/pulls/renatomb/rutorrent?logo=docker)
![Docker Image Size](https://img.shields.io/docker/image-size/renatomb/rutorrent/latest?logo=docker)
![Build](https://github.com/renatomb/docker-rutorrent/actions/workflows/docker-publish.yml/badge.svg)
![GitHub Repo stars](https://img.shields.io/github/stars/renatomb/docker-rutorrent?logo=github)

Projeto completo para executar **rTorrent + ruTorrent + nginx + php-fpm** em um único container Ubuntu, com:

- execução final como usuário **não-root** (UID/GID configurável)
- timezone configurável (padrão `America/Fortaleza`)
- IP externo obtido de `https://ipinfo.io/json`

## Estrutura

```text
.
├── Dockerfile
├── docker-compose.yml
├── files/
│   ├── nginx/
│   │   ├── nginx.conf.template
│   │   └── conf.d/
│   │       └── rutorrent.conf.template
│   ├── php-fpm/
│   │   ├── php-fpm.conf.template
│   │   └── pool.d/
│   │       └── www.conf.template
│   ├── rtorrent/
│   │   └── rtorrent.rc.template
│   ├── rutorrent/
│   │   └── conf/
│   │       └── config.php.template
│   └── scripts/
│       ├── entrypoint.sh
│       └── start-services.sh
└── README.md
```

## Variáveis de ambiente

No `docker-compose.yml`:

- `TIMEZONE` (padrão: `America/Fortaleza`)
- `UID` (padrão: `1000`)
- `GID` (padrão: `1000`)
- `RT_DOWNLOAD_RATE_KB` e `RT_UPLOAD_RATE_KB` (exemplo ativo 10/1 Mbps; ilimitado comentado)

> 10 Mbps ≈ 1250 KB/s e 1 Mbps ≈ 125 KB/s.

## Portas

- `8666:8666` → Interface Web ruTorrent
- `51413:51413/tcp` → tráfego torrent TCP
- `51413:51413/udp` → tráfego torrent UDP
- `51414:51414` → DHT
- **Porta 5000 não é exposta** (SCGI via socket Unix interno)

## Volumes

- `./downloads:/data/downloads`
- `./config:/data/config`
- `./logs:/data/logs`

Validar o XML-RPC do rTorrent:

```bash
curl -H 'Content-Type: text/xml' \
  --data '<?xml version="1.0"?><methodCall><methodName>system.client_version</methodName><params></params></methodCall>' \
  http://localhost:8666/RPC2
```

## Observações técnicas

- O `entrypoint.sh` aplica substitutions por `sed` em todos os templates de `files/`.
- O IP externo é resolvido em runtime via:
  - `curl -fsSL https://ipinfo.io/json | jq -r '.ip'`
- O `rtorrent.rc` foi escrito com sintaxe moderna (`*.set`) e sem comandos obsoletos clássicos (`scgi_port`, etc.).
- Nginx e PHP-FPM usam sockets locais internos.
- O bootstrap remove socket e lock stale do rTorrent em reinicializacoes, evitando erro de sessao presa no volume persistente.

## Autor

Renato Monteiro Batista [https://github.com/renatomb/docker-rutorrent](https://github.com/renatomb/docker-rutorrent)