#!/usr/bin/env bash
set -uo pipefail
OK=0; FAIL=0
chk() { if [ "$1" = "0" ]; then echo "  [OK]   $2"; OK=$((OK+1)); else echo "  [FAIL] $2"; FAIL=$((FAIL+1)); fi; }

echo "=== 1. Diagnóstico de red (TP04) ==="
ping -c 2 notes.local >/dev/null 2>&1; chk $? "ping a notes.local"
getent hosts notes.local | head -1

echo "=== 2. Estado del clúster (TP09) ==="
kubectl get nodes --no-headers | grep -qv "NotReady"; chk $? "nodos Ready"
kubectl get nodes --no-headers
NOT_RUNNING=$(kubectl get pods -A --no-headers | grep -Ev "Running|Completed" | wc -l)
[ "$NOT_RUNNING" -eq 0 ]; chk $? "pods Running/Completed ($NOT_RUNNING fuera de estado)"

echo "=== 3. Aplicación ==="
CODE=$(curl -s -o /dev/null -w "%{http_code}" http://notes.local:8080/)
[ "$CODE" = "200" ]; chk $? "frontend HTTP $CODE"
CODE=$(curl -s -o /dev/null -w "%{http_code}" http://notes.local:8080/health)
[ "$CODE" = "200" ]; chk $? "endpoint de salud HTTP $CODE"
kubectl -n notes-app get endpoints backend-svc -o jsonpath='{.subsets[0].addresses}' 2>/dev/null | grep -q "ip"; chk $? "backend-svc con endpoints"

echo "=== 4. Observabilidad ==="
CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health)
[ "$CODE" = "200" ]; chk $? "Grafana responde en :3000 (HTTP $CODE)"
curl -s -u admin:changeme "http://localhost:3000/api/search?query=Notes" | grep -q "tp13c-notes"; chk $? "dashboard provisionado"
UP=$(curl -s "http://localhost:9090/api/v1/targets?state=active" | grep -o '"health":"up"' | wc -l)
DOWN=$(curl -s "http://localhost:9090/api/v1/targets?state=active" | grep -o '"health":"down"' | wc -l)
[ "$DOWN" -eq 0 ] && [ "$UP" -ge 9 ]; chk $? "targets de Prometheus: $UP UP / $DOWN DOWN"
for J in notes-backend node-exporter cadvisor; do
  N=$(curl -s "http://localhost:9090/api/v1/targets?state=active" | python3 -c "import json,sys;print(sum(1 for t in json.load(sys.stdin)['data']['activeTargets'] if t['labels'].get('job')=='$J' and t['health']=='up'))")
  [ "$N" -gt 0 ]; chk $? "job $J con $N target(s) up"
done

echo "=== RESULTADO: $OK OK, $FAIL FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
