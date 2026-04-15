FROM cgr.dev/chainguard-private/go-fips:latest-dev AS fips

USER root

RUN apk update && apk add --no-cache \
    openssl \
    openssl-config-fipshardened \
    openssl-provider-fips-3.4.0 \
    openssl-fips-test

COPY openssl-fips.cnf /etc/ssl/openssl-fips.cnf

# Stage 2: final runtime stays the working Gotenberg image
FROM cgr.dev/chainguard-private/gotenberg:latest

USER root

# Copy likely-needed OpenSSL/FIPS assets from the donor image.
COPY --from=fips /etc/ssl/ /etc/ssl/
COPY --from=fips /usr/lib/ /usr/lib/
COPY --from=fips /lib/ /lib/
COPY --from=fips /usr/bin/openssl /usr/bin/openssl

ENV PATH="/usr/bin:/usr/local/bin:/bin:${PATH}"
ENV OPENSSL_CONF=/etc/ssl/openssl-fips.cnf

# allow arbitrary UID (like 1001) to run
# RUN chmod -R g=u /usr/bin /usr/local/bin /etc/ssl /tmp || true

USER nonroot
