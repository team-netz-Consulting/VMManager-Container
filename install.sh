#!/usr/bin/env bash
set -Eeuo pipefail

readonly INSTALL_ROOT="/opt/vmmanager"
readonly DATA_ROOT="${INSTALL_ROOT}/data"
readonly IMAGE="ghcr.io/team-netz-consulting/vmmanager"

fail() {
    printf 'FEHLER: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Das Programm '$1' ist nicht installiert."
}

prompt_required() {
    local variable_name="$1" prompt="$2" value
    while [[ -z "${value:-}" ]]; do
        read -r -p "$prompt" value
    done
    [[ "$value" != *$'\n'* && "$value" != *"'"* ]] || fail "Der Wert darf kein Hochkomma enthalten."
    printf -v "$variable_name" '%s' "$value"
}

random_password() {
    printf 'Aa!%s' "$(openssl rand -hex 24)"
}

if [[ "${EUID}" -ne 0 ]]; then
    fail "Bitte mit Root-Rechten starten: sudo ./install.sh"
fi

require_command docker
require_command openssl
docker compose version >/dev/null 2>&1 || fail "Das Docker-Compose-Plug-in fehlt."
docker info >/dev/null 2>&1 || fail "Der Docker-Daemon ist nicht erreichbar."

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${script_dir}/docker-compose.yml" ]] || fail "docker-compose.yml fehlt neben dem Installationsskript."
[[ -f "${script_dir}/deployment/nginx/default.conf.template" ]] || fail "Die Nginx-Konfiguration fehlt."
[[ -f "${script_dir}/deployment/mssql/init.sql" ]] || fail "Die SQL-Initialisierung fehlt."

install -d -m 0750 "$INSTALL_ROOT"
install -d -m 0755 "$INSTALL_ROOT/deployment/nginx" "$INSTALL_ROOT/deployment/mssql"
install -m 0644 "$script_dir/docker-compose.yml" "$INSTALL_ROOT/docker-compose.yml"
install -m 0644 "$script_dir/deployment/nginx/default.conf.template" "$INSTALL_ROOT/deployment/nginx/default.conf.template"
install -m 0644 "$script_dir/deployment/mssql/init.sql" "$INSTALL_ROOT/deployment/mssql/init.sql"

install -d -o 10001 -g 0 -m 0770 "$DATA_ROOT/mssql"
install -d -o 1654 -g 0 -m 0700 "$DATA_ROOT/dataprotection" "$DATA_ROOT/license"
install -d -o 0 -g 0 -m 0750 "$DATA_ROOT/nginx/certs"
install -d -o 101 -g 101 -m 0750 "$DATA_ROOT/nginx/logs"
chown -R 10001:0 "$DATA_ROOT/mssql"
chmod -R u+rwX,g+rwX,o-rwx "$DATA_ROOT/mssql"
chown -R 1654:0 "$DATA_ROOT/dataprotection" "$DATA_ROOT/license"
chmod -R u+rwX,go-rwx "$DATA_ROOT/dataprotection" "$DATA_ROOT/license"

env_file="$INSTALL_ROOT/.env"
if [[ ! -f "$env_file" ]]; then
    default_tag="$(sed -n 's/^VM_MANAGER_IMAGE_TAG=//p' "$script_dir/.env.example" 2>/dev/null | head -n 1)"
    default_tag="${default_tag:-latest}"

    prompt_required server_name 'DNS-Name des VMManagers: '
    prompt_required owner_email 'E-Mail des ersten SystemOwners: '
    prompt_required customer_name 'Lizenz-Kundenname: '
    read -r -p "Container-Version [$default_tag]: " image_tag
    image_tag="${image_tag:-$default_tag}"

    sa_password="$(random_password)"
    app_password="$(random_password)"
    owner_password="$(random_password)"
    jwt_key="$(openssl rand -base64 48 | tr -d '\n')"
    guacamole_key="$(openssl rand -hex 16)"
    routing_key="$(openssl rand -hex 32)"

    {
        printf '%s\n' \
            "VM_MANAGER_DATA_ROOT=$DATA_ROOT" \
            "VM_MANAGER_IMAGE=$IMAGE" \
            "VM_MANAGER_IMAGE_TAG=$image_tag" \
            'VM_MANAGER_HTTP_PORT=80' \
            'VM_MANAGER_HTTPS_PORT=443' \
            'VM_MANAGER_FRONTEND_SUBNET=172.30.0.0/24' \
            "NGINX_SERVER_NAME=$server_name" \
            'TZ=Europe/Berlin' \
            'DEMO_MODE_ENABLED=false' \
            'NUGET_CONFIG_PATH=/dev/null' \
            'LICENSE_MANAGER_BASE_URL=https://license.team-netz.net:5181' \
            "LICENSE_CUSTOMER_NAME=$customer_name" \
            'LICENSE_MANAGER_ALLOW_INVALID_CERTIFICATE=false' \
            'MSSQL_PID=Express' \
            'MSSQL_DATABASE=VMManager' \
            'MSSQL_MEMORY_LIMIT_MB=2048' \
            "MSSQL_SA_PASSWORD=$sa_password" \
            'MSSQL_APP_USER=vmmanager' \
            "MSSQL_APP_PASSWORD=$app_password" \
            "JWT_SIGNING_KEY=$jwt_key" \
            'JWT_ISSUER=VMManager' \
            'JWT_AUDIENCE=VMManager' \
            "BOOTSTRAP_ADMIN_EMAIL=$owner_email" \
            "BOOTSTRAP_ADMIN_PASSWORD=$owner_password" \
            'DISABLE_OWNER_EMAIL_2FA_ON_STARTUP=false' \
            "GUACAMOLE_JSON_SECRET_KEY=$guacamole_key" \
            "REMOTE_CONSOLE_ROUTING_SECRET_KEY=$routing_key" \
            'REMOTE_CONSOLE_MAX_CONNECTIONS=200' \
            'REMOTE_CONSOLE_RDP_SERVER_LAYOUT=de-de-qwertz' \
            'REMOTE_CONSOLE_ENABLED=true'
    } > "$env_file"
    chmod 0600 "$env_file"

    credentials_file="$INSTALL_ROOT/ERSTANMELDUNG.txt"
    {
        printf 'VMManager-Erstanmeldung\nURL: https://%s\nBenutzer: %s\nPasswort: %s\n' \
            "$server_name" "$owner_email" "$owner_password"
        printf '\nDiese Datei nach erfolgreicher Anmeldung sicher loeschen.\n'
    } > "$credentials_file"
    chmod 0600 "$credentials_file"
    printf 'Erstanmeldedaten wurden unter %s gespeichert.\n' "$credentials_file"
else
    printf 'Vorhandene Konfiguration %s wird beibehalten.\n' "$env_file"
fi

cert_file="$DATA_ROOT/nginx/certs/fullchain.pem"
key_file="$DATA_ROOT/nginx/certs/privkey.pem"
if [[ ! -s "$cert_file" || ! -s "$key_file" ]]; then
    server_name="$(sed -n 's/^NGINX_SERVER_NAME=//p' "$env_file" | head -n 1)"
    openssl req -x509 -newkey rsa:3072 -sha256 -days 30 -nodes \
        -subj "/CN=${server_name}" \
        -addext "subjectAltName=DNS:${server_name}" \
        -keyout "$key_file" -out "$cert_file" >/dev/null 2>&1
    chmod 0600 "$key_file"
    chmod 0644 "$cert_file"
    printf 'Ein 30 Tage gueltiges Startzertifikat wurde erzeugt. Fuer Produktion ersetzen.\n'
fi

cd "$INSTALL_ROOT"
docker compose config --quiet
docker compose pull
docker compose up -d --no-build --remove-orphans
docker compose ps

printf '\nInstallation abgeschlossen.\n'
printf 'Konfiguration: %s\nDaten: %s\n' "$env_file" "$DATA_ROOT"
printf 'Status: cd %s && docker compose ps\n' "$INSTALL_ROOT"
printf 'Logs:   cd %s && docker compose logs -f\n' "$INSTALL_ROOT"
