FROM debian:bookworm-slim AS picontrol-build

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates git make gcc libc6-dev && \
    rm -rf /var/lib/apt/lists/*

# Pin must match the piControl tag the host kernel module is built from.
# `linux-kunbus_6.6.84.bb` pairs with picontrol_2.3.7.bb upstream.
RUN git clone --depth 1 --branch v2.3.7 \
        https://github.com/RevolutionPi/piControl.git /src/picontrol

WORKDIR /src/picontrol/piTest
RUN make

FROM debian:bookworm-slim

COPY --from=picontrol-build /src/picontrol/piTest/piTest /usr/local/bin/piTest
COPY --from=picontrol-build /src/picontrol/piTest/piControlReset /usr/local/bin/piControlReset
COPY --from=picontrol-build /src/picontrol/piControl.h /usr/local/include/

CMD ["piTest", "-d"]
