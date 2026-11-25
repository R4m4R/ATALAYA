# Plugin de Notificaciones por Correo - ATALAYA

## Descripción
Sistema modular de alertas por correo electrónico para noticias críticas y graves. Funciona de forma independiente: si falla, no afecta al programa principal.

## Características
- ✅ Tres tipos de servidor soportados: **Gmail**, **Outlook**, **SMTP genérico** (Zimbra, Postfix, etc.)
- ✅ Límite de frecuencia: máximo 1 email por hora (evita spam)
- ✅ Notificaciones consolidadas: agrupa varias alertas en un solo email
- ✅ Envío en background: no bloquea el panel
- ✅ Fácil de desactivar: un checkbox en Ajustes

## Configuración

### 1. Acceder a Ajustes
Haz clic en el botón ⚙️ (Ajustes) en la cabecera.

### 2. Ir a la pestaña "Notificaciones"

### 3. Marcar "Activar notificaciones por correo electrónico"

### 4. Elegir tipo de servidor y configurar

#### **Gmail**
1. Selecciona "Gmail" en "Tipo de servidor"
2. Introduzca tu email de Gmail en "Usuario"
3. En "Contraseña", usa una **[contraseña de aplicación](https://support.google.com/accounts/answer/185833)** (NO tu contraseña normal)
   - En tu cuenta Google, ve a **Seguridad** → **Contraseñas de aplicación**
   - Genera una para "Correo" / "Windows"

#### **Outlook**
1. Selecciona "Outlook"
2. Introduce tu email de Outlook
3. Introduce tu contraseña de Outlook (o contraseña de aplicación si tienes 2FA)

#### **SMTP Genérico** (Zimbra, Postfix, etc.)
1. Selecciona "SMTP generico"
2. Rellena:
   - **Servidor**: mail.tudominio.com (o IP)
   - **Puerto**: 587 (o 25, 465 según tu servidor)
   - **Usuario**: tu_usuario (opcional si tu servidor no requiere autenticación)
   - **Contraseña**: tu_contraseña (opcional)
   - **Email remitente**: quien_envia@tudominio.com
   - **Usar SSL/TLS**: normalmente Sí (587 usa TLS; 465 usa SSL; 25 sin cifrado)

### 5. Rellenar datos básicos
- **Destinatario**: email donde quieres recibir las alertas
- **Asunto**: texto que saldrá en el asunto del email (ej. "ATALAYA: Alerta de seguridad")

### 6. Guardar
Haz clic en "Guardar y buscar" para aplicar.

## Qué recibir en el email
Cuando hay noticias críticas o graves, recibirás un email consolidado con:
- Título de la noticia
- Criticidad (Crítica/Grave)
- Fecha
- CVE asociados
- Fuentes (enlaces)
- Descripción breve

Máximo: 10 noticias por email, 1 email por hora.

## Cómo funciona

| Evento | Acción |
|--------|--------|
| Marcar "Activar" + configurar servidor | Notificaciones habilitadas |
| Llegar noticia Crítica/Grave | Se intenta enviar email (si ha pasado 1+ hora desde el último) |
| Email falla | Se registra en `notificaciones_error.log`, programa continúa sin interrupción |
| Desmarcar "Activar" | Se desactivan completamente, sin envíos |

## Archivos del plugin
- `notificaciones.ps1` → Funciones de envío (no se usa directamente, solo documentación)
- `config.txt` → Parámetros guardados (líneas `notif_*`)
- `notif_ultimoenvio.txt` → Timestamp del último email enviado (creado automáticamente)
- `notificaciones_error.log` → Registro de errores (si los hay)

## Troubleshooting

### "No recibo emails"
1. **Gmail**: ¿Usaste contraseña de aplicación? (NO contraseña normal)
2. **Outlook**: ¿La contraseña es correcta? ¿Tienes 2FA habilitado?
3. **SMTP genérico**: ¿Puerto correcto? ¿Servidor accesible? Prueba ping al servidor.
4. Ver `notificaciones_error.log` para detalles del error
5. Revisa carpeta Spam/Correo no deseado

### "Envía demasiados emails"
- Límite: máximo 1 email por hora
- Espera 60 minutos entre updates
- O desactiva temporalmente en Ajustes

### "¿Se guarda mi contraseña?"
Sí, en `config.txt`. Se recomienda:
- Usar contraseñas de aplicación (no contraseñas principales)
- Si tu servidor lo soporta, usar autenticación sin contraseña (OAuth, tokens, etc.)

## Desactivar el plugin
Es completamente reversible:
1. Ve a Ajustes → Notificaciones
2. Desmarca "Activar notificaciones por correo electrónico"
3. Guarda

El plugin no dejará rastros ni afectará nada si está desactivado.

---

**Versión**: 1.0 | **Fecha**: Noviembre 2026
