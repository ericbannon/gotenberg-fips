FROM cgr.dev/chainguard-private/go-fips:latest-dev AS fips

USER root

RUN apk update && apk add --no-cache \
    openssl \
    openssl-config-fipshardened \
    openssl-provider-fips-3.4.0 \
    openssl-fips-test

COPY openssl-fips.cnf /etc/ssl/openssl-fips.cnf

FROM cgr.dev/chainguard-private/gotenberg:latest

USER root

COPY --from=fips /etc/ssl/ /etc/ssl/
COPY --from=fips /usr/lib/ /usr/lib/
COPY --from=fips /lib/ /lib/
COPY --from=fips /usr/bin/openssl /usr/bin/openssl

ENV OPENSSL_CONF=/etc/ssl/openssl-fips.cnf
ENV PATH="/usr/bin:/usr/local/bin:/bin:${PATH}"
ENV HOME="/home/gotenberg"
ENV XDG_CONFIG_HOME="/home/gotenberg/.config"
ENV XDG_CACHE_HOME="/home/gotenberg/.cache"

RUN mkdir -p \
    /home/gotenberg \
    /home/gotenberg/tmp \
    /home/gotenberg/tls \
    /home/gotenberg/.config \
    /home/gotenberg/.cache \
    /tmp && \
    chown -R 1001:1001 /home/gotenberg /tmp && \
    chmod -R 0775 /home/gotenberg /tmp

WORKDIR /home/gotenberg

ENTRYPOINT ["/usr/bin/gotenberg"]

USER 1001:1001