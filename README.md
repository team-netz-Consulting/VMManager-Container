# VMManager Container

VMManager ist eine zentrale Managementoberfläche für virtuelle Systeme. Die Anwendung bündelt
Inventar, Betrieb, Bereitstellung, Fernzugriff, Organisationen, Berechtigungen, Backups und
Abrechnung in einer gemeinsamen Weboberfläche.

Sie eignet sich für Unternehmen mit eigener Virtualisierungsumgebung, einzelne Standorte sowie
Managed Service Provider (MSP), die mehrere Kunden und getrennte Infrastrukturen zentral betreiben.

## Unterstützte Plattformen

- Xen Orchestra
- XenServer, Citrix Hypervisor und XCP-ng
- Microsoft Hyper-V über den VMManager-Agenten
- VMware ist im Plattformmodell vorbereitet; der produktive Provideradapter folgt in einer
  zukünftigen Version

## Container-Image

Das offizielle Linux-x86-64-Image wird über GitHub Container Registry bereitgestellt:

```text
ghcr.io/team-netz-consulting/vmmanager
```

Für produktive Installationen immer einen freigegebenen Versionstag verwenden:

```bash
docker pull ghcr.io/team-netz-consulting/vmmanager:2026.8.8
```

`latest` verweist auf die zuletzt freigegebene Version, sollte aber nicht für dauerhaft
reproduzierbare Kundeninstallationen verwendet werden.

## Voraussetzungen

- Linux-x86-64-Host mit Docker Engine und Docker Compose
- mindestens 4 GB Arbeitsspeicher
- DNS-Name und TLS-Zertifikat für den öffentlichen Zugriff
- persistenter Speicher für SQL Server, Lizenz und Data-Protection-Schlüssel
- Netzwerkzugriff zu den angebundenen Hypervisoren, Agenten und Gastnetzen

## Installation und Betrieb

VMManager wird als Docker-Compose-Stack mit folgenden Komponenten betrieben:

- VMManager
- Microsoft SQL Server
- Nginx als TLS-Reverse-Proxy
- Apache Guacamole und `guacd` für RDP- und SSH-Konsolen

Die kundenspezifische Bereitstellung enthält eine `.env.example` und eine dazu passende
`docker-compose.yml`. Vor dem ersten Start werden die persistenten Verzeichnisse, TLS-Zertifikate,
Kennwörter und Schlüssel eingerichtet. Danach wird der Stack gestartet:

```bash
cp .env.example .env
chmod 600 .env
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
```

Eine Aktualisierung erfolgt durch Änderung des festen Image-Tags in `.env`:

```bash
docker compose pull
docker compose up -d --remove-orphans
```

## Funktionsbereiche

- providerübergreifendes VM-Inventar und zentrale VM-Aktionen
- Organisationen, Mandanten und rollenbasierte Berechtigungen
- Bereitstellung aus versionierten Golden Images
- Snapshots, Backup-Inventar und Wiederherstellungsaktionen
- eingebettete Hypervisor-, RDP- und SSH-Konsolen
- Tenant-Connectoren für getrennte oder überlappende Kundennetze
- T-Shirt-Größen, Preise, Aufträge und Abrechnungsexporte
- Support-, Aktivitäts-, Audit- und Systemprotokolle

## Lizenzierung

VMManager benötigt für den produktiven Betrieb eine gültige Lizenz. Ohne Lizenz startet die
Anwendung im Demo-Modus. Aktivierung, Offline-Import und Lizenzstatus werden in der
Administrationsoberfläche verwaltet.

Die Lizenzdatei liegt außerhalb des Containers in einem persistenten Verzeichnis und bleibt bei
Container-Updates erhalten.

## Sicherheit

- Zugangsdaten und Schlüssel werden nicht in das Container-Image eingebettet.
- Provider-Zugangsdaten werden verschlüsselt gespeichert.
- Browser erhalten keine Hypervisor-, Agent- oder Konsolenzugangsdaten.
- Produktive Installationen müssen eine vertrauenswürdige TLS-Zertifikatskette verwenden.
- Tenant-Connectoren werden über TLS und einen fest hinterlegten Zertifikatfingerabdruck geprüft.

## Support

Das Image und diese Dokumentation werden von team-netz Consulting GmbH bereitgestellt. Technische
Unterstützung und vollständige kundenspezifische Deployment-Pakete erhalten Kunden über ihren
vereinbarten Supportkanal.

Copyright © team-netz Consulting GmbH. Alle Rechte vorbehalten.
