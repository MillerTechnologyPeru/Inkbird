# Inkbird BLE Protocol

Reverse-engineered notes on how the Inkbird IBS-TH2 temperature and humidity sensor communicates over Bluetooth Low Energy. Inkbird publishes no specification. Everything here comes from captures of a real device or from community sources, and each claim says which.

Status labels:

- **Verified**: seen in our own captures and checked against the bytes, such as by a matching CRC or the value on the display.
- **Observed**: seen in our captures, meaning unclear.
- **Community**: taken from other projects, not yet seen on our device.

Device used for every capture below: IBS-TH2, Bluetooth address `49:22:08:15:04:CB`, internal sensor only.

## Contents

1. [Advertisements](#1-advertisements)
2. [GATT layout](#2-gatt-layout)
3. [Live reading](#3-live-reading)
4. [History](#4-history)
5. [Capturing data](#5-capturing-data)
6. [Open questions](#6-open-questions)

## 1. Advertisements

The sensor advertises with local name `sps` and includes service `FFF0` in its advertisement. It is connectable. **Verified** (2026-10-28). Some variants are reported to use the name `tps`. **Community.**

A reading is broadcast as 9 bytes of manufacturer specific data with no company identifier. Platforms that split off the first two bytes as the "company ID", including CoreBluetooth and PureSwift `Bluetooth`'s `ManufacturerSpecificData`, report the temperature there. A decoder has to put those two bytes back before decoding. **Verified.**

| Bytes | Type | Meaning | Status |
|---|---|---|---|
| 0–1 | int16 LE | Temperature, °C × 100 | Verified |
| 2–3 | uint16 LE | Relative humidity, % × 100 | Verified |
| 4 | uint8 | Probe: `00` internal, `01` external | `00` Verified; `01` Community |
| 5–6 | uint16 LE | CRC-16/MODBUS of bytes 0–4 | Verified |
| 7 | uint8 | Battery, % | Verified (`0x64`, 100 %) |
| 8 | uint8 | Always `08`. Matches the value of `FFF8` ("his data type"), so possibly a model or record-format byte | Observed |

The temperature is assumed to be signed because the sensor goes below 0 °C. No negative sample has been captured yet.

### Worked example

`7C 09 FD 17 00 E8 56 64 08` (2026-10-28):

- Temperature `0x097C` = 2428 → **24.28 °C**
- Humidity `0x17FD` = 6141 → **61.41 %**
- Probe `00` → internal
- CRC: CRC-16/MODBUS (poly `0xA001` reflected, init `0xFFFF`, no final XOR) of `7C 09 FD 17 00` = `0x56E8`, stored as `E8 56`. ✓
- Battery `0x64` → **100 %**

The CRC matches on all 14 captured payloads: 11 from 2026-10-28 and 3 from 2023 (in `Tests/InkbirdTests`). It lets a decoder reject other devices that happen to use the same name.

### Update rate

The sensor updated its broadcast reading every 6–20 s while the scan ran. On macOS each update arrived as two reports in the same millisecond: the previous payload, then the new one. This is probably CoreBluetooth merging an advertisement and a scan response sent with different readings. A client should keep the latest value. **Observed.**

## 2. GATT layout

Survey on 2026-10-28. Every characteristic in `FFF0` has a User Description (`2901`) descriptor, quoted below as the device spells it. **Verified.**

### Device Information (`180A`)

| Characteristic | Value |
|---|---|
| `2A23` System ID | `CB 04 15 00 00 08 22 49`: the Bluetooth address, reversed, with `00 00` in the middle |
| `2A24`–`2A29` | Placeholder strings: `Model Number`, `Serial Number`, `Firmware Revision`, `Hardware Revision`, `Software Revision`, `Manufacturer Name` |
| `2A2A` Regulatory list | `FE 00 65 78 70 65 72 69 6D 65 6E 74 61 6C` (`experimental`) |
| `2A50` PnP ID | `01 04 05 00 00 10 01`: vendor source Bluetooth SIG, vendor `0x0504`, product `0x0000`, version `0x0110` |

The model and firmware version can't be read from this service.

### Inkbird service (`FFF0`)

| UUID | Properties | Description | Value seen | Meaning | Status |
|---|---|---|---|---|---|
| `FFF1` | read, write | `cfg data` | `00 00 00 00 00 00 00 78 00 00 00 32 2D 33 AF 8C 00 00 00 00` | Settings. Bytes 14–15 are a CRC-16/MODBUS of bytes 0–13. Byte 7 `0x78` = 120 may be the logging interval in seconds | CRC Verified; fields Observed |
| `FFF2` | read | `Real time data` | `89 0A 16 16 00 15 A3` | Live reading, see [section 3](#3-live-reading) | Verified |
| `FFF3` | read, write | `cfg data2` | 20 × `00` | Unknown | Observed |
| `FFF4` | read | `measure` | `49 22 08 15 04 CB A6 B6 …` | Bluetooth address, then a CRC-16/MODBUS of those 6 bytes | Verified |
| `FFF5` | read | `recoder frame` | `20 01 00 00` → `21 01 00 00` | Stored record count, LE. It went from 288 to 289 during the 15 s session | Observed |
| `FFF6` | notify | `history data` | (no notifications while idle) | History records | Observed |
| `FFF7` | read, write | `run/stop recoder` | `01 7E 80 00 …` | Logging control. Byte 0 `01` probably means running | Observed |
| `FFF8` | read, write | `his data type` | `08` | Selects what history to send | Observed |
| `FFF9` | write | `reset` | | Reset. **Never write this:** it may erase the stored history or the settings | Observed |

Reading `FFF0` needs no pairing or encryption. **Verified.**

## 3. Live reading

Read `FFF2`. It holds the first 7 bytes of the advertisement payload: temperature, humidity, probe and CRC. It has no battery byte. **Verified.**

`89 0A 16 16 00 15 A3` → 26.97 °C, 56.54 %, internal probe, CRC `0xA315` ✓.

`FFF2` doesn't notify. To follow the reading, poll it or watch advertisements.

## 4. History

**Not captured yet.** From the GATT layout, the sync most likely:

1. Reads `FFF5` for the record count.
2. Writes `FFF8` (data type) and/or `FFF7` to start the transfer.
3. Receives records as notifications on `FFF6`.

The request bytes, record layout, timestamps and end-of-data signal will come from a PacketLogger capture of the Inkbird app (see [section 5](#5-capturing-data)).

## 5. Capturing data

- **Close the Inkbird app first.** The sensor stops advertising while a phone is connected.
- **Advertisements and GATT.** A CoreBluetooth command-line tool needs an embedded `Info.plist` with `NSBluetoothAlwaysUsageDescription` (link with `-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist`). It must run from an app that has Bluetooth permission, such as Terminal. Scan with duplicates allowed.
- **Match on name and CRC.** Before connecting, match the name `sps`/`tps` **and** a 9-byte payload with a valid CRC. A 9-byte length alone also matches Apple devices' manufacturer data.
- **App traffic.** Install Apple's Bluetooth logging profile on the iPhone, restart the phone, connect it to a Mac, and choose **File → New iOS Trace** in PacketLogger (Additional Tools for Xcode). Save as `.pklg`. Screen-record the app at the same time, to match values to bytes.
- **Reading `.pklg` files.** Records are a 4-byte LE length, 4-byte seconds, 4-byte microseconds, a 1-byte type (`02` ACL sent, `03` ACL received), then the payload. ATT is L2CAP channel `0x0004`: `0x12` write request, `0x52` write command, `0x0A`/`0x0B` read request/response, `0x1B` notification.
- Traces contain all of the phone's Bluetooth traffic. Don't commit raw traces; add decoded frames as test vectors with the date and device in a comment.

## 6. Open questions

- History: request bytes, record format, whether records carry timestamps, and how the end is signalled.
- How does the app fetch only new records: by index, by time, or by clearing?
- Is `FFF1` byte 7 (`0x78`) the logging interval? What are bytes 11–13 (`32 2D 33`)?
- What is advertisement byte 8 / `FFF8` (`08`)?
- What does the external probe change: byte 4, and anything else?
- Does the sensor drop idle connections? It stayed connected for the whole 20 s survey.
