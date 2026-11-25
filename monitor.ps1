# Monitor de salud en segundo plano (independiente de la web).
# Cada N segundos (config.txt: monitor_intervalo_seg) comprueba los servicios de estado.txt
# y escribe health.json, que lee la web. Tambien atiende la peticion "Comprobar ahora"
# (fichero health_now.flag creado por el servidor).
#
# Formatos de destino en estado.txt (columna de la derecha):
#   https://...  o http://...   -> comprobacion HTTP (codigo y latencia)
#   host:puerto  o tcp://host:puerto -> comprobacion TCP (el puerto acepta conexiones)
#   ping://host  o solo IP/host  -> ICMP (ping)
# Tercera columna opcional (solo HTTP): texto que debe aparecer en la respuesta.
#
# Config (config.txt): webhook_url (aviso a Teams/Slack),
# mantenimiento (ventanas sin avisos).
#
# NOTA: fichero solo ASCII (Windows PowerShell 5.1).

$ErrorActionPreference = 'Continue'

# Solo puede haber un monitor activo: si ya hay otro, este se cierra (evita dos escrituras de health.json)
$script:mutex = New-Object System.Threading.Mutex($false, 'Local\ATALAYA_MONITOR_SECURITYNEWS')
if (-not $script:mutex.WaitOne(0, $false)) { exit }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls

$root       = Split-Path -Parent $MyInvocation.MyCommand.Path
$healthFile = Join-Path $root 'health_monitor.json'
$flagFile   = Join-Path $root 'health_now.flag'
$history    = @{}
$prevStatus = @{}   # ultimo estado de cada servicio (para detectar caidas y recuperaciones)
$lastRun    = [datetime]::MinValue
$lastNews   = Get-Date   # las noticias se actualizan cada noticias_intervalo_min (el servidor recopila)
$histFile   = Join-Path $root 'historico.txt'

# Carga el historico reciente para no perderlo al reiniciar
if (Test-Path -LiteralPath $histFile) {
    foreach ($ln in (Get-Content -LiteralPath $histFile -Encoding UTF8 | Select-Object -Last 5000)) {
        $f = $ln -split "`t"
        if ($f.Count -ge 4) {
            if (-not $history.ContainsKey($f[1])) { $history[$f[1]] = @() }
            $history[$f[1]] = @(@($history[$f[1]]) + [pscustomobject]@{ t = $f[0]; ms = [int]$f[3]; status = $f[2] })
        }
    }
    foreach ($k in @($history.Keys)) { $history[$k] = @($history[$k] | Select-Object -Last 200) }
}

function Read-Cfg {
    $c = @{ mon = $true; sec = 1800; nmin = 180; lat = 2000; hook = ''; mant = '' }
    $p = Join-Path $root 'config.txt'
    if (-not (Test-Path -LiteralPath $p)) { return $c }
    foreach ($line in (Get-Content -LiteralPath $p -Encoding UTF8)) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $kv = $t -split '=', 2
        if ($kv.Count -ne 2) { continue }
        $k = $kv[0].Trim().ToLower()
        $v = $kv[1].Trim()
        $n = 0
        if ($k -eq 'monitor_salud') { $c.mon = ($v -match '^(on|si|true|1)$') }
        elseif ($k -eq 'monitor_intervalo_seg' -and [int]::TryParse($v, [ref]$n) -and $n -ge 30 -and $n -le 3600) { $c.sec = $n }
        elseif ($k -eq 'noticias_intervalo_min' -and [int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le 1440) { $c.nmin = $n }
        elseif ($k -eq 'latencia_aviso_ms' -and [int]::TryParse($v, [ref]$n) -and $n -ge 0 -and $n -le 60000) { $c.lat = $n }
        elseif ($k -eq 'webhook_url') { $c.hook = $v }
        elseif ($k -eq 'mantenimiento') { $c.mant = $v }
    }
    return $c
}

function Get-Services {
    $list = @()
    $p = Join-Path $root 'estado.txt'
    if (-not (Test-Path -LiteralPath $p)) { return $list }
    foreach ($line in (Get-Content -LiteralPath $p -Encoding UTF8)) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $parts = @($t -split '\|')
        if ($parts.Count -lt 2) { continue }
        $name   = $parts[0].Trim()
        $target = $parts[1].Trim()
        $kw     = ''
        $slat   = -1
        $kind = 'ping'; $h = $target; $port = 0
        if ($target -match '^https?://') { $kind = 'http' }
        elseif ($target -match '^tcp://(.+):(\d+)$') { $kind = 'tcp'; $h = $matches[1]; $port = [int]$matches[2] }
        elseif ($target -match '^(.+):(\d+)$') { $kind = 'tcp'; $h = $matches[1]; $port = [int]$matches[2] }
        elseif ($target -match '^ping://(.+)$') { $kind = 'ping'; $h = $matches[1] }
        $list += [pscustomobject]@{ name = $name; target = $target; kind = $kind; host = $h; port = $port; kw = $kw; slat = $slat }
    }
    return $list
}

# Devuelve $null si el puerto acepta conexion; si no, el motivo
function Test-Tcp([string]$hostName, [int]$port, [int]$timeoutMs) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($hostName, $port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($timeoutMs, $false)
        if ($ok -and $client.Connected) { $client.EndConnect($iar); return $null }
        return ('Sin respuesta en el puerto ' + $port)
    } catch {
        return $_.Exception.Message
    } finally {
        $client.Close()
    }
}

function Write-Health($obj) {
    $json = ConvertTo-Json $obj -Depth 8
    $tmp = $healthFile + '.tmp'
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $healthFile -Force
}

# Ventanas de mantenimiento: "[Lun,Mie ]HH:MM-HH:MM" separadas por ';'
function Test-Maint([string]$spec) {
    if (-not $spec) { return $false }
    $now = Get-Date
    $dayMap = @{ 'dom' = 0; 'lun' = 1; 'mar' = 2; 'mie' = 3; 'jue' = 4; 'vie' = 5; 'sab' = 6 }
    foreach ($entry in ($spec -split ';')) {
        $m = [regex]::Match($entry.Trim(), '^(?:([A-Za-z,]+)\s+)?(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})$')
        if (-not $m.Success) { continue }
        if ($m.Groups[1].Success) {
            $days = @($m.Groups[1].Value.ToLower() -split ',' | ForEach-Object { $dayMap[$_] } | Where-Object { $_ -ne $null })
            if ($days -notcontains [int]$now.DayOfWeek) { continue }
        }
        $t = $now.Hour * 60 + $now.Minute
        $a = ([int]$m.Groups[2].Value) * 60 + [int]$m.Groups[3].Value
        $b = ([int]$m.Groups[4].Value) * 60 + [int]$m.Groups[5].Value
        if (($a -le $b -and $t -ge $a -and $t -lt $b) -or ($a -gt $b -and ($t -ge $a -or $t -lt $b))) { return $true }
    }
    return $false
}

# Disponibilidad (24h, 7d, 30d), latencia media de 24h e incidencias, a partir de historico.txt
function Get-Stats {
    $now = Get-Date
    $rows = @{}
    if (Test-Path -LiteralPath $histFile) {
        foreach ($ln in (Get-Content -LiteralPath $histFile -Encoding UTF8 | Select-Object -Last 60000)) {
            $f = $ln -split "`t"
            if ($f.Count -lt 4) { continue }
            $dt = [datetime]::MinValue
            if (-not [datetime]::TryParseExact($f[0], 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$dt)) { continue }
            if (-not $rows.ContainsKey($f[1])) { $rows[$f[1]] = New-Object System.Collections.ArrayList }
            [void]$rows[$f[1]].Add([pscustomobject]@{ t = $dt; status = $f[2]; ms = [int]$f[3] })
        }
    }
    $out = @{}
    foreach ($name in @($rows.Keys)) {
        $list = @($rows[$name] | Sort-Object t)
        $u = @{}
        foreach ($w in @(1, 7, 30)) {
            $from = $now.AddDays(-$w)
            $win = @($list | Where-Object { $_.t -ge $from })
            $up  = @($win | Where-Object { $_.status -ne 'CAIDA' -and $_.status -ne 'SIN RESPUESTA' })
            $u["d$w"] = if ($win.Count) { [Math]::Round(100.0 * $up.Count / $win.Count, 2) } else { $null }
        }
        $d1 = @($list | Where-Object { $_.t -ge $now.AddDays(-1) -and $_.status -ne 'CAIDA' -and $_.status -ne 'SIN RESPUESTA' })
        $avg = $null
        if ($d1.Count) { $avg = [int](($d1 | Measure-Object -Property ms -Average).Average) }

        $inc = New-Object System.Collections.ArrayList
        $cur = $null
        foreach ($r in @($list | Where-Object { $_.t -ge $now.AddDays(-30) })) {
            $down = ($r.status -eq 'CAIDA' -or $r.status -eq 'SIN RESPUESTA')
            if ($down) {
                if (-not $cur) { $cur = @{ s = $r.t; st = $r.status } }
            } elseif ($cur) {
                [void]$inc.Add([pscustomobject]@{ start = $cur.s.ToString('yyyy-MM-dd HH:mm'); end = $r.t.ToString('yyyy-MM-dd HH:mm'); min = [int]($r.t - $cur.s).TotalMinutes; status = $cur.st; ongoing = $false })
                $cur = $null
            }
        }
        if ($cur) {
            [void]$inc.Add([pscustomobject]@{ start = $cur.s.ToString('yyyy-MM-dd HH:mm'); end = $null; min = [int]($now - $cur.s).TotalMinutes; status = $cur.st; ongoing = $true })
        }
        $out[$name] = [pscustomobject]@{ uptime = $u; avgMs = $avg; incidents = @($inc | Sort-Object start -Descending | Select-Object -First 50) }
    }
    return $out
}

function Send-Hook([string]$hook, [string]$text) {
    if (-not $hook) { return }
    try {
        $json = ConvertTo-Json @{ text = $text } -Compress
        Invoke-WebRequest -Uri $hook -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json)) -UseBasicParsing -TimeoutSec 15 | Out-Null
    } catch {
        Add-Content -LiteralPath (Join-Path $root 'monitor_error.log') -Value ((Get-Date).ToString('s') + ' webhook: ' + $_.Exception.Message)
    }
}

function Run-Cycle($cfg) {
    $now   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $maint = Test-Maint $cfg.mant
    if (-not $cfg.mon) {
        Write-Health ([pscustomobject]@{ enabled = $false; generated = $now; intervalSeg = $cfg.sec; maintenance = $maint; services = @() })
        return
    }
    $results = New-Object System.Collections.ArrayList
    foreach ($s in @(Get-Services)) {
        $code = 0
        $err  = $null
        $body = ''
        $status = 'CAIDA'
        $sw = [Diagnostics.Stopwatch]::StartNew()

        if ($s.kind -eq 'http') {
            try {
                # Comprobacion simple: se pide la URL (siguiendo redirecciones) y se mira el codigo.
                $hr = [System.Net.HttpWebRequest]::Create($s.target)
                $hr.Method = 'GET'; $hr.Timeout = 10000; $hr.ReadWriteTimeout = 10000; $hr.AllowAutoRedirect = $true
                $hr.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36'
                $resp = [System.Net.HttpWebResponse]$hr.GetResponse()
                $code = [int]$resp.StatusCode
                $resp.Close()
            } catch {
                $err = $_.Exception.Message
                # el error real (WebException) puede venir dentro de InnerException
                $wex = $_.Exception
                if ($wex.InnerException) { $wex = $wex.InnerException }
                try { $code = [int]$wex.Response.StatusCode } catch { $code = 0 }
            }
            # OK solo con 200. Cualquier otra respuesta es CAIDA; sin respuesta, SIN RESPUESTA
            if ($code -eq 200) { $status = 'OK' }
            elseif ($code -gt 0) { $status = 'CAIDA'; $err = 'HTTP ' + $code }
            else { $status = 'SIN RESPUESTA' }
        }
        elseif ($s.kind -eq 'tcp') {
            $err = Test-Tcp $s.host $s.port 5000
            if (-not $err) { $status = 'OK' }
        }
        else {
            try {
                $up = Test-Connection -ComputerName $s.host -Count 1 -Quiet -ErrorAction Stop
            } catch { $up = $false; $err = $_.Exception.Message }
            if ($up) { $status = 'OK' } elseif (-not $err) { $err = 'Sin respuesta ICMP' }
        }
        $sw.Stop()
        $ms = [int]$sw.ElapsedMilliseconds

        if (-not $history.ContainsKey($s.name)) { $history[$s.name] = @() }
        $h = @($history[$s.name]) + [pscustomobject]@{ t = $now; ms = $ms; status = $status }
        $history[$s.name] = @($h | Select-Object -Last 200)

        # Historico persistente: una linea por comprobacion
        $line = $now + "`t" + $s.name + "`t" + $status + "`t" + $ms + "`t" + $s.kind
        Add-Content -LiteralPath $histFile -Value $line -Encoding UTF8

        # Aviso externo (webhook) solo al cambiar de estado, y nunca en mantenimiento
        $was = $false; $is = $false
        if ($prevStatus.ContainsKey($s.name)) {
            $was = (@('CAIDA', 'SIN RESPUESTA') -contains $prevStatus[$s.name])
            $is  = (@('CAIDA', 'SIN RESPUESTA') -contains $status)
            if (-not $maint) {
                if ($is -and -not $was) {
                    Send-Hook $cfg.hook ('ATALAYA: Servicio CAIDO - ' + $s.name + ' (' + $s.target + ') ' + $now + $(if ($err) { ' - ' + $err } else { '' }))
                } elseif ($was -and -not $is) {
                    Send-Hook $cfg.hook ('ATALAYA: Servicio RECUPERADO - ' + $s.name + ' (' + $s.target + ') ' + $now)
                }
            }
        }
        $prevStatus[$s.name] = $status

        [void]$results.Add([pscustomobject]@{
            name = $s.name; target = $s.target; kind = $s.kind; url = $s.target
            status = $status; code = $code; ms = $ms; error = $err
            history = @($history[$s.name])
        })
    }

    # Estadisticas (disponibilidad, latencia, incidencias) con el historico ya actualizado
    $stats = Get-Stats
    $out = @()
    foreach ($r in $results) {
        $st = $stats[$r.name]
        $upt = $null; $avg = $null; $incs = @()
        if ($st) { $upt = $st.uptime; $avg = $st.avgMs; $incs = @($st.incidents) }
        $out += [pscustomobject]@{
            name = $r.name; target = $r.target; kind = $r.kind; url = $r.url
            status = $r.status; code = $r.code; ms = $r.ms; error = $r.error
            history = @($r.history)
            uptime = $upt
            avgMs = $avg
            incidents = @($incs)
        }
    }
    Write-Health ([pscustomobject]@{ enabled = $true; generated = $now; intervalSeg = $cfg.sec; maintenance = $maint; services = @($out) })
}

# Bucle principal
while ($true) {
    try {
        $cfg    = Read-Cfg
        $forced = Test-Path -LiteralPath $flagFile
        $due    = ((Get-Date) - $lastRun).TotalSeconds -ge $cfg.sec
        # Actualizacion automatica de noticias: pide al servidor una recopilacion nueva
        if (((Get-Date) - $lastNews).TotalMinutes -ge $cfg.nmin) {
            $lastNews = Get-Date
            # el puerto lo escribe server.ps1 en puerto.txt (8080-8099)
            $pf = Join-Path $root 'puerto.txt'
            $pt = if (Test-Path -LiteralPath $pf) { (Get-Content -LiteralPath $pf -Raw).Trim() } else { '8080' }
            try { Invoke-WebRequest -Uri ('http://localhost:' + $pt + '/api/news?refresh=1') -UseBasicParsing -TimeoutSec 300 | Out-Null } catch {}
        }
        if ($forced -or $due) {
            if ($forced) { Remove-Item -LiteralPath $flagFile -Force -ErrorAction SilentlyContinue }
            $lastRun = Get-Date
            Run-Cycle $cfg
        }
    } catch {
        Add-Content -LiteralPath (Join-Path $root 'monitor_error.log') -Value ((Get-Date).ToString('s') + ' ' + $_.Exception.Message)
    }
    Start-Sleep -Seconds 2
}
