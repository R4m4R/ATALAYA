# Worker de busqueda: lanzado por el servidor. Carga el nucleo y escribe el resultado en un fichero.
param([string]$qb64, [int]$dias = 2, [string]$out)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'nucleo.ps1')
$q = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($qb64))
try {
    $data = Search-Archive $q $dias
    $json = ConvertTo-Json $data -Depth 6
} catch {
    $json = '{"items":[],"total":0,"error":"' + ($_.Exception.Message -replace '"', "'") + '"}'
}
[IO.File]::WriteAllText($out, $json, (New-Object Text.UTF8Encoding($false)))