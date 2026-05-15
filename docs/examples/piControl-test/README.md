# Example — `piControl` health check container

A minimal reference container that:

1. Verifies `/dev/piControl0` is present.
2. Runs `piTest -d` to enumerate Revolution Pi modules.
3. Exits 0 if both succeed, non-zero otherwise.

Useful as a balena fleet health check and as a learning example for the
canonical `piControl`-passthrough pattern.

## Build + run on a Core SE running this BSP

```bash
cd docs/examples/piControl-test
docker compose up --build
```

Expected output ends with:

```
piControl health check: OK
```

## Run on balena (push to a fleet)

```bash
# From a balena app project that points at a fleet with revpi-core-se devices
balena push <fleet-slug>
```

## Notes

- `LED_FILE=/dev/null` is set on the application container as a hint. The
  effective fix for the LED conflict lives on the **supervisor**, set
  through fleet variables — see `docs/piControl-in-containers.md`.
- The `Dockerfile` pins `piControl` to `v2.3.7` to match the kernel
  module recipe (`picontrol_2.3.7.bb`) in `linux-kunbus_6.6.84.bb`. Keep
  these in sync when upstream bumps.
