# FNB58 Bluetooth protocol notes

These notes describe interoperability facts only. Sources are marked:
**Observed** means captured from an FNB58 (firmware value 115).
**App** means read from FNIRSI's legacy Android Bluetooth app v1.0, which doesn't list the FNB58 by name, and hasn't been tried on this tester.

## Frame

`AA <type> <len> <payload> <check>`. `check` is the low byte of CRC-16/XMODEM over all preceding bytes (observed, and confirmed by the app). Integers are little-endian.

## Commands

| Opcode | Payload | Purpose | Status |
|---|---|---|---|
| 81 | none | Start measuring | Observed |
| 82 | none | Start streaming | Observed |
| 84 | none | Stop streaming | App |
| 85 | none | Request trigger status, answered by 0x09 | Observed |
| 86 | protocol u8, millivolts u16 | Trigger a fast-charge protocol | App, can raise VBUS |
| 87 | none | Stop trigger | App |
| 88 | group u8 | Select stored group, confirmed by the next 0x08 packet | Observed |
| 89 | group u8 | **Clear stored group, destructive** | App |
| 8A | none | Request stored-group list, answered by one 0x0A per group | Observed |

Trigger protocols for 86:

| Index | Protocol | Voltages offered by the app |
|---|---|---|
| 0 | QC2.0 | 5, 9, 12, 20 V |
| 1 | QC3.0 | 3.0 to 20.0 V in 0.2 V steps |
| 2 | Huawei FCP | 5, 9, 12 V |
| 3 | Samsung AFC | 5, 9, 12 V |

Example frames:

- Status: `AA8500 30`
- Stop trigger: `AA8700 52`
- Group list: `AA8A00 0E`
- Select group 2: `AA880102 55`
- QC2.0 at 9 V: `AA8603002823 ED`

The app warns that some chargers restart when switching protocol, which voids the trigger and drops Bluetooth, and that some don't reach the requested voltage.

## Packets

| Type | Rate | Payload | Status |
|---|---|---|---|
| 0x01, 0x02 | On reply | Byte 0 is the acknowledged opcode. After 86 or 87, the app then sends 85. Not sent for 85, 88, or 8A | App, absence observed |
| 0x03 | Once | model u16, firmware u16 /100, serial u32, boot count u32, group count u8, current group u8 | Observed, last two fields from app |
| 0x04 | 4/s | volts, amps, watts: u32 /10000 | Observed |
| 0x05 | 4/s | ohms u32 /10000 (0x19999999 means open), temperature sign u8 (above 0 is positive), °C u16 /10 | Observed, sign from app |
| 0x06 | 10/s | D+ u16 /1000, D- u16 /1000, detected protocol 1 u8, detected protocol 2 u8 | Observed, protocol meaning from app |
| 0x07 | 10/s | volts u16 /1000, amps u16 /1000 | Observed |
| 0x08 | 2/s | group u8, Wh u32 /100000, Ah u32 /100000, active s u32, uptime s u32 | Observed |
| 0x09 | On reply | Trigger state: index into the status list, 0 is idle | Observed idle value, other values from app |
| 0x0A | On reply | group u8, Wh u32 /100000, Ah u32 /100000 | Observed, same encoding as 0x08 |

Detected protocols for 0x06: 0 Unknown, 1 DCP 1.5A, 2 QC2.0 5V, 3 QC2.0 9V, 4 QC2.0 12V, 5 QC2.0 20V, 6 QC3.0, 7 Apple 2.1A, 8 Apple 2.4A, 9 Samsung 2.0A, 10 USB2.0 Full, 11 USB2.0 High, 12 FCP/AFC 9V, 13 FCP/AFC 12V, 14 Huawei SCP, 15 PD MTK.

Trigger status for 0x09: 0 None, 1 QC2, 2 QC3, 3 FCP, 4 SCP, 5 AFC, 6 PD, 7 PD1, 8 VOOC, 9 SVOOC, 10 SVOOC.

## Not found

The app has no command for changing tester settings, starting a PD trigger, or running other toolbox tools. Its alarm limits run on the phone, not the tester.
