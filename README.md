# TP13C — OWASP ZAP en Kubernetes (k3s/k3d) con GitHub Actions

Operaciones 1 · Tecnicatura Universitaria en Redes y Operaciones Informáticas · UNaHur
Docente: Juan Antonio Gonzalez · Alumno: Lautaro Dainotta (`laudainotta`)

Escaneo DAST con OWASP ZAP ejecutado como Job de Kubernetes dentro de un clúster k3d local,
disparado desde un pipeline de GitHub Actions con runner self-hosted, sobre la Notes App
(Flask + PostgreSQL + Nginx) del TP06 instrumentada con Prometheus.

## Arquitectura

```
Host: Ubuntu 24.04 sobre VirtualBox (vboxuser) — 9.7 GB RAM, 6 vCPU, swap 2 GB
└─ k3d "notes-cluster" — 1 server + 2 agents, k3s v1.35.5, Traefik desactivado
   ├─ ns notes-app     postgres (StatefulSet + PVC) · backend (Flask+Gunicorn, 2 réplicas)
   │                   frontend (Nginx) · Ingress · Job ZAP + PVC de reportes
   ├─ ns monitoring    Prometheus (LB :9090) · Grafana (LB :3000)
   │                   node-exporter (DaemonSet) · cAdvisor (DaemonSet)
   └─ ns ingress-nginx  controller (LB :80 → host :8080)

GitHub Actions
├─ lint / test / build-push  → runner ubuntu-latest (hosted)
└─ deploy-scan               → runner self-hosted en la VM
```

## Estructura

```
.github/workflows/autoscan.yml   pipeline de 4 jobs
.zap/zap-plan.yaml               plan del Automation Framework (7 jobs)
k8s/base/                        namespace, postgres, backend, frontend, job de ZAP
k8s/monitoring/                  prometheus, exporters, grafana
scripts/verificar-tp13c.sh       verificación de red, clúster, app y observabilidad
scripts/extract-zap-reports.sh   copia los reportes del PVC al host
scripts/fuzz-notes-api.sh        fuzzing dirigido con 12 payloads propios
evidencias/                      logs de las tres corridas, fuzzing y verificaciones
```

## Reproducir

```bash
k3d cluster create notes-cluster -p "8080:80@loadbalancer" -p "3000:3000@loadbalancer" \
  -p "9090:9090@loadbalancer" --agents 2 --k3s-arg "--disable=traefik@server:*"
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer
kubectl apply -f k8s/base/00-namespace.yaml -f k8s/base/01-postgres.yaml
kubectl apply -f k8s/base/02-backend.yaml -f k8s/base/03-frontend.yaml
kubectl apply -f k8s/monitoring/
echo "127.0.0.1 notes.local" | sudo tee -a /etc/hosts
bash scripts/verificar-tp13c.sh
```

## Hallazgos

| # | Hallazgo | Evidencia |
|---|---|---|
| 1 | La guía del enunciado está truncada: anuncia 13 capítulos y termina en el 8.3 | falta todo el capítulo 9 (Kubernetes) |
| 2 | cAdvisor no arranca en k3d con el manifiesto canónico: montar `hostPath: /` hace que runc falle al crear el sandbox | `read-only file system` en `/run/k3s/containerd` |
| 3 | La JVM de ZAP lee la RAM del host, no el límite del contenedor: se autoasignó `-Xmx2485m` con límite de 2560Mi | OOMKilled exit 137 |
| 4 | El AF rechaza `informational`; el valor válido es `info` | Job en estado Failed pese a generar los reportes |
| 5 | El spiderAjax se auto-alimenta: crea notas, las descubre en el DOM y crea más | 357 URLs vs 7 con el ciclo cortado |
| 6 | Scrapear el Service reparte el scrape entre réplicas y corrompe los contadores | resuelto con `role: endpoints` |
| 7 | Gunicorn con varios workers rompe `prometheus_client` (un registry por worker) | 1 worker por pod, paralelismo por réplicas |
| 8 | `try_files` de SPA sobre sitio estático elimina los 404: toda ruta devuelve 200 | `/noexiste` → 200 con `index.html` |
| 9 | Cero validación de entrada: 11 de 12 payloads almacenados y reflejados intactos | `evidencias/fuzzing-resultados.csv` |
| 10 | SQLi sin efecto por las consultas parametrizadas de psycopg2, no por código propio | el `DROP TABLE` viaja como dato |
| 11 | La longitud la valida Postgres, no la app: devuelve 500 en vez de 400 | `StringDataRightTruncation` en `VARCHAR(200)` |
| 12 | Credenciales de Docker Hub en base64 plano en `config.json` | resuelto con `credsStore: secretservice` |
| 13 | Los PAT fine-grained necesitan `Secrets: Read and write` para `gh secret set` | HTTP 403 |
| 14 | Ampliar flake8 a todo `backend/` reveló 6 errores preexistentes en los tests | run 34176539182 |

## Alertas de ZAP

12 warning + 10 note. Headers de seguridad ausentes (`10020`, `10038`, `10021`),
CORS abierto (`10098`), sitio sin HTTPS (`10106`) y fuga de versión de Nginx (`10036`).
La alerta `40014` (XSS persistente en respuesta JSON) aparece solo cuando hay payloads
almacenados de una corrida previa: el resultado del DAST depende del estado de la base.
