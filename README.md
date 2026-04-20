# AXI4-Lite Slave — SystemVerilog

A fully compliant AXI4-Lite Slave interface implemented in SystemVerilog, with a 4-register memory map and a 12-test self-checking testbench.

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

| Address | Name | Access | Reset Value | Description |
|---------|------|--------|-------------|-------------|
| `0x00`  | REG0 | R/W    | 0x00000000  | General purpose |
| `0x04`  | REG1 | R/W    | 0x00000000  | General purpose |
| `0x08`  | REG2 | R/W    | 0x00000000  | General purpose |
| `0x0C`  | REG3 | R/O    | 0xDEADBEEF  | Status / ID register |

Writes to REG3 or any invalid address return **SLVERR** (slave error).

---

## AXI Response Codes

| Code   | Value  | Meaning |
|--------|--------|---------|
| OKAY   | `2'b00` | Transfer successful |
| SLVERR | `2'b10` | Slave error (bad address or RO violation) |

---

## Port List

### Write Address Channel (AW)
| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `s_awaddr` | in | ADDR_W | Write address |
| `s_awvalid` | in | 1 | Master has valid address |
| `s_awready` | out | 1 | Slave ready to accept address |

### Write Data Channel (W)
| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `s_wdata` | in | DATA_W | Write data |
| `s_wstrb` | in | DATA_W/8 | Byte write enables |
| `s_wvalid` | in | 1 | Master has valid data |
| `s_wready` | out | 1 | Slave ready to accept data |

### Write Response Channel (B)
| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `s_bresp` | out | 2 | Write response code |
| `s_bvalid` | out | 1 | Slave has valid response |
| `s_bready` | in | 1 | Master ready to accept response |

### Read Address Channel (AR)
| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `s_araddr` | in | ADDR_W | Read address |
| `s_arvalid` | in | 1 | Master has valid address |
| `s_arready` | out | 1 | Slave ready to accept address |

### Read Data Channel (R)
| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `s_rdata` | out | DATA_W | Read data |
| `s_rresp` | out | 2 | Read response code |
| `s_rvalid` | out | 1 | Slave has valid data |
| `s_rready` | in | 1 | Master ready to accept data |

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

| # | Test | What It Checks |
|---|------|----------------|
| 1 | Reset state | All outputs deasserted after reset |
| 2 | Single write + read | Basic R/W path |
| 3 | All 3 R/W registers | Full register file |
| 4 | Read-only REG3 | Returns 0xDEAD_BEEF |
| 5 | Write to REG3 | Returns SLVERR, value unchanged |
| 6 | Invalid write address | Returns SLVERR |
| 7 | Invalid read address | Returns SLVERR |
| 8 | Byte strobes | Partial 1-byte write |
| 9 | Back-to-back writes | 3 consecutive write transactions |
| 10 | Back-to-back reads | 3 consecutive read transactions |
| 11 | Write then immediate read | No gap between W and R |
| 12 | 20 random write/read pairs | Shadow register comparison |

---

## How to Simulate

```bash
# Compile
iverilog -g2012 -o axi_sim rtl/axi_lite_slave.sv tb/axi_lite_tb.sv

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
│   └── axi_lite_slave.sv    # AXI4-Lite Slave RTL
├── tb/
│   └── axi_lite_tb.sv       # 12-test self-checking testbench
└── README.md
```

---

## Key Concepts Demonstrated

- **VALID/READY handshake** on all 5 channels
- **Byte strobes** (`wstrb`) for partial writes
- **Slave error response** for invalid/RO addresses
- **Shadow register scoreboard** in testbench
- **Protocol monitor** checking VALID stability

---

## What's Next

- [ ] Add SVA assertions for VALID stability rule
- [ ] Add AXI master BFM (Bus Functional Model) class
- [ ] Add interrupt output register
- [ ] Connect as slave to a simple CPU/master module
- [ ] Upgrade to full AXI4 (burst transactions)

---

## Reference

- ARM AMBA AXI4-Lite Specification: IHI0022
- Tools: Icarus Verilog 12+, GTKWave
