# Servidor e Infraestructura — Hardening y Configuración Segura

---

## Hardening inicial de un servidor Linux (Ubuntu/Debian)

### 1. Actualizar el sistema inmediatamente

```bash
apt update && apt upgrade -y

# Actualizaciones de seguridad automáticas
apt install -y unattended-upgrades
dpkg-reconfigure --priority=low unattended-upgrades

# /etc/apt/apt.conf.d/50unattended-upgrades
# Verificar que está activo:
cat /etc/apt/apt.conf.d/20auto-upgrades
# Debe mostrar:
# APT::Periodic::Update-Package-Lists "1";
# APT::Periodic::Unattended-Upgrade "1";
```

### 2. Crear usuario no-root para la aplicación

```bash
# Nunca correr la aplicación como root
adduser --system --group --no-create-home appuser

# La aplicación corre como appuser, no como root
# En el servicio systemd:
# User=appuser
# Group=appuser
```

### 3. Configurar SSH seguro

```bash
# /etc/ssh/sshd_config

# Desactivar login con password — solo llaves
PasswordAuthentication no
ChallengeResponseAuthentication no

# Desactivar login como root por SSH
PermitRootLogin no

# Solo usuarios explícitamente permitidos
AllowUsers tu_usuario

# Puerto no estándar — oscuridad mínima, no seguridad real
# Pero reduce el ruido de bots en los logs
Port 2222

# Desactivar X11 forwarding innecesario
X11Forwarding no

# Tiempo máximo de autenticación
LoginGraceTime 30

# Máximo de intentos de auth por conexión
MaxAuthTries 3

# Desactivar protocolos obsoletos
Protocol 2
```

```bash
# Aplicar cambios
systemctl restart sshd

# Generar par de llaves en tu máquina local (no en el servidor)
ssh-keygen -t ed25519 -C "tu@email.com" -f ~/.ssh/servidor_prod

# Copiar llave pública al servidor
ssh-copy-id -i ~/.ssh/servidor_prod.pub usuario@ip_servidor

# Verificar que puedes conectarte con llave ANTES de desactivar passwords
ssh -i ~/.ssh/servidor_prod usuario@ip_servidor
```

### 4. Firewall con UFW

```bash
# Instalar y configurar UFW (Uncomplicated Firewall)
apt install -y ufw

# Política por defecto: denegar todo lo entrante, permitir todo lo saliente
ufw default deny incoming
ufw default allow outgoing

# Solo abrir los puertos necesarios
ufw allow 443/tcp     # HTTPS
ufw allow 80/tcp      # HTTP (para redirect a HTTPS y Let's Encrypt)
ufw allow 2222/tcp    # SSH (el puerto que configuraste)

# Si la DB está en servidor separado: abrir solo para la IP del servidor de la app
# ufw allow from 10.0.1.100 to any port 5432  # PostgreSQL
# ufw allow from 10.0.1.100 to any port 6379  # Redis

# Activar
ufw enable

# Verificar estado
ufw status verbose
```

### 5. Fail2ban — bloqueo automático de IPs maliciosas

```bash
apt install -y fail2ban

# /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 3600     # Bloquear por 1 hora
findtime = 600      # Ventana de 10 minutos
maxretry = 5        # Máximo 5 intentos fallidos

[sshd]
enabled = true
port    = 2222      # Puerto SSH personalizado
logpath = %(sshd_log)s

[nginx-http-auth]
enabled = true

# Si tienes tu propia app NestJS, crear jail personalizado
[nestjs-auth]
enabled  = true
filter   = nestjs-auth
logpath  = /var/log/nestjs/app.log
maxretry = 5
bantime  = 900      # 15 minutos por intentos de auth fallidos
```

---

## HTTPS con Nginx y Let's Encrypt

### Instalación

```bash
apt install -y nginx certbot python3-certbot-nginx

# Obtener certificado SSL gratuito
certbot --nginx -d tudominio.com -d www.tudominio.com

# Renovación automática — certbot instala cron automáticamente
# Verificar:
certbot renew --dry-run
```

### Configuración Nginx — hardening completo

```nginx
# /etc/nginx/sites-available/myapp

# Redirigir HTTP a HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name tudominio.com www.tudominio.com;

    # Solo para renovación de Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name tudominio.com www.tudominio.com;

    # Certificados SSL (gestionados por certbot)
    ssl_certificate /etc/letsencrypt/live/tudominio.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/tudominio.com/privkey.pem;

    # TLS moderno — desactivar versiones obsoletas
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS — fuerza HTTPS por 1 año
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # OCSP Stapling — mejora performance de validación del certificado
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/tudominio.com/chain.pem;

    # Tamaño máximo de body — previene DoS por uploads masivos
    client_max_body_size 10M;

    # Ocultar versión de Nginx
    server_tokens off;

    # Proxy al frontend (Next.js)
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 60s;
    }

    # Proxy al backend (NestJS)
    location /api/ {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 30s;

        # Rate limiting a nivel de Nginx — primera línea antes de llegar a NestJS
        limit_req zone=api burst=20 nodelay;
    }

    # Bloquear acceso a archivos sensibles
    location ~ /\. { deny all; }
    location ~ ~$  { deny all; }
}

# Zona de rate limiting — definir en nginx.conf
# http {
#   limit_req_zone $binary_remote_addr zone=api:10m rate=30r/m;
# }
```

```bash
# Verificar configuración y activar
nginx -t
ln -s /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/
systemctl reload nginx

# Verificar que el certificado es válido
curl -I https://tudominio.com
# Debe mostrar: HTTP/2 200 y los headers de seguridad
```

---

## Correr la aplicación como servicio systemd

```ini
# /etc/systemd/system/nestjs-api.service

[Unit]
Description=NestJS API
After=network.target postgresql.service redis.service
Requires=postgresql.service redis.service

[Service]
Type=simple
User=appuser                    # ← Usuario sin privilegios
Group=appuser
WorkingDirectory=/apps/api

# Cargar variables de entorno desde archivo seguro
EnvironmentFile=/apps/api/.env

# Nunca como root
NoNewPrivileges=true

# Restringir acceso al sistema de archivos
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/apps/api/logs   # Solo puede escribir en logs

# Limitar llamadas al sistema (hardening avanzado)
PrivateTmp=true
PrivateDevices=true

ExecStart=/usr/bin/node dist/main.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nestjs-api

[Install]
WantedBy=multi-user.target
```

```bash
# Activar y arrancar el servicio
systemctl daemon-reload
systemctl enable nestjs-api
systemctl start nestjs-api
systemctl status nestjs-api

# Ver logs en tiempo real
journalctl -u nestjs-api -f
```

---

## Monitoreo y alertas

### Logs estructurados en NestJS con Pino

```typescript
// pnpm add nestjs-pino pino-http
// main.ts
import { Logger } from "nestjs-pino";

app.useLogger(app.get(Logger));
```

```typescript
// app.module.ts
import { LoggerModule } from "nestjs-pino";

@Module({
  imports: [
    LoggerModule.forRoot({
      pinoHttp: {
        level: process.env.NODE_ENV === "production" ? "info" : "debug",
        // En producción: JSON estructurado para parsear con herramientas
        transport:
          process.env.NODE_ENV !== "production"
            ? { target: "pino-pretty" } // Legible en desarrollo
            : undefined,
        // Correlation ID por request
        genReqId: (req) => req.headers["x-request-id"] ?? randomUUID(),
        // No loguear datos sensibles
        redact: ["req.headers.authorization", "req.body.password"],
        // Loguear todas las requests con su duración
        autoLogging: true,
      },
    }),
  ],
})
export class AppModule {}
```

### Qué monitorear

```bash
# CPU, memoria, disco
apt install -y htop

# Conexiones de red activas
ss -tulpn

# Procesos escuchando en puertos
netstat -tlnp

# Intentos de login fallidos SSH
journalctl -u ssh | grep "Failed"

# IPs bloqueadas por fail2ban
fail2ban-client status sshd

# Logs de Nginx
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log

# Estado de la aplicación
systemctl status nestjs-api
journalctl -u nestjs-api --since "1 hour ago"
```

### Health check endpoint

```typescript
// modules/health/health.controller.ts
import { Controller, Get } from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service";
import { RedisService } from "../redis/redis.service";

@Controller("health")
export class HealthController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  @Get()
  async check() {
    const checks = await Promise.allSettled([
      this.prisma.$queryRaw`SELECT 1`,
      this.redis.get("health:ping"),
    ]);

    const [db, cache] = checks;

    return {
      status: checks.every((c) => c.status === "fulfilled") ? "ok" : "degraded",
      database: db.status === "fulfilled" ? "ok" : "error",
      cache: cache.status === "fulfilled" ? "ok" : "error",
      timestamp: new Date().toISOString(),
    };
  }
}
```

---

## Audit de seguridad — comandos de diagnóstico rápido

```bash
# Ver todos los puertos abiertos al exterior
ss -tulpn | grep LISTEN

# Verificar que PostgreSQL no está expuesto a internet
ss -tulpn | grep 5432
# Debe mostrar 127.0.0.1:5432, nunca 0.0.0.0:5432

# Verificar que Redis no está expuesto
ss -tulpn | grep 6379
# Debe mostrar 127.0.0.1:6379

# Verificar headers de seguridad de tu dominio
curl -I https://tudominio.com

# Test de configuración TLS
openssl s_client -connect tudominio.com:443 -tls1_1
# Debe fallar si desactivaste TLS 1.1

# Verificar certificado
openssl s_client -connect tudominio.com:443 | openssl x509 -noout -dates

# Escanear vulnerabilidades conocidas en dependencias
pnpm audit --audit-level=high

# Verificar permisos de archivos sensibles
ls -la /apps/api/.env
# Debe ser: -rw------- (solo el owner puede leer/escribir)
chmod 600 /apps/api/.env

# Buscar archivos con permisos excesivos
find /apps -name "*.env" -perm /o+r
# No debe retornar nada — los .env no deben ser legibles por otros

# Ver usuarios del sistema con shell
grep -v nologin /etc/passwd | grep -v false
```

### Herramientas de audit externas

```
SSL Labs — calificación de configuración TLS
https://www.ssllabs.com/ssltest/

Security Headers — verificar headers HTTP
https://securityheaders.com

Observatory Mozilla — audit completo de seguridad web
https://observatory.mozilla.org

Shodan — verificar qué puertos tiene expuestos tu IP
https://www.shodan.io
```
