# AXI4-Lite Slave — SystemVerilog

An AXI4-Lite slave with a 4-register memory map, verified by a 16-test self-checking testbench, a procedural protocol monitor, and a counter-based functional coverage monitor. Everything runs on Icarus Verilog 12.

The current result is 94 checks passed, 0 failed, 0 protocol violations, and 42/42 coverage bins hit. While building the bench it found a real read-channel bug, which has been fixed (see [Read-channel bug](#read-channel-bug-found-and-fixed)). See [Limitations](#limitations) for what this design does **not** do.

---

## Register Map

| Address | Name | Access | Reset / value | Description |
| ------- | ---- | ------ | ------------- | ----------- |
| `0x0`   | REG0 | R/W    | `0x00000000`  | General purpose |
| `0x4`   | REG1 | R/W    | `0x00000000`  | General purpose |
| `0x8`   | REG2 | R/W    | `0x00000000`  | General purpose |
| `0xC`   | REG3 | R/O    | `0xDEADBEEF`  | Constant ID (not a flop) |

- **Writes:** writes to REG0–REG2 honour `WSTRB` and return OKAY. A write to REG3 or to any other address returns SLVERR and changes nothing.
- **Reads:** a read of 0x0/0x4/0x8/0xC returns OKAY. Any other address returns SLVERR with RDATA = 0.

| Response | Value   | Meaning |
| -------- | ------- | ------- |
| OKAY     | `2'b00` | Transfer successful |
| SLVERR   | `2'b10` | Read-only write or invalid address |

---

## Ports

| Channel | Port | Dir | Width | Description |
| ------- | ---- | --- | ----- | ----------- |
| AW | `s_awaddr`  | in  | ADDR_W   | Write address |
| AW | `s_awvalid` | in  | 1        | Master has a valid address |
| AW | `s_awready` | out | 1        | Slave accepts the address |
| W  | `s_wdata`   | in  | DATA_W   | Write data |
| W  | `s_wstrb`   | in  | DATA_W/8 | Byte write enables |
| W  | `s_wvalid`  | in  | 1        | Master has valid data |
| W  | `s_wready`  | out | 1        | Slave accepts the data |
| B  | `s_bresp`   | out | 2        | Write response |
| B  | `s_bvalid`  | out | 1        | Slave has a valid response |
| B  | `s_bready`  | in  | 1        | Master accepts the response |
| AR | `s_araddr`  | in  | ADDR_W   | Read address |
| AR | `s_arvalid` | in  | 1        | Master has a valid address |
| AR | `s_arready` | out | 1        | Slave accepts the address |
| R  | `s_rdata`   | out | DATA_W   | Read data |
| R  | `s_rresp`   | out | 2        | Read response |
| R  | `s_rvalid`  | out | 1        | Slave has valid data |
| R  | `s_rready`  | in  | 1        | Master accepts the data |

Defaults: `DATA_W = 32`, `ADDR_W = 4` (synchronous active-low reset `rst_n`).

---

## Timing

A transfer happens on a rising edge where VALID and READY are both high.

- **AW / W:** AWREADY and WREADY are registered, one-cycle pulses. Each READY rises on the edge after its VALID is first seen, and the handshake happens on the next edge. AW and W are handled independently and may arrive in any order (TEST 15).
- **B:** BVALID is set on the edge of the later of the AW and W handshakes, so it is first visible one cycle after both are done. It holds, with a stable BRESP, until BREADY.
- **AR / R:**
  - ARREADY is a one-cycle pulse. It is only allowed while no read is outstanding: a `rd_pending_r` flag is set on the AR handshake and cleared on the R handshake.
  - RDATA/RRESP are decoded from the latched address `rd_addr_r`.
  - RVALID is visible one cycle after the AR handshake, so read latency is 1 cycle.
- **Throughput:** the earliest next AW or AR handshake is 2 edges after the previous B or R handshake. With READY always high on B/R, back-to-back reads therefore take 3 cycles each (TEST 14 and TEST 16d show the exact edges).

---

## Testbench (`tb/axi_lite_tb.sv`)

**How it drives the bus**
- The tasks `axi_write`, `axi_read` and `axi_write_skew` are built on per-channel handshake helpers: `aw_wait_hs`, `w_wait_hs`, `ar_wait_hs`, `b_wait_hs` and `r_wait_hs`.
- Each helper samples READY/VALID at the clock edge, drops its own VALID (or READY) 1 ns after its own handshake, and prints `[FAIL]` and counts a failure if no handshake happens within 20 cycles.
- The helpers are `automatic` because they run concurrently inside `fork`.

**Final verdict:** `ALL TESTS PASSED` requires both 0 scoreboard failures and 0 protocol-monitor violations. The 500 µs watchdog prints `** FAILED: simulation timeout **`.

| #  | Test | What it checks | Checks |
| -- | ---- | -------------- | ------ |
| 1  | Reset state | AWREADY, WREADY, BVALID, ARREADY, RVALID low after reset | 5 |
| 2  | Single write + readback | Basic write/read path, OKAY on both | 3 |
| 3  | All R/W registers | Write and read back REG0–REG2 | 6 |
| 4  | Read-only REG3 | Returns `0xDEADBEEF`, OKAY | 2 |
| 5  | Write to REG3 | SLVERR, value unchanged | 2 |
| 6  | Invalid write address (0xE) | SLVERR | 1 |
| 7  | Invalid read address (0xE) | SLVERR | 1 |
| 8  | Byte strobes | 4'h1, 4'h2, 4'h4, 4'h8, 4'h3, 4'hC partial writes | 6 |
| 9  | Consecutive writes | 3 writes plus readbacks. The tasks insert idle cycles, so these are **not** back-to-back on the bus | 6 |
| 10 | Consecutive reads | 3 reads (task-paced, not back-to-back) | 3 |
| 11 | Write then read | Readback via the tasks | 1 |
| 12 | Random | 20 write/read pairs to REG0–REG2 against a shadow model. One check per pair; only failures print. `$random` is unseeded, so the sequence is fixed | 20 |
| 13 | Back-pressure | BVALID/RVALID and their data held while READY is low for 3+ cycles, and exactly one write and two reads happen (handshake counts) | 8 |
| 14 | Back-to-back reads, ARVALID held high | Two reads with ARVALID never dropped: (a) RREADY low, (b) RREADY high. Beat data and AR == R handshake counts | 6 |
| 15 | AW/W skew | AW 3 cycles before W, W 3 cycles before AW, both together: BRESP, readback, BVALID not before both handshakes | 9 |
| 16 | Coverage gaps | (a-i) ordered write→read, (a-ii) read of another register overlapping a write, (b/c) exactly 1 cycle of B/R back-pressure, (d) back-to-back writes at the DUT's maximum rate | 15 |
|    | **Total** | | **94** |

Result from the latest run:

```
  RESULTS: 94 PASSED  |  0 FAILED
  MONITOR: 0 protocol violation(s)
  ** ALL TESTS PASSED **
```

---

## Protocol Monitor (`tb/axi_lite_sva.sv`)

The file and module are named `axi_lite_sva` for historical reasons, but this is **not SVA**: it contains no `assert`, `property` or `sequence`. Every rule is a plain `always @(posedge clk)` block that prints `[MON FAIL] ...` and increments that rule's failure counter.

At `$finish` the monitor prints a per-rule table. **Evaluated** counts the clock edges on which the rule actually constrained the bus; it is not a "pass" count.

| Rule | What "evaluated" means | Evaluated | Failed |
| ---- | ---------------------- | --------: | -----: |
| S1 AWVALID / WVALID / ARVALID held until handshake | edges with a transfer pending | 54 / 54 / 61 | 0 |
| S2 BVALID / RVALID held until handshake | edges with a response pending | 4 / 8 | 0 |
| S3 AWADDR / ARADDR / WDATA / WSTRB stable while pending (including the handshake edge) | edges with a transfer pending and VALID high | 54 / 61 / 54 / 54 | 0 |
| S4 BVALID, RVALID, AWREADY, WREADY, ARREADY low after reset | each reset release | 15 | 0 |
| S5 BRESP / RRESP is OKAY or SLVERR | edges with VALID high | 58 / 63 | 0 |
| S6 R/W-register write → OKAY | each B handshake to 0x0/0x4/0x8 | 52 | 0 |
| S6 REG3 write → SLVERR | each B handshake to 0xC | 1 | 0 |
| S6 REG3 read → `0xDEADBEEF`, OKAY | each R handshake from 0xC | 2 | 0 |
| S8 BVALID rises only after AW+W / RVALID only after AR | each rising edge of VALID | 54 / 55 | 0 |
| S9 RDATA / RRESP / BRESP stable while VALID=1, READY=0 | edges where the response waited | 8 / 8 / 4 | 0 |

**Notes on these rules**
- **WSTRB = 0 is information only.** AXI allows a write with WSTRB = 0: it completes normally and updates no bytes. The monitor prints `[MON INFO]` and counts these writes, but never fails on them; this run had 0.
- **There is no S7.** That number was the old WSTRB rule, and the remaining sections keep their original numbers.
- **The bench has its own VALID check.** It keeps an inline "VALID dropped before READY" check that counts into the scoreboard's `fail_count`.

---

## Functional Coverage (`tb/axi_lite_coverage.sv`)

Coverage is counter-based: there is no `covergroup`. Integer counters are incremented on handshakes, and a bin is "hit" when its counter is > 0.

| Group | Bins | Sampled at | Result |
| ----- | ---- | ---------- | ------ |
| 1 Write | 5 address (REG0–3, invalid) + 2 response + 5 legal address×response | B handshake | 12/12 |
| 2 Read | 5 address + 2 response + 5 legal address×response + REG3×DEADBEEF | R handshake | 13/13 |
| 3 Strobes | 4'h1, 4'h2, 4'h4, 4'h8, 4'h3, 4'hC, 4'hF | W handshake | 7/7 |
| 4 Back-pressure | B and R × {immediate, exactly 1 wait cycle, 2+} | B/R handshake | 6/6 |
| 5 Sequences | see below | AR/AW handshake | 4/4 |

**Group 5 bins.** These are defined for this DUT's registered READY, where N is the edge of the previous handshake:
- **Back-to-back write:** an AW handshake exactly 2 edges after a B handshake. The DUT frees its write channel on edge N, so AWREADY can rise at N+1 and the next AW handshake can't come before N+2 (TEST 16d).
- **Back-to-back read:** an AR handshake exactly 2 edges after an R handshake (TEST 14).
- **Write then read (ordered):** an AR handshake 1–2 edges after a B handshake, for a read whose ARVALID was raised after the write (TEST 16a-i, gap of 2 edges).
- **Read overlapping a write:** ARVALID was high while a write was in progress, i.e. AW/W VALID was high or B was not yet accepted (TEST 16a-ii). This read is not counted as "write then read".

**How the totals are computed:** each group's % is its bins hit divided by its bins. The report prints two totals:

```
  TOTAL (average of 5 groups) : 100.0%
  TOTAL (bins hit / all bins) : 100.0% (42/42)
```

**Other report lines**
- "Gaps to improve" lists every counted bin with zero hits. In this run it lists none.
- The report also prints some information-only counters that are not bins: write data all-zero/all-ones (sampled at the W handshake), read data all-zero or `0xDEADBEEF`, and other WSTRB values.
- Illegal address×response combinations are not bins. They print `[COV ILLEGAL]`, and in this run there were none.

---

## Read-channel bug (found and fixed)

**The bug.** ARREADY was gated by `!s_rvalid`, but RVALID is registered and rises one edge after the AR handshake. That left a one-cycle window where ARREADY was high while a read was already in flight. A master that kept ARVALID high for a second read got a second AR handshake:

- **RREADY low:** RDATA was overwritten before the first beat was accepted.
- **RREADY high:** the R handshake and the second read landed on the same edge, and that read's response was lost.

The original bench missed it because `axi_read` drops ARVALID right after every handshake, and nothing checked RDATA stability.

**How it was caught.** TEST 14 holds ARVALID high across two reads (REG0 = `0x11110000`, then REG1 = `0x22220004`), and monitor rule S9 checks RDATA stability.

| TEST 14 | Before the fix (commit `142a8d4`) | After the fix (commit `87a8e50` onward) |
| ------- | --------------------------------- | ---------------------------------------- |
| (a) RREADY low | `RDATA changed while RVALID=1, RREADY=0: 0x11110000 -> 0x22220004`; beat 0 = `0x22220004`; 2 AR / 1 R | beat 0 = `0x11110000`; 2 AR / 2 R; no monitor hit |
| (b) RREADY high | beat 0 correct; 2 AR / **1** R, second response lost | 2 AR / 2 R |
| Verdict | `3 check(s), 1 monitor error(s)` | all pass |

**The fix** is in `rtl/axi_lite_slave.sv`, in the AR and R blocks only:
- **One read outstanding:** a `rd_pending_r` flag is set on the AR handshake and cleared on the R handshake.
- **ARREADY:** it may only pulse, for one cycle, when no read is pending.
- **Decode:** RDATA/RRESP are decoded from the latched `rd_addr_r`.

Because a new address can't be accepted while a response waits, RDATA and RRESP can't change while RVALID=1 and RREADY=0. Read latency is unchanged at 1 cycle.

---

## How to Run

Requires Icarus Verilog 12 (`iverilog`, `vvp`) and optionally GTKWave.

```
run.bat
```

or manually:

```
iverilog -g2012 -o axi_sim rtl/axi_lite_slave.sv tb/axi_lite_sva.sv tb/axi_lite_coverage.sv tb/axi_lite_tb.sv
vvp axi_sim
gtkwave axi_lite_tb.vcd
```

- `run.bat` deletes the old `axi_sim` first and stops if compilation fails, so a stale binary is never run.
- In VS Code, the default build task ("Run AXI Simulation") calls `run.bat`.
- The build is warning-free on Icarus 12.

---

## Project Structure

```
axi_lite_sv/
├── rtl/
│   └── axi_lite_slave.sv      # AXI4-Lite slave
├── tb/
│   ├── axi_lite_tb.sv         # 16-test self-checking testbench
│   ├── axi_lite_sva.sv        # procedural protocol monitor (not SVA)
│   └── axi_lite_coverage.sv   # counter-based functional coverage
├── .vscode/tasks.json         # build task -> run.bat
├── run.bat                    # compile + run
└── README.md
```

Build outputs (`axi_sim`, `*.vcd`, `*.log`) are git-ignored.

---

## Limitations

- **One outstanding read.** A new AR is not accepted until the previous R handshake. The earliest next AW/AR handshake is 2 edges after the previous B/R handshake, so this is not a full-throughput slave.
- **Unaligned addresses return SLVERR.** The decoder matches all 4 address bits, so for example 0x1 or 0x5 is treated as invalid rather than aligned down.
- **No AWPROT/ARPROT ports,** although the AXI4-Lite interface defines them.
- **Not truly parameterisable.** `DATA_W`/`ADDR_W` are parameters, but the case labels, 4-bit strobe logic and 32-bit ID constant assume 32/4.
- **Address capture relies on the master.** The DUT latches AWADDR/ARADDR on the edge it raises READY, one edge before the handshake. This is correct only because AXI requires the master to hold the address stable until the handshake. Monitor rule S3 checks that requirement.
- **Built for Icarus Verilog 12.**
  - The monitor and coverage use no SVA or covergroups.
  - The testbench and both monitors use `always @(posedge clk)` with every counter driven by one process, which is intended to be portable, but the files have only been run on Icarus 12.
  - TEST 12 uses unseeded `$random`.

---

## Reference

- ARM AMBA AXI and ACE Protocol Specification (IHI0022), AXI4-Lite
- Tools: Icarus Verilog 12, GTKWave
