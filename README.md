# TP13B — Seguridad DAST con OWASP ZAP

Integración de OWASP ZAP en el pipeline de CI/CD mediante el Automation Framework,
sobre la Notes App del TP06 (Flask + PostgreSQL + Nginx).

## Estructura

- `.zap/zap-plan.yml` — Plan del Automation Framework (spider, spiderAjax, passiveScan-wait, activeScan, report HTML + SARIF)
- `.github/workflows/zap-security.yml` — Pipeline de escaneo en cada push y PR
- `verificar-zap.sh` — Ejecución local del plan
- `reports/` — Reportes generados
- `evidencias/` — Logs de escaneos y reportes comparativos

## Uso local

```bash
cp .env.example .env
docker compose up -d --build
./verificar-zap.sh
xdg-open reports/zap-report.html
```

Requiere al menos 8 GB de RAM disponibles. Con 4 GB el `spiderAjax` agota la memoria
y bloquea el entorno gráfico.

## Resultados del escaneo

| Riesgo | Alertas |
|---|---|
| Alto | 0 |
| Medio | 3 (CSP, Cross-Domain, Anti-clickjacking) |
| Bajo | 3 (XSS persistente, versión del servidor, X-Content-Type-Options) |
| Informativo | 1 |

Sin inyección SQL: las consultas del backend usan parámetros.
El XSS persistente es explotable pese a estar clasificado como Bajo,
porque el frontend inserta el contenido con `innerHTML`.

## Desviaciones respecto del enunciado

| Original | Aplicado | Motivo |
|---|---|---|
| `zaproxy/zap-stable` | `ghcr.io/zaproxy/zaproxy:stable` | La imagen del enunciado no existe |
| sin red declarada | `--network host` + `-port 8091` | Alcanzar la app y evitar colisión con Nginx |
| step `checkout` extra | eliminado | `git clean -ffdx` borraba el reporte antes de subirlo |
| `docker_env_vars` sin `env:` | bloque `env:` agregado | Las variables llegaban vacías |
| `sleep 30` | espera activa sobre `/health` | Evitar escanear una app a medio levantar |
| sin `permissions` | `security-events: write` | Requisito de `upload-sarif` |
| `zap-report.sarif.json` | `zap-report.json` | Nombre real que genera el template |
