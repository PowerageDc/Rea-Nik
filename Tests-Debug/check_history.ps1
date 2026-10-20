param([Parameter(Mandatory)][string[]]$Path)

$pats = [ordered]@{
  'pasos/fases'  = '\b[Pp]asos?\b|\b[Ff]ases?\b|\b[Ee]tapas?\b|\b\d[a-d]\b|\u2705|\u23F3|\b[Ll][i\u00ed]neas? [A-Z]\b'
  'temporal'     = '[Tt]odav[i\u00ed]a|[Pp]or ahora|[Aa] futuro|[Aa]ntes |[Yy]a no|[Rr]esuelto|\bv[0-9]\b|[Nn]uevo|[Hh]oy '
  'validaciones' = '[Vv]erificad|[Vv]alidad|[Pp]robad|en dev|en sala|iPhone|Android|celular'
  'fechas'       = '\b20\d\d\b|\b\d{4}-\d{2}-\d{2}\b|REAPER 7\.\d+'
}

foreach ($f in $Path) {
  "== $f"
  foreach ($k in $pats.Keys) {
    Select-String -Path $f -Pattern $pats[$k] | ForEach-Object {
      "[$k] $($_.LineNumber): $($_.Line.Trim())"
    }
  }
}