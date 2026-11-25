# Servidor ATALAYA: el nucleo (funciones) esta en nucleo.ps1; las busquedas largas se hacen en buscar_worker.ps1
. (Join-Path $PSScriptRoot 'nucleo.ps1')

# Puerto dinamico: el primero libre entre 8080 y 8099
$listener = $null
foreach ($p in 8080..8099) {
    $try = New-Object System.Net.HttpListener
    $try.Prefixes.Add("http://localhost:$p/")
    try { $try.Start(); $listener = $try; $port = $p; break } catch { $try.Close() }
}
if (-not $listener) { throw 'No hay ningun puerto libre entre 8080 y 8099' }
# Los demas scripts (monitor, iniciar.bat) leen el puerto de este fichero
Write-Utf8 'puerto.txt' ([string]$port)
Write-Host "ATALAYA activo en http://localhost:$port/   (Ctrl+C para parar)"

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response
    try {
        $path = $req.Url.AbsolutePath
        if ($path -eq '/api/news') {
            # El refresco de fuentes corre en un proceso aparte (refrescar_worker.ps1) para no
            # bloquear la web: aqui solo se lee lo ya guardado y, si toca, se lanza el worker.
            $force   = ($req.QueryString['refresh'] -eq '1')
            $lock    = Join-Path $root 'refresco.lock'
            $cached  = Get-CacheReport
            $activo  = Test-Path -LiteralPath $lock

            if ($force) {
                if (-not $activo) { [void](Start-RefrescoWorker); $activo = $true }
                $prog = Get-ProgresoFuentes
                $ack  = [pscustomobject]@{ iniciando = $true; total = $prog.total }
                Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $ack -Compress))) $jsonType
            }
            elseif ($cached) {
                # Cache caducado por tiempo y sin worker en marcha: se refresca en 2o plano (no bloquea esta respuesta)
                $cfg = Get-Config
                $gen = [datetime]::MinValue
                [void][datetime]::TryParseExact([string]$cached.generated, 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$gen)
                if ($gen -ne [datetime]::MinValue -and ((Get-Date) - $gen).TotalMinutes -ge $cfg.noticias_intervalo_min -and -not $activo) {
                    [void](Start-RefrescoWorker)
                }
                Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $cached -Depth 6))) $jsonType
            }
            else {
                # Primera vez: todavia no hay nada guardado
                if (-not $activo) { [void](Start-RefrescoWorker); $activo = $true }
                $prog = Get-ProgresoFuentes
                $ack  = [pscustomobject]@{ iniciando = $true; total = $prog.total }
                Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $ack -Compress))) $jsonType
            }
        }
        elseif ($path -eq '/api/progreso_fuentes') {
            $prog = Get-ProgresoFuentes
            Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $prog -Compress))) $jsonType
        }
        elseif ($path -eq '/api/health') {
            if ($req.QueryString['refresh'] -eq '1') { Set-Content -LiteralPath (Join-Path $root 'health_now.flag') -Value '1' }
            Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes((Get-HealthJson))) $jsonType
        }
        elseif ($path -eq '/api/buscar') {
            # Busqueda sincrona (el worker asincrono queda pendiente de depurar)
            $q = [string]$req.QueryString['q']
            $dias = 2
            [void][int]::TryParse([string]$req.QueryString['dias'], [ref]$dias)
            $dias = [Math]::Min(365, [Math]::Max(1, $dias))
            $data = Search-Archive $q $dias
            Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $data -Depth 6))) $jsonType
        }
        elseif ($path -eq '/api/archivo') {
            # Buscador del feed: SOLO lee el fichero interno de noticias (archivo.jsonl), nunca las fuentes en vivo
            $dias = 365
            [void][int]::TryParse([string]$req.QueryString['dias'], [ref]$dias)
            $dias = [Math]::Min(365, [Math]::Max(1, $dias))
            $data = Search-ArchivoLocal $dias
            Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $data -Depth 6))) $jsonType
        }
        elseif ($path -eq '/api/historico') {
            # Historico por periodo (dias) y, opcionalmente, de un servicio (svc)
            $dias = 1
            [void][int]::TryParse([string]$req.QueryString['dias'], [ref]$dias)
            $dias = [Math]::Min(30, [Math]::Max(1, $dias))
            $svc  = [string]$req.QueryString['svc']
            $from = (Get-Date).AddDays(-$dias)
            $rows = New-Object System.Collections.ArrayList
            $hp = Join-Path $root 'historico.txt'
            if (Test-Path -LiteralPath $hp) {
                foreach ($ln in (Get-Content -LiteralPath $hp -Encoding UTF8 | Select-Object -Last 80000)) {
                    $f = $ln -split "`t"
                    if ($f.Count -lt 4) { continue }
                    if ($svc -and $f[1] -ne $svc) { continue }
                    $dt = [datetime]::MinValue
                    if (-not [datetime]::TryParseExact($f[0], 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$dt)) { continue }
                    if ($dt -lt $from) { continue }
                    [void]$rows.Add([pscustomobject]@{ t = $f[0]; name = $f[1]; status = $f[2]; ms = [int]$f[3] })
                }
            }
            $json = if ($rows.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject @($rows) -Depth 3 }
            Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes($json)) $jsonType
        }
        elseif ($path -eq '/api/estado') {
            Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json (Get-EstadoJson) -Depth 6))) $jsonType
        }
        elseif ($path -eq '/api/event-notificacion' -and $req.HttpMethod -eq 'POST') {
            $sr   = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
            $body = $sr.ReadToEnd() | ConvertFrom-Json
            Trigger-EventNotification $body
            Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes('{"ok":true}')) $jsonType
        }
        elseif ($path -eq '/api/settings' -and $req.HttpMethod -eq 'GET') {
            $cfg = Get-Config
            $notifCfg = Get-NotificacionesConfig
            # Agregar parametros de notificaciones al config
            foreach ($k in $notifCfg.Keys) { $cfg | Add-Member -NotePropertyName $k -NotePropertyValue $notifCfg[$k] -Force }
            $s = [pscustomobject]@{ config = $cfg; fuentes = (Read-Raw 'fuentes.txt'); temas = (Read-Raw 'temas.txt'); omitir = (Read-Raw 'omitir.txt'); estado = (Read-Raw 'estado.txt') }
            Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $s -Depth 5))) $jsonType
        }
        elseif ($path -eq '/api/settings' -and $req.HttpMethod -eq 'POST') {
            $sr   = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
            $body = $sr.ReadToEnd() | ConvertFrom-Json
            if ($null -ne $body.fuentes) { Write-Utf8 'fuentes.txt' ([string]$body.fuentes) }
            if ($null -ne $body.temas)   { Write-Utf8 'temas.txt'   ([string]$body.temas) }
            if ($null -ne $body.omitir)  { Write-Utf8 'omitir.txt'  ([string]$body.omitir) }
            if ($null -ne $body.estado)  {
                Write-Utf8 'estado.txt'  ([string]$body.estado)
                # pide al monitor una comprobacion inmediata de los servicios nuevos
                Set-Content -LiteralPath (Join-Path $root 'health_now.flag') -Value '1'
            }
            if ($null -ne $body.config) {
                $sevs = @($body.config.severidades | Where-Object { $validSev -contains $_ })
                if ($sevs.Count -eq 0) { $sevs = @('Critica', 'Grave') }
                $dias  = [Math]::Min(30, [Math]::Max(1, [int]$body.config.dias))
                $cache = [Math]::Min(1440, [Math]::Max(1, [int]$body.config.noticias_intervalo_min))
                $tema = [string]$body.config.tema
                if ($validTheme -notcontains $tema) { $tema = 'profesional' }
                $mon = [bool]$body.config.monitor_salud
                $isec = [Math]::Min(3600, [Math]::Max(30, [int]$body.config.monitor_intervalo_seg))
                $ifont = [Math]::Min(20, [Math]::Max(11, [int]$body.config.tamano_letra))
                $uv = 90; if ($null -ne $body.config.salud_umbral_verde) { $uv = [Math]::Min(100, [Math]::Max(1, [int]$body.config.salud_umbral_verde)) }
                $ua = 60; if ($null -ne $body.config.salud_umbral_ambar) { $ua = [Math]::Min(100, [Math]::Max(1, [int]$body.config.salud_umbral_ambar)) }
                if ($ua -gt $uv) { $ua = $uv }
                $lat = 2000; if ($null -ne $body.config.latencia_aviso_ms) { $lat = [Math]::Min(60000, [Math]::Max(0, [int]$body.config.latencia_aviso_ms)) }
                $hook = ''; if ($null -ne $body.config.webhook_url) { $hook = ([string]$body.config.webhook_url).Trim(); if ($hook -notmatch '^(https?://\S+)?$') { $hook = '' } }
                $mant = ''; if ($null -ne $body.config.mantenimiento) { $mant = (([string]$body.config.mantenimiento) -replace '[\r\n]', ' ').Trim() }
                $anc = 100; if ($null -ne $body.config.ancho_pct) { $anc = [Math]::Min(100, [Math]::Max(50, [int]$body.config.ancho_pct)) }
                $cas = 8; if ($null -ne $body.config.casillas_fila) { $cas = [Math]::Min(12, [Math]::Max(1, [int]$body.config.casillas_fila)) }
                $rch = 1000; if ($null -ne $body.config.resumen_caracteres) { $rch = [Math]::Min(5000, [Math]::Max(100, [int]$body.config.resumen_caracteres)) }
                $tmon = 11; if ($null -ne $body.config.tamano_monitor) { $tmon = [Math]::Min(16, [Math]::Max(9, [int]$body.config.tamano_monitor)) }
                $hgen = 24; if ($null -ne $body.config.horas_grafica_general) { $hgen = [Math]::Min(168, [Math]::Max(1, [int]$body.config.horas_grafica_general)) }
                $hsvc = 2; if ($null -ne $body.config.horas_grafica_servicio) { $hsvc = [Math]::Min(24, [Math]::Max(1, [int]$body.config.horas_grafica_servicio)) }
                $minInc = 15; if ($null -ne $body.config.minutos_aviso_incidencia) { $minInc = [Math]::Min(1440, [Math]::Max(1, [int]$body.config.minutos_aviso_incidencia)) }
                $topN = 10; if ($null -ne $body.config.top_noticias) { $topN = [Math]::Min(50, [Math]::Max(1, [int]$body.config.top_noticias)) }
                $mvista = 'max'; if ($null -ne $body.config.monitor_vista -and @('max','min') -contains [string]$body.config.monitor_vista) { $mvista = [string]$body.config.monitor_vista }
                $pnl = 'ultimas'; if ($null -ne $body.config.panel_derecho -and @('ultimas','temas') -contains [string]$body.config.panel_derecho) { $pnl = [string]$body.config.panel_derecho }
                # Notificaciones (plugin) - se guardan en archivo separado
                if ($body.config.notif_habilitado -eq '1') { $notifHab = '1' } else { $notifHab = '0' }
                $notifTipo = [string]$body.config.notif_tipo; if ($notifTipo -notin @('gmail','outlook','smtp','')) { $notifTipo = '' }
                $notifAsun = [string]$body.config.notif_asunto; if ([string]::IsNullOrWhiteSpace($notifAsun)) { $notifAsun = 'ATALAYA: Alerta de seguridad' }
                $notifDest = [string]$body.config.notif_destino
                $notifGuser = [string]$body.config.notif_gmail_usuario
                $notifGpass = [string]$body.config.notif_gmail_password
                $notifOuser = [string]$body.config.notif_outlook_usuario
                $notifOpass = [string]$body.config.notif_outlook_password
                $notifSsrv = [string]$body.config.notif_smtp_servidor
                $notifSpue = 587; if ($null -ne $body.config.notif_smtp_puerto) { $notifSpue = [Math]::Min(65535, [Math]::Max(1, [int]$body.config.notif_smtp_puerto)) }
                $notifSuser = [string]$body.config.notif_smtp_usuario
                $notifSpass = [string]$body.config.notif_smtp_password
                $notifSrem = [string]$body.config.notif_smtp_remitente
                if ($body.config.notif_smtp_ssl -eq '1') { $notifSssl = '1' } else { $notifSssl = '0' }
                # Guardar notificaciones en archivo separado (encriptar passwords)
                $notifGpassEnc = if ($notifGpass) { Encrypt-Password $notifGpass } else { '' }
                $notifOpassEnc = if ($notifOpass) { Encrypt-Password $notifOpass } else { '' }
                $notifSpassEnc = if ($notifSpass) { Encrypt-Password $notifSpass } else { '' }
                Write-Utf8 'notificaciones_config.txt' @"
# Configuracion de notificaciones por correo electronico (passwords encriptados)
notif_habilitado=$notifHab
notif_tipo=$notifTipo
notif_asunto=$notifAsun
notif_destino=$notifDest
notif_gmail_usuario=$notifGuser
notif_gmail_password=$notifGpassEnc
notif_outlook_usuario=$notifOuser
notif_outlook_password=$notifOpassEnc
notif_smtp_servidor=$notifSsrv
notif_smtp_puerto=$notifSpue
notif_smtp_usuario=$notifSuser
notif_smtp_password=$notifSpassEnc
notif_smtp_remitente=$notifSrem
notif_smtp_ssl=$notifSssl
"@
                Save-Config ([pscustomobject]@{ severidades = $sevs; dias = $dias; noticias_intervalo_min = $cache; tema = $tema; monitor_salud = $mon; monitor_intervalo_seg = $isec; tamano_letra = $ifont; salud_umbral_verde = $uv; salud_umbral_ambar = $ua; latencia_aviso_ms = $lat; webhook_url = $hook; mantenimiento = $mant; ancho_pct = $anc; casillas_fila = $cas; resumen_caracteres = $rch; tamano_monitor = $tmon; horas_grafica_general = $hgen; horas_grafica_servicio = $hsvc; minutos_aviso_incidencia = $minInc; panel_derecho = $pnl; top_noticias = $topN; monitor_vista = $mvista })
            }
            $script:cache = $null
            Remove-Item -LiteralPath (Join-Path $root 'cache_noticias.json') -Force -ErrorAction SilentlyContinue
            [void](Start-RefrescoWorker)   # la configuracion nueva (severidades, dias, etc.) se aplica ya en 2o plano
            Set-Content -LiteralPath (Join-Path $root 'health_now.flag') -Value '1'   # el monitor aplica la config de inmediato
            Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes('{"ok":true}')) $jsonType
        }
        else {
            if ($path -eq '/') { $path = '/index.html' }
            $full = [IO.Path]::GetFullPath((Join-Path $pubDir ($path.TrimStart('/') -replace '/', '\')))
            if ($full.StartsWith($pubDir, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $full -PathType Leaf)) {
                $ext  = [IO.Path]::GetExtension($full).ToLower()
                $type = $mime[$ext]
                if (-not $type) { $type = 'application/octet-stream' }
                Send-Bytes $res ([IO.File]::ReadAllBytes($full)) $type
            } else {
                Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes('404 no encontrado')) 'text/plain; charset=utf-8' 404
            }
        }
    } catch {
        Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes('Error: ' + $_.Exception.Message)) 'text/plain; charset=utf-8' 500
    }
    $res.OutputStream.Close()
}
