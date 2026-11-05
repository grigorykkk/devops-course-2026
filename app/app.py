"""Учебное Flask-приложение для ПР7 (Docker Compose)."""
import os

from flask import Flask

app = Flask(__name__)

SURNAME = os.environ.get("SURNAME", "[Surname]")


@app.get("/")
def index():
    return f"Hello from Docker, {SURNAME}!\n"


@app.get("/health")
def health():
    return {"status": "ok"}, 200


if __name__ == "__main__":
    # В контейнере слушаем все интерфейсы; наружу публикуем только 127.0.0.1:5000
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "5000")))
