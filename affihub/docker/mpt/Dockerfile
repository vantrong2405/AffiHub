FROM python:3.11-slim-bookworm

ARG MPT_COMMIT=fafec0fbf3142ad5ad7212c2e17996bf247c360a

WORKDIR /MoneyPrinterTurbo

RUN apt-get update && \
    apt-get install --no-install-recommends -y ca-certificates ffmpeg git && \
    rm -rf /var/lib/apt/lists/*

RUN git init && \
    git remote add origin https://github.com/harry0703/MoneyPrinterTurbo.git && \
    git fetch --depth 1 origin "$MPT_COMMIT" && \
    git checkout --detach FETCH_HEAD

COPY docker/mpt/patches/0001-support-vieneu-wav.patch /tmp/0001-support-vieneu-wav.patch
COPY docker/mpt/patches/0002-tts-fallback-callback.patch /tmp/0002-tts-fallback-callback.patch

RUN git apply --check /tmp/0001-support-vieneu-wav.patch && \
    git apply /tmp/0001-support-vieneu-wav.patch && \
    git apply --check /tmp/0002-tts-fallback-callback.patch && \
    git apply /tmp/0002-tts-fallback-callback.patch && \
    rm -rf .git /tmp/0001-support-vieneu-wav.patch /tmp/0002-tts-fallback-callback.patch

RUN pip install --no-cache-dir --retries 3 --timeout 60 -r requirements.txt && \
    useradd --system --create-home --home-dir /home/mpt mpt && \
    chown -R mpt:mpt /MoneyPrinterTurbo

RUN mkdir -p /MoneyPrinterTurbo/storage && chown mpt:mpt /MoneyPrinterTurbo/storage

COPY --chown=mpt:mpt docker/mpt/entrypoint.py /usr/local/bin/mpt-entrypoint.py

VOLUME ["/MoneyPrinterTurbo/storage"]

ENV PYTHONPATH=/MoneyPrinterTurbo
USER mpt

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/ping', timeout=4).read(16)" || exit 1
ENTRYPOINT ["python3", "/usr/local/bin/mpt-entrypoint.py"]
