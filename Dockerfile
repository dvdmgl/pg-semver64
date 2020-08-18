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
    && rm -rf /tempdb \
    # clean
    && cd / \
    && apk del .build-deps \
    && rm -rf /tmp/*

# RUN set -ex \
#     && apk add --no-cache \
#         autoconf \
#         automake \
#         file \
#         libtool \
#         make \
#         llvm10-dev \
#         pcre-dev \
#         perl \
#         clang-dev \
#         g++ \
#         gcc

# COPY . /usr/src/semver64
# RUN cd /usr/src/semver64 \
#     && make \
#     && make install
#     # && mkdir /tempdb \
#     # && chown -R postgres:postgres /tempdb \
#     # && su postgres -c 'pg_ctl -D /tempdb init' \
#     # && su postgres -c 'pg_ctl -D /tempdb start' \
#     # && cd /usr/src/semver \
#     # && make installcheck PGUSER=postgres \
#     # && cat /usr/src/semver/regression.diffs \
#     # && cat /usr/src/semver/results/base.out

#     # && mkdir /tempdb \
#     # && chown -R postgres:postgres /tempdb \
#     # && su postgres -c 'pg_ctl -D /tempdb init' \
#     # && su postgres -c 'pg_ctl -D /tempdb start'
# #     && make installcheck PGUSER=postgres \
# #     && rm -rf /tempdb \
# #     && cat /usr/src/semver/regression.out \
# #     && cat /usr/src/semver/regression.diffs \
# # # clean
# #     && cd / \
# #     && rm -rf /usr/src/semver /tmp/*
