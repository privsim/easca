#!/bin/bash

# Step 7: Authelia Configuration
cat > configuration.yml <<EOF
---
default_redirection_url: https://authelia.${BASE_DOMAIN}/

server:
  address: 'tcp://0.0.0.0:9091/'
  buffers:
    read: 8192
    write: 8192
  endpoints:
    enable_pprof: false
    enable_expvars: false
  disable_healthcheck: false

log:
  level: info
  file_path: /config/authelia.log

totp:
  issuer: aletheia.observer

webauthn:
  disable: false
  display_name: Authelia
  attestation_conveyance_preference: direct
  user_verification: required
  timeout: 60s

ntp:
  address: "time.cloudflare.com:123"
  version: 4
  max_desync: 3s
  disable_startup_check: false

authentication_backend:
  password_reset.disable: true
  refresh_interval: 5m
  file:
    path: /config/users_database.yml
    password:
      algorithm: argon2id
      iterations: 1
      key_length: 32
      salt_length: 16
      memory: 1024
      parallelism: 8

access_control:
  default_policy: deny
  rules:
    - domain: authelia.${BASE_DOMAIN}
      policy: bypass
    - domain: ${BASE_DOMAIN}
      policy: bypass
    - domain: "*.${BASE_DOMAIN}"
      policy: two_factor

session:
  name: authelia_session
  expiration: 3600
  inactivity: 300
  domain: aletheia.observer
  same_site: lax
  remember_me_duration: 2M
  redis:
    host: redis
    port: 6379
    database_index: 0
    maximum_active_connections: 10
    minimum_idle_connections: 0

regulation:
  max_retries: 3
  find_time: 120m
  ban_time: 12h

storage:
  mysql:
    address: 'tcp://mariadb:3306/'
    database: authelia
    username: authelia

notifier:
  smtp:
    address: submission://${SMTP_RELAY}:587
    username: ${SMTP_LOGIN}
    sender: "Authentication Service <noreply@authelia.${BASE_DOMAIN}>"
    subject: "{title}"
    startup_check_address: "noreply@authelia.${BASE_DOMAIN}"
    disable_require_tls: false
    disable_html_emails: false
    tls:
      skip_verify: false
      minimum_version: TLS1.2

identity_providers:
  oidc:
    access_token_lifespan: 1h
    authorize_code_lifespan: 1m
    id_token_lifespan: 1h
    refresh_token_lifespan: 90m
    enable_client_debug_messages: false
    enforce_pkce: always
    cors:
      endpoints:
        - authorization
        - token
        - revocation
        - introspection
        - userinfo
      allowed_origins:
        - "*"
      allowed_origins_from_client_redirect_uris: false
    clients:
      - id: cloudflare
        description: Cloudflare ZeroTrust
        secret: ${CF_SECRET}
        public: false
        authorization_policy: two_factor
        pre_configured_consent_duration: '365d'
        redirect_uris:
          - https://${CF_ZEROTRUST_NAME}.cloudflareaccess.com/cdn-cgi/access/callback
        scopes:
          - openid
          - profile
          - email
        userinfo_signing_algorithm: RS256
EOF

echo "# Step 8: Users Database Configuration for Authelia"

cat > users_database.yml <<EOF
users:
  ${USER1}:
    disabled: false
    displayname: ${USER1}
    password: ${ARGON_HASHED_USER1_PASS}
    email: ${EMAIL_USER1}
    groups:
      - 'admins'
  ${USER2}:
    disabled: false
    displayname: ${USER2}
    password: ${ARGON_HASHED_USER2_PASS}
    email: ${EMAIL_USER2}
    groups:
      - 'admins'
EOF