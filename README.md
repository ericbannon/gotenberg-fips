# swimlane-gotenberg-fips
The encryption endpoint uses qpdf, which links to OpenSSL (libcrypto.so.3). We verified that OpenSSL is operating with the Chainguard FIPS provider and enforcing approved algorithms (e.g., MD5 is rejected). Therefore, PDF encryption operations performed through this endpoint are executed within the OpenSSL FIPS boundary.

Validated on gotenberg-fips:latest:
- OpenSSL providers: base, default, fips all active
- MD5 rejected by OpenSSL under configured policy
- SHA-256 remains available
- Gotenberg 8.30.1 starts successfully
- qpdf binary links to libqpdf.so.30
- libqpdf.so.30 links to libcrypto.so.3
- qpdf-backed PDF encryption succeeded through Envoy
- Resulting encrypted output was a valid PDF
- mTLS boundary validated at proxy layer

NOTE: 
- HTML → PDF rendering is outside FIPS boundary
- Any TLS or crypto inside Chromium is non-FIPS
- LibreOffice uses NSS and is not validated against FIPS 140-3
- Document conversion (.docx → PDF, etc.) is outside FIPS boundary

## Verification Tests

**Show provider is active**
```
docker run --rm --entrypoint /usr/bin/openssl gotenberg-fips:latest list -providers
```

**Failed Cipher Test**
```
docker run --rm --entrypoint /usr/bin/openssl gotenberg-fips:latest md5 /etc/hosts
Error setting digest
20807182FFFF0000:error:0308010C:digital envelope routines:inner_evp_generic_fetch:unsupported:crypto/evp/evp_fetch.c:376:Global default library context, Algorithm (MD5 : 89), Properties ()
20807182FFFF0000:error:03000086:digital envelope routines:evp_md_init_internal:initialization error:crypto/evp/digest.c:271:
```

**Successful Ciphers**
```
docker run --rm --entrypoint /usr/bin/openssl gotenberg-fips:latest sha256 /etc/hosts
SHA2-256(/etc/hosts)= e4489d054e2349bbda6c8900d82d4cd2a12bbbde827e0a4a6df80497bec490ad
```

## Pass/Fail Script

**Verify all checks pass**:
```
chmod +x verify-gotenberg-fips.sh
./verify-gotenberg-fips.sh
```

### Local Tests (Optional)

**Test for lbcrypto requirements**:

```
rm -rf rootfs
mkdir -p rootfs

docker create --name tmp gotenberg-fips:latest
docker export tmp | tar -xf - -C rootfs --exclude='dev/*'
docker rm tmp

docker run --rm -v $(pwd)/rootfs:/work -w /work \
  cgr.dev/chainguard/wolfi-base:latest \
  sh -c '
    apk add --no-cache binutils &&
    for f in $(find /work -name "libqpdf.so*" 2>/dev/null); do
      echo "== $f ==";
      readelf -d "$f" | grep NEEDED || true;
    done
  '

```
**Expected output:**

```
== /work/usr/lib/libqpdf.so.30.3.2 ==
 0x0000000000000001 (NEEDED)             Shared library: [libz.so.1]
 0x0000000000000001 (NEEDED)             Shared library: [libjpeg.so.8]
 0x0000000000000001 (NEEDED)             Shared library: [libcrypto.so.3]
 0x0000000000000001 (NEEDED)             Shared library: [libstdc++.so.6]
 0x0000000000000001 (NEEDED)             Shared library: [libgcc_s.so.1]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]
 0x0000000000000001 (NEEDED)             Shared library: [ld-linux-aarch64.so.1]
== /work/usr/lib/libqpdf.so.30 ==
 0x0000000000000001 (NEEDED)             Shared library: [libz.so.1]
 0x0000000000000001 (NEEDED)             Shared library: [libjpeg.so.8]
 0x0000000000000001 (NEEDED)             Shared library: [libcrypto.so.3]
 0x0000000000000001 (NEEDED)             Shared library: [libstdc++.so.6]
 0x0000000000000001 (NEEDED)             Shared library: [libgcc_s.so.1]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]
 0x0000000000000001 (NEEDED)             Shared library: [ld-linux-aarch64.so.1]
 ```

# Proxy-TLS FIPS 

We deployed Envoy in front of Gotenberg and enforced mutual TLS at the service boundary. Requests without a valid client certificate fail during the TLS handshake. We also validated TLS policy enforcement by confirming that a weak TLS 1.2 cipher is rejected while a strong AES-GCM/ECDHE TLS 1.2 cipher succeeds. HTML-to-PDF conversion and qpdf-backed PDF encryption both function correctly through this protected path.

## Deploy & Test with Envoy Proxy

```
kubectl create secret generic envoy-mtls-certs -n gotenberg \
  --from-file=server.crt \
  --from-file=server.key \
  --from-file=ca.crt
```

```
kubectl create namespace gotenberg
```

### Deploy Envoy

```
kubectl apply -f envoy-configmap.yaml

kubectl apply -f gotenberg.yaml

kubectl apply -f envoy.yaml
```

**Check Rollout Status**:
```
kubectl get pods -n gotenberg
kubectl get svc -n gotenberg
kubectl rollout status deploy/gotenberg -n gotenberg
kubectl rollout status deploy/envoy-gotenberg -n gotenberg
```

## Test pdf backend ecrypt path through Envoy
```
cat > index.html <<'EOF'
<!doctype html>
<html>
  <body>
    <h1>Hello through Envoy mTLS</h1>
  </body>
</html>
EOF

curl -k \
  --cert ./client.crt \
  --key ./client.key \
  --cacert ./ca.crt \
  -F 'files=@./test.pdf;type=application/pdf' \
  -F 'userPassword=secret123' \
  -F 'ownerPassword=owner123' \
  https://127.0.0.1:8443/forms/pdfengines/encrypt \
  -o encrypted.pdf
  ```

  ## FIPS validation test for TLS

**Weak TLS versions un-approved**
  ```
  curl -k \
  --tls-max 1.0 \
  --cert ./client.crt \
  --key ./client.key \
  https://127.0.0.1:8443

  ```

  **Unapproved Cipher**
  ```
  curl -vk \
  --tls-max 1.2 \
  --tlsv1.2 \
  --ciphers AES128-SHA \
  --cert ./client.crt \
  --key ./client.key \
  --cacert ./ca.crt \
  https://127.0.0.1:8443/health
  ```

  **Approved Cipher**
  ```
  curl -vk \
  --tls-max 1.2 \
  --tlsv1.2 \
  --ciphers ECDHE-RSA-AES256-GCM-SHA384 \
  --cert ./client.crt \
  --key ./client.key \
  --cacert ./ca.crt \
  https://127.0.0.1:8443/health
  ```