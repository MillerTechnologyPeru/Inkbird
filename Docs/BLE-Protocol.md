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
| `FFF1` | read, write | `cfg data` | `00 00 00 00 00 00 00 78 00 00 00 32 2D 33 AF 8C 00 00 00 00` | Settings. Bytes 14–15 are a CRC-16/MODBUS of bytes 0–13. Byte 7 `0x78` = 120 matches the 2-minute sampling interval measured from `FFF5`. History records are stored less often | CRC Verified; fields Observed |
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
| 2 | `01` | Temperature records, about 600 notifications |
| 3 | `07` | Temperature trailer, 1 notification |
| 4 | `04` | Humidity header, 1 notification |
| 5 | `03` | Humidity records, about 600 notifications |
| 6 | `08` | Humidity trailer, 1 notification |

Each reply arrives about 30 ms after its write response. The app waited for the last record before sending the next write. In this capture, it also read `FFF1`, `FFF2` and `FFF4` while the temperature records were streaming. The sensor did not object.

### Header

`30 75 00 00 1E FE` followed by zeros (20 bytes). Bytes 0–3 are uint32 LE `30000`, and bytes 4–5 are a CRC-16/MODBUS of bytes 0–3. The CRC is **Verified**.

The value was the same for both buffers. In the two downloads so far, it was 24000 more than the number of records sent: `30000` with 6000 records, and `30003` (`33 75 00 00 1E BA`) with 6003. A header requested a few minutes later read `30004`. **Observed.** The library doesn't rely on this.

### Records

Every notification is 20 bytes: 10 records of 2 bytes each. In the capture, each stream was 600 notifications, so 6000 records. A download from the same sensor on 2026-10-29 at 04:55 UTC sent **601** notifications per buffer. The last held 3 records followed by 14 zero bytes, and the trailer CRC covers exactly 12006 bytes (6003 records). **Verified.**

The buffer is not a fixed 6000 records. Compared with the capture, the 04:55 download had dropped the 14 oldest records and added 17 new ones.

| Buffer | Record | Example |
|---|---|---|
| Temperature | int16 LE, °C × 100 | `88 0A` → 26.96 °C |
| Humidity | uint16 LE, % × 100 | `FD 15` → 56.29 % |

The records carry no timestamps or indices. They arrive **oldest first**. The two newest records are the hand-warming done just before the sync (24.47 → 26.54 → 26.96 °C). The newest pair also matches the live `FFF2` read in the same session (26.99 °C, 56.43 %). **Verified.**

Every one of the 6000 values in both buffers was plausible (15.35–39.02 °C, 32.80–86.02 %). None was `FFFF` or another fill value, so the buffer was full. A sensor with less stored history probably sends fewer records or fill values. **Not captured.**

The records stream has no end marker. The app sent the trailer request 65 ms after the 600th notification, though gaps between records reached 211 ms. So it knew the count in advance, possibly from the header. **Verified.**

This library collects records until none has arrived for 2 s. It then requests the trailer and keeps the longest prefix whose CRC matches it, which drops the zero padding (at most 9 records). If no prefix matches, records were lost and the download fails.

The Inkbird app showed Min 23.97 °C and Max 35.82 °C for the day. Those are the min and max of the newest 94–190 records. Its chart covered 16:50–22:28, about 338 minutes, and matched the newest ~44 records, which suggests records about 8 minutes apart (see [Timestamps](#timestamps)).

### Trailer

`AF 9B` (temperature) and `FF 9F` (humidity), each followed by zeros. Each is a CRC-16/MODBUS over all of that buffer's record bytes, without the padding, stored LE (`0x9BAF`, `0x9FFF`). It confirms the transfer was complete and in order. **Verified.**

### Timestamps

**The interval between history records is not known yet.**

- The sensor samples every 120 s. `FFF1` byte 7 reads `0x78` (120), and `FFF5` went up 6 times in 12 minutes, on average every 119.8 s. **Observed.**
- History records are stored less often. Between the capture (02:27:34 UTC) and the next download (04:54:47 UTC), 17 records were added in 147 minutes. That means one record every 8.2–9.2 minutes, not 120 s. **Verified.**
- The app's chart (16:50–22:28 for the newest ~44 records) also suggests about 8 minutes.

The sensor may store every 4th sample (8 minutes), with some samples lost while connected, but this needs a measurement over several hours with the sensor left alone. Requests to `FFF8` hold back the sampling timer (see below), so polling the header can't measure it.

The library currently dates the newest record as the time of the download and each older one `FFF1`'s interval earlier. **This spaces the records too closely.** It reads the interval as a uint16 LE from `FFF1` bytes 7–8. Byte 8 has only been seen as `00`, so it could also be a separate field.

### Record counter (`FFF5`)

`FFF5` is a uint32 LE that goes up by one with each sample, every 120 s. It read 288 → 289 at 22:25:17 (±8 s), went from 291 to 297 between 22:32 and 22:44, and read 363 at 04:54 UTC. It does not count history records. **Observed.**

Writing to `FFF8` holds back the sampling timer. Requesting the header every 15 s kept `FFF5` at 364 for over 5 minutes, while reads alone (the 12-minute poll) didn't. **Observed.**

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

- **The history record interval** (see [Timestamps](#timestamps)).
- Fetching only new records: every download so far sent the whole buffer. A client can find the new records by matching the end of its previous download.
- What does a sensor with much less stored history send?
- What exactly does the header mean? Its offset of 24000 from the record count is unexplained.
- What does `FFF9` `06` do?
- What are `FFF1` bytes 11–13 (`32 2D 33`)? Is changing byte 7 how the app sets the interval?
- What is advertisement byte 8 (`08`)?
- What does the external probe change: advertisement byte 4, and anything else?
- Idle disconnects: a 12-minute session with a read every 10 s was never dropped. Truly idle connections are untested.
