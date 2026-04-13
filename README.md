# swimlane-gotenberg-fips
The encryption endpoint uses qpdf, which links to OpenSSL (libcrypto.so.3). We verified that OpenSSL is operating with the Chainguard FIPS provider and enforcing approved algorithms (e.g., MD5 is rejected). Therefore, PDF encryption operations performed through this endpoint are executed within the OpenSSL FIPS boundary.

Validated on gotenberg-fips:latest:
- OpenSSL providers: base, default, fips all active
- MD5 rejected by OpenSSL under configured policy
- SHA-256 remains available
- Gotenberg 8.30.1 starts successfully
- qpdf binary links to libqpdf.so.30
- libqpdf.so.30 links to libcrypto.so.3

NOTE: 
- HTML → PDF rendering is outside FIPS boundary
- Any TLS or crypto inside Chromium is non-FIPS
- LibreOffice uses NSS and is not validated against FIPS 140-3

Summary:
1. Document conversion (.docx → PDF, etc.) is outside FIPS boundary


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


