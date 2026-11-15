param(
    [string]$Repo = 'C:\dev\Rea-Nik',
    [string]$Pendiente = '_docs\DEPLOY_PENDIENTE.md'
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Paquetes = @(
    @{ Etiqueta = 'RemoteControl (scripts)'; Ancla = 'RemoteControl/Nik_RemoteState_Poll.lua' },
    @{ Etiqueta = 'MusicState (scripts)';    Ancla = 'MusicState/Nik_MusicState_Helper.lua' },
    @{ Etiqueta = 'MonitorMix (scripts)';    Ancla = 'MonitorMix/Nik_MonitorMix_Publish.lua' },
    @{ Etiqueta = 'Interfaz web (.www)';     Ancla = 'web/Nik_RemoteControl_WebUI.www' },
    @{ Etiqueta = 'ProjectFolder (scripts)'; Ancla = 'ProjectFolder/Nik_ProjectFolder_OpenRoot.lua' }
)

# Archivos de un dominio deployable que son de uso local a proposito (no van al @provides)
$Locales = @(
    'ProjectFolder/Nik_ProjectFolder_CollectSamples.lua'
)

function Invoke-Git { & git -C $Repo -c core.quotepath=false @args }
function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }

function Resolve-Ruta([string]$dir, [string]$rel) {
    $partes = New-Object System.Collections.Generic.List[string]
    foreach ($s in ("$dir/$rel" -split '/')) {
        if ($s -eq '' -or $s -eq '.') { continue }
        if ($s -eq '..') { if ($partes.Count -gt 0) { $partes.RemoveAt($partes.Count - 1) } }
        else { $partes.Add($s) }
    }
    $partes -join '/'
}

function Get-Dir([string]$ruta) {
    if ($ruta.Contains('/')) { $ruta -replace '/[^/]*$', '' } else { '' }
}

function ConvertTo-PatronRegex([string]$p) {
    $sb = New-Object System.Text.StringBuilder '^'
    for ($i = 0; $i -lt $p.Length; $i++) {
        $c = $p[$i]
        if ($c -eq '*' -and ($i + 1) -lt $p.Length -and $p[$i + 1] -eq '*') { [void]$sb.Append('.*'); $i++ }
        elseif ($c -eq '*') { [void]$sb.Append('[^/]*') }
        elseif ($c -eq '?') { [void]$sb.Append('[^/]') }
        elseif ($c -eq '{') { [void]$sb.Append('(') }
        elseif ($c -eq '}') { [void]$sb.Append(')') }
        elseif ($c -eq ',') { [void]$sb.Append('|') }
        else { [void]$sb.Append([regex]::Escape([string]$c)) }
    }
    [void]$sb.Append('$')
    $sb.ToString()
}

function Get-Header([string]$ruta) {
    $version = $null
    $provides = @()
    $enProvides = $false
    $cl = $false
    foreach ($l in @(Invoke-Git show "HEAD:$ruta")) {
        if ($l -notmatch '^--') { break }
        if ($l -match '^--\s*@version\s+(\S+)') { $version = $Matches[1]; $enProvides = $false; continue }
        if ($l -match '^--\s*@changelog') { $cl = $true; $enProvides = $false; continue }
        if ($l -match '^--\s*@provides\s*$') { $enProvides = $true; continue }
        if ($l -match '^--\s*@') { $enProvides = $false; continue }
        if ($enProvides -and $l -match '^--\s{2,}(\S.*)$') { $provides += $Matches[1].Trim() }
    }
    @{ Version = $version; Provides = $provides; Changelog = $cl }
}

function Expand-Provides($header, [string]$ancla, $archivosHead) {
    if ($header.Provides.Count -eq 0) { return @($ancla) }
    $dir = Get-Dir $ancla
    $res = @()
    foreach ($p in $header.Provides) {
        $p = (($p -replace '^\[[^\]]*\]\s*', '') -replace '\s*>.*$', '').Trim()
        if ($p -eq '.') { $res += $ancla; continue }
        $ruta = Resolve-Ruta $dir $p
        if ($ruta -match '[*?{]') {
            $rx = ConvertTo-PatronRegex $ruta
            foreach ($f in $archivosHead) { if ($f -match $rx) { $res += $f } }
        } else { $res += $ruta }
    }
    $res | Sort-Object -Unique
}

$xml = New-Object System.Xml.XmlDocument
$xml.Load((Join-Path $Repo 'index.xml'))

function Get-Indexado([string]$ancla) {
    $hoja = [IO.Path]::GetFileName($ancla)
    $base = [IO.Path]::GetFileNameWithoutExtension($ancla)
    $nodo = $xml.SelectNodes('//reapack') | Where-Object {
        $n = $_.GetAttribute('name'); ($n -eq $hoja) -or ($n -eq $base)
    } | Select-Object -First 1
    if (-not $nodo) { return $null }
    $ver = $nodo.SelectNodes('version') | Sort-Object {
        try { [version]$_.GetAttribute('name') } catch { [version]'0.0' }
    } | Select-Object -Last 1
    $archivos = @()
    $hash = $null
    foreach ($s in $ver.SelectNodes('source')) {
        if ($s.InnerText -match '/raw/([0-9a-f]{7,40})/(.+)$') {
            if (-not $hash) { $hash = $Matches[1] }
            $archivos += [uri]::UnescapeDataString($Matches[2])
        }
    }
    @{ Version = $ver.GetAttribute('name'); Hash = $hash; Archivos = $archivos }
}

# Lista de deploy pendiente: version publicada y cantidad de lineas por seccion
$lista = @{}
$rutaP = Join-Path $Repo $Pendiente
if (Test-Path $rutaP) {
    $sec = $null
    foreach ($l in (Get-Content -Encoding UTF8 $rutaP)) {
        if ($l -match '^##\s+(.+?)\s+\S+\s+publicado\s+(\S+)\s*$') {
            $sec = $Matches[1]
            $lista[$sec] = @{ Version = $Matches[2]; Lineas = 0 }
            continue
        }
        if ($l -match '^#') { $sec = $null; continue }
        if ($sec -and $l.Trim() -ne '') { $lista[$sec].Lineas++ }
    }
}

if (@(Invoke-Git status --porcelain).Count -gt 0) {
    Say 'AVISO: hay cambios sin comitear. Este chequeo solo ve lo comiteado (HEAD).' 'Yellow'
}
$rama = (Invoke-Git rev-parse --abbrev-ref HEAD | Select-Object -First 1)
if ($rama -ne 'main') {
    Say "AVISO: HEAD esta en la rama '$rama'. Para el bump final, correr parado en main." 'Yellow'
}

# Pasada 1: datos por paquete
$archivosHead = @(Invoke-Git ls-tree -r --name-only HEAD)
$datos = @()
foreach ($p in $Paquetes) {
    $hdr = Get-Header $p.Ancla
    $idx = Get-Indexado $p.Ancla
    $act = @(Expand-Provides $hdr $p.Ancla $archivosHead)
    $d = [pscustomobject]@{
        P = $p; Hdr = $hdr; Idx = $idx; Act = $act
        Mod = @(); Nuevos = @(); Quitados = @(); Tardios = @(); Altas = @(); Cmp = $null
    }
    if ($hdr.Version -and $idx -and $idx.Hash) {
        $rango = "$($idx.Hash)..HEAD"
        $cambiados = @(Invoke-Git diff --name-only --no-renames $rango)
        $d.Mod = @($act | Where-Object { ($idx.Archivos -contains $_) -and ($cambiados -contains $_) })
        $d.Nuevos = @($act | Where-Object { $idx.Archivos -notcontains $_ })
        $d.Quitados = @($idx.Archivos | Where-Object { $act -notcontains $_ })
        $d.Altas = @(Invoke-Git diff --name-only --diff-filter=A --no-renames $rango)
        $d.Cmp = ([version]$hdr.Version).CompareTo([version]$idx.Version)
        if ($d.Cmp -gt 0) {
            $c = Invoke-Git log --max-count=1 --format=%H -S "@version $($hdr.Version)" $p.Ancla | Select-Object -First 1
            if ($c) {
                $d.Tardios = @(Invoke-Git diff --name-only --no-renames "$c..HEAD" | Where-Object { $act -contains $_ })
            }
        }
    }
    $datos += $d
}

# Union de todo lo provisto y modulos cargados por dofile que no estan en ningun @provides
$todos = @()
foreach ($d in $datos) { $todos += $d.Act }
$huerfanos = @()
foreach ($d in $datos) {
    foreach ($f in @($d.Act | Where-Object { $_ -like '*.lua' })) {
        $dirF = Get-Dir $f
        $src = (@(Invoke-Git show "HEAD:$f")) -join "`n"
        foreach ($m in [regex]::Matches($src, 'dofile\s*\([^"'']*["'']([^"'']+\.lua)["'']')) {
            $dep = Resolve-Ruta $dirF $m.Groups[1].Value
            if ($todos -notcontains $dep) { $huerfanos += "$dep  (cargado por $f)" }
        }
    }
}

# Pasada 2: informe
$aBumpear = @()
$aRevisar = @()
foreach ($d in $datos) {
    $p = $d.P; $i = $d.Idx; $h = $d.Hdr
    Say ('=' * 64)
    Say "$($p.Etiqueta)   [$($p.Ancla)]" 'Cyan'
    if (-not $h.Version) { Say '   ERROR: no se pudo leer el header de la ancla en HEAD' 'Red'; continue }
    if (-not $i) { Say '   No esta en index.xml (paquete nuevo o nombre distinto)' 'Yellow'; continue }
    Say "   Indexado:    $($i.Version)  (commit $($i.Hash.Substring(0, 7)))"
    Say "   Header HEAD: $($h.Version)"
    $dirA = Get-Dir $p.Ancla
    $sinPaquete = @($d.Altas | Where-Object { $_.StartsWith("$dirA/") -and ($todos -notcontains $_) -and ($Locales -notcontains $_) })
    if ($d.Mod.Count)      { Say '   Provistos modificados:';        $d.Mod      | ForEach-Object { Say "      M  $_" } }
    if ($d.Nuevos.Count)   { Say '   Provistos nuevos:';             $d.Nuevos   | ForEach-Object { Say "      A  $_" } }
    if ($d.Quitados.Count) { Say '   Provistos que ya no estan:';    $d.Quitados | ForEach-Object { Say "      D  $_" } }
    if ($sinPaquete.Count) { $aRevisar += $p.Etiqueta; Say '   Altas en su carpeta sin paquete (revisar @provides):' 'Yellow'; $sinPaquete | ForEach-Object { Say "      A  $_" 'Yellow' } }
    $hay = ($d.Mod.Count + $d.Nuevos.Count + $d.Quitados.Count) -gt 0
    if ($d.Cmp -lt 0)      { Say '   Veredicto: REVISAR, el header es menor que el indice' 'Red' }
    elseif ($d.Cmp -eq 0 -and $hay)  { Say '   Veredicto: BUMP NECESARIO' 'Red'; $aBumpear += $p.Etiqueta }
    elseif ($d.Cmp -eq 0)  { Say '   Veredicto: sin cambios' 'Green' }
    elseif ($d.Tardios.Count) {
        Say "   Veredicto: bump hecho ($($i.Version) -> $($h.Version)) pero hay cambios posteriores: otro bump" 'Red'
        $d.Tardios | ForEach-Object { Say "      M  $_" 'Red' }
        $aBumpear += $p.Etiqueta
    }
    elseif ($sinPaquete.Count) { Say "   Veredicto: bump hecho ($($i.Version) -> $($h.Version)), pero hay altas sin paquete: resolver antes de reindexar" 'Red' }
    else { Say "   Veredicto: bump hecho ($($i.Version) -> $($h.Version)), listo para reindexar" 'Green' }
    if ($d.Cmp -gt 0 -and -not $h.Changelog) { Say '   AVISO: version nueva sin @changelog en el header' 'Yellow' }
    $lst = $lista[$p.Etiqueta]
    if (-not $lst) { Say '   AVISO: no hay seccion de este paquete en la lista de deploy pendiente' 'Yellow' }
    else {
        Say "   Lista:       $($lst.Lineas) linea(s)"
        if ($lst.Version -ne $i.Version) { Say "   AVISO: el titulo de la lista dice publicado $($lst.Version), el indice dice $($i.Version)" 'Yellow' }
        if ($hay -and $d.Cmp -eq 0 -and $lst.Lineas -eq 0) { Say '   AVISO: hay cambios en el paquete y la lista esta vacia' 'Yellow' }
        if (-not $hay -and $d.Cmp -eq 0 -and $lst.Lineas -gt 0) { Say '   AVISO: la lista tiene lineas pero el diff del paquete esta vacio' 'Yellow' }
    }
}

Say ('=' * 64)
if ($huerfanos.Count) {
    Say 'Modulos cargados por dofile que no estan en ningun @provides:' 'Red'
    $huerfanos | Sort-Object -Unique | ForEach-Object { Say "   $_" 'Red' }
} else { Say 'dofile: todos los modulos cargados estan en algun @provides' 'Green' }
if ($aBumpear.Count) { Say ('A bumpear: ' + ($aBumpear -join ', ')) 'Cyan' } else { Say 'Ningun paquete necesita bump' 'Green' }
if ($aRevisar.Count) { Say ('A revisar (altas sin paquete): ' + ($aRevisar -join ', ')) 'Yellow' }