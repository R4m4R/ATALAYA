# Panel SOC - servidor local (Windows PowerShell 5.1, sin dependencias).
# Lee config.txt, fuentes.txt y temas.txt, recopila noticias, elimina duplicados
# y sirve la web en http://localhost:8080/
# NOTA: este fichero es solo ASCII a proposito (Windows PowerShell 5.1 lee mal UTF-8 sin BOM).

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls

$root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$pubDir   = [IO.Path]::GetFullPath((Join-Path $root 'public'))
$port     = 8080
$validSev   = @('Critica', 'Grave', 'Media', 'Baja', 'Info')
$validTheme = @('profesional', 'corporativo')

$script:cache     = $null
$script:cacheTime = [datetime]::MinValue

$months = @{
    jan=1; feb=2; mar=3; apr=4; may=5; jun=6; jul=7; aug=8; sep=9; oct=10; nov=11; dec=12;
    ene=1; abr=4; ago=8; dic=12; enero=1; febrero=2; marzo=3; abril=4; mayo=5; junio=6; julio=7;
    agosto=8; septiembre=9; setiembre=9; octubre=10; noviembre=11; diciembre=12
}

function Read-ConfigLines([string]$name) {
    $p = Join-Path $root $name
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    return @(Get-Content -LiteralPath $p -Encoding UTF8 | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') })
}

function Read-Raw([string]$name) {
    $p = Join-Path $root $name
    if (Test-Path -LiteralPath $p) { return [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) }
    return ''
}

function Write-Utf8([string]$name, [string]$text) {
    [IO.File]::WriteAllText((Join-Path $root $name), $text, (New-Object Text.UTF8Encoding($false)))
}

function Get-Config {
    $c = [pscustomobject]@{ severidades = @('Critica', 'Grave'); dias = 2; noticias_intervalo_min = 180; tema = 'profesional'; monitor_salud = $true; monitor_intervalo_seg = 1800; tamano_letra = 14; salud_umbral_verde = 90; salud_umbral_ambar = 60; latencia_aviso_ms = 2000; webhook_url = ''; mantenimiento = ''; ancho_pct = 100; casillas_fila = 8; resumen_caracteres = 1000; tamano_monitor = 11; horas_grafica_general = 24; horas_grafica_servicio = 2; minutos_aviso_incidencia = 15; panel_derecho = 'ultimas'; top_noticias = 10; monitor_vista = 'max' }
    foreach ($line in (Read-ConfigLines 'config.txt')) {
        $kv = $line -split '=', 2
        if ($kv.Count -ne 2) { continue }
        $k = $kv[0].Trim().ToLower()
        $v = $kv[1].Trim()
        $n = 0
        if ($k -eq 'severidades') {
            $c.severidades = @($v -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $validSev -contains $_ })
        } elseif ($k -eq 'tema' -and $validTheme -contains $v) {
            $c.tema = $v
        } elseif ($k -eq 'monitor_salud') {
            $c.monitor_salud = ($v -match '^(on|si|true|1)$')
        } elseif ($k -eq 'monitor_intervalo_seg' -and [int]::TryParse($v, [ref]$n) -and $n -ge 30 -and $n -le 3600) {
            $c.monitor_intervalo_seg = $n
        } elseif ($k -eq 'tamano_letra' -and [int]::TryParse($v, [ref]$n) -and $n -ge 11 -and $n -le 20) {
            $c.tamano_letra = $n
        } elseif ($k -eq 'salud_umbral_verde' -and [int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le 100) {
            $c.salud_umbral_verde = $n
        } elseif ($k -eq 'salud_umbral_ambar' -and [int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le 100) {
            $c.salud_umbral_ambar = $n
        } elseif ($k -eq 'latencia_aviso_ms' -and [int]::TryParse($v, [ref]$n) -and $n -ge 0 -and $n -le 60000) {
            $c.latencia_aviso_ms = $n
        } elseif ($k -eq 'webhook_url') {
            $c.webhook_url = $v
        } elseif ($k -eq 'mantenimiento') {
            $c.mantenimiento = $v
        } elseif ($k -eq 'ancho_pct' -and [int]::TryParse($v, [ref]$n) -and $n -ge 50 -and $n -le 100) {
            $c.ancho_pct = $n
        } elseif ($k -eq 'casillas_fila' -and [int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le 12) {
            $c.casillas_fila = $n
        } elseif ($k -eq 'monitor_vista' -and @('max','min') -contains $v) {
            $c.monitor_vista = $v
        } elseif ($k -eq 'top_noticias' -and [int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le 50) {
            $c.top_noticias = $n        } elseif ($k -eq 'panel_derecho' -and @('ultimas','temas') -contains $v) {
            $c.panel_derecho = $v
        } elseif ($k -eq 'minutos_aviso_incidencia' -and [int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le 1440) {
            $c.minutos_aviso_incidencia = $n
        } elseif ($k -eq 'horas_grafica_general' -and [int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le 168) {
            $c.horas_grafica_general = $n
        } elseif ($k -eq 'horas_grafica_servicio' -and [int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le 24) {
            $c.horas_grafica_servicio = $n
        } elseif ($k -eq 'tamano_monitor' -and [int]::TryParse($v, [ref]$n) -and $n -ge 9 -and $n -le 16) {
            $c.tamano_monitor = $n
        } elseif ($k -eq 'resumen_caracteres' -and [int]::TryParse($v, [ref]$n) -and $n -ge 100 -and $n -le 5000) {
            $c.resumen_caracteres = $n
        } elseif ($k -eq 'dias' -and [int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le 30) {
            $c.dias = $n
        } elseif ($k -eq 'noticias_intervalo_min' -and [int]::TryParse($v, [ref]$n) -and $n -ge 1 -and $n -le 1440) {
            $c.noticias_intervalo_min = $n
        }
    }
    if ($c.severidades.Count -eq 0) { $c.severidades = @('Critica', 'Grave') }
    return $c
}

function Save-Config($c) {
    $text = "# Configuracion del panel SOC (tambien editable desde la web, boton Ajustes)`r`n" +
            "# severidades: Critica, Grave, Media, Baja, Info (separadas por coma)`r`n" +
            "# dias: ventana temporal en dias (1-30)`r`n" +
            "# noticias_intervalo_min: cada cuantos minutos se actualizan las noticias (1-1440, por defecto 180)`r`n" +
            "severidades=" + (@($c.severidades) -join ',') + "`r`n" +
            "dias=" + [int]$c.dias + "`r`n" +
            "noticias_intervalo_min=" + [int]$c.noticias_intervalo_min + "`r`n" +
            "# tema visual: profesional o corporativo`r`n" +
            "tema=" + $c.tema + "`r`n" +
            "# monitor de salud de servicios (on/off)`r`n" +
            "monitor_salud=" + $(if ($c.monitor_salud) { 'on' } else { 'off' }) + "`r`n" +
            "# intervalo de comprobacion de salud en segundos (30-3600)`r`n" +
            "monitor_intervalo_seg=" + [int]$c.monitor_intervalo_seg + "`r`n" +
            "# umbrales del estado general de salud (%): verde si >= verde, ambar si >= ambar, rojo si es menor`r`n" +
            "salud_umbral_verde=" + [int]$c.salud_umbral_verde + "`r`n" +
            "salud_umbral_ambar=" + [int]$c.salud_umbral_ambar + "`r`n" +
            "# latencia: un servicio que responde OK pero tarda mas que esto (ms) pasa a LENTO (0 = desactivado)`r`n" +
            "latencia_aviso_ms=" + [int]$c.latencia_aviso_ms + "`r`n" +
            "# webhook (Teams/Slack): URL que recibe un aviso al caer o recuperarse un servicio (vacio = desactivado)`r`n" +
            "webhook_url=" + [string]$c.webhook_url + "`r`n" +
            "# mantenimiento: ventanas sin avisos. Formato: [Lun,Mie ]HH:MM-HH:MM separadas por ; (ej. Sab 02:00-04:00;23:00-23:30)`r`n" +
            "mantenimiento=" + [string]$c.mantenimiento + "`r`n" +
            "# ancho de la web en % de la pantalla (50-100)`r`n" +
            "ancho_pct=" + [int]$c.ancho_pct + "`r`n" +
            "# casillas de monitorizacion por fila (1-12)`r`n" +
            "casillas_fila=" + [int]$c.casillas_fila + "`r`n" +
            "# caracteres del resumen de cada noticia en el popup (100-5000)`r`n" +
            "resumen_caracteres=" + [int]$c.resumen_caracteres + "`r`n" +
            "# tamano de letra de las tarjetas del monitor de salud (px, 9-16)`r`n" +
            "tamano_monitor=" + [int]$c.tamano_monitor + "`r`n" +
            "# horas que muestra la grafica principal del monitor (1-168, por defecto 24)`r`n" +
            "horas_grafica_general=" + [int]$c.horas_grafica_general + "`r`n" +
            "# horas que muestra cada grafica pequeña de servicio (1-24, por defecto 2)`r`n" +
            "horas_grafica_servicio=" + [int]$c.horas_grafica_servicio + "`r`n" +
            "# minutos que se muestra el aviso 'Detectada ... normalidad ...' bajo la grafica general (1-1440)`r`n" +
            "minutos_aviso_incidencia=" + [int]$c.minutos_aviso_incidencia + "`r`n" +
            "# panel derecho por defecto: ultimas o temas`r`n" +
            "panel_derecho=" + [string]$c.panel_derecho + "`r`n" +
            "# numero de noticias en el TOP de Ultimas noticias (1-50)`r`n" +
            "top_noticias=" + [int]$c.top_noticias + "`r`n" +
            "# monitor de salud al abrir: max (maximizado) o min (minimizado)`r`n" +
            "monitor_vista=" + [string]$c.monitor_vista + "`r`n" +
            "# tamano de letra de la web en px (11-20)`r`n" +
            "tamano_letra=" + [int]$c.tamano_letra + "`r`n"
    Write-Utf8 'config.txt' $text
}

function Get-Sources {
    $list = @()
    foreach ($line in (Read-ConfigLines 'fuentes.txt')) {
        $p = $line -split '\|'
        if ($p.Count -ge 2) {
            $list += [pscustomobject]@{ name = $p[0].Trim(); url = $p[1].Trim() }
        }
    }
    return $list
}

function Get-Topics { return @(Read-ConfigLines 'temas.txt') }

function Convert-Html([string]$s) {
    $t = [regex]::Replace($s, '<[^>]+>', ' ')
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    return ([regex]::Replace($t, '\s+', ' ')).Trim()
}

function Get-DateFromText([string]$t) {
    $m = [regex]::Match($t, '(\d{4})-(\d{2})-(\d{2})')
    if ($m.Success) { try { return [datetime]::new([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value) } catch {} }
    $m = [regex]::Match($t, '(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})')
    if ($m.Success) { try { return [datetime]::new([int]$m.Groups[3].Value, [int]$m.Groups[2].Value, [int]$m.Groups[1].Value) } catch {} }
    $m = [regex]::Match($t, '(?i)\b([a-z]{3,10})\.?\s+(\d{1,2}),?\s+(\d{4})')
    if ($m.Success -and $months.ContainsKey($m.Groups[1].Value.ToLower())) {
        try { return [datetime]::new([int]$m.Groups[3].Value, $months[$m.Groups[1].Value.ToLower()], [int]$m.Groups[2].Value) } catch {}
    }
    $m = [regex]::Match($t, '(?i)\b(\d{1,2})\s+(?:de\s+)?([a-z]{3,10})\.?,?\s+(?:de\s+)?(\d{4})')
    if ($m.Success -and $months.ContainsKey($m.Groups[2].Value.ToLower())) {
        try { return [datetime]::new([int]$m.Groups[3].Value, $months[$m.Groups[2].Value.ToLower()], [int]$m.Groups[1].Value) } catch {}
    }
    return $null
}

# Igual que Get-DateFromText, pero conserva la hora cuando la fuente la trae (RSS/Atom)
function Get-DateTimeFromText([string]$t) {
    $d = Get-DateFromText $t
    if (-not $d) { return $null }
    try {
        $full = [DateTimeOffset]::Parse($t, [Globalization.CultureInfo]::InvariantCulture).LocalDateTime
        if ($full.Date -eq $d.Date -and ($full.Hour -ne 0 -or $full.Minute -ne 0)) { return $full }
    } catch {}
    return $d
}

function Get-Severity([string]$title, [string]$text) {
    $max = -1.0
    foreach ($m in [regex]::Matches($text, '(?i)CVSS[^0-9]{0,15}(\d{1,2}(?:[.,]\d)?)')) {
        $v = [double]::Parse(($m.Groups[1].Value -replace ',', '.'), [Globalization.CultureInfo]::InvariantCulture)
        if ($v -le 10 -and $v -gt $max) { $max = $v }
    }
    if ($max -ge 9) { return @('Critica', 4, $max) }
    if ($max -ge 7) { return @('Grave', 3, $max) }
    if ($max -ge 4) { return @('Media', 2, $max) }
    if ($max -ge 0) { return @('Baja', 1, $max) }
    if ($title -match '(?i)cr.tic|zero.?day|0.?day|remote code|\bRCE\b|explotad|actively exploited|ejecuci.n remota') { return @('Critica', 4, $null) }
    if ($title -match '(?i)vulnerab|CVE-|parche|patch|exploit|malware|ransomware|escritura fuera|desbordamiento|overflow|inyecci|bypass|elevaci.n de privilegios|flaw|code execution|execute code|breach') { return @('Grave', 3, $null) }
    return @('Info', 0, $null)
}

# Invoke-WebRequest -UseBasicParsing decodifica el cuerpo como ISO-8859-1 cuando el sitio no
# declara su charset en la cabecera Content-Type (aunque el contenido real sea UTF-8, lo habitual
# hoy en dia). Eso produce el tipico texto corrupto "MÃºltiples" en vez de "Múltiples". Se evita
# leyendo los bytes crudos de la respuesta y decodificandolos siempre como UTF-8.
function Get-ResponseTextUtf8($r) {
    try { return [System.Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()) }
    catch { return [string]$r.Content }
}

function Get-SourceItems($src) {
    $r = Invoke-WebRequest -Uri $src.url -UseBasicParsing -TimeoutSec 25 `
         -Headers @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'; 'Accept' = 'text/html,application/xhtml+xml,application/rss+xml,application/xml;q=0.9'; 'Accept-Language' = 'es-ES,es;q=0.9,en;q=0.8' }
    return Parse-SourceHtml (Get-ResponseTextUtf8 $r) $src
}

# Convierte el HTML (o RSS) de una pagina en noticias
function Parse-SourceHtml([string]$html, $src) {

    # Fuentes RSS / Atom (XML): se leen los campos directamente
    if ($html -match '<(rss|feed)[\s>]') {
        [xml]$x = $html.TrimStart([char]0xFEFF)
        if ($x.rss) { $entries = @($x.rss.channel.item) } else { $entries = @($x.feed.entry) }
        $outX = New-Object System.Collections.ArrayList
        foreach ($e in $entries) {
            $title = Convert-Html ([string]$e.title)
            if ($title.Length -lt 25 -or $title.Length -gt 250) { continue }
            $lk = $null
            foreach ($l in @($e.link)) { if ($l.href) { $lk = $l.href; break } }
            if (-not $lk) { $lk = [string]$e.link }
            if (-not $lk) { continue }
            $ds = [string]$e.pubDate
            if (-not $ds) { $ds = [string]$e.published }
            if (-not $ds) { $ds = [string]$e.updated }
            # el contenido puede llegar como elemento XML (no como texto): se toma su texto
            $desc = if ($e.description -is [System.Xml.XmlElement]) { $e.description.InnerText } else { [string]$e.description }
            if (-not $desc) { $desc = if ($e.summary -is [System.Xml.XmlElement]) { $e.summary.InnerText } else { [string]$e.summary } }
            $ctxT = Convert-Html $desc
            [void]$outX.Add([pscustomobject]@{
                title   = $title
                url     = $lk.Trim()
                source  = $src.name
                date    = (Get-DateTimeFromText $ds)
                context = $ctxT.Substring(0, [Math]::Min(3000, $ctxT.Length))
            })
        }
        return $outX
    }

    $base = New-Object System.Uri($src.url)
    $out  = New-Object System.Collections.ArrayList
    $rx   = [regex]'(?is)<a\s[^>]*?href\s*=\s*["'']([^"'']+)["''][^>]*>(.*?)</a>'
    foreach ($m in $rx.Matches($html)) {
        $title = Convert-Html $m.Groups[2].Value
        if ($title.Length -lt 25 -or $title.Length -gt 250) { continue }
        $href = $m.Groups[1].Value
        if ($href -match '^(#|mailto:|javascript:)') { continue }
        try { $url = (New-Object System.Uri($base, $href)).AbsoluteUri } catch { continue }
        $aEnd  = $m.Index + $m.Length
        $after = $html.Substring($aEnd, [Math]::Min(500, $html.Length - $aEnd))
        $bSt   = [Math]::Max(0, $m.Index - 300)
        $before = $html.Substring($bSt, $m.Index - $bSt)
        $date = Get-DateFromText $after
        if (-not $date) { $date = Get-DateFromText $before }
        [void]$out.Add([pscustomobject]@{
            title   = $title
            url     = $url
            source  = $src.name
            date    = $date
            context = (Convert-Html ($html.Substring($aEnd, [Math]::Min(3000, $html.Length - $aEnd))))
        })
    }
    return $out
}

function Get-Norm([string]$t) {
    return (([regex]::Replace($t.ToLower(), '[^a-z0-9 ]', ' ')) -replace '\s+', ' ').Trim()
}

# Palabras significativas (mas de 2 letras) de un titulo, precalculadas UNA vez por noticia.
# El dedup compara cada noticia contra todas las demas: calcular esto en cada comparacion
# (como se hacia antes) es la causa de que el refresco tardase mas de 20s con pocos cientos
# de noticias. Con el set ya calculado, cada comparacion es O(palabras) en vez de recalcular.
function Get-WordSet([string]$title) {
    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($w in (Get-Norm $title).Split(' ')) { if ($w.Length -gt 2) { [void]$set.Add($w) } }
    return $set
}

function Test-Duplicate($a, $b) {
    if (@($a.cves | Where-Object { $_ -in $b.cves }).Count -gt 0) { return $true }
    if ($a.WordSet.Count -eq 0 -or $b.WordSet.Count -eq 0) { return $false }
    $inter = 0
    foreach ($w in $a.WordSet) { if ($b.WordSet.Contains($w)) { $inter++ } }
    $union = $a.WordSet.Count + $b.WordSet.Count - $inter
    if ($union -eq 0) { return $false }
    return (($inter / $union) -ge 0.6)
}

# Archivo historico de noticias (archivo.jsonl): cada noticia con fecha se guarda una vez.
# Algunas webs (p.ej. INCIBE) sirven el mismo aviso en dos rutas distintas ("/incibe-cert/..."
# y "/index.php/incibe-cert/..."), lo que duplicaba la entrada en el archivo al no coincidir
# la URL exacta. Se normaliza quitando ese "/index.php" antes de usarla como clave de duplicado.
function Get-NormalizedUrl([string]$url) {
    return $url -replace '/index\.php(/|$)', '$1'
}

function Save-Archive($items) {
    $p = Join-Path $root 'archivo.jsonl'
    $seen = @{}
    if (Test-Path -LiteralPath $p) {
        foreach ($ln in [IO.File]::ReadAllLines($p, [Text.Encoding]::UTF8)) {
            try { $o = $ln | ConvertFrom-Json; $seen[(Get-NormalizedUrl ([string]$o.url))] = $true } catch {}
        }
    }
    $add = New-Object System.Collections.ArrayList
    foreach ($it in $items) {
        $key = Get-NormalizedUrl ([string]$it.url)
        if (-not $it.date -or $seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $ctx = [string]$it.context
        if ($ctx.Length -gt 1500) { $ctx = $ctx.Substring(0, 1500) }
        $rec = [pscustomobject]@{ title = [string]$it.title; url = [string]$it.url; source = [string]$it.source; date = $it.date.ToString('yyyy-MM-ddTHH:mm'); context = $ctx }
        [void]$add.Add((ConvertTo-Json $rec -Compress))
    }
    if ($add.Count -gt 0) { [IO.File]::AppendAllLines($p, [string[]]$add, (New-Object Text.UTF8Encoding($false))) }
    return $add.Count
}

# Busqueda en el archivo: palabra + periodo en dias. Mismas reglas de severidad y temas que el feed.
# ---- Motor general de busqueda historica ----
# Descarga una pagina (HTML) con el mismo navegador de cabecera que el resto del programa.
function Get-PageRaw([string]$url) {
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 25 -Headers @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'; 'Accept-Language' = 'es-ES,es;q=0.9,en;q=0.8' }
    return Get-ResponseTextUtf8 $r
}

# Enlaces de paginacion del mismo sitio: "siguiente", "anteriores", rel=next, numeros de pagina y
# URLs con page/paged/pagina/p= . Asi se descubre la paginacion de cada web sin reglas fijas.
function Get-PageLinks([string]$html, [string]$base) {
    $out = New-Object System.Collections.ArrayList
    $bu = [Uri]$base
    foreach ($m in [regex]::Matches($html, '(?is)<a\s[^>]*?href\s*=\s*["'']([^"'']+)["''][^>]*>(.*?)</a>')) {
        $href = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value)
        $txt  = Convert-Html $m.Groups[2].Value
        $rel  = $m.Value -match '(?i)rel\s*=\s*["'']?next'
        $pag  = $href -match '(?i)(\bpage[=/-]?|\bpaged[=/]|\bpagina[=/-]?|[?&]p=|/pag/)\d+'
        $txtP = ($txt -match '(?i)^(siguiente|next|older|anteriores?|m[aá]s antiguas?|»|›|>|\d{1,3})$')
        if (-not ($rel -or $pag -or $txtP)) { continue }
        try { $u = (New-Object Uri($bu, $href)).AbsoluteUri } catch { continue }
        if (([Uri]$u).Host -ne $bu.Host) { continue }
        if (-not $out.Contains($u)) { [void]$out.Add($u) }
    }
    return ,@($out)
}

# Formulario de busqueda del sitio (input type=search o nombre tipico): devuelve la URL de busqueda para el termino.
function Get-SearchUrl([string]$html, [string]$base, [string]$term) {
    foreach ($f in [regex]::Matches($html, '(?is)<form\b[^>]*>.*?</form>')) {
        $inp = [regex]::Match($f.Value, '(?is)<input\b[^>]*(type\s*=\s*["'']?search|name\s*=\s*["'']?(s|q|query|search|keyword|keywords|texto|buscar|busqueda)["''\s>])[^>]*>')
        if (-not $inp.Success) { continue }
        $nm = [regex]::Match($inp.Value, '(?i)name\s*=\s*["'']?([^"''\s>]+)').Groups[1].Value
        if (-not $nm) { continue }
        $act = [regex]::Match($f.Value, '(?i)<form\b[^>]*action\s*=\s*["'']([^"'']*)').Groups[1].Value
        $au = $base
        if ($act) { try { $au = (New-Object Uri((New-Object Uri($base)), [System.Net.WebUtility]::HtmlDecode($act))).AbsoluteUri } catch {} }
        $sep = '?'; if ($au -match '\?') { $sep = '&' }
        return ($au + $sep + $nm + '=' + [Uri]::EscapeDataString($term))
    }
    return $null
}

# Recorre una web: busqueda propia + paginas de listado y de resultados, de la mas reciente a la mas antigua.
# Para cuando una pagina ya no tiene noticias dentro del periodo o no aporta nada nuevo.
function Invoke-Crawl([string]$start, [string]$name, [string]$term, [int]$dias, [int]$maxPages) {
    $cutoff = (Get-Date).Date.AddDays(-$dias)
    $queue = New-Object System.Collections.Queue
    $seen  = @{}
    $pages = 0
    $first = Get-PageRaw $start
    $su = Get-SearchUrl $first $start $term
    if (-not $su) { $su = ([Uri]$start).GetLeftPart([UriPartial]::Authority) + '/?s=' + [Uri]::EscapeDataString($term) }
    $queue.Enqueue($su)
    if ($dias -gt 2) { $queue.Enqueue($start) }
    while ($queue.Count -gt 0 -and $pages -lt $maxPages) {
        $u = [string]$queue.Dequeue()
        if ($seen.ContainsKey($u)) { continue }
        $seen[$u] = $true
        $pages++
        if ($u -eq $start) { $html = $first } else {
            try { $html = Get-PageRaw $u } catch { continue }
        }
        $items = @(Parse-SourceHtml $html ([pscustomobject]@{ name = $name; url = $u }))
        $added = Save-Archive $items
        $dated = @($items | Where-Object { $_.date })
        if ($dated.Count -eq 0) { continue }
        if (-not ($dated | Where-Object { $_.date -ge $cutoff })) { continue }
        if ($added -eq 0 -and $u -ne $start) { continue }
        foreach ($l in (Get-PageLinks $html $u)) { if (-not $seen.ContainsKey($l)) { $queue.Enqueue($l) } }
        Start-Sleep -Milliseconds 1000
    }
}

# Busca el termino en cada fuente (buscador propio + paginacion). Para periodos de mas de 2 dias recorre mas paginas.
function Search-Sources([string]$q, [int]$dias) {
    $maxPages = 3
    if ($dias -gt 2) { $maxPages = 12 }
    foreach ($src in (Get-Sources)) {
        try { Invoke-Crawl $src.url $src.name $q $dias $maxPages } catch {}
    }
}
# Busqueda SOLO en el fichero interno de noticias (archivo.jsonl), sin tocar las fuentes en vivo.
# La usa el buscador del feed: nunca descarga nada de internet, solo filtra lo ya guardado.
# Lee el archivo interno de noticias (archivo.jsonl) dentro de una ventana de fechas.
# La usan tanto el feed principal como el buscador: una fuente puede dejar de listar en su
# pagina/RSS una noticia de hace 1-2 dias (porque ya hay noticias mas nuevas en su lugar) aunque
# siga dentro de la ventana configurada; leyendo del archivo en vez de solo lo recien descargado
# en esta pasada, esas noticias no desaparecen del feed mientras sigan dentro de la ventana.
function Get-ArchiveItems([datetime]$cutoff) {
    $p = Join-Path $root 'archivo.jsonl'
    $all = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $p) {
        foreach ($ln in [IO.File]::ReadAllLines($p, [Text.Encoding]::UTF8)) {
            try { $o = $ln | ConvertFrom-Json } catch { continue }
            $d = [datetime]::MinValue
            if (-not [datetime]::TryParseExact([string]$o.date, 'yyyy-MM-ddTHH:mm', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { continue }
            if ($d -lt $cutoff) { continue }
            [void]$all.Add([pscustomobject]@{ title = [string]$o.title; url = [string]$o.url; source = [string]$o.source; date = $d; context = [string]$o.context })
        }
    }
    return $all
}

# Busqueda SOLO en el fichero interno de noticias (archivo.jsonl), sin tocar las fuentes en vivo.
# La usa el buscador del feed: nunca descarga nada de internet, solo filtra lo ya guardado.
function Search-ArchivoLocal([int]$dias) {
    $cfg    = Get-Config
    $topics = Get-Topics
    $omit   = @(Read-ConfigLines 'omitir.txt')
    $cutoff = (Get-Date).Date.AddDays(-$dias)
    $all    = Get-ArchiveItems $cutoff
    $final  = Convert-Items $all $cfg $topics $omit $cutoff
    return [pscustomobject]@{
        generated  = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        windowDays = $dias
        total      = $final.Count
        items      = $final
    }
}

function Search-Archive([string]$q, [int]$dias) {
    if ($q) { Search-Sources $q $dias }
    $cfg    = Get-Config
    $topics = Get-Topics
    $omit   = @(Read-ConfigLines 'omitir.txt')
    $cutoff = (Get-Date).Date.AddDays(-$dias)
    $p = Join-Path $root 'archivo.jsonl'
    $all = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $p) {
        foreach ($ln in [IO.File]::ReadAllLines($p, [Text.Encoding]::UTF8)) {
            try { $o = $ln | ConvertFrom-Json } catch { continue }
            $d = [datetime]::MinValue
            if (-not [datetime]::TryParseExact([string]$o.date, 'yyyy-MM-ddTHH:mm', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { continue }
            if ($d -lt $cutoff) { continue }
            $txt = ([string]$o.title) + ' ' + ([string]$o.context)
            if ($q -and ($txt.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -lt 0)) { continue }
            [void]$all.Add([pscustomobject]@{ title = [string]$o.title; url = [string]$o.url; source = [string]$o.source; date = $d; context = [string]$o.context })
        }
    }
    $final = Convert-Items $all $cfg $topics $omit $cutoff

    # Fallback histórico: si hay pocos resultados, agregar del histórico (últimos 2 días guardados)
    if ($final.Count -lt 10 -and $dias -le 2) {
        $hp = Join-Path $root 'historico.txt'
        if (Test-Path -LiteralPath $hp) {
            $hist = New-Object System.Collections.ArrayList
            $fallbackCutoff = (Get-Date).Date.AddDays(-14)
            foreach ($ln in (Get-Content -LiteralPath $hp -Encoding UTF8 | Select-Object -Last 10000)) {
                $f = $ln -split "`t"
                if ($f.Count -lt 4) { continue }
                $dt = [datetime]::MinValue
                if (-not [datetime]::TryParseExact($f[0], 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$dt)) { continue }
                # Solo agregar si está fuera del periodo actual pero no muy antiguo
                if ($dt -ge $cutoff -or $dt -lt $fallbackCutoff) { continue }
                [void]$hist.Add([pscustomobject]@{ title = $f[1]; severity = $f[2]; date = $dt; source = 'Histórico' })
            }
            # Agregar hasta 5 items del histórico
            $toAdd = $hist | Select-Object -First ([Math]::Min(5, 20 - $final.Count))
            foreach ($h in $toAdd) {
                [void]$final.Add($h)
            }
        }
    }

    return [pscustomobject]@{
        generated  = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        windowDays = $dias
        query      = $q
        total      = $final.Count
        items      = $final
    }
}

# Convierte noticias en bruto en las noticias finales (severidad, temas, omitir, dedupe).
# Nota de rendimiento: usar Where-Object/ForEach-Object dentro del bucle principal (uno por
# cada noticia, para cada tema y cada termino a omitir) recompila un regex nuevo en cada
# vuelta y resuelve variables por scope-chain en cada llamada: con unos cientos de noticias
# y una veintena de temas esto llegaba a tardar mas de 15 segundos. Los regex de temas/omitir
# se compilan UNA sola vez aqui fuera, y el filtrado usa bucles foreach normales (sin pipeline).
function Convert-Items($all, $cfg, $topics, $omit, $cutoff) {
    $topicRx = [ordered]@{}
    foreach ($t in $topics) { $topicRx[$t] = [regex]::new('(?i)(?<![A-Za-z])' + [regex]::Escape($t) + '(?![A-Za-z])') }
    $omitRx = @()
    foreach ($o in $omit) { $omitRx += [regex]::new('(?i)(?<![A-Za-z])' + [regex]::Escape($o) + '(?![A-Za-z])') }
    $cveRx = [regex]::new('CVE-\d{4}-\d{4,7}')

    $list = New-Object System.Collections.ArrayList
    foreach ($it in $all) {
        # Solo noticias con fecha detectada dentro de la ventana
        if (-not $it.date -or $it.date -lt $cutoff) { continue }
        $ctx  = $it.context.Substring(0, [Math]::Min(300, $it.context.Length))
        $sev  = Get-Severity $it.title ($it.title + ' ' + $ctx)
        # Se descartan de inmediato los niveles que el usuario no quiere buscar
        if ($cfg.severidades -notcontains $sev[0]) { continue }

        $cvesSet = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($m in $cveRx.Matches($it.title + ' ' + $ctx)) { [void]$cvesSet.Add($m.Value.ToUpper()) }
        $cves = @($cvesSet)

        $tp = New-Object 'System.Collections.Generic.List[string]'
        foreach ($t in $topics) { if ($topicRx[$t].IsMatch($it.title)) { $tp.Add($t) } }
        # Solo se muestran noticias que coinciden con algun tema solicitado
        if ($tp.Count -eq 0) { continue }
        # Omitir: si el titulo contiene un termino omitido Y un tema, se descarta (solo se mira el titulo)
        $omitido = $false
        foreach ($rx in $omitRx) { if ($rx.IsMatch($it.title)) { $omitido = $true; break } }
        if ($omitido) { continue }

        # resumen: hasta resumen_caracteres caracteres, cortado en una palabra completa
        $summ = [string]$it.context
        $lim = [int]$cfg.resumen_caracteres
        if ($summ.Length -gt $lim) {
            $summ = $summ.Substring(0, $lim)
            $sp = $summ.LastIndexOf(' ')
            if ($sp -gt 0) { $summ = $summ.Substring(0, $sp) }
            $summ = $summ + '...'
        }
        $dateStr = $null; $key = '000000000000'
        if ($it.date) {
            # con hora si la fuente la trae; key = orden cronologico
            $dateStr = if ($it.date.Hour -or $it.date.Minute) { $it.date.ToString('yyyy-MM-dd HH:mm') } else { $it.date.ToString('yyyy-MM-dd') }
            $key = $it.date.ToString('yyyyMMddHHmm')
        }
        [void]$list.Add([pscustomobject]@{
            title = $it.title; url = $it.url; date = $dateStr; key = $key; summary = $summ; alts = @()
            severity = $sev[0]; rank = $sev[1]; cvss = $sev[2]; WordSet = (Get-WordSet $it.title)
            cves = $cves; topics = @($tp); sources = @($it.source)
        })
    }

    # Deduplicado: se fusionan noticias del mismo CVE o con titulo casi identico
    $ordered = @($list | Sort-Object -Property @{Expression = 'rank'; Descending = $true}, @{Expression = 'key'; Descending = $true})
    $uniq = New-Object System.Collections.ArrayList
    foreach ($x in $ordered) {
        $dup = $null
        foreach ($u in $uniq) { if (Test-Duplicate $u $x) { $dup = $u; break } }
        if ($dup) {
            if (-not ($dup.sources -contains $x.sources[0])) { $dup.sources = @($dup.sources + $x.sources) }
            # se guarda el aviso repetido para mostrarlo en el popup de la noticia
            $dup.alts = @(@($dup.alts) + [pscustomobject]@{ title = $x.title; url = $x.url; source = $x.sources[0] })
            $dup.topics = @(@($dup.topics + $x.topics) | Select-Object -Unique)
            $dup.cves   = @(@($dup.cves + $x.cves) | Select-Object -Unique)
            if ($x.key -gt $dup.key) { $dup.key = $x.key; $dup.date = $x.date }   # se queda con la fecha mas reciente
        } else {
            [void]$uniq.Add($x)
        }
    }
    $final = @($uniq | Sort-Object -Property @{Expression = 'rank'; Descending = $true}, @{Expression = 'key'; Descending = $true})
    # El WordSet solo hacia falta para el dedup: se quita para no mandarlo en el JSON de salida
    foreach ($f in $final) { $f.PSObject.Properties.Remove('WordSet') }
    return $final
}

# Escribe el progreso del refresco de fuentes (lo consulta la web para mostrar un % real)
function Set-ProgresoFuentes([int]$done, [int]$total, [bool]$activo) {
    $json = ConvertTo-Json ([pscustomobject]@{ done = $done; total = $total; activo = $activo }) -Compress
    $p = Join-Path $root 'refresco_progreso.json'
    try {
        # Escritura atomica (fichero temporal + rename) para que la web nunca lea el fichero a medio escribir
        $tmp = $p + '.tmp'
        [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $p -Force
    } catch {}
}

function Get-ProgresoFuentes {
    $p = Join-Path $root 'refresco_progreso.json'
    if (Test-Path -LiteralPath $p) {
        try { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {}
    }
    return [pscustomobject]@{ done = 0; total = 0; activo = $false }
}

# Ultimo informe generado (persistido en disco: lo escribe el worker de refresco en segundo plano)
function Get-CacheReport {
    $p = Join-Path $root 'cache_noticias.json'
    if (Test-Path -LiteralPath $p) {
        try { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {}
    }
    return $null
}

function Save-CacheReport($report) {
    Write-Utf8 'cache_noticias.json' (ConvertTo-Json $report -Depth 6)
}

# Descarga todas las fuentes EN PARALELO (en vez de una a una) para que el refresco sea rapido.
# Si se indica $progresoPath, va dejando el avance (fuentes completadas / total) para que la web
# pueda mostrar un % real en lugar de uno inventado.
function Fetch-SourcesParallel($sources) {
    $total = @($sources).Count
    $status = New-Object System.Collections.ArrayList
    $all    = New-Object System.Collections.ArrayList
    if ($total -eq 0) { return [pscustomobject]@{ status = $status; items = $all } }

    Set-ProgresoFuentes 0 $total $true
    $nucleoPath = Join-Path $root 'nucleo.ps1'
    $pool = [runspacefactory]::CreateRunspacePool(1, [Math]::Min(8, $total))
    $pool.Open()
    $jobs = New-Object System.Collections.ArrayList
    foreach ($s in $sources) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript({
            param($nucleoPath, $s)
            . $nucleoPath
            try {
                $items = @(Get-SourceItems $s)
                [pscustomobject]@{ name = $s.name; url = $s.url; ok = $true; items = $items; error = $null }
            } catch {
                [pscustomobject]@{ name = $s.name; url = $s.url; ok = $false; items = @(); error = $_.Exception.Message }
            }
        }).AddArgument($nucleoPath).AddArgument($s)
        [void]$jobs.Add([pscustomobject]@{ Pipe = $ps; Handle = $ps.BeginInvoke(); Done = $false })
    }

    $doneCount = 0
    while (@($jobs | Where-Object { -not $_.Done }).Count -gt 0) {
        foreach ($j in $jobs) {
            if (-not $j.Done -and $j.Handle.IsCompleted) {
                try {
                    $r = $j.Pipe.EndInvoke($j.Handle)
                    foreach ($res in $r) {
                        [void]$status.Add([pscustomobject]@{ name = $res.name; url = $res.url; ok = $res.ok; total = @($res.items).Count; error = $res.error })
                        foreach ($it in $res.items) { [void]$all.Add($it) }
                    }
                } catch {
                } finally {
                    $j.Pipe.Dispose()
                    $j.Done = $true
                    $doneCount++
                    Set-ProgresoFuentes $doneCount $total $true
                }
            }
        }
        if (@($jobs | Where-Object { -not $_.Done }).Count -gt 0) { Start-Sleep -Milliseconds 120 }
    }
    $pool.Close(); $pool.Dispose()
    return [pscustomobject]@{ status = $status; items = $all }
}

function Build-Report {
    $cfg     = Get-Config
    $sources = Get-Sources
    $topics  = Get-Topics
    $omit    = @(Read-ConfigLines 'omitir.txt')
    $cutoff  = (Get-Date).Date.AddDays(-$cfg.dias)

    $res    = Fetch-SourcesParallel $sources
    $status = $res.status

    [void](Save-Archive $res.items)
    # El feed se construye desde el archivo acumulado (no solo de lo recien descargado en esta
    # pasada): asi una noticia de hace 1-2 dias que una fuente ya no lista en su pagina/RSS sigue
    # apareciendo mientras este dentro de la ventana configurada.
    $all   = Get-ArchiveItems $cutoff
    $final = Convert-Items $all $cfg $topics $omit $cutoff

    return [pscustomobject]@{
        generated  = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        windowDays = $cfg.dias
        severities = @($cfg.severidades)
        sources    = @($status)
        topics     = @($topics)
        total      = $final.Count
        items      = $final
    }
}

# Lanza el refresco de fuentes en un proceso aparte (no bloquea el servidor mientras descarga).
# Devuelve $false si ya habia uno en marcha.
function Start-RefrescoWorker {
    $lock = Join-Path $root 'refresco.lock'
    if (Test-Path -LiteralPath $lock) {
        # Si el candado lleva mas de 5 minutos, se considera un worker muerto y se limpia
        if (((Get-Date) - (Get-Item -LiteralPath $lock).LastWriteTime).TotalMinutes -lt 5) { return $false }
        Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
    }
    Set-Content -LiteralPath $lock -Value ([string](Get-Date)) -Encoding UTF8
    $sources = Get-Sources
    Set-ProgresoFuentes 0 (@($sources).Count) $true
    $worker = Join-Path $root 'refrescar_worker.ps1'
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $worker) | Out-Null
    return $true
}

function Get-Report([bool]$force) {
    $cfg = Get-Config
    $age = (Get-Date) - $script:cacheTime
    if (-not $force -and $script:cache -and $age.TotalMinutes -lt $cfg.noticias_intervalo_min) { return $script:cache }
    $script:cache     = Build-Report
    $script:cacheTime = Get-Date
    return $script:cache
}

# ---- Monitor de salud de servicios (tipo Downdetector, mediante comprobacion HTTP) ----
$script:healthHist  = @{}
$script:healthCache = $null
$script:healthTime  = [datetime]::MinValue

# La comprobacion de salud la hace monitor.ps1 en segundo plano y escribe health.json.
# Aqui solo se lee ese fichero; "Comprobar ahora" deja un flag que monitor.ps1 atiende.
function Get-HealthJson {
    $p = Join-Path $root 'health_monitor.json'
    if (Test-Path -LiteralPath $p) {
        try { return [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) } catch {}
    }
    return '{"enabled":false,"generated":"","intervalSeg":0,"services":[]}'
}

function Send-Bytes($res, [byte[]]$bytes, [string]$type, [int]$status = 200) {
    $res.StatusCode = $status
    $res.ContentType = $type
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
}

$mime = @{
    '.html' = 'text/html; charset=utf-8'; '.js' = 'application/javascript; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8';  '.json' = 'application/json; charset=utf-8'
    '.svg'  = 'image/svg+xml'
}
$jsonType = 'application/json; charset=utf-8'


# ---- Estado de ATALAYA y estadisticas (sistema + analisis) ----
function Get-EstadoJson {
    $now = Get-Date
    $hp = Join-Path $root 'health_monitor.json'
    $h = $null
    if (Test-Path -LiteralPath $hp) { try { $h = Get-Content -Raw -LiteralPath $hp -Encoding UTF8 | ConvertFrom-Json } catch {} }
    $gen = $null
    if ($h) { $gen = [datetime]::MinValue; [void][datetime]::TryParseExact([string]$h.generated, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$gen) }
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'monitor\.ps1' }).Count
    $archP = Join-Path $root 'archivo.jsonl'
    $histP = Join-Path $root 'historico.txt'
    $archLines = @(); if (Test-Path -LiteralPath $archP) { $archLines = [IO.File]::ReadAllLines($archP, [Text.Encoding]::UTF8) }
    $histLines = @(); if (Test-Path -LiteralPath $histP) { $histLines = @(Get-Content -LiteralPath $histP -Encoding UTF8 -Tail 40000) }
    $tam = 0; if (Test-Path -LiteralPath $histP) { $tam = [Math]::Round((Get-Item -LiteralPath $histP).Length / 1MB, 2) }

    # comprobaciones de las ultimas 24 h y por hora
    $porHora = @(0..23 | ForEach-Object { 0 })
    $porHoraCaida = @(0..23 | ForEach-Object { 0 })
    $est24 = @{}
    $cut24 = $now.AddHours(-24)
    foreach ($ln in $histLines) {
        $f = $ln -split "`t"; if ($f.Count -lt 4) { continue }
        $dt = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($f[0], 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$dt)) { continue }
        if ($dt -lt $cut24) { continue }
        $hr = $dt.Hour
        $porHora[$hr]++
        $st = $f[2]; if (-not $est24.ContainsKey($st)) { $est24[$st] = 0 }; $est24[$st]++
        if ($st -eq 'CAIDA' -or $st -eq 'SIN RESPUESTA') { $porHoraCaida[$hr]++ }
    }

    # servicios (estado actual, disponibilidad e incidencias)
    $svcs = @()
    if ($h -and $h.services) {
        foreach ($s in $h.services) {
            $inc = @($s.incidents).Count
            $svcs += [pscustomobject]@{ name = $s.name; status = $s.status; d1 = $s.uptime.d1; d7 = $s.uptime.d7; d30 = $s.uptime.d30; incidencias30 = $inc; avgMs = $s.avgMs }
        }
    }

    # analisis del archivo de noticias (cada linea = una noticia guardada)
    $porFuente = @{}; $porTema = @{}; $porSev = @{ Critica = 0; Grave = 0; Media = 0; Baja = 0; Info = 0 }; $porMes = @{}
    $topicsList = @(Get-Topics)
    foreach ($ln in $archLines) {
        try { $o = $ln | ConvertFrom-Json } catch { continue }
        $src = [string]$o.source; if (-not $porFuente.ContainsKey($src)) { $porFuente[$src] = 0 }; $porFuente[$src]++
        $title = [string]$o.title
        $sev = (Get-Severity $title ($title + ' ' + [string]$o.context))[0]
        if ($porSev.ContainsKey($sev)) { $porSev[$sev]++ }
        foreach ($tp in $topicsList) { if ($title -match ('(?i)(?<![A-Za-z])' + [regex]::Escape($tp) + '(?![A-Za-z])')) { if (-not $porTema.ContainsKey($tp)) { $porTema[$tp] = 0 }; $porTema[$tp]++ } }
        $mes = ([string]$o.date).Substring(0, [Math]::Min(7, ([string]$o.date).Length)); if ($mes) { if (-not $porMes.ContainsKey($mes)) { $porMes[$mes] = 0 }; $porMes[$mes]++ }
    }

    # noticias actuales (ultimo informe persistido en disco)
    $rep = Get-CacheReport
    $fuentesOk = @(); if ($rep) { foreach ($f in $rep.sources) { $fuentesOk += [pscustomobject]@{ name = $f.name; ok = [bool]$f.ok; total = $f.total } } }

    return [pscustomobject]@{
        sistema = [pscustomobject]@{
            puerto = [string]$script:port
            monitorGenerado = if ($gen) { $gen.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
            monitorIntervaloSeg = if ($h) { [int]$h.intervalSeg } else { 0 }
            monitorProcesos = $procs
            monitorMantenimiento = if ($h) { [bool]$h.maintenance } else { $false }
            archivoNoticias = $archLines.Count
            historicoLineas = $histLines.Count
            historicoMB = $tam
        }
        analisis = [pscustomobject]@{
            servicios = $svcs
            comprobaciones24h = @($est24.GetEnumerator() | ForEach-Object { [pscustomobject]@{ estado = $_.Key; n = $_.Value } })
            porHora = $porHora
            porHoraCaida = $porHoraCaida
            archivoPorSeveridad = $porSev
            archivoPorFuente = @($porFuente.GetEnumerator() | ForEach-Object { [pscustomobject]@{ fuente = $_.Key; n = $_.Value } })
            archivoPorTema = @($porTema.GetEnumerator() | ForEach-Object { [pscustomobject]@{ tema = $_.Key; n = $_.Value } })
            archivoPorMes = @($porMes.GetEnumerator() | Sort-Object Key | ForEach-Object { [pscustomobject]@{ mes = $_.Key; n = $_.Value } })
            fuentesActuales = $fuentesOk
            noticiasActuales = if ($rep) { [int]$rep.total } else { 0 }
        }
    }
}

# PLUGIN: Encriptacion basica de passwords (base64 + HEX)
function Encrypt-Password([string]$pwd) {
    if ([string]::IsNullOrWhiteSpace($pwd)) { return '' }
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pwd))
    $hex = -join ($b64.ToCharArray() | ForEach-Object { [string]::Format('{0:X2}', [int][char]$_) })
    return $hex
}

function Decrypt-Password([string]$hex) {
    if ([string]::IsNullOrWhiteSpace($hex)) { return '' }
    try {
        $bytes = @()
        for ($i = 0; $i -lt $hex.Length; $i += 2) {
            $bytes += [byte][Convert]::ToInt32($hex.Substring($i, 2), 16)
        }
        $b64 = [System.Text.Encoding]::UTF8.GetString($bytes)
        return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
    } catch { return '' }
}

# PLUGIN: Enviar notificacion por correo de eventos (servicios/noticias)
function Trigger-EventNotification([pscustomobject]$evento) {
    try {
        # Leer configuracion de notificaciones desde archivo separado
        $notifCfg = @{}
        $notifFile = Join-Path $root 'notificaciones_config.txt'
        if (Test-Path -LiteralPath $notifFile -PathType Leaf) {
            $lines = @(Get-Content -LiteralPath $notifFile -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') })
            foreach ($ln in $lines) {
                $kv = $ln -split '=', 2
                if ($kv.Count -eq 2) { $notifCfg[$kv[0].Trim()] = $kv[1].Trim() }
            }
        }

        # Si las notificaciones no estan habilitadas, retornar silenciosamente
        if ([string]$notifCfg['notif_habilitado'] -ne '1') { return }

        $destino = [string]$notifCfg['notif_destino']
        $asunto = [string]$notifCfg['notif_asunto']
        if ([string]::IsNullOrWhiteSpace($asunto)) { $asunto = "ATALAYA: Alerta de seguridad" }

        if ([string]::IsNullOrWhiteSpace($destino)) { return }

        $tipo = [string]$evento.type
        $titulo = [string]$evento.title
        $desc = [string]$evento.description
        $ahora = Get-Date

        # Construir cuerpo del email segun el tipo de evento
        switch ($tipo) {
            'service_down' {
                $cuerpo = @"
ALERTA: SERVICIO CAIDO
Fecha: $ahora

Servicio: $titulo
Detalles: $desc

Revisar el panel: http://localhost:8080/
"@
                $asunto = "ATALAYA: ALERTA - Servicio caido ($titulo)"
            }
            'service_up' {
                $cuerpo = @"
NOTIFICACION: SERVICIO RECUPERADO
Fecha: $ahora

Servicio: $titulo
Detalles: $desc

Revisar el panel: http://localhost:8080/
"@
                $asunto = "ATALAYA: INFO - Servicio recuperado ($titulo)"
            }
            'news' {
                $cantidad = [string]$evento.count
                $titulos = $evento.titles -join "`r`n  "
                $cuerpo = @"
ALERTA: NOTICIAS NUEVAS
Fecha: $ahora

Se han detectado $cantidad noticia(s) nueva(s):

  $titulos

Revisar el panel: http://localhost:8080/
"@
                $asunto = "ATALAYA: $cantidad noticia(s) nueva(s)"
            }
            default { return }
        }

        # Intentar enviar el correo
        try {
            $tipoSrv = [string]$notifCfg['notif_tipo']
            switch ($tipoSrv) {
                'gmail' {
                    $user = [string]$notifCfg['notif_gmail_usuario']
                    $pass = Decrypt-Password([string]$notifCfg['notif_gmail_password'])
                    if (-not [string]::IsNullOrWhiteSpace($user) -and -not [string]::IsNullOrWhiteSpace($pass)) {
                        $cred = New-Object System.Management.Automation.PSCredential($user, (ConvertTo-SecureString $pass -AsPlainText -Force))
                        Send-MailMessage -SmtpServer 'smtp.gmail.com' -Port 587 -UseSsl -Credential $cred -From $user -To $destino -Subject $asunto -Body $cuerpo -Encoding UTF8 -ErrorAction Stop
                    }
                }
                'outlook' {
                    $user = [string]$notifCfg['notif_outlook_usuario']
                    $pass = Decrypt-Password([string]$notifCfg['notif_outlook_password'])
                    if (-not [string]::IsNullOrWhiteSpace($user) -and -not [string]::IsNullOrWhiteSpace($pass)) {
                        $cred = New-Object System.Management.Automation.PSCredential($user, (ConvertTo-SecureString $pass -AsPlainText -Force))
                        Send-MailMessage -SmtpServer 'smtp-mail.outlook.com' -Port 587 -UseSsl -Credential $cred -From $user -To $destino -Subject $asunto -Body $cuerpo -Encoding UTF8 -ErrorAction Stop
                    }
                }
                'smtp' {
                    $srv = [string]$notifCfg['notif_smtp_servidor']
                    $pue = 587; if ($notifCfg['notif_smtp_puerto']) { $pue = [int]$notifCfg['notif_smtp_puerto'] }
                    $rem = [string]$notifCfg['notif_smtp_remitente']
                    $ssl = $notifCfg['notif_smtp_ssl'] -eq '1'
                    if (-not [string]::IsNullOrWhiteSpace($srv) -and -not [string]::IsNullOrWhiteSpace($rem)) {
                        $params = @{SmtpServer = $srv; Port = $pue; UseSsl = $ssl; From = $rem; To = $destino; Subject = $asunto; Body = $cuerpo; Encoding = [Text.Encoding]::UTF8; ErrorAction = 'Stop'}
                        $user = [string]$notifCfg['notif_smtp_usuario']
                        $pass = Decrypt-Password([string]$notifCfg['notif_smtp_password'])
                        if (-not [string]::IsNullOrWhiteSpace($user) -and -not [string]::IsNullOrWhiteSpace($pass)) {
                            $cred = New-Object System.Management.Automation.PSCredential($user, (ConvertTo-SecureString $pass -AsPlainText -Force))
                            $params.Credential = $cred
                        }
                        Send-MailMessage @params
                    }
                }
            }
        } catch {
            # Loguear error en archivo de log
            [void](Add-Content (Join-Path $root 'notificaciones_error.log') "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Evento $tipo - $_" -ErrorAction SilentlyContinue)
        }
    } catch {
        # Error silencioso para no afectar el flujo principal
    }
}

# PLUGIN: Leer configuracion de notificaciones desde archivo separado
function Get-NotificacionesConfig {
    $cfg = @{
        notif_habilitado = '0'
        notif_tipo = ''
        notif_asunto = 'ATALAYA: Alerta de seguridad'
        notif_destino = ''
        notif_gmail_usuario = ''
        notif_gmail_password = ''
        notif_outlook_usuario = ''
        notif_outlook_password = ''
        notif_smtp_servidor = ''
        notif_smtp_puerto = '587'
        notif_smtp_usuario = ''
        notif_smtp_password = ''
        notif_smtp_remitente = ''
        notif_smtp_ssl = '1'
    }

    $notifFile = Join-Path $root 'notificaciones_config.txt'
    if (Test-Path -LiteralPath $notifFile -PathType Leaf) {
        $lines = @(Get-Content -LiteralPath $notifFile -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') })
        foreach ($ln in $lines) {
            $kv = $ln -split '=', 2
            if ($kv.Count -eq 2) { $cfg[$kv[0].Trim()] = $kv[1].Trim() }
        }
    }
    return $cfg
}

# PLUGIN: Integración con notificaciones por correo
function Trigger-NewsNotifications([pscustomobject]$report) {
    try {
        # Leer configuracion de notificaciones desde archivo separado
        $notifCfg = @{}
        $notifFile = Join-Path $root 'notificaciones_config.txt'
        if (Test-Path -LiteralPath $notifFile -PathType Leaf) {
            $lines = @(Get-Content -LiteralPath $notifFile -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') })
            foreach ($ln in $lines) {
                $kv = $ln -split '=', 2
                if ($kv.Count -eq 2) { $notifCfg[$kv[0].Trim()] = $kv[1].Trim() }
            }
        }
        # Si las notificaciones no estan habilitadas, retornar silenciosamente
        if ([string]$notifCfg['notif_habilitado'] -ne '1') { return }

        # Buscar las noticias criticas y graves
        $alertas = @($report.items | Where-Object { @('Critica','Grave') -contains $_.severity })
        if ($alertas.Count -eq 0) { return }

        # Si no hay configuracion de destino, retornar
        $destino = [string]$notifCfg['notif_destino']
        if ([string]::IsNullOrWhiteSpace($destino)) { return }

        # Leer timestamp de ultimo envio
        $timestampFile = Join-Path $root 'notif_ultimoenvio.txt'
        $ahora = Get-Date
        $debeEnviar = $true

        if (Test-Path -LiteralPath $timestampFile -PathType Leaf) {
            try {
                $ultima = Get-Content -LiteralPath $timestampFile -Encoding UTF8 | Select-Object -First 1
                if ([datetime]::TryParse($ultima, [ref]$null)) {
                    $ultima = [datetime]::Parse($ultima)
                    # Solo enviar si ha pasado al menos 1 hora desde el ultimo envio
                    if (($ahora - $ultima).TotalMinutes -lt 60) { $debeEnviar = $false }
                }
            } catch { }
        }

        if (-not $debeEnviar) { return }

        # Enviar notificacion consolidada con las alertas criticas/graves
        $asunto = [string]$notifCfg['notif_asunto']
        if ([string]::IsNullOrWhiteSpace($asunto)) { $asunto = "ATALAYA: Alerta de seguridad" }

        $cuerpo = "ALERTA DE SEGURIDAD - ATALAYA`r`n`r`n"
        $cuerpo += "Se han detectado $($alertas.Count) noticias criticas o graves:`r`n`r`n"

        foreach ($alerta in $alertas | Select-Object -First 10) {
            $titulo = [string]$alerta.titulo
            $sev = [string]$alerta.severity
            $fecha = [string]$alerta.fecha
            $cves = if ($alerta.cves -and $alerta.cves.Count -gt 0) { $alerta.cves -join ", " } else { "-" }

            $cuerpo += "[$sev] $titulo`r`n"
            $cuerpo += "  Fecha: $fecha`r`n"
            $cuerpo += "  CVE: $cves`r`n"
            $cuerpo += "  Fuentes: " + (@($alerta.fuentes | Select-Object -First 2) -join ", ") + "`r`n`r`n"
        }

        $cuerpo += "Revisar el panel: http://localhost:8080/`r`n"

        # Intentar enviar el correo
        try {
            $tipo = [string]$notifCfg['notif_tipo']
            switch ($tipo) {
                'gmail' {
                    $user = [string]$notifCfg['notif_gmail_usuario']
                    $pass = Decrypt-Password([string]$notifCfg['notif_gmail_password'])
                    if (-not [string]::IsNullOrWhiteSpace($user) -and -not [string]::IsNullOrWhiteSpace($pass)) {
                        $cred = New-Object System.Management.Automation.PSCredential($user, (ConvertTo-SecureString $pass -AsPlainText -Force))
                        Send-MailMessage -SmtpServer 'smtp.gmail.com' -Port 587 -UseSsl -Credential $cred -From $user -To $destino -Subject $asunto -Body $cuerpo -Encoding UTF8 -ErrorAction Stop
                    }
                }
                'outlook' {
                    $user = [string]$notifCfg['notif_outlook_usuario']
                    $pass = Decrypt-Password([string]$notifCfg['notif_outlook_password'])
                    if (-not [string]::IsNullOrWhiteSpace($user) -and -not [string]::IsNullOrWhiteSpace($pass)) {
                        $cred = New-Object System.Management.Automation.PSCredential($user, (ConvertTo-SecureString $pass -AsPlainText -Force))
                        Send-MailMessage -SmtpServer 'smtp-mail.outlook.com' -Port 587 -UseSsl -Credential $cred -From $user -To $destino -Subject $asunto -Body $cuerpo -Encoding UTF8 -ErrorAction Stop
                    }
                }
                'smtp' {
                    $srv = [string]$notifCfg['notif_smtp_servidor']
                    $pue = 587; if ($notifCfg['notif_smtp_puerto']) { $pue = [int]$notifCfg['notif_smtp_puerto'] }
                    $rem = [string]$notifCfg['notif_smtp_remitente']
                    $ssl = $notifCfg['notif_smtp_ssl'] -eq '1'
                    if (-not [string]::IsNullOrWhiteSpace($srv) -and -not [string]::IsNullOrWhiteSpace($rem)) {
                        $params = @{SmtpServer = $srv; Port = $pue; UseSsl = $ssl; From = $rem; To = $destino; Subject = $asunto; Body = $cuerpo; Encoding = [Text.Encoding]::UTF8; ErrorAction = 'Stop'}
                        $user = [string]$notifCfg['notif_smtp_usuario']
                        $pass = Decrypt-Password([string]$notifCfg['notif_smtp_password'])
                        if (-not [string]::IsNullOrWhiteSpace($user) -and -not [string]::IsNullOrWhiteSpace($pass)) {
                            $cred = New-Object System.Management.Automation.PSCredential($user, (ConvertTo-SecureString $pass -AsPlainText -Force))
                            $params.Credential = $cred
                        }
                        Send-MailMessage @params
                    }
                }
            }
            # Actualizar timestamp de ultimo envio
            Set-Content -LiteralPath $timestampFile -Value $ahora.ToString('yyyy-MM-dd HH:mm:ss') -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch {
            # Loguear error en archivo de log
            [void](Add-Content (Join-Path $root 'notificaciones_error.log') "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $_" -ErrorAction SilentlyContinue)
        }
    } catch {
        # Error silencioso para no afectar el flujo principal
    }
}
