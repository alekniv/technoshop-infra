# Red y firewall – TechnoShop SRL

Documentación de la segmentación de red y las reglas de FW01 (OPNsense).
Ticket: TS-0004. Última actualización: 2026-10-02.

## Segmentos

| Segmento | Interfaz FW01 | Red | Gateway / DNS | Uso |
|---|---|---|---|---|
| INET-SIM (WAN) | WAN (em0) | 203.0.113.0/24 | 203.0.113.1 | Internet simulada (TEST-NET-3) |
| LAN-SRV | LAN (em1) | 10.10.10.0/24 | 10.10.10.1 | Servidores (DC01, APP01, OPS01) |
| LAN-USR | OPT1 (em2) | 10.10.20.0/24 | 10.10.20.1 | Puestos de usuarios (WS01) |
| LAN-MGMT | OPT2 (em3) | 10.10.99.0/24 | 10.10.99.1 | Gestión (ADM01, estación de administración) |

## Inventario de IPs

| Host | IP | Segmento |
|---|---|---|
| FW01 | 203.0.113.2 / 10.10.10.1 / 10.10.20.1 / 10.10.99.1 | Todos |
| DC01 | 10.10.10.10 | LAN-SRV |
| APP01 | 10.10.10.20 | LAN-SRV |
| OPS01 | 10.10.10.30 | LAN-SRV |
| ADM01 | 10.10.99.50 | LAN-MGMT |
| WS01 | DHCP (pendiente) | LAN-USR |
| WEB01 | 203.0.113.10 | INET-SIM |

## Configuración base de FW01

- OPNsense 26.7.4_1 (FreeBSD 15.1), 2 GB RAM.
- Hostname: fw01.corp.technoshop.lab. Zona horaria: America/Argentina/Buenos_Aires.
- DNS: Unbound con DNSSEC y Harden DNSSEC.
- WAN: Block RFC1918 activado. Block bogons **desactivado**: INET-SIM usa TEST-NET-3, que figura en la lista de bogons y bloquearía a WEB01. En producción con IP pública iría activado.
- Sin DHCP en LAN-SRV (servidores con IP fija). IPv6 no se usa.

## Política de firewall

Principio: **default deny** entre segmentos. Cada segmento solo sale a Internet y usa el DNS del firewall; las excepciones se agregan explícitamente.

Alias `RFC1918` = 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16.

### LAN (LAN-SRV)

| # | Acción | Proto | Origen | Destino | Puerto | Log | Motivo |
|---|---|---|---|---|---|---|---|
| 0 | Pass | TCP | LAN net | LAN address | 443/80/22 | – | Anti-lockout (automática) |
| 1 | Pass | TCP/UDP | LAN net | LAN address | 53 | No | DNS del firewall |
| 2 | Block | any | LAN net | RFC1918 | any | Sí | Segmentación (evita movimiento lateral) |
| 3 | Pass | any | LAN net | any | any | No | Salida a Internet |
| – | Desactivada | any | LAN net | any | any | – | Regla IPv6 por defecto |

### OPT1 (LAN-USR)

| # | Acción | Proto | Origen | Destino | Puerto | Log | Motivo |
|---|---|---|---|---|---|---|---|
| 1 | Pass | TCP/UDP | OPT1 net | OPT1 address | 53 | No | DNS del firewall |
| 2 | Block | any | OPT1 net | This Firewall | any | Sí | Usuarios sin acceso a la GUI ni servicios del FW |
| 3 | Block | any | OPT1 net | RFC1918 | any | Sí | Segmentación (excepciones hacia DC01 en TS-0005) |
| 4 | Pass | any | OPT1 net | any | any | No | Salida a Internet |

### OPT2 (LAN-MGMT)

| # | Acción | Proto | Origen | Destino | Puerto | Log | Motivo |
|---|---|---|---|---|---|---|---|
| 1 | Pass | TCP | OPT2 net | This Firewall | 443 | No | GUI de administración (explícita) |
| 2 | Pass | any | OPT2 net | any | any | Sí | Acceso total de administradores, auditado |

## Pruebas realizadas (2026-10-01)

| Origen | Prueba | Resultado |
|---|---|---|
| LAN-SRV (10.10.10.50) | ping google.com / ping 10.10.20.1 | OK / bloqueado (log) |
| LAN-USR (10.10.20.50) | google.com | OK |
| LAN-USR | ping 10.10.20.1, 10.10.10.1 / HTTPS a la GUI | Bloqueado por "bloquear acceso al firewall" (log) |
| LAN-USR | ping 10.10.10.10 | Bloqueado por "bloquear otras redes internas" (log) |
| LAN-MGMT (10.10.99.50) | google.com, 10.10.20.1, GUI | OK |

## Backup de configuración

- Export XML **cifrado** (AES-256-CBC), guardado fuera de la VM en el host del laboratorio.
- La clave de cifrado está en el gestor de contraseñas. **El XML nunca se sube a este repositorio.**
- Snapshot de VirtualBox: `05-reglas-segmentacion`.

## Pendientes

- Excepciones LAN-USR → DC01 (DNS, Kerberos, LDAP, SMB) en TS-0005.
- Actualizar a OPNsense 26.7.5 (parches de seguridad).