param(
    [int]$Width = 16,
    [int]$Height = 130,
    [double[]]$Feather = @(2, 4, 6),
    [string]$OutDir = (Join-Path $PSScriptRoot 'masks')
)

# Máscara vertical en escala de grises: blanca en todo el ancho, con degradado
# suave (smoothstep) de $Feather px arriba y abajo. Un PNG por cada valor.

Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Get-Smoothstep([double]$t) {
    $t = [Math]::Min([Math]::Max($t, 0), 1)
    return $t * $t * (3 - 2 * $t)
}

foreach ($f in $Feather) {
    $bmp = New-Object System.Drawing.Bitmap($Width, $Height)
    for ($y = 0; $y -lt $Height; $y++) {
        $top = Get-Smoothstep (($y + 0.5) / $f)
        $bottom = Get-Smoothstep (($Height - $y - 0.5) / $f)
        $v = [int][Math]::Round([Math]::Min($top, $bottom) * 255)
        $color = [System.Drawing.Color]::FromArgb($v, $v, $v)
        for ($x = 0; $x -lt $Width; $x++) {
            $bmp.SetPixel($x, $y, $color)
        }
    }
    $path = Join-Path $OutDir ("mascara_vertical_{0}px.png" -f $f)
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "Generada: $path"
}