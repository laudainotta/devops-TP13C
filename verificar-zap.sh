#!/bin/bash
# verificar-zap.sh
# Valida la sintaxis del plan localmente si tenés Docker
echo "=== Verificando Plan de ZAP AF ==="
mkdir -p reports
chmod -R a+rwx reports
docker run --rm --network host -v $(pwd):/zap/wrk/:rw -t ghcr.io/zaproxy/zaproxy:stable zap.sh \
    -cmd -port 8091 -autorun /zap/wrk/.zap/zap-plan.yml
