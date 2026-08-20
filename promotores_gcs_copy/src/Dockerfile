FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY config/ config/
COPY config_loader.py dates.py gcs_copy.py manifest.py prepare.py worker.py main.py ./

ENV CONFIG_PATH=/app/config/config.json
ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["python", "main.py"]
