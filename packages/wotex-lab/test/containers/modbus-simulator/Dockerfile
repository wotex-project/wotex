FROM python:3.15-slim@sha256:f48fda6d59b2b3437781d1c3ccf4aa0e26ae871de3cdd758b49ab45ee7291619

WORKDIR /lab
COPY requirements.txt ./
RUN pip install --no-cache-dir --no-deps --require-hashes -r requirements.txt
COPY server.py ./
USER 65532:65532
EXPOSE 5020
CMD ["python", "-u", "server.py"]
