FROM postgres:12.3-alpine

ENV SEMVER64_VERSION 0.1.0

COPY . /usr/src/semver64

RUN set -ex \
    && apk add --no-cache --virtual .build-deps \
        autoconf \
        automake \
        file \
        libtool \
        make \
        llvm10-dev \
        pcre-dev \
        perl \
        clang-dev \
        g++ \
        gcc \
    && cd /usr/src/semver64 \
    && make \
    && make install \
    && mkdir /tempdb \
    && chown -R postgres:postgres /tempdb \
    && su postgres -c 'pg_ctl -D /tempdb init' \
    && su postgres -c 'pg_ctl -D /tempdb start' \
    && make installcheck PGUSER=postgres \
    # keep deps
    && runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
            | tr ',' '\n' \
            | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )" \
    # clean
    && apk add --virtual .pg-rundeps $runDeps \
    && apk del .build-deps \
    && rm -rf /tmp/* /tempdb
