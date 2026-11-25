# Plugin de notificaciones por correo electronico
# Bajo acoplamiento: si falla, no afecta al programa principal
# Las funciones estan envueltas en try-catch

function Send-EmailNotification {
    param(
        [hashtable]$config,
        [hashtable]$noticia
    )

    # Si las notificaciones no estan habilitadas, retornar silenciosamente
    if ([string]$config.notif_habilitado -ne '1') { return }

    try {
        $tipo = [string]$config.notif_tipo
        if ([string]::IsNullOrWhiteSpace($tipo)) { return }

        $asunto = [string]$config.notif_asunto
        if ([string]::IsNullOrWhiteSpace($asunto)) { $asunto = "ATALAYA: Alerta de seguridad" }

        $destino = [string]$config.notif_destino
        if ([string]::IsNullOrWhiteSpace($destino)) { return }

        # Construir el cuerpo del email
        $titulo = [string]$noticia.titulo
        $criticidad = [string]$noticia.severidad
        $fecha = [string]$noticia.fecha
        $fuentes = $noticia.fuentes -join "`r`n  "
        $cve = if ($noticia.cves -and $noticia.cves.Count -gt 0) { $noticia.cves -join ", " } else { "Sin asignar" }
        $afecta = [string]$noticia.afecta
        $descripcion = [string]$noticia.descripcion

        # Limitar descripcion a 500 caracteres
        if ($descripcion.Length -gt 500) {
            $descripcion = $descripcion.Substring(0, 497) + "..."
        }

        $cuerpo = @"
ALERTA DE SEGURIDAD - ATALAYA

TITULO: $titulo

CRITICIDAD: $criticidad
FECHA: $fecha

FUENTES:
  $fuentes

CVE: $cve

A QUIEN AFECTA:
$afecta

DESCRIPCION:
$descripcion
"@

        # Enviar segun el tipo
        switch ($tipo) {
            'gmail' { Send-GmailNotification $config $destino $asunto $cuerpo }
            'outlook' { Send-OutlookNotification $config $destino $asunto $cuerpo }
            'smtp' { Send-SmtpNotification $config $destino $asunto $cuerpo }
            default { }
        }
    } catch {
        # Loguear error pero no fallar
        [void](Add-Content (Join-Path $root 'notificaciones_error.log') "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $_")
    }
}

function Send-GmailNotification {
    param([hashtable]$cfg, [string]$to, [string]$subj, [string]$body)

    $user = [string]$cfg.notif_gmail_usuario
    $pass = [string]$cfg.notif_gmail_password

    if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($pass)) { return }

    try {
        $cred = New-Object System.Management.Automation.PSCredential($user, (ConvertTo-SecureString $pass -AsPlainText -Force))

        $params = @{
            SmtpServer = 'smtp.gmail.com'
            Port = 587
            UseSsl = $true
            Credential = $cred
            From = $user
            To = $to
            Subject = $subj
            Body = $body
            Encoding = [Text.Encoding]::UTF8
        }

        Send-MailMessage @params
    } catch {
        throw "Gmail: $_"
    }
}

function Send-OutlookNotification {
    param([hashtable]$cfg, [string]$to, [string]$subj, [string]$body)

    $user = [string]$cfg.notif_outlook_usuario
    $pass = [string]$cfg.notif_outlook_password

    if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($pass)) { return }

    try {
        $cred = New-Object System.Management.Automation.PSCredential($user, (ConvertTo-SecureString $pass -AsPlainText -Force))

        $params = @{
            SmtpServer = 'smtp-mail.outlook.com'
            Port = 587
            UseSsl = $true
            Credential = $cred
            From = $user
            To = $to
            Subject = $subj
            Body = $body
            Encoding = [Text.Encoding]::UTF8
        }

        Send-MailMessage @params
    } catch {
        throw "Outlook: $_"
    }
}

function Send-SmtpNotification {
    param([hashtable]$cfg, [string]$to, [string]$subj, [string]$body)

    $servidor = [string]$cfg.notif_smtp_servidor
    $puerto = [int]$cfg.notif_smtp_puerto
    $user = [string]$cfg.notif_smtp_usuario
    $pass = [string]$cfg.notif_smtp_password
    $ssl = $cfg.notif_smtp_ssl -eq '1'
    $from = [string]$cfg.notif_smtp_remitente

    if ([string]::IsNullOrWhiteSpace($servidor) -or $puerto -le 0 -or [string]::IsNullOrWhiteSpace($from)) { return }

    try {
        $params = @{
            SmtpServer = $servidor
            Port = $puerto
            UseSsl = $ssl
            From = $from
            To = $to
            Subject = $subj
            Body = $body
            Encoding = [Text.Encoding]::UTF8
        }

        if (-not [string]::IsNullOrWhiteSpace($user) -and -not [string]::IsNullOrWhiteSpace($pass)) {
            $cred = New-Object System.Management.Automation.PSCredential($user, (ConvertTo-SecureString $pass -AsPlainText -Force))
            $params.Credential = $cred
        }

        Send-MailMessage @params
    } catch {
        throw "SMTP ($servidor): $_"
    }
}

# Exportar funcion publica
Export-ModuleMember -Function Send-EmailNotification
