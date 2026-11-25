# Worker de refresco: lanzado por el servidor (no bloquea la web mientras descarga las fuentes).
# Descarga todas las fuentes EN PARALELO, guarda el progreso real y deja el informe final en
# cache_noticias.json. El servidor solo lee estos ficheros, nunca descarga el mismo.
param()
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'nucleo.ps1')

$lock = Join-Path $root 'refresco.lock'
try {
    $report = Build-Report
    Save-CacheReport $report
    # El refresco se marca como terminado AQUI (la web ya puede mostrar el 100%): el envio
    # de notificaciones por correo es un efecto secundario que no debe retrasar ese aviso.
    Set-ProgresoFuentes $report.sources.Count $report.sources.Count $false
    [void](Trigger-NewsNotifications $report)
} catch {
    Set-ProgresoFuentes 0 0 $false
} finally {
    Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
}
