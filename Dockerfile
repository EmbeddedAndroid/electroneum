# Multistage docker build, requires docker 17.05

# builder stage
FROM ubuntu:16.04 as builder

RUN apt-get update && \
    apt-get --no-install-recommends --yes install \
        ca-certificates \
        cmake \
        g++ \
        make \
        pkg-config \
        graphviz \
        doxygen \
        git \
        libboost1.58-all-dev \
        curl \
        libtool-bin \
        autoconf \
        automake

WORKDIR /usr/local

# OpenSSL
ARG OPENSSL_VERSION=1.0.2n
ARG OPENSSL_HASH=370babb75f278c39e0c50e8c4e7493bc0f18db6867478341a832a982fd15a8fe
RUN curl -s -O https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz \
    && echo "${OPENSSL_HASH} openssl-${OPENSSL_VERSION}.tar.gz" | sha256sum -c \
    && tar -xzf openssl-${OPENSSL_VERSION}.tar.gz \
    && cd openssl-${OPENSSL_VERSION} \
    && ./Configure linux-x86_64 no-shared --static -fPIC \
    && make build_crypto build_ssl \
    && make install
ENV OPENSSL_ROOT_DIR=/usr/local/openssl-${OPENSSL_VERSION}

# ZMQ
ARG ZMQ_VERSION=v4.2.3
ARG ZMQ_HASH=3226b8ebddd9c6c738ba42986822c26418a49afb
RUN git clone https://github.com/zeromq/libzmq.git -b ${ZMQ_VERSION} \
    && cd libzmq \
    && test `git rev-parse HEAD` = ${ZMQ_HASH} || exit 1 \
    && ./autogen.sh \
    && CFLAGS="-fPIC" CXXFLAGS="-fPIC" ./configure --enable-static --disable-shared \
    && make \
    && make install \
    && ldconfig

# zmq.hpp
ARG CPPZMQ_HASH=6aa3ab686e916cb0e62df7fa7d12e0b13ae9fae6
RUN git clone https://github.com/zeromq/cppzmq.git -b ${ZMQ_VERSION} \
    && cd cppzmq \
    && test `git rev-parse HEAD` = ${CPPZMQ_HASH} || exit 1 \
    && mv *.hpp /usr/local/include

# Readline
ARG READLINE_VERSION=7.0
ARG READLINE_HASH=750d437185286f40a369e1e4f4764eda932b9459b5ec9a731628393dd3d32334
RUN curl -s -O https://ftp.gnu.org/gnu/readline/readline-${READLINE_VERSION}.tar.gz \
    && echo "${READLINE_HASH} readline-${READLINE_VERSION}.tar.gz" | sha256sum -c \
    && tar -xzf readline-${READLINE_VERSION}.tar.gz \
    && cd readline-${READLINE_VERSION} \
    && CFLAGS="-fPIC" CXXFLAGS="-fPIC" ./configure \
    && make \
    && make install

# Sodium
ARG SODIUM_VERSION=1.0.16
ARG SODIUM_HASH=675149b9b8b66ff44152553fb3ebf9858128363d
RUN git clone https://github.com/jedisct1/libsodium.git -b ${SODIUM_VERSION} \
    && cd libsodium \
    && test `git rev-parse HEAD` = ${SODIUM_HASH} || exit 1 \
    && ./autogen.sh \
    && CFLAGS="-fPIC" CXXFLAGS="-fPIC" ./configure \
    && make \
    && make check \
    && make install

WORKDIR /src

COPY . .

ARG NPROC
RUN rm -rf build && \
    if [ -z "$NPROC" ];then make -j$(nproc) release-static;else make -j$NPROC release-static;fi

# runtime stage
FROM ubuntu:16.04

RUN apt-get update && \
    apt-get --no-install-recommends --yes install ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt

COPY --from=builder /src/build/release/bin/* /usr/local/bin/

# Contains the blockchain
VOLUME /root/.electroneum

# Generate your wallet via accessing the container and run:
# cd /wallet
# electroneum-wallet-cli
VOLUME /wallet

EXPOSE 26967
EXPOSE 26968

ENTRYPOINT ["electroneumd", "--p2p-bind-ip=0.0.0.0", "--p2p-bind-port=26967", "--rpc-bind-ip=0.0.0.0", "--rpc-bind-port=26968", "--non-interactive", "--confirm-external-bind"]
