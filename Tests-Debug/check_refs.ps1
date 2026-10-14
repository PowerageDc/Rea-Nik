# check_refs.ps1 -- control de referencias entre docs y codigo.
# Uso, desde la raiz del repo:  powershell -File Tests-Debug\check_refs.ps1
# Salida: lista de problemas; codigo de salida 1 si hay errores.
# Con -Avisos muestra ademas el chequeo 4 (lupa informativa, con falsos positivos).
param([switch]$Avisos)

$root = (Get-Location).Path
$skip = '\\_archive\\|\\_flujo\\|\\reference\\|\\node_modules\\|\\\.git\\'
$sec  = [string][char]0xA7     # simbolo de seccion, sin depender de la codificacion del script
$ignorar = @()                 # nombres de .md que no se verifican
$errores = 0

function Rel($p) { $p.Substring($root.Length + 1) }
function Informar($titulo, $items, $cuenta) {
    $items = @(@($items) | Where-Object { $_ })
    if ($items.Count -eq 0) { return }
    Write-Host "`n[$titulo] ($($items.Count))" -ForegroundColor Yellow
    $items | ForEach-Object { Write-Host "  $_" }
    if ($cuenta) { $script:errores += $items.Count }
}

$codigo = Get-ChildItem -Recurse -File -Include *.lua,*.js,*.css,*.html |
    Where-Object { $_.FullName -notmatch $skip }
$docs = Get-ChildItem -Path _docs -Recurse -File -Filter *.md |
    Where-Object { $_.FullName -notmatch $skip }

# 1. El codigo no cita docs (relacion de una sola via)
$r1 = $codigo | Select-String -Pattern ('\.md\b|' + $sec + '|IMPL_') -Encoding utf8 |
    ForEach-Object { "$(Rel $_.Path):$($_.LineNumber): $($_.Line.Trim())" }
Informar 'Codigo que cita docs' $r1 $true

# 2. Docs que citan un .md inexistente
$nombres = @{}
$docs | ForEach-Object { $nombres[$_.Name] = $_ }
$r2 = foreach ($d in $docs) {
    Select-String -Path $d.FullName -Pattern '`([\w./\-]+\.md)`' -AllMatches -Encoding utf8 | ForEach-Object {
        foreach ($m in $_.Matches) {
            $n = Split-Path $m.Groups[1].Value -Leaf
            if (-not $nombres.ContainsKey($n) -and $ignorar -notcontains $n) {
                "$(Rel $d.FullName):$($_.LineNumber): $($m.Groups[1].Value)"
            }
        }
    }
}
Informar 'Docs que citan un .md inexistente' $r2 $true

# 3. Citas "`archivo.md` §N" cuya seccion no existe (acepta nombre corto: `data_model`)
$titulos = @{}
foreach ($d in $docs) {
    $titulos[$d.Name] = @(Get-Content $d.FullName -Encoding utf8 | Where-Object { $_ -match '^#{1,6}\s' })
}
function Resolver($n) {
    foreach ($c in @($n, "$n.md", "musicstate_$n.md")) {
        $k = Split-Path $c -Leaf
        if ($nombres.ContainsKey($k)) { return $k }
    }
    return $null
}
$rx = '`([\w./\-]+)`[ ,]{0,2}' + $sec + '\s*(\d+(?:\.\d+)*)'
$r3 = foreach ($d in $docs) {
    Select-String -Path $d.FullName -Pattern $rx -AllMatches -Encoding utf8 | ForEach-Object {
        foreach ($m in $_.Matches) {
            $k = Resolver $m.Groups[1].Value
            if (-not $k) { continue }
            $num = [regex]::Escape($m.Groups[2].Value)
            $ok = $titulos[$k] | Where-Object { $_ -match ('^#{1,6}\s+(?:' + $sec + '\s*)?' + $num + '(?!\d|\.\d)') }
            if (-not $ok) { "$(Rel $d.FullName):$($_.LineNumber): $($m.Value) -> falta la seccion en $k" }
        }
    }
}
Informar 'Citas a secciones inexistentes' $r3 $true

# 4. Aviso (no cuenta como error): afirmaciones temporales en comentarios
if ($Avisos) {
    $r4 = $codigo | Select-String -Pattern '(--|//|/\*|\*).*(todav.a|a.n no|por ahora|TODO|FIXME)' -Encoding utf8 |
        ForEach-Object { "$(Rel $_.Path):$($_.LineNumber): $($_.Line.Trim())" }
    Informar 'Aviso: afirmaciones temporales en comentarios' $r4 $false
}

if ($errores -eq 0) { Write-Host "`nOK: sin problemas de referencias." -ForegroundColor Green }
exit ([int]($errores -gt 0))