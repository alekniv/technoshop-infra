# Runbook: Build de DC01 (AD DS + DNS + DHCP)

| Campo | Valor |
|---|---|
| Ticket | TS-0005 |
| Host | DC01 — 10.10.10.10/24 (LAN-SRV) |
| SO | Windows Server 2025 Standard Eval (Desktop Experience, ES) |
| Dominio | corp.technoshop.lab (NetBIOS TECHNOSHOP) |
| Autor | Alejandro |
| Última ejecución | 2026-10-05 |

> Ninguna credencial va en este documento. Todas las claves (DSRM, adm.alejandro, bg.admin, backups FW01) están en Bitwarden.

## 0. Requisitos previos

- FW01 encendido (gateway y DNS iniciales 10.10.10.1).
- VM en VirtualBox: perfil "Windows 2022 (64-bit)" (VBox 7.1.4 no tiene perfil 2025), adaptador 1 en red interna `LAN-SRV`.
- ISO Windows Server 2025 Eval (solo español).

## 1. Red, zona horaria y nombre

```powershell
Get-NetAdapter
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.10.10.10 -PrefixLength 24 -DefaultGateway 10.10.10.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 10.10.10.1
Get-NetIPConfiguration
Test-Connection google.com -Count 2
Set-TimeZone -Id "Argentina Standard Time"
Rename-Computer -NewName "DC01" -Restart
```

**Verificación:** IP 10.10.10.10 (no 169.254.x.x / APIPA) y ping a internet OK.
**Troubleshooting:** si aparece APIPA, volver a ejecutar `New-NetIPAddress` y confirmar que FW01 esté encendido.

## 2. Actualizaciones

Windows Update hasta quedar al día, luego:

```powershell
Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object HotFixID, Description, InstalledOn
```

📸 Snapshot `01-base-actualizada`.

## 3. AD DS + DNS (nuevo bosque)

```powershell
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Install-ADDSForest -DomainName "corp.technoshop.lab" -DomainNetbiosName "TECHNOSHOP" -InstallDns -SafeModeAdministratorPassword (Read-Host -AsSecureString "Clave DSRM")
```

- Guardar la clave DSRM en Bitwarden **antes** de ejecutar.
- La advertencia de delegación DNS es esperada (no existe zona padre `technoshop.lab`).
- El servidor reinicia solo.

```powershell
Get-ADDomain
Add-DnsServerForwarder -IPAddress 10.10.10.1
Resolve-DnsName google.com
```

📸 Snapshot `02-ad-ds`.

## 4. Estructura de OUs

```powershell
New-ADOrganizationalUnit -Name "TechnoShop" -Path "DC=corp,DC=technoshop,DC=lab"
```

Hijas de `OU=TechnoShop,DC=corp,DC=technoshop,DC=lab`: `Usuarios`, `Equipos`, `Servidores`, `Grupos`, `CuentasServicio`, `Admins`.

```powershell
New-ADOrganizationalUnit -Name "Usuarios" -Path "OU=TechnoShop,DC=corp,DC=technoshop,DC=lab"
```

Hijas de `OU=Usuarios,OU=TechnoShop,DC=corp,DC=technoshop,DC=lab`: `Administracion`, `Ventas`, `Logistica`, `Desarrollo`, `Marketing`, `Gerencia`.

```powershell
New-ADOrganizationalUnit -Name "Administracion" -Path "OU=Usuarios,OU=TechnoShop,DC=corp,DC=technoshop,DC=lab"
```

**Verificación:** `Get-ADOrganizationalUnit -Filter * | Select-Object Name` → 13 OUs (+ Domain Controllers).
**Corrección de nombres:** `Rename-ADObject -Identity "<DN>" -NewName "<nombre>"`.

## 5. Cuentas privilegiadas

### 5.1 Admin nominal

```powershell
New-ADUser -Name "adm.alejandro" -SamAccountName "adm.alejandro" -UserPrincipalName "adm.alejandro@corp.technoshop.lab" -Path "OU=Admins,OU=TechnoShop,DC=corp,DC=technoshop,DC=lab" -AccountPassword (Read-Host -AsSecureString "Clave") -Enabled $true
Add-ADGroupMember -Identity "Admins. del dominio" -Members adm.alejandro
Get-ADGroupMember "Admins. del dominio" | Select-Object Name
```

> El nombre del grupo está localizado: "Admins. del dominio" (no "Domain Admins").

**Troubleshooting:** si `New-ADUser` falla a mitad de camino la cuenta puede quedar creada pero **deshabilitada** ("la cuenta ya existe"):

```powershell
Set-ADAccountPassword adm.alejandro -Reset -NewPassword (Read-Host -AsSecureString "Clave")
Enable-ADAccount adm.alejandro
```

Validar iniciando sesión como `TECHNOSHOP\adm.alejandro` y ejecutar `whoami /groups | findstr /i "dominio"`.

### 5.2 Break-glass

El Administrador integrado se renombra a `bg.admin` (cuenta de emergencia, no de uso diario):

```powershell
Set-ADUser Administrador -SamAccountName "bg.admin" -UserPrincipalName "bg.admin@corp.technoshop.lab"
Get-ADUser bg.admin | Rename-ADObject -NewName "bg.admin"
Get-ADUser bg.admin | Select-Object Name, SamAccountName, Enabled
```

📸 Snapshot `03-ous-admins`.

## 6. DHCP

```powershell
Install-WindowsFeature DHCP -IncludeManagementTools
Add-DhcpServerInDC -DnsName "dc01.corp.technoshop.lab" -IPAddress 10.10.10.10
Add-DhcpServerv4Scope -Name "LAN-USR" -StartRange 10.10.20.100 -EndRange 10.10.20.200 -SubnetMask 255.255.255.0 -State Active
Set-DhcpServerv4OptionValue -ScopeId 10.10.20.0 -Router 10.10.20.1 -DnsServer 10.10.10.10 -DnsDomain "corp.technoshop.lab"
Get-DhcpServerv4Scope
Get-DhcpServerv4OptionValue -ScopeId 10.10.20.0
```

## 7. FW01: DHCP relay y reglas

Los broadcasts DHCP no cruzan routers, por eso FW01 reenvía las peticiones de LAN-USR a DC01.

1. **Services → DHCRelay → Destinations:** `DC01` = `10.10.10.10`.
2. **Relays:** Enabled, Interface `OPT1`, Destination `DC01` → Save → **Apply** (Status verde).
3. Verificar que **Dnsmasq** y **Kea** no tengan rangos en OPT1.
4. **Alias** `AD_Ports` (Port(s)): `53, 88, 123, 135, 389, 445, 464, 636, 3268, 3269, 67, 49152:65535`.
5. **Regla LAN** (arriba de "bloquear otras redes internas"):
   Pass · UDP · src `10.10.10.10` → dst `OPT1 address` puerto `67` — respuesta del DHCP al relay.
6. **Regla OPT1** (arriba de "bloquear acceso al firewall"):
   Pass · TCP/UDP · src `OPT1 network` → dst `10.10.10.10` puertos `AD_Ports` — log activado (temporal).
7. **Apply** y backup XML cifrado → `/media/sf_Backups` + `sha256sum`. **Nunca a GitHub.**

## 8. Verificación final

```powershell
dcdiag /q          # sin salida = todas las pruebas OK
Get-ADDomain
Get-DhcpServerv4Scope
```

📸 Snapshot `04-dhcp-relay-ok` (VM **apagada**: `Stop-Computer`).

## Pendientes

- Prueba DHCP de punta a punta con un cliente en LAN-USR (al crear WS01).
- Desactivar el log de la regla OPT1 → DC01 una vez validado el join de WS01.
