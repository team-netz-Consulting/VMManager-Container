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
docker pull ghcr.io/team-netz-consulting/vmmanager:2026.08.24.1032
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

Das öffentliche Repository enthält die `.env.example`, die dazu passende `docker-compose.yml`,
Nginx- und SQL-Konfiguration sowie den optionalen Tenant-Connector. Es kann direkt auf den
Docker-Host geklont werden:

```bash
git clone https://github.com/team-netz-Consulting/VMManager-Container.git
cd VMManager-Container
```

Für eine neue Installation übernimmt das Installationsskript die vollständige Einrichtung unter
`/opt/vmmanager`. Es erzeugt sichere SQL-, Owner-, JWT-, Guacamole- und Routing-Schlüssel, richtet
die persistenten Verzeichnisse mit den erforderlichen Container-UIDs ein und startet den Stack:

```bash
sudo ./install.sh
```

Das Skript fragt DNS-Namen, Owner-E-Mail, Lizenz-Kundenname und Image-Version ab. Die einmaligen
Owner-Zugangsdaten werden ausschließlich root-lesbar unter
`/opt/vmmanager/ERSTANMELDUNG.txt` gespeichert. Ohne vorhandenes TLS-Zertifikat wird ein 30 Tage
gültiges selbstsigniertes Startzertifikat erzeugt; für den Produktivbetrieb muss es ersetzt werden.
Eine vorhandene `/opt/vmmanager/.env` und bestehende Nutzdaten werden nicht überschrieben.

Vor dem ersten Start werden die persistenten Verzeichnisse, TLS-Zertifikate, Kennwörter und
Schlüssel eingerichtet. Danach wird der Stack gestartet:

```bash
cp .env.example .env
chmod 600 .env
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
```

Das TLS-Zertifikat und sein privater Schlüssel werden unterhalb von `VM_MANAGER_DATA_ROOT` erwartet:

```text
nginx/certs/fullchain.pem
nginx/certs/privkey.pem
```

Eine Aktualisierung erfolgt durch Änderung des festen Image-Tags in `.env`:

```bash
docker compose pull
docker compose up -d --remove-orphans
```

## Tenant-Connector

Für getrennte Kundennetze oder überlappende IP-Adressbereiche wird der Connector in dem jeweiligen
Kundennetz installiert:

```bash
cd tenant-connector
./install.sh
```

Das Installationsskript erstellt ein selbstsigniertes TLS-Zertifikat, startet den Connector und
zeigt den SHA-256-Fingerabdruck zur Übernahme in die VMManager-Tenantkonfiguration an. Port 4822 darf
nur über das private VPN oder den vereinbarten Tunnel vom VMManager erreichbar sein.

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
