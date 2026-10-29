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
| 8 | uint8 | Always `08` (2023 and 2026). `FFF8` also read `08`, which is the last history request the app sends, so the match may be a coincidence | Observed |

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
| `FFF1` | read, write | `cfg data` | `00 00 00 00 00 00 00 78 00 00 00 32 2D 33 AF 8C 00 00 00 00` | Settings. Bytes 14–15 are a CRC-16/MODBUS of bytes 0–13. Byte 7 `0x78` = 120 matches the 2-minute logging interval measured from `FFF5` | CRC Verified; fields Observed |
| `FFF2` | read | `Real time data` | `89 0A 16 16 00 15 A3` | Live reading, see [section 3](#3-live-reading) | Verified |
| `FFF3` | read, write | `cfg data2` | 20 × `00` | Unknown | Observed |
| `FFF4` | read | `measure` | `49 22 08 15 04 CB A6 B6 …` | Bluetooth address, then a CRC-16/MODBUS of those 6 bytes | Verified |
| `FFF5` | read | `recoder frame` | `20 01 00 00` → `21 01 00 00` | Record counter, uint32 LE, +1 per record. See [section 4](#record-counter-fff5) | Observed |
| `FFF6` | notify | `history data` | (no notifications while idle) | History replies, see [section 4](#4-history) | Verified |
| `FFF7` | read, write | `run/stop recoder` | `01 7E 80 00 …` | Logging control. Byte 0 `01` probably means running. The app didn't touch it | Observed |
| `FFF8` | read, write | `his data type` | `08` | History request: the byte written selects the header, records or trailer of each buffer (Verified). It read `08`, the last request of a sync, so it probably reads back the last value written (Observed) | Verified |
| `FFF9` | write | `reset` | | The app writes `06` after a sync, and this didn't clear the history counter. Don't write any other value: it may erase the history or the settings | Observed |

Reading `FFF0` needs no pairing or encryption. **Verified.**

## 3. Live reading

Read `FFF2`. It holds the first 7 bytes of the advertisement payload: temperature, humidity, probe and CRC. It has no battery byte. **Verified.**

`89 0A 16 16 00 15 A3` → 26.97 °C, 56.54 %, internal probe, CRC `0xA315` ✓.

`FFF2` doesn't notify. To follow the reading, poll it or watch advertisements.

## 4. History

From a PacketLogger capture of the Inkbird app (iOS) syncing on 2026-10-28 at about 22:27 local time.

The sensor keeps temperature and humidity in separate buffers. Each step is a write request to `FFF8` ("his data type") with one byte, and the sensor answers with notifications on `FFF6` ("history data"). Subscribe to `FFF6` first (CCCD handle `0x31`, `01 00`). **Verified.**

| Step | Write to `FFF8` | Reply on `FFF6` |
|---|---|---|
| 1 | `02` | Temperature header, 1 notification |
| 2 | `01` | Temperature records, 600 notifications |
| 3 | `07` | Temperature trailer, 1 notification |
| 4 | `04` | Humidity header, 1 notification |
| 5 | `03` | Humidity records, 600 notifications |
| 6 | `08` | Humidity trailer, 1 notification |

Each reply arrives about 30 ms after its write response. The app waited for the last record before sending the next write. In this capture, it also read `FFF1`, `FFF2` and `FFF4` while the temperature records were streaming. The sensor did not object.

### Header

`30 75 00 00 1E FE` followed by zeros (20 bytes). Bytes 0–3 are uint32 LE `30000`, and bytes 4–5 are a CRC-16/MODBUS of bytes 0–3. The CRC is **Verified**. The value's meaning is **Observed**: it was the same for both buffers, and it isn't the record count (6000) or the byte count (12000).

### Records

Every notification is 20 bytes: 10 records of 2 bytes each. Each stream was 600 notifications, so **6000 records**, about 8.3 days at a 2-minute interval. **Verified.**

| Buffer | Record | Example |
|---|---|---|
| Temperature | int16 LE, °C × 100 | `88 0A` → 26.96 °C |
| Humidity | uint16 LE, % × 100 | `FD 15` → 56.29 % |

The records carry no timestamps or indices. They arrive **oldest first**. The two newest records are the hand-warming done just before the sync (24.47 → 26.54 → 26.96 °C). The newest pair also matches the live `FFF2` read in the same session (26.99 °C, 56.43 %). **Verified.**

Every one of the 6000 values in both buffers was plausible (15.35–39.02 °C, 32.80–86.02 %). None was `FFFF` or another fill value, so the buffer was full. A sensor with less stored history probably sends fewer records or fill values. **Not captured.**

The records stream has no end marker. The app sent the trailer request 65 ms after the 600th notification, though gaps between records reached 211 ms. So it stopped at a known count instead of waiting for the stream to go quiet. **Verified.**

This library does the same. It stops at 600 notifications, or after the stream has been quiet for the reply timeout, then checks the trailer CRC. The CRC catches a stream that was cut short or lost notifications.

The Inkbird app showed Min 23.97 °C and Max 35.82 °C for the day. Those are the min and max of the newest 94–190 records, consistent with records 2 minutes apart. Its average (27.80 °C) and chart don't match any window of the stream exactly. The app seems to chart its own stored copy of earlier syncs.

### Trailer

`AF 9B` (temperature) and `FF 9F` (humidity), each followed by zeros. Each is a CRC-16/MODBUS over all 12000 bytes of that buffer's records, stored LE (`0x9BAF`, `0x9FFF`). It confirms the transfer was complete and in order. **Verified.**

### Timestamps

Records are taken at a fixed interval, which is `FFF1` byte 7 in seconds (`0x78` = 120 s). Two observations support this. **Observed.**

- `FFF1` byte 7 reads `0x78`.
- Polling `FFF5` every 10 s for 12 minutes, it went up by one 6 times, on average every 119.8 s.

Date the newest record as the time of the sync, and each older one an interval earlier. Each date can be up to one interval late.

The library reads the interval as a uint16 LE from `FFF1` bytes 7–8, like the other multi-byte fields. Byte 8 has only been seen as `00`, so it could also be a separate field. Changing the interval in the Inkbird app would settle this.

### Record counter (`FFF5`)

`FFF5` is a uint32 LE that goes up by one with each record. It read 288 → 289 at 22:25:17 (±8 s), and went from 291 to 297 between 22:32 and 22:44. It does not equal the number of records the sync sends (6000). It may count records since logging started or since the buffer last wrapped. **Observed.**

### After the sync

After the humidity trailer, the app wrote `06` to `FFF9` ("reset") and disconnected. This did not clear `FFF5`: it kept counting from about 290. The logging schedule did shift around the sync. At a steady 120 s, counting from the 22:25:17 tick would give 292 by 22:31:17, but it was still 291 at 22:32:22. Later ticks fall about 120 s apart, starting near 22:32:38. The write may restart the logging timer, or the sensor may pause logging while connected. **Observed.**

The history can be read without this write, so a client should not send it until its effect is known.

### Duration

Each 600-notification stream took about 41 s (about 68 ms per notification). A full sync of both buffers took about 85 s. **Verified.**

PureSwift `GATT` buffers 100 notifications per subscription. At the sensor's pace that is plenty, but a client that stops reading for several seconds mid-stream will lose records. The trailer CRC detects this.

## 5. Capturing data

- **Close the Inkbird app first.** The sensor stops advertising while a phone is connected.
- **Advertisements and GATT.** A CoreBluetooth command-line tool needs an embedded `Info.plist` with `NSBluetoothAlwaysUsageDescription` (link with `-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist`). It must run from an app that has Bluetooth permission, such as Terminal. Scan with duplicates allowed.
- **Match on name and CRC.** Before connecting, match the name `sps`/`tps` **and** a 9-byte payload with a valid CRC. A 9-byte length alone also matches Apple devices' manufacturer data.
- **App traffic.** Install Apple's Bluetooth logging profile on the iPhone, restart the phone, connect it to a Mac, and choose **File → New iOS Trace** in PacketLogger (Additional Tools for Xcode). Save as `.pklg`. Screen-record the app at the same time, to match values to bytes.
- **Reading `.pklg` files.** Records are a 4-byte LE length, 4-byte seconds, 4-byte microseconds, a 1-byte type (`02` ACL sent, `03` ACL received), then the payload. ATT is L2CAP channel `0x0004`: `0x12` write request, `0x52` write command, `0x0A`/`0x0B` read request/response, `0x1B` notification. ACL packets with packet-boundary flag `01` continue the previous L2CAP frame, so join them before decoding. Map handles to UUIDs from the app's own discovery (Read By Type responses). On the 2026-10-28 capture, `FFF1` = `0x21`, `FFF2` = `0x24`, `FFF4` = `0x2A`, `FFF5` = `0x2D`, `FFF6` = `0x30` (CCCD `0x31`), `FFF7` = `0x34`, `FFF8` = `0x37`, `FFF9` = `0x3A`.
- **Polling.** To time the logging interval, connect and read `FFF5` every 10 s. Each change marks a new record.
- Traces contain all of the phone's Bluetooth traffic. Don't commit raw traces; add decoded frames as test vectors with the date and device in a comment.

## 6. Open questions

- Fetching only new records: the app downloaded the whole buffer (6000 records). It might work out which records are new from `FFF5` or from its own records. A second sync capture would show whether the stream is always the full buffer.
- What does a sensor with fewer than 6000 stored records send: fewer records, or fill values?
- What do the header's `30000` and `FFF5` mean exactly?
- What does `FFF9` `06` do?
- What are `FFF1` bytes 11–13 (`32 2D 33`)? Is changing byte 7 how the app sets the interval?
- What is advertisement byte 8 (`08`)?
- What does the external probe change: advertisement byte 4, and anything else?
- Idle disconnects: a 12-minute session with a read every 10 s was never dropped. Truly idle connections are untested.
