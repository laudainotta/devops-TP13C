#!/bin/sh
# Usamos /bin/sh porque python:3.12-slim NO trae bash instalado.
# Con #!/bin/bash el contenedor fallaría con "no such file or directory".
set -e


echo "Esperando a Postgres..."
until python -c "
import psycopg2, os, sys
try:
    psycopg2.connect(
        host=os.getenv('DB_HOST','db'),
        port=os.getenv('DB_PORT','5432'),
        dbname=os.getenv('DB_NAME','notesdb'),
        user=os.getenv('DB_USER','postgres'),
        password=os.getenv('DB_PASSWORD','postgres')
    )
    sys.exit(0)
except Exception:
    sys.exit(1)
" 2>/dev/null; do
    echo "  Postgres no disponible, reintentando en 2s..."
    sleep 2
done


echo "Postgres listo. Inicializando schema..."
python -c "import app; app.init_db()" || echo "  Aviso: init_db() lanzó un error (puede ser normal si la tabla ya existe)"

echo "Iniciando app..."
exec "$@"
