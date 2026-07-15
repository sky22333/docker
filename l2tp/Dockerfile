ARG ACCEL_PPP_REPO=https://github.com/accel-ppp/accel-ppp.git
ARG ACCEL_PPP_BRANCH=stable

FROM alpine:3.21 AS builder
ARG ACCEL_PPP_REPO
ARG ACCEL_PPP_BRANCH

RUN apk add --no-cache \
        build-base \
        cmake \
        git \
        openssl-dev \
        pcre2-dev \
        linux-headers \
        libucontext-dev

WORKDIR /src
RUN git clone --depth 1 --branch "${ACCEL_PPP_BRANCH}" "${ACCEL_PPP_REPO}" .

RUN mkdir build && cd build \
    && cmake -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_INSTALL_PREFIX=/usr \
             -DLIB_SUFFIX= \
             -DRADIUS=FALSE \
             -DSHAPER=FALSE \
             .. \
    && make -j"$(nproc)" \
    && make install DESTDIR=/opt/install

FROM alpine:3.21

RUN apk add --no-cache \
        libreswan \
        nss-tools \
        openssl \
        pcre2 \
        libucontext \
        iproute2 \
        kmod \
        procps-ng \
        curl \
    && mkdir -p /etc/accel-ppp /var/log/accel-ppp /var/lib/accel-ppp \
                /etc/ipsec.d /etc/ppp /var/run/pluto /var/lib/ipsec/nss

COPY --from=builder /opt/install/ /
COPY config/ipsec.conf /etc/ipsec.conf
COPY config/accel-ppp.conf /etc/accel-ppp/accel-ppp.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && accel-pppd -V \
    && ipsec --version

ENTRYPOINT ["/entrypoint.sh"]
