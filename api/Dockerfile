FROM python:3.12-slim AS builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

FROM python:3.12-slim

WORKDIR /app

RUN groupadd -r vaultai && useradd -r -g vaultai vaultai

COPY --from=builder /root/.local /home/vaultai/.local
COPY . .

RUN chown -R vaultai:vaultai /app /home/vaultai/.local
USER vaultai

ENV PATH=/home/vaultai/.local/bin:$PATH

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/healthz')" || exit 1

CMD ["uvicorn", "metrics:app", "--host", "0.0.0.0", "--port", "8000"]
