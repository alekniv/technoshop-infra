
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Alta masiva de empleados de TechnoShop en Active Directory desde un CSV.
.DESCRIPTION
    Lee un CSV (Legajo, Nombre, Apellido, Area, Puesto). Por cada fila:
    si el legajo no existe en AD, crea el usuario nombre.apellido en la OU de su area;
    asegura el grupo GG_<Area> y la membresia. Idempotente.
.PARAMETER CsvPath
    Ruta del CSV de RR.HH.
.PARAMETER CredentialsPath
    Archivo donde se guardan las claves iniciales generadas (FUERA del repo).
.PARAMETER LogPath
    Carpeta donde se guarda el log de cada corrida.
.EXAMPLE
    .\New-TechnoShopUsers.ps1 -CsvPath C:\Scripts\empleados-ejemplo.csv -WhatIf
.NOTES
    Ticket: TS-0006 - Autor: Alejandro
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [string]$CredentialsPath = 'C:\Secure\TS-0006-claves-iniciales.csv',

    [string]$LogPath = 'C:\Scripts\Logs'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------
# Configuracion del dominio
# ---------------------------------------------------------------
$DomainDN    = 'DC=corp,DC=technoshop,DC=lab'
$UsersBaseOU = "OU=Usuarios,OU=TechnoShop,$DomainDN"
$GroupsOU    = "OU=Grupos,OU=TechnoShop,$DomainDN"
$UpnSuffix   = 'corp.technoshop.lab'
$Company     = 'TechnoShop SRL'
$MaxSamLen   = 20

# ---------------------------------------------------------------
# Funcion: pasa un texto a minusculas, sin tildes, enes ni espacios
# Ej: 'Muñoz' -> 'munoz' | 'María José' -> 'mariajose'
# ---------------------------------------------------------------
function ConvertTo-AsciiLower {
    param([Parameter(Mandatory)][string]$Text)

    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder

    foreach ($ch in $normalized.ToCharArray()) {
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }

    return ($sb.ToString().ToLower() -replace '[^a-z0-9]', '')
}

# ---------------------------------------------------------------
# Nombres asignados en ESTA corrida (para que -WhatIf sea realista)
# ---------------------------------------------------------------
$ReservedSams = New-Object 'System.Collections.Generic.HashSet[string]'

# ---------------------------------------------------------------
# Funcion: devuelve un SamAccountName libre (nombre.apellido, 2, 3...)
# respetando el limite de 20 caracteres
# ---------------------------------------------------------------
function Get-UniqueSamAccountName {
    param(
        [Parameter(Mandatory)][string]$Nombre,
        [Parameter(Mandatory)][string]$Apellido
    )

    $base = '{0}.{1}' -f (ConvertTo-AsciiLower $Nombre), (ConvertTo-AsciiLower $Apellido)
    $i = 1

    while ($true) {
        $suffix    = if ($i -eq 1) { '' } else { "$i" }
        $maxBase   = $MaxSamLen - $suffix.Length
        $candidate = $base.Substring(0, [Math]::Min($base.Length, $maxBase)).TrimEnd('.') + $suffix

        $existsInAD = Get-ADUser -Filter "SamAccountName -eq '$candidate'"
        if (-not $existsInAD -and -not $ReservedSams.Contains($candidate)) {
            [void]$ReservedSams.Add($candidate)
            return $candidate
        }
        $i++
    }
}

# ---------------------------------------------------------------
# Generador de numeros aleatorios criptograficamente seguro
# ---------------------------------------------------------------
$Rng = [Security.Cryptography.RandomNumberGenerator]::Create()

function Get-SecureRandomIndex {
    param([Parameter(Mandatory)][int]$Max)
    $bytes = New-Object byte[] 4
    $Rng.GetBytes($bytes)
    return [int]([BitConverter]::ToUInt32($bytes, 0) % [uint32]$Max)
}

# ---------------------------------------------------------------
# Funcion: clave aleatoria con mayuscula, minuscula, numero y simbolo
# ---------------------------------------------------------------
function New-RandomPassword {
    param([int]$Length = 16)

    $sets  = 'ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!@#$%*-_=+?'
    $all   = -join $sets
    $chars = New-Object 'System.Collections.Generic.List[char]'

    # 1 caracter garantizado de cada grupo
    foreach ($set in $sets) {
        $chars.Add($set[(Get-SecureRandomIndex $set.Length)])
    }
    # Resto al azar de todos los grupos
    while ($chars.Count -lt $Length) {
        $chars.Add($all[(Get-SecureRandomIndex $all.Length)])
    }
    # Mezcla (Fisher-Yates) para que los garantizados no queden siempre al principio
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $j = Get-SecureRandomIndex ($i + 1)
        $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
    }

    return -join $chars
}

# ---------------------------------------------------------------
# Preparacion: carpetas, registro de resultados y lectura del CSV
# ---------------------------------------------------------------
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

foreach ($dir in @($LogPath, (Split-Path $CredentialsPath -Parent))) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -WhatIf:$false | Out-Null
    }
}

$LogFile = Join-Path $LogPath "New-TechnoShopUsers-$timestamp.csv"
$Results = New-Object 'System.Collections.Generic.List[object]'

function Write-Result {
    param([string]$Legajo, [string]$Usuario, [string]$Accion, [string]$Detalle = '')
    $Results.Add([pscustomobject]@{
        Fecha   = Get-Date -Format 's'
        Legajo  = $Legajo
        Usuario = $Usuario
        Accion  = $Accion
        Detalle = $Detalle
    })
    Write-Host ('{0,-9} {1,-22} {2,-12} {3}' -f $Legajo, $Usuario, $Accion, $Detalle)
}

$empleados = @(Import-Csv -Path $CsvPath -Encoding UTF8)

$required = 'Legajo', 'Nombre', 'Apellido', 'Area', 'Puesto'
$missing  = $required | Where-Object { $_ -notin $empleados[0].PSObject.Properties.Name }
if ($missing) {
    throw "Faltan columnas en el CSV: $($missing -join ', ')"
}

Write-Host "Empleados en el CSV: $($empleados.Count)`n"

# ---------------------------------------------------------------
# Bucle principal: un empleado por vuelta
# ---------------------------------------------------------------
$Credentials   = New-Object 'System.Collections.Generic.List[object]'
$CreatedGroups = New-Object 'System.Collections.Generic.HashSet[string]'

foreach ($emp in $empleados) {
    $legajo = $emp.Legajo.Trim()
    $area   = $emp.Area.Trim()

    try {
        # 1) La OU del area tiene que existir
        $areaOU = "OU=$area,$UsersBaseOU"
        if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$areaOU'")) {
            Write-Result $legajo '-' 'ERROR' "No existe la OU del area '$area'"
            continue
        }

        # 2) Asegurar el grupo GG_<Area>
        $groupName   = "GG_$area"
        $groupExists = [bool](Get-ADGroup -Filter "Name -eq '$groupName'")
        if (-not $groupExists -and -not $CreatedGroups.Contains($groupName)) {
            if ($PSCmdlet.ShouldProcess($groupName, 'Crear grupo global de seguridad')) {
                New-ADGroup -Name $groupName -SamAccountName $groupName -GroupScope Global `
                    -GroupCategory Security -Path $GroupsOU -Description "Empleados del area $area"
                $groupExists = $true
            }
            [void]$CreatedGroups.Add($groupName)
            Write-Result '-' $groupName 'GRUPO-NUEVO'
        }

        # 3) Buscar al empleado por LEGAJO (clave de la idempotencia)
        $user = Get-ADUser -Filter "EmployeeID -eq '$legajo'"

        if ($user) {
            $sam = $user.SamAccountName
            Write-Result $legajo $sam 'EXISTE'
        }
        else {
            $sam      = Get-UniqueSamAccountName -Nombre $emp.Nombre -Apellido $emp.Apellido
            $password = New-RandomPassword
            $display  = "$($emp.Nombre) $($emp.Apellido)"

            # El Name (CN) no puede repetirse dentro de la misma OU
            $cn = $display
            if (Get-ADUser -Filter "Name -eq '$cn'" -SearchBase $areaOU -SearchScope OneLevel) {
                $cn = "$display ($sam)"
            }

            $params = @{
                Name                  = $cn
                SamAccountName        = $sam
                UserPrincipalName     = "$sam@$UpnSuffix"
                GivenName             = $emp.Nombre
                Surname               = $emp.Apellido
                DisplayName           = $display
                EmployeeID            = $legajo
                Title                 = $emp.Puesto
                Department            = $area
                Company               = $Company
                Path                  = $areaOU
                AccountPassword       = (ConvertTo-SecureString $password -AsPlainText -Force)
                ChangePasswordAtLogon = $true
                Enabled               = $true
            }

            if ($PSCmdlet.ShouldProcess("$sam ($legajo)", 'Crear usuario')) {
                New-ADUser @params
                $Credentials.Add([pscustomobject]@{
                    Legajo       = $legajo
                    Usuario      = $sam
                    ClaveInicial = $password
                })
            }
            Write-Result $legajo $sam 'CREADO' $areaOU
        }

        # 4) Membresia en el grupo (solo si todavia no es miembro)
        $alreadyMember = $false
        if ($groupExists) {
            $alreadyMember = @(Get-ADGroupMember -Identity $groupName |
                Where-Object SamAccountName -eq $sam).Count -gt 0
        }
        if (-not $alreadyMember) {
            if ($PSCmdlet.ShouldProcess("$sam -> $groupName", 'Agregar al grupo')) {
                Add-ADGroupMember -Identity $groupName -Members $sam
            }
            Write-Result $legajo $sam 'AL-GRUPO' $groupName
        }
    }
    catch {
        Write-Result $legajo '-' 'ERROR' $_.Exception.Message
    }
}

# ---------------------------------------------------------------
# Cierre: log, claves iniciales y resumen
# ---------------------------------------------------------------
$Results | Export-Csv -Path $LogFile -NoTypeInformation -Encoding UTF8 -WhatIf:$false

if ($Credentials.Count -gt 0) {
    $Credentials | Export-Csv -Path $CredentialsPath -NoTypeInformation -Encoding UTF8 -Append -WhatIf:$false
    Write-Warning "Claves iniciales en $CredentialsPath -> entregar a RR.HH. y BORRAR el archivo."
}

Write-Host "`n===== Resumen ====="
$Results | Group-Object Accion | Sort-Object Name |
    Format-Table @{ Label = 'Accion'; Expression = { $_.Name } }, Count -AutoSize

if ($WhatIfPreference) {
    Write-Host 'MODO SIMULACION (-WhatIf): no se modifico Active Directory.' -ForegroundColor Yellow
}
Write-Host "Log de la corrida: $LogFile"
