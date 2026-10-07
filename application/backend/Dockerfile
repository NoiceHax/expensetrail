FROM python:3.12-slim

# pick up OS security patches released after the base image was built
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY alembic.ini .
COPY alembic ./alembic
COPY app ./app

# run as an unprivileged user
RUN useradd --create-home --uid 10001 appuser
USER 10001

EXPOSE 8000
# compose: migrate on start. Kubernetes sets RUN_MIGRATIONS=false and runs a one-off migration Job instead.
CMD ["sh", "-c", "if [ \"${RUN_MIGRATIONS:-true}\" = \"true\" ]; then alembic upgrade head; fi && exec uvicorn app.main:app --host 0.0.0.0 --port 8000"]
