FROM ubuntu:22.04 AS builder
SHELL ["/bin/bash","-c"]
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -qqy --no-install-recommends \
    build-essential nasm autotools-dev autoconf libjemalloc-dev \
    tcl tcl-dev uuid-dev libcurl4-openssl-dev libbz2-dev \
    libzstd-dev liblz4-dev libsnappy-dev libssl-dev pkg-config git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY . /tmp/KeyDB
WORKDIR /tmp/KeyDB
RUN make -j$(nproc) BUILD_TLS=yes && \
    cd src && strip keydb-server keydb-cli keydb-benchmark keydb-check-rdb keydb-check-aof keydb-sentinel

FROM ubuntu:22.04
RUN groupadd -r keydb && useradd -r -g keydb keydb
RUN apt-get update && apt-get install -qqy --no-install-recommends \
    libcurl4 libjemalloc2 libssl3 libzstd1 liblz4-1 libsnappy1v5 libuuid1 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /tmp/KeyDB/src/keydb-server /tmp/KeyDB/src/keydb-cli \
    /tmp/KeyDB/src/keydb-benchmark /tmp/KeyDB/src/keydb-check-rdb \
    /tmp/KeyDB/src/keydb-check-aof /tmp/KeyDB/src/keydb-sentinel /usr/local/bin/
RUN ln -s /usr/local/bin/keydb-cli /usr/local/bin/redis-cli && \
    mkdir /data && chown keydb:keydb /data
VOLUME /data
WORKDIR /data
EXPOSE 6379
ENTRYPOINT ["keydb-server"]
CMD ["--protected-mode", "no"]
