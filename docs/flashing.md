# Flashing a Revolution Pi Core SE

The Core SE uses Raspberry Pi's `rpiboot` (USB device mode) to expose its
internal eMMC as a USB mass-storage device on a Linux or macOS host. This is
the only supported way to provision a blank unit.

You need:

- The Revolution Pi Core SE with its 24 V supply ready (do not power it yet).
- A **micro-USB cable** to connect the Core SE's `Console / Service` port to
  your host computer.
- A host computer (Linux x86_64 or macOS) with admin / root access.
- The balenaOS image: `balena-image-revpi-core-se.balenaos-img` (from
  `./scripts/build.sh dev|prod|flasher`).

---

## Install `rpiboot` on the host

### Linux (Debian / Ubuntu)

```bash
sudo apt update
sudo apt install -y libusb-1.0-0-dev pkg-config build-essential git
git clone --depth 1 https://github.com/raspberrypi/usbboot.git
cd usbboot
make
sudo make install
which rpiboot     # /usr/local/sbin/rpiboot
```

### macOS

```bash
brew install libusb pkg-config
git clone --depth 1 https://github.com/raspberrypi/usbboot.git
cd usbboot
make
# rpiboot binary is in the current directory; use sudo ./rpiboot below
```

> Apple Silicon: known to work via native build. Don't run `rpiboot` from
> inside Docker on macOS — the VM doesn't pass USB through reliably.

---

## Put the Core SE into eMMC mass-storage mode

1. **Power off** the Core SE (disconnect the 24 V supply).
2. Plug the micro-USB cable into the Core SE's `Console / Service` port and
   into your host computer.
3. On the host, in one terminal, run:

   ```bash
   sudo rpiboot
   ```

   You'll see:

   ```
   Waiting for BCM2835/6/7/2711/2712...
   ```

4. **Now** apply 24 V power to the Core SE.

5. After a few seconds `rpiboot` will detect the device, push the bootloader
   stub, and the host kernel will enumerate the eMMC as a USB mass-storage
   device. You'll see a new block device, typically `/dev/sdX` on Linux or a
   "(no name) — XX GB" disk on macOS.

   ```
   Sending bootcode.bin
   Successful read 4 bytes
   Waiting for BCM2835/6/7/2711/2712...
   Loading: msd.bin
   Second stage boot server done
   ```

---

## Write the balenaOS image

Find the eMMC block device first; **be careful** — writing the wrong device
will destroy your host system.

### Linux

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,TRAN | grep -i 'usb\|RPi'
# Example:
#   sdb   14.6G  RPi-MSD-     0001  usb

# Inspect with sudo fdisk -l before writing.

# Write (replace /dev/sdX with the actual device):
sudo dd if=balena-image-revpi-core-se.balenaos-img of=/dev/sdX bs=4M conv=fsync status=progress
sudo sync
```

### macOS

```bash
diskutil list
# Find the "RPi MSD" entry, e.g. /dev/disk5

diskutil unmountDisk /dev/disk5

# Use the RAW device (rdisk) for speed:
sudo dd if=balena-image-revpi-core-se.balenaos-img of=/dev/rdisk5 bs=4m
sudo sync
```

> **balenaEtcher works** and is the safer option if you're unsure about
> `dd` device selection. It autodetects the RPi MSD device and refuses to
> overwrite the host system disk.

---

## First boot

1. **Power off** the Core SE.
2. Unplug the micro-USB cable from both ends.
3. Connect the X1 RJ45 to a network with DHCP.
4. Apply 24 V power.

For a `dev` image, the SSH server listens on TCP/22222:

```bash
ssh -p 22222 root@<device-ip>
```

`<device-ip>` can be found from your DHCP server, or via `avahi-resolve` /
`mDNS` (the device advertises itself by hostname).

For a `prod` image there is no SSH; the device only talks to the configured
balena fleet endpoint (balenaCloud or openBalena). See your fleet's docs.

---

## Troubleshooting

**`rpiboot` doesn't detect the device.**
- Confirm USB cable carries data (not power-only). Try another cable.
- Try a different USB port on the host. **USB 3.0 hubs can cause issues**;
  a direct USB 2.0 port on the host or a powered USB 2.0 hub is most reliable.
- Confirm you're plugged into the Core SE's `Console / Service` micro-USB
  port (the one near the SD card slot), not the standard USB hosts.

**The eMMC block device shows the wrong size.**
- `rpiboot` should have completed before the host enumerates the device. If
  the size is suspicious (e.g. < 1 GB), unplug, power-cycle, and re-run.

**`dd` fails or hangs.**
- Stop, unmount any auto-mounted partitions, and retry. The kernel may
  auto-mount partition tables that appear during the write.

**Device boots but is unreachable.**
- Connect a USB-to-serial adapter to the Core SE console for early-boot
  logs. Default baud `115200 8N1`.
- Confirm the network: the Core SE only has 10/100 Ethernet; check your
  switch reports the correct link speed.

**Recovery: device boots loop / unbootable image.**
- Repeat the flashing procedure with a known-good image. `rpiboot` is
  always available regardless of what's on the eMMC.

---

## References

- [Kunbus official `rpiboot` flashing guide](https://revolutionpi.com/en/docs/revpi-core-s/flashing-firmware/)
- [Raspberry Pi `usbboot` repo](https://github.com/raspberrypi/usbboot)
- [Balena flashing docs (general)](https://docs.balena.io/reference/OS/installing-balenaOS/)
