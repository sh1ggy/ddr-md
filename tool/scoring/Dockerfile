FROM python:3.12-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends cmake g++ && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY tool/scoring/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
COPY tool/scoring /app/tool/scoring
RUN cmake -S tool/scoring/native -B /tmp/native && cmake --build /tmp/native --parallel 2
# Supply canonical Dart derivatives from the pinned app checkout. A production
# Linux bundle is frozen and conformance-checked before inference is enabled.
ENTRYPOINT ["python", "tool/scoring/cli.py"]
