# Match the service's Python version in CI and use the official slim Linux image.
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Cache dependencies separately; only runtime packages belong in this image.
COPY requirements.txt ./requirements.txt
RUN python -m pip install --no-cache-dir -r requirements.txt

# Copy only runtime modules, not local settings, tests, or credentials.
COPY app.py risk.py explanation.py notifications.py ./services/risk_service/

# A numeric user avoids adding user-management packages to the runtime image.
USER 10001:10001

EXPOSE 8000

CMD ["python", "-m", "uvicorn", "services.risk_service.app:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
