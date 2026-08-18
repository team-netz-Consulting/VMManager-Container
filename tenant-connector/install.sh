#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIND_IP=""
TENANT_NAME=""
CERT_DIR="${SCRIPT_DIR}/data/certs"
FORCE=false
START=true

usage() {
    cat <<'EOF'
VMManager Tenant-Connector installieren

Verwendung:
  ./install.sh [Optionen]

Optionen:
  --bind-ip IP       Private VPN-/LAN-Adresse, an die Port 4822 gebunden wird
  --tenant NAME      Tenantname für den Zertifikatsnamen
  --cert-dir PFAD    Persistenter Zertifikatspfad (Standard: ./data/certs)
  --force            Vorhandenes Zertifikat ersetzen
  --no-start         Konfiguration erstellen, Container noch nicht starten
  -h, --help         Hilfe anzeigen
EOF
}

while (($#)); do
    case "$1" in
        --bind-ip) BIND_IP="${2:?Für --bind-ip fehlt ein Wert}"; shift 2 ;;
        --tenant) TENANT_NAME="${2:?Für --tenant fehlt ein Wert}"; shift 2 ;;
        --cert-dir) CERT_DIR="${2:?Für --cert-dir fehlt ein Wert}"; shift 2 ;;
        --force) FORCE=true; shift ;;
        --no-start) START=false; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

for command_name in openssl docker; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "Fehlendes Programm: ${command_name}" >&2
        exit 1
    }
done
docker compose version >/dev/null 2>&1 || {
    echo "Docker Compose V2 ('docker compose') ist nicht installiert." >&2
    exit 1
}

if [[ -z "$BIND_IP" ]]; then
    if command -v ip >/dev/null 2>&1; then
        BIND_IP="$(ip -4 -o address show scope global | awk '$2 !~ /^(docker|br-|veth)/ { split($4, address, "/"); print address[1]; exit }')"
    fi
    read -r -p "Private Bind-IP für den Connector${BIND_IP:+ [${BIND_IP}]}: " entered_ip
    BIND_IP="${entered_ip:-$BIND_IP}"
fi
[[ "$BIND_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || {
    echo "Ungültige IPv4-Adresse: ${BIND_IP:-<leer>}" >&2
    exit 1
}
IFS=. read -r -a ip_octets <<< "$BIND_IP"
for octet in "${ip_octets[@]}"; do
    ((10#$octet <= 255)) || {
        echo "Ungültige IPv4-Adresse: ${BIND_IP}" >&2
        exit 1
    }
done
if command -v ip >/dev/null 2>&1 && ! ip -4 -o address show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$BIND_IP"; then
    echo "Die Bind-IP ${BIND_IP} ist auf diesem System nicht konfiguriert." >&2
    exit 1
fi

if [[ -z "$TENANT_NAME" ]]; then
    read -r -p "Name des Tenants: " TENANT_NAME
fi
[[ -n "${TENANT_NAME//[[:space:]]/}" ]] || {
    echo "Der Tenantname darf nicht leer sein." >&2
    exit 1
}
CERTIFICATE_NAME="${TENANT_NAME//$'\n'/ }"
CERTIFICATE_NAME="${CERTIFICATE_NAME//\//-}"

mkdir -p "$CERT_DIR"
CERT_DIR="$(cd -- "$CERT_DIR" && pwd)"
CERT_FILE="${CERT_DIR}/tls.crt"
KEY_FILE="${CERT_DIR}/tls.key"

if [[ ( -e "$CERT_FILE" && ! -e "$KEY_FILE" ) || ( ! -e "$CERT_FILE" && -e "$KEY_FILE" ) ]]; then
    if [[ "$FORCE" != true ]]; then
        echo "Zertifikat oder Schlüssel fehlt in ${CERT_DIR}. Mit --force kann das unvollständige Paar ersetzt werden." >&2
        exit 1
    fi
fi

if [[ -e "$CERT_FILE" && -e "$KEY_FILE" ]]; then
    if [[ "$FORCE" != true ]]; then
        echo "Es existiert bereits ein Zertifikat in ${CERT_DIR}."
        echo "Es wird weiterverwendet. Mit --force kann ein neues erzeugt werden."
    else
        openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 825 \
            -subj "/CN=${CERTIFICATE_NAME} VMManager Connector" \
            -addext "subjectAltName=IP:${BIND_IP}" \
            -keyout "$KEY_FILE" -out "$CERT_FILE"
    fi
else
    openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 825 \
        -subj "/CN=${CERTIFICATE_NAME} VMManager Connector" \
        -addext "subjectAltName=IP:${BIND_IP}" \
        -keyout "$KEY_FILE" -out "$CERT_FILE"
fi

chmod 600 "$KEY_FILE"
chmod 644 "$CERT_FILE"

umask 077
printf 'TENANT_CONNECTOR_BIND_IP=%s\nTENANT_CONNECTOR_CERT_DIR=%s\n' \
    "$BIND_IP" "$CERT_DIR" > "${SCRIPT_DIR}/.env"

if [[ "$START" == true ]]; then
    cd "$SCRIPT_DIR"
    docker compose up -d

    container_id="$(docker compose ps -q guacd-connector)"
    for _ in {1..30}; do
        health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id")"
        [[ "$health" == healthy ]] && break
        [[ "$health" == unhealthy || "$health" == exited ]] && {
            docker compose logs --tail=100 guacd-connector >&2
            echo "Der Tenant-Connector konnte nicht erfolgreich gestartet werden." >&2
            exit 1
        }
        sleep 2
    done
    [[ "${health:-}" == healthy ]] || {
        docker compose logs --tail=100 guacd-connector >&2
        echo "Der Healthcheck des Tenant-Connectors wurde nicht rechtzeitig erfolgreich." >&2
        exit 1
    }
fi

fingerprint_colon="$(openssl x509 -in "$CERT_FILE" -noout -fingerprint -sha256 | cut -d= -f2)"
fingerprint_compact="${fingerprint_colon//:/}"

cat <<EOF

Tenant-Connector erfolgreich eingerichtet.

Connector-Host: ${BIND_IP}
Connector-Port: 4822
SHA-256-Fingerabdruck (zum Kopieren):
${fingerprint_compact}

Fingerabdruck mit Doppelpunkten:
${fingerprint_colon}

Zertifikat: ${CERT_FILE}
Privater Schlüssel: ${KEY_FILE}
EOF

if [[ "$START" == true ]]; then
    echo
    docker compose ps
fi
