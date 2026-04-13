#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:-gotenberg-fips:latest}"
PORT="${PORT:-3000}"
BASE_URL="http://127.0.0.1:${PORT}"
CONTAINER_NAME="gotenberg-fips-verify"
EXTRACT_CONTAINER_NAME="${CONTAINER_NAME}-extract"

pass() { printf "[PASS] %s\n" "$1"; }
fail() { printf "[FAIL] %s\n" "$1"; exit 1; }
info() { printf "[INFO] %s\n" "$1"; }

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm -f "$EXTRACT_CONTAINER_NAME" >/dev/null 2>&1 || true
  rm -f index.html test.pdf encrypted.pdf render.headers encrypt.headers md5.out sha256.out providers.out
  rm -rf "${TMPDIR:-}"
}
trap cleanup EXIT

info "Starting container ${IMAGE} on port ${PORT}..."
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker run -d --rm \
  --name "$CONTAINER_NAME" \
  -p "${PORT}:3000" \
  -e OTEL_EXPORTER_OTLP_ENDPOINT= \
  -e OTEL_EXPORTER_OTLP_TRACES_ENDPOINT= \
  -e OTEL_EXPORTER_OTLP_METRICS_ENDPOINT= \
  -e OTEL_EXPORTER_OTLP_LOGS_ENDPOINT= \
  "$IMAGE" >/dev/null

info "Waiting for service..."
for _ in $(seq 1 30); do
  if curl -fsS "${BASE_URL}/health" >/dev/null 2>&1; then
    pass "API health check succeeded"
    break
  fi
  sleep 1
done

curl -fsS "${BASE_URL}/health" >/dev/null 2>&1 || fail "API health check failed"

info "Checking OpenSSL providers..."
docker run --rm --entrypoint /usr/bin/openssl "$IMAGE" list -providers > providers.out
grep -q "fips" providers.out \
  && pass "OpenSSL FIPS provider is active" \
  || { cat providers.out; fail "OpenSSL FIPS provider not detected"; }

info "Checking FIPS enforcement blocks MD5..."
if docker run --rm --entrypoint /usr/bin/openssl "$IMAGE" md5 /etc/hosts > md5.out 2>&1; then
  cat md5.out
  fail "MD5 unexpectedly succeeded"
else
  pass "MD5 is blocked"
fi

info "Checking approved digest still works..."
docker run --rm --entrypoint /usr/bin/openssl "$IMAGE" sha256 /etc/hosts > sha256.out 2>&1 \
  && pass "SHA-256 works" \
  || { cat sha256.out; fail "SHA-256 failed"; }

info "Creating HTML test input..."
cat > index.html <<'EOF'
<!doctype html>
<html>
  <body>
    <h1>FIPS Test</h1>
    <p>Chromium render smoke test</p>
  </body>
</html>
EOF

info "Rendering HTML to PDF through Chromium..."
curl -fsS \
  -D render.headers \
  -F 'index.html=@./index.html;filename=index.html;type=text/html' \
  "${BASE_URL}/forms/chromium/convert/html" \
  -o test.pdf || {
    cat render.headers 2>/dev/null || true
    fail "Chromium render request failed"
  }

if file test.pdf | grep -q "PDF document"; then
  pass "Chromium render produced a PDF"
else
  echo "--- render headers ---"
  cat render.headers || true
  echo "--- render body ---"
  cat test.pdf || true
  fail "Chromium render did not produce a PDF"
fi

info "Encrypting PDF through pdfengines..."
curl -fsS \
  -D encrypt.headers \
  -F 'files=@./test.pdf;type=application/pdf' \
  -F 'userPassword=secret123' \
  -F 'ownerPassword=owner123' \
  "${BASE_URL}/forms/pdfengines/encrypt" \
  -o encrypted.pdf || {
    echo "--- encrypt headers ---"
    cat encrypt.headers 2>/dev/null || true
    echo "--- encrypt body ---"
    cat encrypted.pdf 2>/dev/null || true
    fail "Encrypt request failed"
  }

if file encrypted.pdf | grep -q "PDF document"; then
  pass "Encrypt endpoint produced a PDF"
else
  echo "--- encrypt headers ---"
  cat encrypt.headers || true
  echo "--- encrypt body ---"
  cat encrypted.pdf || true
  fail "Encrypt endpoint did not produce a PDF"
fi

info "Confirming qpdf stack links to libcrypto..."
TMPDIR="$(mktemp -d)"
mkdir -p "${TMPDIR}"

docker rm -f "$EXTRACT_CONTAINER_NAME" >/dev/null 2>&1 || true
docker create --name "$EXTRACT_CONTAINER_NAME" "$IMAGE" >/dev/null

# Copy likely libqpdf candidates directly from the image.
docker cp "${EXTRACT_CONTAINER_NAME}:/usr/lib/libqpdf.so.30" "${TMPDIR}/libqpdf.so.30" >/dev/null 2>&1 || true
docker cp "${EXTRACT_CONTAINER_NAME}:/usr/lib/libqpdf.so.30.3.2" "${TMPDIR}/libqpdf.so.30.3.2" >/dev/null 2>&1 || true

docker rm -f "$EXTRACT_CONTAINER_NAME" >/dev/null 2>&1 || true

if ! ls "${TMPDIR}"/libqpdf.so* >/dev/null 2>&1; then
  fail "Could not extract any libqpdf.so* candidates from the image"
fi

docker run --rm -v "${TMPDIR}:/work" -w /work \
  cgr.dev/chainguard/wolfi-base:latest \
  sh -c '
    apk add --no-cache binutils >/dev/null
    found=0
    for f in /work/libqpdf.so*; do
      [ -e "$f" ] || continue
      echo "checking $f" >&2
      if readelf -d "$f" | grep -q "libcrypto.so.3"; then
        echo "$f"
        found=1
        exit 0
      fi
    done
    exit 1
  ' > libqpdf_path.out \
  && {
    cat libqpdf_path.out
    pass "libqpdf links to libcrypto.so.3"
  } \
  || fail "Could not prove libqpdf links to libcrypto.so.3"

info "Summary"
cat <<EOF
- OpenSSL FIPS provider: active
- MD5: blocked
- SHA-256: allowed
- Chromium render: working
- PDF encrypt endpoint: working
- libqpdf -> libcrypto.so.3: verified

Conclusion:
OpenSSL-backed PDF crypto operations are inside the FIPS boundary.
Chromium rendering works, but Chromium itself is not FIPS.
LibreOffice was not tested by this script and is not part of the FIPS claim.
EOF