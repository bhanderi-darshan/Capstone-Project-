# Register Map Specification

**Project:** Design and Verification of an AHB-Lite Based I²C Master Controller with Programmable Clock Generation and Hardware Clock-Stretching Timeout  
**Author:** Darshan Bhanderi  
**Base Address Offset:** `0x00`  
**Address Bus Width:** 32-bit (Word-Aligned, byte addressing)  

---

## 1. Register Memory Map Summary

| Offset | Register Name | Access | Reset Value | Description |
|:---:|:---|:---:|:---:|:---|
| `0x00` | **CONTROL** | R/W | `0x00000000` | Controller configuration (Enable, Interrupt Enable, Auto-STOP) |
| `0x04` | **STATUS** | RO | `0x00000002` | Hardware status flags (`TX_EMPTY = 1` at reset) |
| `0x08` | **CLOCK_DIV** | R/W | `0x01F401F4` | SCL clock dividers: `[15:0] HIGH_COUNT`, `[31:16] LOW_COUNT` |
| `0x0C` | **TX_DATA** | R/W | `0x00000000` | Transmit holding register (Slave address byte or payload data byte) |
| `0x10` | **RX_DATA** | RO | `0x00000000` | Received data byte (Reading clears `STATUS.RX_VALID`) |
| `0x14` | **COMMAND** | WO | `0x00000000` | 1-cycle command strobes (START, WRITE, READ, STOP, RESTART) |
| `0x18` | **TIMEOUT** | R/W | `0x000186A0` | Hardware timeout limit (100,000 cycles = 1.0 ms default; 0 = Disabled) |
| `0x1C` | **IRQ** | R/W1C | `0x00000000` | Interrupt status (W1C pending flags `[2:0]`, interrupt enables `[10:8]`) |

---

## 2. Detailed Register Bitfield Descriptions

### 2.1 CONTROL (Offset: `0x00`) — Read/Write
The CONTROL register configures core enablement, interrupt line masking, and automatic framing behavior.

| Bits | Field Name | Access | Reset | Description |
|:---:|:---|:---:|:---:|:---|
| `[31:3]` | *Reserved* | RO | `0x0` | Reserved; reads return 0. |
| `[2]` | `AUTO_STOP` | R/W | `0` | **Automatic STOP Condition Enable**<br>1: Controller automatically executes STOP sequence following data byte write or read completion.<br>0: Manual STOP generation via COMMAND register required.<br>*Note: AUTO_STOP is ignored on the Address byte phase.* |
| `[1]` | `INT_ENABLE` | R/W | `0` | **Global Interrupt Enable**<br>1: Enables propagation of unmasked pending events to `irq_o`.<br>0: System interrupt line `irq_o` is forced LOW. |
| `[0]` | `ENABLE` | R/W | `0` | **Controller Enable**<br>1: Controller operational; commands processed.<br>0: Core disabled; FSM forced to `ST_IDLE`, all drives released. |

---

### 2.2 STATUS (Offset: `0x04`) — Read-Only
The STATUS register reflects real-time core activity, data buffer occupancy, and latched transfer outcomes.

| Bits | Field Name | Access | Reset | Description |
|:---:|:---|:---:|:---:|:---|
| `[31:6]` | *Reserved* | RO | `0x0` | Reserved; reads return 0. |
| `[5]` | `DONE` | RO | `0` | **Operation Completed Successfully**<br>Asserts on successful completion of START, byte transfer (ACKed), read, or STOP. Cleared automatically upon writing any non-zero value to COMMAND. |
| `[4]` | `TIMEOUT_ERROR` | RO | `0` | **Clock-Stretching Timeout Error**<br>Asserts when slave clock stretching exceeds `TIMEOUT` threshold. Latched until next command write. |
| `[3]` | `ACK_ERROR` | RO | `0` | **Acknowledge Error (NACK Detected)**<br>Asserts when slave generates NACK on address or data write. Latched until next command write. |
| `[2]` | `RX_VALID` | RO | `0` | **Receive Data Valid**<br>Asserts when a newly received byte has been latched into `RX_DATA`. Cleared automatically on read of `RX_DATA` or issuance of a new read command. |
| `[1]` | `TX_EMPTY` | RO | `1` | **Transmit Buffer Empty**<br>1: Transmit holding register ready to accept next byte.<br>0: Byte transfer in progress; `TX_DATA` holding active byte. |
| `[0]` | `BUSY` | RO | `0` | **I²C Core Busy**<br>1: Controller currently executing a bus operation (START through STOP).<br>0: Bus is in IDLE state. |

---

### 2.3 CLOCK_DIV (Offset: `0x08`) — Read/Write
Defines the SCL HIGH and LOW half-cycle counts in units of 100 MHz HCLK cycles ($T_{clk} = 10\text{ ns}$).

| Bits | Field Name | Access | Reset | Description |
|:---:|:---|:---:|:---:|:---|
| `[31:16]` | `LOW_COUNT` | R/W | `0x01F4` | **SCL LOW Phase Duration**<br>Number of HCLK cycles SCL is actively driven LOW ($N_{LOW} \ge 1$).<br>Default = 500 cycles (5.0 $\mu\text{s}$). |
| `[15:0]` | `HIGH_COUNT` | R/W | `0x01F4` | **SCL HIGH Phase Duration**<br>Number of HCLK cycles SCL is held HIGH ($N_{HIGH} \ge 1$).<br>Default = 500 cycles (5.0 $\mu\text{s}$). |

**Timing Calculation:**
$$F_{SCL} = \frac{100\text{ MHz}}{\text{LOW\_COUNT} + \text{HIGH\_COUNT}}$$

---

### 2.4 TX_DATA (Offset: `0x0C`) — Read/Write
Holding register for address bytes and data payload bytes transmitted onto the I²C bus.

| Bits | Field Name | Access | Reset | Description |
|:---:|:---|:---:|:---:|:---|
| `[31:8]` | *Reserved* | RO | `0x0` | Reserved; reads return 0. |
| `[7:0]` | `TX_DATA` | R/W | `0x00` | **Transmit Byte**<br>For Address phase: `[7:1]` Slave Address, `[0]` Direction (0 = Write, 1 = Read).<br>For Data phase: 8-bit payload data byte. |

---

### 2.5 RX_DATA (Offset: `0x10`) — Read-Only
Holds the most recently received data byte from an I²C slave.

| Bits | Field Name | Access | Reset | Description |
|:---:|:---|:---:|:---:|:---|
| `[31:8]` | *Reserved* | RO | `0x0` | Reserved; reads return 0. |
| `[7:0]` | `RX_DATA` | RO | `0x00` | **Received Data Byte**<br>Latched at conclusion of `ST_READ`. Reading this register automatically clears `STATUS.RX_VALID`. |

---

### 2.6 COMMAND (Offset: `0x14`) — Write-Only Strobes
Generates single-cycle command strobes to initiate bus actions. Reading this register always returns `32'h00000000`. Writing any non-zero value clears sticky status flags (`DONE`, `ACK_ERROR`, `TIMEOUT_ERROR`).

| Bits | Field Name | Access | Reset | Description |
|:---:|:---|:---:|:---:|:---|
| `[31:5]` | *Reserved* | WO | `0x0` | Reserved. |
| `[4]` | `CMD_RESTART` | WO | `0` | **Repeated START Strobe**<br>Generates Repeated START framing without releasing the bus to IDLE. |
| `[3]` | `CMD_STOP` | WO | `0` | **STOP Condition Strobe**<br>Executes STOP framing sequence and releases both lines to High-Z. |
| `[2]` | `CMD_READ` | WO | `0` | **Byte Read Strobe**<br>Initiates 8-bit data reception from slave followed by Master NACK on 9th clock. |
| `[1]` | `CMD_WRITE` | WO | `0` | **Byte Write Strobe**<br>Transmits byte currently held in `TX_DATA` onto the bus with slave ACK/NACK evaluation. |
| `[0]` | `CMD_START` | WO | `0` | **START Condition Strobe**<br>Generates START condition if bus-free qualification ($t_{BUF}$) is satisfied. |

---

### 2.7 TIMEOUT (Offset: `0x18`) — Read/Write
Configures the hardware clock-stretching watchdog counter.

| Bits | Field Name | Access | Reset | Description |
|:---:|:---|:---:|:---:|:---|
| `[31:0]` | `TIMEOUT` | R/W | `0x000186A0` | **Clock-Stretching Timeout Threshold (Cycles)**<br>Maximum number of consecutive HCLK cycles SCL may be held LOW by a slave while the master expects HIGH.<br>Default = 100,000 cycles (1.0 ms at 100 MHz HCLK).<br>`0x00000000` = Timeout detection disabled. |

---

### 2.8 IRQ (Offset: `0x1C`) — Read / Write-1-to-Clear (W1C)
Unified register housing event pending latches and individual interrupt enable masks.

| Bits | Field Name | Access | Reset | Description |
|:---:|:---|:---:|:---:|:---|
| `[31:11]` | *Reserved* | RO | `0x0` | Reserved; reads return 0. |
| `[10]` | `TIMEOUT_ENABLE` | R/W | `0` | **Timeout Interrupt Enable**<br>1: Enables `TIMEOUT_PENDING` to assert `irq_o`. |
| `[9]` | `ACK_ERROR_ENABLE`| R/W | `0` | **ACK Error Interrupt Enable**<br>1: Enables `ACK_ERROR_PENDING` to assert `irq_o`. |
| `[8]` | `DONE_ENABLE` | R/W | `0` | **Done Interrupt Enable**<br>1: Enables `DONE_PENDING` to assert `irq_o`. |
| `[7:3]` | *Reserved* | RO | `0x0` | Reserved; reads return 0. |
| `[2]` | `TIMEOUT_PENDING`| R/W1C | `0` | **Timeout Event Pending**<br>Latched on hardware timeout abort. Write 1 to clear. |
| `[1]` | `ACK_ERROR_PENDING`| R/W1C | `0` | **ACK Error Event Pending**<br>Latched on slave NACK. Write 1 to clear. |
| `[0]` | `DONE_PENDING` | R/W1C | `0` | **Done Event Pending**<br>Latched on successful completion. Write 1 to clear. |

**Interrupt Output Logic:**
$$\text{irq\_o} = \text{CONTROL.INT\_ENABLE} \ \& \Big( (\text{DONE\_PENDING} \ \& \ \text{DONE\_ENABLE}) \ \big| \ (\text{ACK\_ERROR\_PENDING} \ \& \ \text{ACK\_ERROR\_ENABLE}) \ \big| \ (\text{TIMEOUT\_PENDING} \ \& \ \text{TIMEOUT\_ENABLE}) \Big)$$

---

## 3. Recommended Software Programming Sequences

### 3.1 Single-Byte Write Sequence
1. Write `CONTROL = 0x00000001` (Enable controller).
2. Configure speed: e.g., Fast Mode write `CLOCK_DIV = 0x00820078`.
3. Issue START: Write `COMMAND = 0x00000001`.
4. Poll `STATUS` until `STATUS.DONE == 1`.
5. Load slave write address: Write `TX_DATA = {Slave_Addr[6:0], 1'b0}`.
6. Transmit address: Write `COMMAND = 0x00000002` (CMD_WRITE).
7. Poll `STATUS`: Verify `STATUS.DONE == 1` and `STATUS.ACK_ERROR == 0`.
8. Load data byte: Write `TX_DATA = Data_Byte`.
9. Transmit data: Write `COMMAND = 0x00000002` (CMD_WRITE).
10. Poll `STATUS`: Verify `STATUS.DONE == 1`.
11. Issue STOP: Write `COMMAND = 0x00000008` (CMD_STOP).
12. Poll `STATUS` until `STATUS.BUSY == 0`.

### 3.2 Single-Byte Read Sequence
1. Write `CONTROL = 0x00000001` (Enable controller).
2. Issue START: Write `COMMAND = 0x00000001`.
3. Poll `STATUS` until `STATUS.DONE == 1`.
4. Load slave read address: Write `TX_DATA = {Slave_Addr[6:0], 1'b1}`.
5. Transmit address: Write `COMMAND = 0x00000002` (CMD_WRITE).
6. Poll `STATUS`: Verify `STATUS.DONE == 1` and `STATUS.ACK_ERROR == 0`.
7. Issue Read: Write `COMMAND = 0x00000004` (CMD_READ).
8. Poll `STATUS` until `STATUS.DONE == 1` and `STATUS.RX_VALID == 1`.
9. Read received data byte: Read `RX_DATA` (clears `STATUS.RX_VALID`).
10. Issue STOP: Write `COMMAND = 0x00000008` (CMD_STOP).
11. Poll `STATUS` until `STATUS.BUSY == 0`.
