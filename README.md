# AXI4-Lite Slave — SystemVerilog

A fully compliant AXI4-Lite Slave interface implemented in SystemVerilog, with a 4-register memory map, a 13-test self-checking testbench, SVA protocol assertions, and a functional coverage monitor.

---

## What is AXI4-Lite?

AXI4-Lite is ARM's AMBA bus protocol used in virtually every modern SoC to connect a CPU (master) to peripherals (slaves). It uses 5 independent channels, each with a **VALID/READY handshake**:

> **A transfer occurs when VALID=1 AND READY=1 on the same rising clock edge.**

---

## Block Diagram

```
     CPU / AXI Master
          │
┌─────────┴──────────────────────────┐
│         AXI4-Lite Slave            │
│                                    │
│  AW ──► [Write Addr Latch]         │
│  W  ──► [Write Data Latch]         │
│                    │               │
│            [Write Executor]──────► │──► REG0 (0x00)
│                    │               │──► REG1 (0x04)
│  B  ◄── [Response Gen]             │──► REG2 (0x08)
│                                    │    REG3 (0x0C) R/O
│  AR ──► [Read Addr Latch]          │         │
│  R  ◄── [Read Data Mux] ◄──────────┘─────────┘
└────────────────────────────────────┘
```

---

## Register Map

| Address | Name | Access | Reset Value | Description          |
| ------- | ---- | ------ | ----------- | -------------------- |
| `0x00`  | REG0 | R/W    | 0x00000000  | General purpose      |
| `0x04`  | REG1 | R/W    | 0x00000000  | General purpose      |
| `0x08`  | REG2 | R/W    | 0x00000000  | General purpose      |
| `0x0C`  | REG3 | R/O    | 0xDEADBEEF  | Status / ID register |

Writes to REG3 or any invalid address return **SLVERR** (slave error).

---

## AXI Response Codes

| Code   | Value   | Meaning                                   |
| ------ | ------- | ----------------------------------------- |
| OKAY   | `2'b00` | Transfer successful                       |
| SLVERR | `2'b10` | Slave error (bad address or RO violation) |

---

## Port List

### Write Address Channel (AW)

| Port        | Dir | Width   | Description                   |
| ----------- | --- | ------- | ----------------------------- |
| `s_awaddr`  | in  | ADDR\_W | Write address                 |
| `s_awvalid` | in  | 1       | Master has valid address      |
| `s_awready` | out | 1       | Slave ready to accept address |

### Write Data Channel (W)

| Port       | Dir | Width     | Description                |
| ---------- | --- | --------- | -------------------------- |
| `s_wdata`  | in  | DATA\_W   | Write data                 |
| `s_wstrb`  | in  | DATA\_W/8 | Byte write enables         |
| `s_wvalid` | in  | 1         | Master has valid data      |
| `s_wready` | out | 1         | Slave ready to accept data |

### Write Response Channel (B)

| Port       | Dir | Width | Description                     |
| ---------- | --- | ----- | ------------------------------- |
| `s_bresp`  | out | 2     | Write response code             |
| `s_bvalid` | out | 1     | Slave has valid response        |
| `s_bready` | in  | 1     | Master ready to accept response |

### Read Address Channel (AR)

| Port        | Dir | Width   | Description                   |
| ----------- | --- | ------- | ----------------------------- |
| `s_araddr`  | in  | ADDR\_W | Read address                  |
| `s_arvalid` | in  | 1       | Master has valid address      |
| `s_arready` | out | 1       | Slave ready to accept address |

### Read Data Channel (R)

| Port       | Dir | Width   | Description                 |
| ---------- | --- | ------- | --------------------------- |
| `s_rdata`  | out | DATA\_W | Read data                   |
| `s_rresp`  | out | 2       | Read response code          |
| `s_rvalid` | out | 1       | Slave has valid data        |
| `s_rready` | in  | 1       | Master ready to accept data |

---

## AXI-Lite Write Transaction

```
         1       2       3       4
clk  ────┐  ┌───┐  ┌───┐  ┌───┐  ┌
         └──┘   └──┘   └──┘   └──┘

AWVALID ─────────────┐
                     └──────────────
AWREADY      ────────┐
                     └──────────────
           ↑ transfer happens here

WVALID  ─────────────┐
                     └──────────────
WREADY       ────────┐
                     └──────────────

BVALID               ────────┐
                             └──────
BREADY  ─────────────────────┐
                             └──────
                    ↑ response here
```

---

## Test Cases

| #  | Test                        | What It Checks                              |
| -- | --------------------------- | ------------------------------------------- |
| 1  | Reset state                 | All outputs deasserted after reset          |
| 2  | Single write + read         | Basic R/W path                              |
| 3  | All 3 R/W registers         | Full register file                          |
| 4  | Read-only REG3              | Returns 0xDEAD\_BEEF                        |
| 5  | Write to REG3               | Returns SLVERR, value unchanged             |
| 6  | Invalid write address       | Returns SLVERR                              |
| 7  | Invalid read address        | Returns SLVERR                              |
| 8  | Byte strobes (6 patterns)   | byte0/1/2/3 only, low half, high half       |
| 9  | Back-to-back writes         | 3 consecutive write transactions            |
| 10 | Back-to-back reads          | 3 consecutive read transactions             |
| 11 | Write then immediate read   | No gap between W and R                      |
| 12 | 20 random write/read pairs  | Shadow register comparison                  |
| 13 | Back-pressure               | BVALID/RVALID held when READY delayed       |

**Simulation results: 62 PASSED / 0 FAILED**

---

## SVA Assertion Monitor (`tb/axi_lite_sva.sv`)

Protocol assertions implemented as always-block monitors, compatible with Icarus Verilog. Covers 8 rule categories:

| Section | Rule                                                    |
| ------- | ------------------------------------------------------- |
| 1       | VALID stability — AWVALID/WVALID/ARVALID must not drop before READY |
| 2       | Slave VALID stability — BVALID/RVALID must hold until master accepts |
| 3       | Address & data stability — must not change while VALID=1, READY=0   |
| 4       | Reset behavior — all slave outputs deasserted after rst_n            |
| 5       | Response code legality — only OKAY or SLVERR, never EXOKAY/DECERR   |
| 6       | Register response rules — REG3 write→SLVERR, REG3 read→DEADBEEF     |
| 7       | Protocol ordering — BVALID only after AW+W done; RVALID only after AR |
| 8       | WSTRB safety — WSTRB must not be all-zero when WVALID=1              |

**Assertion results: 62 PASSED / 0 FAILED**

---

## Functional Coverage Monitor (`tb/axi_lite_coverage.sv`)

Counter-based coverage monitor, compatible with Icarus Verilog. Prints a detailed bin-level report at end of simulation.

| Group | What is Covered                                         | Coverage |
| ----- | ------------------------------------------------------- | -------- |
| 1     | Write transactions — address bins, response bins, addr×resp cross with illegal bins | 100%  |
| 2     | Read transactions — address bins, response bins, REG3×DEADBEEF cross               | 100%  |
| 3     | Write byte strobes — all 6 meaningful patterns (byte0–3, low half, high half, full)| 100%  |
| 4     | Back-pressure timing — immediate vs multi-cycle BREADY/RREADY delay                | 66.7% |
| 5     | Sequence patterns — back-to-back writes, reads, write-then-read                    | 0%    |

**Total: 73.3%**

> Group 5 (sequence patterns) is verified functionally by TEST 9, 10, and 11.
> Counter-based sampling is incompatible with task pipelining in iverilog;
> an event-driven UVM monitor is needed for accurate detection.

---

## How to Simulate

```
# Compile (all three tb files required)
iverilog -g2012 -o axi_sim rtl/axi_lite_slave.sv tb/axi_lite_sva.sv tb/axi_lite_coverage.sv tb/axi_lite_tb.sv

# Run
vvp axi_sim

# Waveform
gtkwave axi_lite_tb.vcd
```

---

## Project Structure

```
axi_lite_sv/
├── rtl/
│   └── axi_lite_slave.sv      # AXI4-Lite Slave RTL
├── tb/
│   ├── axi_lite_tb.sv         # 13-test self-checking testbench
│   ├── axi_lite_sva.sv        # SVA protocol assertion monitor
│   └── axi_lite_coverage.sv   # Functional coverage monitor
└── README.md
```

---

## Key Concepts Demonstrated

- **VALID/READY handshake** on all 5 channels
- **Byte strobes** (`wstrb`) for partial writes — all 6 patterns tested
- **Slave error response** for invalid/RO addresses
- **Shadow register scoreboard** for self-checking
- **Protocol assertions** — 8 rule categories, 62 checks
- **Functional coverage** — 5 covergroups with bin-level reporting
- **Back-pressure testing** — BVALID and RVALID hold behavior verified
- **iverilog compatibility** — no SVA `property`/`covergroup` keywords

---

## What's Next

- [ ] Add AXI master BFM (Bus Functional Model) as UVM active agent
- [ ] Migrate testbench to UVM (seq_item, driver, monitor, scoreboard)
- [ ] Add RAL (Register Abstraction Layer) model
- [ ] Add interrupt output register
- [ ] Connect as slave to a simple CPU/master module
- [ ] Upgrade to full AXI4 (burst transactions)

---

## Reference

- ARM AMBA AXI4-Lite Specification: IHI0022
- Tools: Icarus Verilog 12+, GTKWave