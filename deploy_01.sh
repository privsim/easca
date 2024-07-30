#!/bin/bash

# Step 1: Install Docker and Docker Compose
#sudo apt update
#sudo apt install -y docker.io docker-compose
#sudo systemctl enable docker
#sudo systemctl start docker

# Step 2: Directory Structure
mkdir -p ${PWD}/docker/{authelia,headscale,redis,mariadb,traefik/letsencrypt,traefik/certificates}
cd ~/docker

# Step 3: Secret Generation Script
cat > generate_secrets.sh <<EOF
#!/bin/bash

SECRET_DIR=${PWD}/docker/authelia/.secrets
SECRETS_FILE=${PWD}/docker/authelia/.secrets.env

mkdir -p "\${SECRET_DIR}"

generate_secret() {
  SECRET=\$(openssl rand -hex 32)
  echo "\${SECRET}" > "\${SECRET_DIR}/\$1"
  echo "AUTHELIA_\$1_FILE=/config/.secrets/\$1" >> "\${SECRETS_FILE}"
}

generate_secret "storage_mysql_password"
generate_secret "identity_providers_oidc_hmac_secret"

echo "Enter SMTP password:"
stty -echo
read SMTP
stty echo
echo "\${SMTP}" > "\${SECRET_DIR}/smtp"
echo "AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE=/config/.secrets/smtp" >> "\${SECRETS_FILE}"
echo

openssl genrsa -out "\${SECRET_DIR}/oidc.pem" 4096
openssl rsa -in "\${SECRET_DIR}/oidc.pem" -outform PEM -pubout -out "\${SECRET_DIR}/oidc.pub.pem"
echo "AUTHELIA_IDENTITY_PROVIDERS_OIDC_ISSUER_PRIVATE_KEY_FILE=/config/.secrets/oidc.pem" >> "\${SECRETS_FILE}"
echo "AUTHELIA_IDENTITY_PROVIDERS_OIDC_ISSUER_PUBLIC_KEY_FILE=/config/.secrets/oidc.pub.pem" >> "\${SECRETS_FILE}"

echo "Enter the domain name for the TLS certificate (e.g., yourdomain.com):"
read DOMAIN

openssl genpkey -algorithm RSA -out "\${SECRET_DIR}/tlskey.pem" -pkeyopt rsa_keygen_bits:4096
openssl req -new -key "\${SECRET_DIR}/tlskey.pem" -out "\${SECRET_DIR}/tlskey.csr" -subj "/CN=\${DOMAIN}"
openssl x509 -req -days 365 -in "\${SECRET_DIR}/tlskey.csr" -signkey "\${SECRET_DIR}/tlskey.pem" -out "\${SECRET_DIR}/tlscert.pem"
rm "\${SECRET_DIR}/tlskey.csr"
echo "AUTHELIA_SERVER_TLS_KEY_FILE=/config/.secrets/tlskey.pem" >> "\${SECRETS_FILE}"
echo "AUTHELIA_SERVER_TLS_CERTIFICATE_FILE=/config/.secrets/tlscert.pem" >> "\${SECRETS_FILE}"

chmod 600 -R "\${SECRET_DIR}"

echo "Secrets generated and saved in \${SECRET_DIR}"
echo "Environment variable mappings saved in \${SECRETS_FILE}"
EOF

chmod +x generate_secrets.sh
./generate_secrets.sh


# Step 4: Docker Compose Configuration
cat > docker-compose.yml <<EOF
version: '3.9'

services:
  traefik:
    image: traefik:v3.1
    container_name: traefik
    command:
      - "--api.insecure=true"
      - "--api.dashboard=true"
      - "--traefik.http.routers.api.rule=Host(\`traefik.\${DOMAIN}\`)"
      - "--traefik.http.routers.api.middlewares"
      - "--traefik.http.routers.api.service=api@internal"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--providers.docker.endpoint=tcp://docker-socket-proxy:2375"
      - "--providers.docker.exposedbydefault=false"
    ports:
      - "80:80"
      - "443:443"
      - "8888:8888"
    volumes:
      - "/home/${PWD}/docker/letsencrypt:/letsencrypt"
      - "/home/${PWD}/docker/traefik/traefik.yml:/etc/traefik/traefik.yml"
      - "/home/${PWD}/docker/traefik/fileConfig.yml:/etc/traefik/fileConfig.yml"
    networks:
      - proxy
    environment:
      - CF_API_EMAIL=\${ACME_EMAIL}
      - CF_DNS_API_TOKEN=\${CF_DNS_API_TOKEN}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(\`traefik.\${DOMAIN}\`)"
      - "traefik.http.routers.api.entrypoints=websecure"
      - "traefik.http.routers.api.service=api@internal"
      - "traefik.http.routers.api.middlewares=auth@file"
    restart: unless-stopped

  docker-socket-proxy:
    image: tecnativa/docker-socket-proxy
    container_name: docker-socket-proxy
    environment:
      - CONTAINERS=1
      - NETWORKS=1
      - SERVICES=1
      - TASKS=1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - proxy
    restart: unless-stopped

  authelia:
    container_name: authelia
    image: authelia/authelia:latest
    ports:
      - "9091:9091"
    volumes:
      - /home/${PWD}/docker/authelia:/config
    env_file:
      - /home/${PWD}/docker/authelia/.secrets.env
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.authelia.rule=Host(\`authelia.\${DOMAIN}\`)"
      - "traefik.http.routers.authelia.entrypoints=websecure"
      - "traefik.http.services.authelia.loadbalancer.server.port=9091"
    networks:
      - proxy
    restart: unless-stopped
    depends_on:
      - redis
      - mariadb

  redis:
    container_name: redis
    image: bitnami/redis:latest
    expose:
      - 6379
    volumes:
      - /home/${PWD}/docker/redis:/bitnami/
    environment:
      - REDIS_PASSWORD=\${REDIS_PASS}
    networks:
      - proxy
    restart: unless-stopped

  mariadb:
    container_name: mariadb
    image: linuxserver/mariadb:latest
    expose:
      - 3306
    volumes:
      - /home/${PWD}/docker/mariadb:/config
      - /home/${PWD}/docker/mariadb/init.sh:/docker-entrypoint-initdb.d/init.sh
    environment:
      - MYSQL_ROOT_PASSWORD=\${MARIA_ROOT_PASS}
      - MYSQL_ROOT_USER=root
      - MYSQL_DATABASE=authelia
      - MYSQL_USER=authelia
      - MYSQL_PASSWORD=\${MARIA_USER_PASS}
    networks:
      - proxy
    restart: unless-stopped

  headscale:
    image: headscale/headscale:latest
    container_name: headscale
    restart: unless-stopped
    command: headscale serve
    volumes:
      - ./headscale/config:/etc/headscale
      - ./headscale/data:/var/lib/headscale
    labels:
      - traefik.enable=true
      - traefik.http.routers.headscale-rtr.rule=PathPrefix(\`/\`) && Host(\`headscale.\${DOMAIN}\`)
      - traefik.http.services.headscale-svc.loadbalancer.server.port=8080
    networks:
      - proxy

  headscale-ui:
    image: ghcr.io/gurucomputing/headscale-ui:latest
    container_name: headscale-ui
    restart: unless-stopped
    labels:
      - traefik.enable=true
      - traefik.http.routers.headscale-ui-rtr.rule=PathPrefix(\`/web\`) && Host(\`headscale-ui.\${DOMAIN}\`)
      - traefik.http.services.headscale-ui-svc.loadbalancer.server.port=80
    networks:
      - proxy

networks:
  proxy:
    driver: bridge
EOF

# Step 5: Traefik Configuration
cat > traefik.yml <<EOF
global:
  checkNewVersion: true
  sendAnonymousUsage: false

serversTransport:
  insecureSkipVerify: true

log:
  level: INFO

api:
  dashboard: true
  insecure: true

providers:
  providersThrottleDuration: 2s
  file:
    filename: /etc/traefik/fileConfig.yml
    watch: true
  docker:
    watch: true
    network: proxy
    defaultRule: "Host(\`{{ lower (trimPrefix \`/\` .Name )}}.${BASE_DOMAIN}\`)"
    exposedByDefault: false
    endpoint: "tcp://docker-socket-proxy:2375"

entryPoints:
  web:
    address: ":80"
    forwardedHeaders:
      trustedIPs: &trustedIps
        - 173.245.48.0/20
        - 103.21.244.0/22
        - 103.22.200.0/22
        - 103.31.4.0/22
        - 141.101.64.0/18
        - 108.162.192.0/18
        - 190.93.240.0/20
        - 188.114.96.0/20
        - 197.234.240.0/22
        - 198.41.128.0/17
        - 162.158.0.0/15
        - 104.16.0.0/13
        - 104.24.0.0/14
        - 172.64.0.0/13
        - 131.0.72.0/22
        - 2400:cb00::/32
        - 2606:4700::/32
        - 2803:f800::/32
        - 2405:b500::/32
        - 2405:8100::/32
        - 2a06:98c0::/29
        - 2c0f:f248::/32
        - 127.0.0.1/32
        - 10.0.0.0/8
        - 192.168.0.0/16
        - 172.16.0.0/12
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true

  websecure:
    address: ":443"
    forwardedHeaders:
      trustedIPs: *trustedIps
    http:
      tls:
        certResolver: letsencrypt
        domains:
          - main: ${BASE_DOMAIN}
            sans:
              - '*.${BASE_DOMAIN}'
      middlewares:
        - securityHeaders@file

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${CERT_EMAIL}
      storage: /letsencrypt/acme.json
      dnsChallenge:
        provider: cloudflare
        resolvers:
          - "1.1.1.1:53"
          - "1.0.0.1:53"
        delayBeforeCheck: 90
EOF

# Step 6: File Configuration for Traefik
cat > fileConfig.yml <<EOF
auth:
  forwardauth:
    address: http://authelia:9091/api/verify?rd=https://authelia.${BASE_DOMAIN}/
    trustForwardHeader: true
    authResponseHeaders:
      - Remote-User
      - Remote-Groups
      - Remote-Name
      - Remote-Email

auth-basic:
  forwardauth:
    address: http://authelia:9091/api/verify?auth=basic
    trustForwardHeader: true
    authResponseHeaders:
      - Remote-User
      - Remote-Groups
      - Remote-Name
      - Remote-Email

securityHeaders:
  headers:
    customResponseHeaders:
      X-Robots-Tag: "none,noarchive,nosnippet,notranslate,noimageindex"
      X-Forwarded-Proto: "https"
      server: ""
    customRequestHeaders:
      X-Forwarded-Proto: "https"
    sslProxyHeaders:
      X-Forwarded-Proto: "https"
    referrerPolicy: "same-origin"
    hostsProxyHeaders:
      - "X-Forwarded-Host"
    contentTypeNosniff: true
    browserXssFilter: true
    forceSTSHeader: true
    stsIncludeSubdomains: true
    stsSeconds: 63072000
    stsPreload: true

tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
EOF
