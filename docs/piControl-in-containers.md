# Running `piControl` from a container

`/dev/piControl0` is the character device exposing the Revolution Pi process
image and ioctls. It can be passed into a Docker / balena application
container **without `--privileged`**.

This page documents the canonical pattern and the known pitfalls.

---

## Minimum viable compose

```yaml
services:
  app:
    image: debian:bookworm-slim
    devices:
      - /dev/piControl0:/dev/piControl0
    group_add:
      - picontrol
    volumes:
      - /etc/revpi:/etc/revpi:ro     # piControl reads config.rsc from here
    command: piTest -d
```

What this does:

- `devices:` exposes the host's `/dev/piControl0` directly to the container.
- `group_add: [picontrol]` adds the container's primary user to the
  `picontrol` group inside the container, satisfying the `0660 root:picontrol`
  permissions on `/dev/piControl0` enforced by the host udev rule.

  > **balenaOS-specific:** name-based `group_add` (e.g. `group_add: [picontrol]`)
  > works because the balena supervisor resolves the group name against the
  > **host's** `/etc/group` and injects the host GID into the container.
  > Vanilla Docker Engine on Raspberry Pi OS / Debian does **not** do this:
  > there, `group_add` only matches a group inside the container image, so
  > tests on a non-balenaOS host with the same compose file may show
  > permission-denied even when `picontrol` exists on the host. If you need
  > to run the same compose file on both, add the user to the picontrol GID
  > **by number** inside your Dockerfile, matching the host GID.
- The `/etc/revpi` bind mount lets `piTest` / `piControl` find
  `config.rsc` (the process-image topology produced by PiCtory or hand-rolled).

> If your container image doesn't have `piTest` installed, install
> `picontrol` (Debian/Ubuntu) or copy the binary from the host into your
> image. See [Custom application image](#custom-application-image) below.

---

## A balena-fleet-friendly compose (no manual `services:` mapping needed)

balena's `docker-compose.yml` accepts the same `devices:` and `group_add:`
syntax. Drop this in your application repo and `balena push`:

```yaml
version: '2.4'

services:
  app:
    build: .
    privileged: false
    devices:
      - /dev/piControl0:/dev/piControl0
    group_add:
      - picontrol
    volumes:
      - revpi-config:/etc/revpi:ro
    environment:
      - LED_FILE=/dev/null
    restart: always

volumes:
  revpi-config:
```

Notes:

- `LED_FILE=/dev/null` is **on the supervisor**, not the application
  container. See [Known pitfalls § supervisor LEDs](#supervisor-grabs-leds).
- A balena named volume (`revpi-config`) is used here so the topology
  survives container rebuilds. You can also mount the host path
  `/mnt/data/revpi-config` if you prefer it visible outside docker.

---

## Custom application image (with `piTest` baked in)

If you want `piTest`, `piControlReset`, and `piControl.h` headers inside
your container, build them from source at image build time. They're small
and have no external runtime dependencies.

```dockerfile
FROM debian:bookworm-slim AS picontrol-build
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates git make gcc libc6-dev && \
    rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch v2.3.7 \
        https://github.com/RevolutionPi/piControl.git /src/picontrol
WORKDIR /src/picontrol/piTest
RUN make

FROM debian:bookworm-slim
COPY --from=picontrol-build /src/picontrol/piTest/piTest /usr/local/bin/piTest
COPY --from=picontrol-build /src/picontrol/piTest/piControlReset /usr/local/bin/piControlReset
# Your app entry point below
COPY --from=picontrol-build /src/picontrol/piControl.h /usr/local/include/
```

Pin the `--branch` to the same `piControl` tag the host kernel module is
built from (`v2.3.7` matches `linux-kunbus_6.6.84.bb`'s
`picontrol_2.3.7.bb`). Mismatched ABI between userspace and kernel module
is a real risk — Kunbus generally maintains backward compatibility but
sometimes adds new ioctls.

---

## Known pitfalls

### Supervisor grabs LEDs

The Balena supervisor by default takes ownership of the `/sys/class/leds/*`
entries to display device state. On RevPi, the A1 / A2 / A3 LEDs are
also writable through `piControl`'s LED ioctl. If both compete you'll see
flickering or your writes silently overridden.

**Workaround:** set `LED_FILE=/dev/null` as an environment variable on the
supervisor (via `RESIN_HOST_LOG_TO_DISPLAY=0` and the fleet variable
`SUPERVISOR_LED_FILE=/dev/null`, depending on supervisor version).

Reference:
[forums.balena.io thread 36197](https://forums.balena.io/t/kunbus-revolution-pi-revpi-core-3-and-dio-module/36197).

### `config.rsc` topology mismatch silently no-ops writes

If `/etc/revpi/config.rsc` declares modules that aren't physically present,
writes to those module's process-image bytes succeed (return non-error) but
have no effect. This is upstream behavior, not a balena bug.

**Workaround:** ship a `config.rsc` matching your actual PiBridge topology.
For a bare Core SE with no expansion modules, a minimal `config.rsc`
declaring only the base unit is enough.

### `KB_RESET` ioctl from inside a container

The `piControl` `KB_RESET` ioctl (used by `piControlReset`) can leave the
piControl process in a confused state if called frequently from inside a
container. Documented in
[revolutionpi.com forum 2970](https://revolutionpi.com/forum/viewtopic.php?t=2970).

**Workaround:** call `piControlReset` sparingly. If you need module
re-detection during runtime, prefer cycling power to the PiBridge modules
over repeated `KB_RESET` from userspace.

### `picontrol` GID inside the container

The host's `picontrol` group has a numeric GID assigned at image build
time. `group_add: [picontrol]` works because balenaOS resolves group names
against the host's `/etc/group` for containers. If you build a container
that adds the user to the group **by GID** instead of name, hardcode the
GID Kunbus uses upstream (currently `1001` on the Kunbus image, but
**this is image-dependent** — let the supervisor resolve it by name).

### Multiple containers fighting over `/dev/piControl0`

`piControl` is single-writer by design. If you run two containers each
writing to outputs, the last writer wins. Architect your application so a
single container owns I/O and exposes a higher-level API to the rest of the
fleet.

---

## Health-check example

A minimal exit-non-zero-if-broken container, useful as a balena
`healthcheck`:

```yaml
services:
  picontrol-health:
    image: debian:bookworm-slim
    devices:
      - /dev/piControl0:/dev/piControl0
    group_add:
      - picontrol
    command: >
      sh -c "test -c /dev/piControl0
             && piTest -d > /dev/null
             && echo OK
             || (echo FAIL; exit 1)"
    restart: on-failure:3
```

See `docs/examples/piControl-test/` in this repo for a runnable reference.

---

## References

- [piControl on GitHub](https://github.com/RevolutionPi/piControl)
- [Kunbus official Docker tutorial](https://revolutionpi.com/en/tutorials/docker-auf-revpi-geraeten-verwenden)
- [forums.balena.io — RevPi Core 3 + DIO discussion](https://forums.balena.io/t/kunbus-revolution-pi-revpi-core-3-and-dio-module/36197)
- [Kunbus forum — PiControl0 KB_RESET in Docker](https://revolutionpi.com/forum/viewtopic.php?t=2970)
