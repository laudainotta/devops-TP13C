#!/usr/bin/env bash
set -uo pipefail
BASE=${1:-http://notes.local:8080}
OUT=evidencias/fuzzing-resultados.csv
mkdir -p evidencias
echo "id,payload,http_code,tiempo_ms,bytes,reflejado" > "$OUT"

PAYLOADS=(
  "' OR '1'='1"
  "'; DROP TABLE notes;--"
  "1' UNION SELECT NULL,NULL,NULL--"
  "<script>alert(document.cookie)</script>"
  "<img src=x onerror=alert(1)>"
  "javascript:alert(1)"
  "../../../../etc/passwd"
  "\$(id)"
  "; cat /etc/passwd"
  "{{7*7}}"
  "%00"
  "AAAAAAAAAA_5K_TRUNCADO"
)

i=0
for p in "${PAYLOADS[@]}"; do
  i=$((i+1))
  if [ "$p" = "AAAAAAAAAA_5K_TRUNCADO" ]; then
    p=$(printf 'A%.0s' $(seq 1 5000))
  fi
  BODY=$(python3 -c "import json,sys;print(json.dumps({'title':sys.argv[1],'content':'fuzz-'+sys.argv[2]}))" "$p" "$i")
  RES=$(curl -s -o /tmp/fuzz-body -w "%{http_code},%{time_total},%{size_download}" \
        -X POST "$BASE/api/notes" -H "Content-Type: application/json" -d "$BODY")
  CODE=${RES%%,*}; REST=${RES#*,}; T=${REST%%,*}; SZ=${REST##*,}
  MS=$(awk -v t="$T" 'BEGIN{printf "%.0f", t*1000}')

  REFL="no"
  if [ "$CODE" = "201" ]; then
    curl -s "$BASE/api/notes" | grep -qF "fuzz-$i" && REFL="si"
  fi

  SHORT=$(printf '%s' "$p" | cut -c1-35 | tr -d '\n' | tr ',' ';')
  echo "$i,\"$SHORT\",$CODE,$MS,$SZ,$REFL" >> "$OUT"
  printf "%-3s %-37s HTTP %-4s %5sms  reflejado:%s\n" "$i" "$SHORT" "$CODE" "$MS" "$REFL"
done

echo "--- resumen por código HTTP ---"
tail -n +2 "$OUT" | cut -d, -f3 | sort | uniq -c
echo "--- integridad de la tabla tras los payloads SQL ---"
curl -s "$BASE/api/notes" >/dev/null && echo "la tabla notes sigue respondiendo" || echo "ERROR: la tabla no responde"
echo "resultados en $OUT"
