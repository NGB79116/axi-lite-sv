// ============================================================
// Module  : axi_lite_sva
// Purpose : Procedural protocol monitor for axi_lite_slave.
//           Despite the file/module name this is NOT SVA:
//           there are no assert/property/sequence constructs.
//           Every rule is a plain always block that prints
//           [MON FAIL] and counts, so it runs on Icarus 12.
//
//           For each rule the final report prints:
//             Evaluated - edges on which the rule actually
//                         constrained the bus (defined per
//                         rule below)
//             Failed    - edges on which it was violated
//           Every counter is driven by exactly one process
//           (initialised in its declaration, incremented in
//           one always block), so stricter simulators accept it.
//
// Instantiate in axi_lite_tb.sv after the DUT:
//
//   axi_lite_sva #(.DATA_W(DATA_W),.ADDR_W(ADDR_W)) u_sva (
//     .clk(clk), .rst_n(rst_n),
//     .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
//     .s_wdata(s_wdata),   .s_wstrb(s_wstrb),
//     .s_wvalid(s_wvalid), .s_wready(s_wready),
//     .s_bresp(s_bresp),   .s_bvalid(s_bvalid),   .s_bready(s_bready),
//     .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
//     .s_rdata(s_rdata),   .s_rresp(s_rresp),
//     .s_rvalid(s_rvalid), .s_rready(s_rready)
//   );
// ============================================================

`timescale 1ns/1ps

module axi_lite_sva #(
  parameter int DATA_W = 32,
  parameter int ADDR_W = 4
)(
  input logic                  clk,
  input logic                  rst_n,
  input logic [ADDR_W-1:0]     s_awaddr,
  input logic                  s_awvalid,
  input logic                  s_awready,
  input logic [DATA_W-1:0]     s_wdata,
  input logic [DATA_W/8-1:0]   s_wstrb,
  input logic                  s_wvalid,
  input logic                  s_wready,
  input logic [1:0]            s_bresp,
  input logic                  s_bvalid,
  input logic                  s_bready,
  input logic [ADDR_W-1:0]     s_araddr,
  input logic                  s_arvalid,
  input logic                  s_arready,
  input logic [DATA_W-1:0]     s_rdata,
  input logic [1:0]            s_rresp,
  input logic                  s_rvalid,
  input logic                  s_rready
);

  // ──────────────────────────────────────────────────────
  // Per-rule counters: n_* = evaluated, f_* = failed
  // ──────────────────────────────────────────────────────
  integer n_awvalid_hold = 0, f_awvalid_hold = 0;
  integer n_wvalid_hold  = 0, f_wvalid_hold  = 0;
  integer n_arvalid_hold = 0, f_arvalid_hold = 0;
  integer n_bvalid_hold  = 0, f_bvalid_hold  = 0;
  integer n_rvalid_hold  = 0, f_rvalid_hold  = 0;
  integer n_awaddr_stab  = 0, f_awaddr_stab  = 0;
  integer n_araddr_stab  = 0, f_araddr_stab  = 0;
  integer n_wdata_stab   = 0, f_wdata_stab   = 0;
  integer n_wstrb_stab   = 0, f_wstrb_stab   = 0;
  integer n_reset_outs   = 0, f_reset_outs   = 0;
  integer n_bresp_legal  = 0, f_bresp_legal  = 0;
  integer n_rresp_legal  = 0, f_rresp_legal  = 0;
  integer n_wr_rw_okay   = 0, f_wr_rw_okay   = 0;
  integer n_wr_reg3_err  = 0, f_wr_reg3_err  = 0;
  integer n_rd_reg3_id   = 0, f_rd_reg3_id   = 0;
  integer n_bvalid_order = 0, f_bvalid_order = 0;
  integer n_rvalid_order = 0, f_rvalid_order = 0;
  integer n_rdata_stab   = 0, f_rdata_stab   = 0;
  integer n_rresp_stab   = 0, f_rresp_stab   = 0;
  integer n_bresp_stab   = 0, f_bresp_stab   = 0;
  integer info_wstrb_zero = 0;   // not a rule, see SECTION 7

  // Total failures; read by the testbench's final verdict
  wire [31:0] sva_fail_count =
      f_awvalid_hold + f_wvalid_hold + f_arvalid_hold +
      f_bvalid_hold  + f_rvalid_hold +
      f_awaddr_stab  + f_araddr_stab + f_wdata_stab + f_wstrb_stab +
      f_reset_outs   +
      f_bresp_legal  + f_rresp_legal +
      f_wr_rw_okay   + f_wr_reg3_err + f_rd_reg3_id +
      f_bvalid_order + f_rvalid_order +
      f_rdata_stab   + f_rresp_stab  + f_bresp_stab;

  // ──────────────────────────────────────────────────────
  // Sticky VALID trackers
  // *_saw = 1 after an edge where VALID was high and no
  // handshake happened, i.e. a transfer is pending.
  // ──────────────────────────────────────────────────────
  logic aw_valid_saw;   // AWVALID pending
  logic w_valid_saw;    // WVALID  pending
  logic ar_valid_saw;   // ARVALID pending
  logic bvalid_saw;     // BVALID  pending
  logic rvalid_saw;     // RVALID  pending

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_valid_saw <= 1'b0;
      w_valid_saw  <= 1'b0;
      ar_valid_saw <= 1'b0;
      bvalid_saw   <= 1'b0;
      rvalid_saw   <= 1'b0;
    end else begin
      // Set while VALID is high, clear on handshake
      aw_valid_saw <= s_awvalid && !s_awready;
      w_valid_saw  <= s_wvalid  && !s_wready;
      ar_valid_saw <= s_arvalid && !s_arready;
      bvalid_saw   <= s_bvalid  && !s_bready;
      rvalid_saw   <= s_rvalid  && !s_rready;
    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 1 — Master VALID Stability
  // Once AWVALID/WVALID/ARVALID is high it must stay high
  // until the handshake. Evaluated on every edge where a
  // transfer was pending; fails if VALID is now low, no
  // matter what READY is (READY without VALID is not a
  // handshake).
  // ──────────────────────────────────────────────────────
  always @(posedge clk) begin
    if (rst_n) begin

      if (aw_valid_saw) begin
        n_awvalid_hold <= n_awvalid_hold + 1;
        if (!s_awvalid) begin
          $display("[MON FAIL] AWVALID dropped before handshake at %0t", $time);
          f_awvalid_hold <= f_awvalid_hold + 1;
        end
      end

      if (w_valid_saw) begin
        n_wvalid_hold <= n_wvalid_hold + 1;
        if (!s_wvalid) begin
          $display("[MON FAIL] WVALID dropped before handshake at %0t", $time);
          f_wvalid_hold <= f_wvalid_hold + 1;
        end
      end

      if (ar_valid_saw) begin
        n_arvalid_hold <= n_arvalid_hold + 1;
        if (!s_arvalid) begin
          $display("[MON FAIL] ARVALID dropped before handshake at %0t", $time);
          f_arvalid_hold <= f_arvalid_hold + 1;
        end
      end

    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 2 — Slave VALID Stability
  // BVALID and RVALID must hold until the master accepts.
  // Same evaluation as SECTION 1.
  // ──────────────────────────────────────────────────────
  always @(posedge clk) begin
    if (rst_n) begin

      if (bvalid_saw) begin
        n_bvalid_hold <= n_bvalid_hold + 1;
        if (!s_bvalid) begin
          $display("[MON FAIL] BVALID dropped before handshake at %0t", $time);
          f_bvalid_hold <= f_bvalid_hold + 1;
        end
      end

      if (rvalid_saw) begin
        n_rvalid_hold <= n_rvalid_hold + 1;
        if (!s_rvalid) begin
          $display("[MON FAIL] RVALID dropped before handshake at %0t", $time);
          f_rvalid_hold <= f_rvalid_hold + 1;
        end
      end

    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 3 — Master Payload Stability
  // While a transfer is pending, AWADDR/ARADDR/WDATA/WSTRB
  // must equal last edge's value, up to and including the
  // handshake edge. Evaluated on edges where the transfer
  // was pending and VALID is still high (a VALID drop is
  // SECTION 1's failure).
  // ──────────────────────────────────────────────────────
  logic [ADDR_W-1:0]   prev_awaddr;
  logic [ADDR_W-1:0]   prev_araddr;
  logic [DATA_W-1:0]   prev_wdata;
  logic [DATA_W/8-1:0] prev_wstrb;

  always @(posedge clk) begin
    prev_awaddr <= s_awaddr;
    prev_araddr <= s_araddr;
    prev_wdata  <= s_wdata;
    prev_wstrb  <= s_wstrb;
  end

  always @(posedge clk) begin
    if (rst_n) begin

      if (aw_valid_saw && s_awvalid) begin
        n_awaddr_stab <= n_awaddr_stab + 1;
        if (prev_awaddr !== s_awaddr) begin
          $display("[MON FAIL] AWADDR changed while AW pending: 0x%h -> 0x%h at %0t",
                   prev_awaddr, s_awaddr, $time);
          f_awaddr_stab <= f_awaddr_stab + 1;
        end
      end

      if (ar_valid_saw && s_arvalid) begin
        n_araddr_stab <= n_araddr_stab + 1;
        if (prev_araddr !== s_araddr) begin
          $display("[MON FAIL] ARADDR changed while AR pending: 0x%h -> 0x%h at %0t",
                   prev_araddr, s_araddr, $time);
          f_araddr_stab <= f_araddr_stab + 1;
        end
      end

      if (w_valid_saw && s_wvalid) begin
        n_wdata_stab <= n_wdata_stab + 1;
        if (prev_wdata !== s_wdata) begin
          $display("[MON FAIL] WDATA changed while W pending: 0x%08h -> 0x%08h at %0t",
                   prev_wdata, s_wdata, $time);
          f_wdata_stab <= f_wdata_stab + 1;
        end
      end

      if (w_valid_saw && s_wvalid) begin
        n_wstrb_stab <= n_wstrb_stab + 1;
        if (prev_wstrb !== s_wstrb) begin
          $display("[MON FAIL] WSTRB changed while W pending: 4'b%b -> 4'b%b at %0t",
                   prev_wstrb, s_wstrb, $time);
          f_wstrb_stab <= f_wstrb_stab + 1;
        end
      end

    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 4 — Reset Behavior
  // On the first edge after rst_n is released, BVALID,
  // RVALID, AWREADY, WREADY and ARREADY must all be low.
  // Evaluated once per reset release.
  // ──────────────────────────────────────────────────────
  logic rst_n_prev;

  always @(posedge clk) begin
    rst_n_prev <= rst_n;
  end

  always @(posedge clk) begin
    if (rst_n && !rst_n_prev) begin
      n_reset_outs <= n_reset_outs + 1;
      if (s_bvalid || s_rvalid || s_awready || s_wready || s_arready) begin
        $display("[MON FAIL] Outputs not idle after reset (BVALID=%b RVALID=%b AWREADY=%b WREADY=%b ARREADY=%b) at %0t",
                 s_bvalid, s_rvalid, s_awready, s_wready, s_arready, $time);
        f_reset_outs <= f_reset_outs + 1;
      end
    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 5 — Response Code Legality
  // This slave may only return OKAY (2'b00) or SLVERR
  // (2'b10). Evaluated on every edge VALID is high.
  // ──────────────────────────────────────────────────────
  always @(posedge clk) begin
    if (rst_n) begin

      if (s_bvalid) begin
        n_bresp_legal <= n_bresp_legal + 1;
        if (s_bresp !== 2'b00 && s_bresp !== 2'b10) begin
          $display("[MON FAIL] Illegal BRESP=2'b%b at %0t", s_bresp, $time);
          f_bresp_legal <= f_bresp_legal + 1;
        end
      end

      if (s_rvalid) begin
        n_rresp_legal <= n_rresp_legal + 1;
        if (s_rresp !== 2'b00 && s_rresp !== 2'b10) begin
          $display("[MON FAIL] Illegal RRESP=2'b%b at %0t", s_rresp, $time);
          f_rresp_legal <= f_rresp_legal + 1;
        end
      end

    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 6 — Register-specific Response Rules
  // The address is latched at the AW/AR handshake; the
  // rule is evaluated once per transaction, at the B/R
  // handshake, and only for the addresses it covers.
  // ──────────────────────────────────────────────────────
  logic [ADDR_W-1:0] chk_waddr;
  logic [ADDR_W-1:0] chk_raddr;
  logic chk_w_pending;
  logic chk_r_pending;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      chk_waddr     <= '0;
      chk_raddr     <= '0;
      chk_w_pending <= 1'b0;
      chk_r_pending <= 1'b0;
    end else begin
      if (s_awvalid && s_awready) begin
        chk_waddr     <= s_awaddr;
        chk_w_pending <= 1'b1;
      end
      if (s_arvalid && s_arready) begin
        chk_raddr     <= s_araddr;
        chk_r_pending <= 1'b1;
      end
      if (s_bvalid && s_bready) chk_w_pending <= 1'b0;
      if (s_rvalid && s_rready) chk_r_pending <= 1'b0;
    end
  end

  always @(posedge clk) begin
    if (rst_n && s_bvalid && s_bready && chk_w_pending) begin

      // Write to a R/W register must return OKAY
      if (chk_waddr == 4'h0 || chk_waddr == 4'h4 || chk_waddr == 4'h8) begin
        n_wr_rw_okay <= n_wr_rw_okay + 1;
        if (s_bresp !== 2'b00) begin
          $display("[MON FAIL] Write to R/W reg 0x%h returned BRESP=2'b%b (expected OKAY) at %0t",
                   chk_waddr, s_bresp, $time);
          f_wr_rw_okay <= f_wr_rw_okay + 1;
        end
      end

      // Write to REG3 (read-only) must return SLVERR
      if (chk_waddr == 4'hC) begin
        n_wr_reg3_err <= n_wr_reg3_err + 1;
        if (s_bresp !== 2'b10) begin
          $display("[MON FAIL] Write to REG3 (R/O) returned BRESP=2'b%b (expected SLVERR) at %0t",
                   s_bresp, $time);
          f_wr_reg3_err <= f_wr_reg3_err + 1;
        end
      end

    end
  end

  always @(posedge clk) begin
    if (rst_n && s_rvalid && s_rready && chk_r_pending && chk_raddr == 4'hC) begin
      // Read of REG3 must return OKAY and 0xDEAD_BEEF
      n_rd_reg3_id <= n_rd_reg3_id + 1;
      if (s_rresp !== 2'b00 || s_rdata !== 32'hDEAD_BEEF) begin
        $display("[MON FAIL] REG3 read returned 0x%08h RRESP=2'b%b (expected 0xDEADBEEF, OKAY) at %0t",
                 s_rdata, s_rresp, $time);
        f_rd_reg3_id <= f_rd_reg3_id + 1;
      end
    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 7 — WSTRB = 0 (information only)
  // AXI allows WVALID with WSTRB = 0: the write completes
  // with a normal response and no byte is updated. It is
  // therefore not a protocol violation. It is unusual, so
  // each such W handshake is reported as [MON INFO] and
  // counted, but never fails the run.
  // ──────────────────────────────────────────────────────
  always @(posedge clk) begin
    if (rst_n && s_wvalid && s_wready && s_wstrb === '0) begin
      $display("[MON INFO] W handshake with WSTRB=0 (legal, no bytes written) at %0t", $time);
      info_wstrb_zero <= info_wstrb_zero + 1;
    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 8 — Protocol Ordering
  // BVALID must not rise before the AW and W handshakes;
  // RVALID must not rise before the AR handshake.
  // Evaluated on each rising edge of BVALID / RVALID.
  // ──────────────────────────────────────────────────────
  logic aw_done, w_done, ar_done;
  logic bvalid_prev, rvalid_prev;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_done     <= 1'b0;
      w_done      <= 1'b0;
      ar_done     <= 1'b0;
      bvalid_prev <= 1'b0;
      rvalid_prev <= 1'b0;
    end else begin
      if (s_awvalid && s_awready) aw_done <= 1'b1;
      if (s_wvalid  && s_wready)  w_done  <= 1'b1;
      if (s_arvalid && s_arready) ar_done <= 1'b1;
      if (s_bvalid  && s_bready) begin
        aw_done <= 1'b0;
        w_done  <= 1'b0;
      end
      if (s_rvalid && s_rready) ar_done <= 1'b0;

      bvalid_prev <= s_bvalid;
      rvalid_prev <= s_rvalid;
    end
  end

  always @(posedge clk) begin
    if (rst_n) begin

      if (s_bvalid && !bvalid_prev) begin
        n_bvalid_order <= n_bvalid_order + 1;
        if (!(aw_done && w_done)) begin
          $display("[MON FAIL] BVALID rose without completed AW+W handshakes at %0t", $time);
          f_bvalid_order <= f_bvalid_order + 1;
        end
      end

      if (s_rvalid && !rvalid_prev) begin
        n_rvalid_order <= n_rvalid_order + 1;
        if (!ar_done) begin
          $display("[MON FAIL] RVALID rose without prior AR handshake at %0t", $time);
          f_rvalid_order <= f_rvalid_order + 1;
        end
      end

    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 9 — Slave Payload Stability
  // RDATA/RRESP must hold while RVALID=1, RREADY=0.
  // BRESP must hold while BVALID=1, BREADY=0.
  // Evaluated on edges where the response was waiting on
  // the previous edge and VALID is still high.
  // ──────────────────────────────────────────────────────
  logic [DATA_W-1:0] prev_rdata;
  logic [1:0]        prev_rresp;
  logic [1:0]        prev_bresp;

  always @(posedge clk) begin
    prev_rdata <= s_rdata;
    prev_rresp <= s_rresp;
    prev_bresp <= s_bresp;
  end

  always @(posedge clk) begin
    if (rst_n) begin

      if (rvalid_saw && s_rvalid) begin
        n_rdata_stab <= n_rdata_stab + 1;
        if (prev_rdata !== s_rdata) begin
          $display("[MON FAIL] RDATA changed while RVALID=1, RREADY=0: 0x%08h -> 0x%08h at %0t",
                   prev_rdata, s_rdata, $time);
          f_rdata_stab <= f_rdata_stab + 1;
        end
      end

      if (rvalid_saw && s_rvalid) begin
        n_rresp_stab <= n_rresp_stab + 1;
        if (prev_rresp !== s_rresp) begin
          $display("[MON FAIL] RRESP changed while RVALID=1, RREADY=0: 2'b%b -> 2'b%b at %0t",
                   prev_rresp, s_rresp, $time);
          f_rresp_stab <= f_rresp_stab + 1;
        end
      end

      if (bvalid_saw && s_bvalid) begin
        n_bresp_stab <= n_bresp_stab + 1;
        if (prev_bresp !== s_bresp) begin
          $display("[MON FAIL] BRESP changed while BVALID=1, BREADY=0: 2'b%b -> 2'b%b at %0t",
                   prev_bresp, s_bresp, $time);
          f_bresp_stab <= f_bresp_stab + 1;
        end
      end

    end
  end

  // ──────────────────────────────────────────────────────
  // Final report — printed automatically at $finish
  // ──────────────────────────────────────────────────────
  // One row per rule: evaluated, failed, rule name
  final begin
    $display("");
    $display("========================================");
    $display("  Protocol Monitor Report");
    $display("========================================");
    $display("  Evaluated  Failed   Rule");
    $display("  %9d %7d   %s", n_awvalid_hold, f_awvalid_hold, "S1 AWVALID held until handshake");
    $display("  %9d %7d   %s", n_wvalid_hold, f_wvalid_hold, "S1 WVALID held until handshake");
    $display("  %9d %7d   %s", n_arvalid_hold, f_arvalid_hold, "S1 ARVALID held until handshake");
    $display("  %9d %7d   %s", n_bvalid_hold, f_bvalid_hold, "S2 BVALID held until handshake");
    $display("  %9d %7d   %s", n_rvalid_hold, f_rvalid_hold, "S2 RVALID held until handshake");
    $display("  %9d %7d   %s", n_awaddr_stab, f_awaddr_stab, "S3 AWADDR stable while pending");
    $display("  %9d %7d   %s", n_araddr_stab, f_araddr_stab, "S3 ARADDR stable while pending");
    $display("  %9d %7d   %s", n_wdata_stab, f_wdata_stab, "S3 WDATA stable while pending");
    $display("  %9d %7d   %s", n_wstrb_stab, f_wstrb_stab, "S3 WSTRB stable while pending");
    $display("  %9d %7d   %s", n_reset_outs, f_reset_outs, "S4 outputs idle after reset");
    $display("  %9d %7d   %s", n_bresp_legal, f_bresp_legal, "S5 BRESP is OKAY or SLVERR");
    $display("  %9d %7d   %s", n_rresp_legal, f_rresp_legal, "S5 RRESP is OKAY or SLVERR");
    $display("  %9d %7d   %s", n_wr_rw_okay, f_wr_rw_okay, "S6 R/W reg write returns OKAY");
    $display("  %9d %7d   %s", n_wr_reg3_err, f_wr_reg3_err, "S6 REG3 write returns SLVERR");
    $display("  %9d %7d   %s", n_rd_reg3_id, f_rd_reg3_id, "S6 REG3 read returns DEADBEEF, OKAY");
    $display("  %9d %7d   %s", n_bvalid_order, f_bvalid_order, "S8 BVALID rises after AW+W");
    $display("  %9d %7d   %s", n_rvalid_order, f_rvalid_order, "S8 RVALID rises after AR");
    $display("  %9d %7d   %s", n_rdata_stab, f_rdata_stab, "S9 RDATA stable while waiting");
    $display("  %9d %7d   %s", n_rresp_stab, f_rresp_stab, "S9 RRESP stable while waiting");
    $display("  %9d %7d   %s", n_bresp_stab, f_bresp_stab, "S9 BRESP stable while waiting");
    $display("  ----------------------------------------");
    $display("  Info: W handshakes with WSTRB=0 (legal) : %0d", info_wstrb_zero);
    $display("  Total rule failures                    : %0d", sva_fail_count);
    if (sva_fail_count == 0)
      $display("  ** NO PROTOCOL VIOLATIONS **");
    else
      $display("  ** %0d PROTOCOL VIOLATION(S) **", sva_fail_count);
    $display("========================================");
  end

endmodule : axi_lite_sva
