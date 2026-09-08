#!/usr/bin/env bash
set -euo pipefail
NS=notes-app
DEST=${1:-./reports}
mkdir -p "$DEST"

kubectl -n "$NS" delete pod zap-reader --ignore-not-found --wait=true >/dev/null 2>&1 || true
kubectl -n "$NS" run zap-reader --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"zap-reader","image":"busybox:1.36","command":["sleep","300"],"volumeMounts":[{"name":"r","mountPath":"/data"}]}],"volumes":[{"name":"r","persistentVolumeClaim":{"claimName":"zap-reports"}}]}}'
kubectl -n "$NS" wait --for=condition=Ready pod/zap-reader --timeout=120s

echo "--- contenido del PVC ---"
kubectl -n "$NS" exec zap-reader -- ls -lh /data/reports

for f in $(kubectl -n "$NS" exec zap-reader -- sh -c 'ls /data/reports'); do
  kubectl -n "$NS" cp "zap-reader:/data/reports/$f" "$DEST/$f" 2>/dev/null
  echo "copiado: $DEST/$f"
done

kubectl -n "$NS" delete pod zap-reader --wait=false >/dev/null 2>&1
ls -lh "$DEST"
