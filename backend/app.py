from flask import Flask, jsonify, request, Response
from flask_cors import CORS
import psycopg2
import os
import datetime
import time
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST


app = Flask(__name__)
CORS(app)

REQUEST_COUNT = Counter(
    "notes_http_requests_total", "Total de requests HTTP",
    ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "notes_http_request_duration_seconds", "Latencia de requests HTTP",
    ["method", "endpoint"]
)
ERROR_COUNT = Counter(
    "notes_http_errors_total", "Total de respuestas de error",
    ["method", "endpoint", "status"]
)


def get_conn():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "db"),
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("DB_NAME", "notesdb"),
        user=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD", "postgres")
    )


def init_db():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS notes (
            id SERIAL PRIMARY KEY,
            title VARCHAR(200) NOT NULL,
            content TEXT,
            created_at TIMESTAMP DEFAULT NOW()
        )
    """)
    conn.commit()
    cur.close()
    conn.close()


@app.route("/health")
def health():
    try:
        conn = get_conn()
        conn.close()
        db_status = "connected"
    except Exception as e:
        db_status = f"error: {e}"
    return jsonify({
        "status": "ok",
        "db": db_status,
        "time": datetime.datetime.utcnow().isoformat()
    })


@app.route("/api/notes", methods=["GET"])
def get_notes():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT id, title, content, created_at FROM notes ORDER BY created_at DESC")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify([
        {"id": r[0], "title": r[1], "content": r[2], "created_at": str(r[3])}
        for r in rows
    ])


@app.route("/api/notes", methods=["POST"])
def create_note():
    data = request.get_json(silent=True)
    if not data or not data.get("title"):
        return jsonify({"error": "title is required"}), 400

    conn = get_conn()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO notes (title, content) VALUES (%s, %s) RETURNING id",
        (data["title"], data.get("content", ""))
    )
    note_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()
    return jsonify({"id": note_id, "message": "nota creada"}), 201


@app.route("/api/notes/<int:note_id>", methods=["DELETE"])
def delete_note(note_id):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("DELETE FROM notes WHERE id = %s", (note_id,))
    conn.commit()
    cur.close()
    conn.close()
    return jsonify({"message": "nota eliminada"})


@app.before_request
def _start_timer():
    request._start_time = time.time()


@app.after_request
def _record_metrics(response):
    endpoint = request.endpoint or "unknown"
    elapsed = time.time() - getattr(request, "_start_time", time.time())
    REQUEST_LATENCY.labels(request.method, endpoint).observe(elapsed)
    REQUEST_COUNT.labels(request.method, endpoint, response.status_code).inc()
    if response.status_code >= 400:
        ERROR_COUNT.labels(request.method, endpoint, response.status_code).inc()
    return response


@app.route("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=5000)
