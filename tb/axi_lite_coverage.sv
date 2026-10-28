// ============================================================
// Module  : axi_lite_coverage
// Purpose : Functional coverage monitor for axi_lite_slave
//           Written for Icarus Verilog (iverilog) compatibility.
//           No covergroup — uses integer counters + always blocks.
//           Every counter is driven by exactly one process
//           (initialised in its declaration, incremented in
//           one always block).
//
// Instantiate in axi_lite_tb.sv after the DUT:
//
//   axi_lite_coverage #(.DATA_W(DATA_W),.ADDR_W(ADDR_W)) u_cov (
//     .clk(clk), .rst_n(rst_n),
//     .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
//     .s_wdata(s_wdata),   .s_wstrb(s_wstrb),
//     .s_wvalid(s_wvalid), .s_wready(s_wready),
//     .s_bresp(s_bresp),   .s_bvalid(s_bvalid),   .s_bready(s_bready),
//     .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
//     .s_rdata(s_rdata),   .s_rresp(s_rresp),
//     .s_rvalid(s_rvalid), .s_rready(s_rready)
//   );
//
// Call u_cov.print_coverage() just before $finish.
//
// Report: each group's % is (bins hit / bins in group). Two
// totals are printed: the plain average of the 5 group %s,
// and the overall bins hit / total bins (42 counted bins).
// ============================================================

`timescale 1ns/1ps

module axi_lite_coverage #(
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
  // Handshake pulses
  // ──────────────────────────────────────────────────────
  wire aw_hs = s_awvalid && s_awready;
  wire w_hs  = s_wvalid  && s_wready;
  wire b_hs  = s_bvalid  && s_bready;
  wire ar_hs = s_arvalid && s_arready;
  wire r_hs  = s_rvalid  && s_rready;

  // Latch addresses at AW/AR handshake (mirrors DUT behavior)
  logic [ADDR_W-1:0] cov_waddr;
  logic [ADDR_W-1:0] cov_raddr;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cov_waddr <= '0;
      cov_raddr <= '0;
    end else begin
      if (aw_hs) cov_waddr <= s_awaddr;
      if (ar_hs) cov_raddr <= s_araddr;
    end
  end

  // Address decode: anything but 0x0/0x4/0x8/0xC is invalid
  wire wr_addr_inv = !(cov_waddr == 4'h0 || cov_waddr == 4'h4 ||
                       cov_waddr == 4'h8 || cov_waddr == 4'hC);
  wire rd_addr_inv = !(cov_raddr == 4'h0 || cov_raddr == 4'h4 ||
                       cov_raddr == 4'h8 || cov_raddr == 4'hC);

  // ──────────────────────────────────────────────────────
  // COVERAGE GROUP 1 — Write Transactions (12 bins)
  // Sampled at B-channel handshake:
  //   5 address bins, 2 response bins, 5 legal addr x resp
  // ──────────────────────────────────────────────────────
  integer cov_wr_reg0 = 0, cov_wr_reg1 = 0, cov_wr_reg2 = 0;
  integer cov_wr_reg3 = 0, cov_wr_invalid = 0;
  integer cov_wr_okay = 0, cov_wr_slverr = 0;
  // Cross: addr x resp (legal combinations)
  integer cov_cx_reg0_okay = 0, cov_cx_reg1_okay = 0, cov_cx_reg2_okay = 0;
  integer cov_cx_reg3_slverr = 0, cov_cx_inv_slverr = 0;
  // Illegal cross hits (should stay 0, not counted as bins)
  integer cov_ill_reg0_slverr = 0, cov_ill_reg1_slverr = 0, cov_ill_reg2_slverr = 0;
  integer cov_ill_reg3_okay = 0,   cov_ill_inv_okay = 0;

  always @(posedge clk) begin
    if (rst_n && b_hs) begin

      // Address bins
      case (cov_waddr)
        4'h0: cov_wr_reg0    <= cov_wr_reg0    + 1;
        4'h4: cov_wr_reg1    <= cov_wr_reg1    + 1;
        4'h8: cov_wr_reg2    <= cov_wr_reg2    + 1;
        4'hC: cov_wr_reg3    <= cov_wr_reg3    + 1;
        default: cov_wr_invalid <= cov_wr_invalid + 1;
      endcase

      // Response bins
      if (s_bresp == 2'b00) cov_wr_okay   <= cov_wr_okay   + 1;
      if (s_bresp == 2'b10) cov_wr_slverr <= cov_wr_slverr + 1;

      // Cross: addr x resp — legal
      if (cov_waddr == 4'h0 && s_bresp == 2'b00) cov_cx_reg0_okay   <= cov_cx_reg0_okay   + 1;
      if (cov_waddr == 4'h4 && s_bresp == 2'b00) cov_cx_reg1_okay   <= cov_cx_reg1_okay   + 1;
      if (cov_waddr == 4'h8 && s_bresp == 2'b00) cov_cx_reg2_okay   <= cov_cx_reg2_okay   + 1;
      if (cov_waddr == 4'hC && s_bresp == 2'b10) cov_cx_reg3_slverr <= cov_cx_reg3_slverr + 1;
      if (wr_addr_inv       && s_bresp == 2'b10) cov_cx_inv_slverr  <= cov_cx_inv_slverr  + 1;

      // Cross: illegal combinations — these should stay 0
      if (cov_waddr == 4'h0 && s_bresp == 2'b10) begin
        cov_ill_reg0_slverr <= cov_ill_reg0_slverr + 1;
        $display("[COV ILLEGAL] REG0 write returned SLVERR at %0t", $time);
      end
      if (cov_waddr == 4'h4 && s_bresp == 2'b10) begin
        cov_ill_reg1_slverr <= cov_ill_reg1_slverr + 1;
        $display("[COV ILLEGAL] REG1 write returned SLVERR at %0t", $time);
      end
      if (cov_waddr == 4'h8 && s_bresp == 2'b10) begin
        cov_ill_reg2_slverr <= cov_ill_reg2_slverr + 1;
        $display("[COV ILLEGAL] REG2 write returned SLVERR at %0t", $time);
      end
      if (cov_waddr == 4'hC && s_bresp == 2'b00) begin
        cov_ill_reg3_okay <= cov_ill_reg3_okay + 1;
        $display("[COV ILLEGAL] REG3 (R/O) write returned OKAY at %0t", $time);
      end
      if (wr_addr_inv && s_bresp == 2'b00) begin
        cov_ill_inv_okay <= cov_ill_inv_okay + 1;
        $display("[COV ILLEGAL] Invalid-address write 0x%h returned OKAY at %0t",
                 cov_waddr, $time);
      end

    end
  end

  // Write data patterns — information only, not counted.
  // Sampled at the W handshake, when WDATA is the real data.
  integer cov_wr_allzero = 0, cov_wr_allones = 0;

  always @(posedge clk) begin
    if (rst_n && w_hs) begin
      if (s_wdata == 32'h0000_0000) cov_wr_allzero <= cov_wr_allzero + 1;
      if (s_wdata == 32'hFFFF_FFFF) cov_wr_allones <= cov_wr_allones + 1;
    end
  end

  // ──────────────────────────────────────────────────────
  // COVERAGE GROUP 2 — Read Transactions (13 bins)
  // Sampled at R-channel handshake:
  //   5 address bins, 2 response bins, 5 legal addr x resp,
  //   1 REG3 x DEADBEEF
  // ──────────────────────────────────────────────────────
  integer cov_rd_reg0 = 0, cov_rd_reg1 = 0, cov_rd_reg2 = 0;
  integer cov_rd_reg3 = 0, cov_rd_invalid = 0;
  integer cov_rd_okay = 0, cov_rd_slverr = 0;
  integer cov_rd_deadbeef = 0, cov_rd_zero = 0;     // info only
  integer cov_cx_rdreg0_okay = 0, cov_cx_rdreg1_okay = 0, cov_cx_rdreg2_okay = 0;
  integer cov_cx_rdreg3_okay = 0, cov_cx_rdinv_slverr = 0;
  integer cov_cx_reg3_deadbeef = 0;
  integer cov_ill_rdreg3_slverr = 0;                 // should stay 0

  always @(posedge clk) begin
    if (rst_n && r_hs) begin

      // Address bins
      case (cov_raddr)
        4'h0: cov_rd_reg0    <= cov_rd_reg0    + 1;
        4'h4: cov_rd_reg1    <= cov_rd_reg1    + 1;
        4'h8: cov_rd_reg2    <= cov_rd_reg2    + 1;
        4'hC: cov_rd_reg3    <= cov_rd_reg3    + 1;
        default: cov_rd_invalid <= cov_rd_invalid + 1;
      endcase

      // Response bins
      if (s_rresp == 2'b00) cov_rd_okay   <= cov_rd_okay   + 1;
      if (s_rresp == 2'b10) cov_rd_slverr <= cov_rd_slverr + 1;

      // Data pattern bins (info only)
      if (s_rdata == 32'hDEAD_BEEF) cov_rd_deadbeef <= cov_rd_deadbeef + 1;
      if (s_rdata == 32'h0000_0000) cov_rd_zero     <= cov_rd_zero     + 1;

      // Cross: addr x resp
      if (cov_raddr == 4'h0 && s_rresp == 2'b00) cov_cx_rdreg0_okay  <= cov_cx_rdreg0_okay  + 1;
      if (cov_raddr == 4'h4 && s_rresp == 2'b00) cov_cx_rdreg1_okay  <= cov_cx_rdreg1_okay  + 1;
      if (cov_raddr == 4'h8 && s_rresp == 2'b00) cov_cx_rdreg2_okay  <= cov_cx_rdreg2_okay  + 1;
      if (cov_raddr == 4'hC && s_rresp == 2'b00) cov_cx_rdreg3_okay  <= cov_cx_rdreg3_okay  + 1;
      if (rd_addr_inv       && s_rresp == 2'b10) cov_cx_rdinv_slverr <= cov_cx_rdinv_slverr + 1;

      // REG3 must return DEADBEEF
      if (cov_raddr == 4'hC && s_rdata == 32'hDEAD_BEEF)
        cov_cx_reg3_deadbeef <= cov_cx_reg3_deadbeef + 1;

      // Illegal: REG3 read should never get SLVERR
      if (cov_raddr == 4'hC && s_rresp == 2'b10) begin
        cov_ill_rdreg3_slverr <= cov_ill_rdreg3_slverr + 1;
        $display("[COV ILLEGAL] REG3 read returned SLVERR at %0t", $time);
      end

    end
  end

  // ──────────────────────────────────────────────────────
  // COVERAGE GROUP 3 — Write Byte Strobes (7 bins)
  // Sampled at W-channel handshake
  // ──────────────────────────────────────────────────────
  integer cov_strb_byte0 = 0, cov_strb_byte1 = 0, cov_strb_byte2 = 0, cov_strb_byte3 = 0;
  integer cov_strb_low_half = 0, cov_strb_high_half = 0, cov_strb_full = 0;
  integer cov_strb_other = 0;                        // info only

  always @(posedge clk) begin
    if (rst_n && w_hs) begin
      case (s_wstrb)
        4'b0001: cov_strb_byte0     <= cov_strb_byte0     + 1;
        4'b0010: cov_strb_byte1     <= cov_strb_byte1     + 1;
        4'b0100: cov_strb_byte2     <= cov_strb_byte2     + 1;
        4'b1000: cov_strb_byte3     <= cov_strb_byte3     + 1;
        4'b0011: cov_strb_low_half  <= cov_strb_low_half  + 1;
        4'b1100: cov_strb_high_half <= cov_strb_high_half + 1;
        4'b1111: cov_strb_full      <= cov_strb_full      + 1;
        default: cov_strb_other     <= cov_strb_other     + 1;
      endcase
    end
  end

  // ──────────────────────────────────────────────────────
  // COVERAGE GROUP 4 — Back-pressure Timing (6 bins)
  // Edges BVALID/RVALID waited with READY low before the
  // handshake: 0 (immediate), exactly 1, or 2+.
  // ──────────────────────────────────────────────────────
  integer cov_b_imm = 0, cov_b_1cyc = 0, cov_b_multi = 0;   // BVALID wait cycles
  integer cov_r_imm = 0, cov_r_1cyc = 0, cov_r_multi = 0;   // RVALID wait cycles
  integer b_wait_cnt = 0, r_wait_cnt = 0;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      b_wait_cnt <= 0;
      r_wait_cnt <= 0;
    end else begin
      if (s_bvalid && !s_bready) b_wait_cnt <= b_wait_cnt + 1;
      else if (b_hs)             b_wait_cnt <= 0;
      if (s_rvalid && !s_rready) r_wait_cnt <= r_wait_cnt + 1;
      else if (r_hs)             r_wait_cnt <= 0;
    end
  end

  always @(posedge clk) begin
    if (rst_n && b_hs) begin
      if      (b_wait_cnt == 0)   cov_b_imm   <= cov_b_imm   + 1;
      else if (b_wait_cnt == 1)   cov_b_1cyc  <= cov_b_1cyc  + 1;
      else                        cov_b_multi <= cov_b_multi + 1;
    end
    if (rst_n && r_hs) begin
      if      (r_wait_cnt == 0)   cov_r_imm   <= cov_r_imm   + 1;
      else if (r_wait_cnt == 1)   cov_r_1cyc  <= cov_r_1cyc  + 1;
      else                        cov_r_multi <= cov_r_multi + 1;
    end
  end

  // ──────────────────────────────────────────────────────
  // COVERAGE GROUP 5 — Transaction Sequence Patterns (4 bins)
  // Defined for THIS DUT, whose AWREADY/ARREADY are
  // registered: READY rises on the edge after VALID is
  // first seen with the channel free, and the handshake
  // happens one edge later.
  //
  //   b2b write : AW handshake exactly 2 edges after a B
  //               handshake. The DUT frees its write channel
  //               on the B edge N, so AWREADY can rise at
  //               N+1 and the next AW handshake can't be
  //               earlier than N+2: this is the max rate.
  //   b2b read  : AR handshake exactly 2 edges after an R
  //               handshake (rd_pending_r clears on the R
  //               edge, same reasoning).
  //   wr->rd    : ordered write then read: an AR handshake 1
  //               or 2 edges after a B handshake, for a read
  //               whose ARVALID was NOT raised during the
  //               write. Ordered masters get N+2 at best.
  //   rd||wr    : read overlapping a write: ARVALID was high
  //               on an edge while a write was in progress
  //               (AWVALID/WVALID high, or AW/W handshaken
  //               and B not yet accepted). Counted at that
  //               read's AR handshake; excluded from wr->rd.
  // ──────────────────────────────────────────────────────
  integer cov_seq_b2b_write = 0, cov_seq_b2b_read = 0;
  integer cov_seq_wr_then_rd = 0, cov_seq_rd_ovl_wr = 0;

  logic b_hs_d1, b_hs_d2;      // B handshake 1 / 2 edges ago
  logic r_hs_d1, r_hs_d2;      // R handshake 1 / 2 edges ago
  logic wr_inflight;           // AW or W handshaken, B not yet accepted
  logic rd_overlap;            // pending read's ARVALID seen during a write

  wire wr_in_progress = wr_inflight || s_awvalid || s_wvalid;
  wire rd_overlap_now = rd_overlap || (s_arvalid && wr_in_progress);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      b_hs_d1     <= 1'b0;
      b_hs_d2     <= 1'b0;
      r_hs_d1     <= 1'b0;
      r_hs_d2     <= 1'b0;
      wr_inflight <= 1'b0;
      rd_overlap  <= 1'b0;
    end else begin
      b_hs_d1 <= b_hs;
      b_hs_d2 <= b_hs_d1;
      r_hs_d1 <= r_hs;
      r_hs_d2 <= r_hs_d1;

      if (aw_hs || w_hs) wr_inflight <= 1'b1;
      if (b_hs)          wr_inflight <= 1'b0;

      if (s_arvalid && wr_in_progress) rd_overlap <= 1'b1;
      if (ar_hs)                       rd_overlap <= 1'b0;
    end
  end

  always @(posedge clk) begin
    if (rst_n) begin
      if (aw_hs && b_hs_d2)
        cov_seq_b2b_write <= cov_seq_b2b_write + 1;
      if (ar_hs && r_hs_d2)
        cov_seq_b2b_read  <= cov_seq_b2b_read  + 1;
      if (ar_hs && rd_overlap_now)
        cov_seq_rd_ovl_wr <= cov_seq_rd_ovl_wr + 1;
      else if (ar_hs && (b_hs_d1 || b_hs_d2))
        cov_seq_wr_then_rd <= cov_seq_wr_then_rd + 1;
    end
  end

  // ──────────────────────────────────────────────────────
  // Print coverage report
  // ──────────────────────────────────────────────────────
  integer n_gaps;

  task gap;                    // list one unhit bin
    input string  name;
    input integer hits;
    begin
      if (hits == 0) begin
        $display("    - [%0s]", name);
        n_gaps = n_gaps + 1;
      end
    end
  endtask

  task automatic print_coverage();
    integer h1, h2, h3, h4, h5, hit_all, bins_all;
    real    p1, p2, p3, p4, p5, avg_cov, all_cov;

    h1 = (cov_wr_reg0 > 0) + (cov_wr_reg1 > 0) + (cov_wr_reg2 > 0) +
         (cov_wr_reg3 > 0) + (cov_wr_invalid > 0) +
         (cov_wr_okay > 0) + (cov_wr_slverr > 0) +
         (cov_cx_reg0_okay > 0) + (cov_cx_reg1_okay > 0) + (cov_cx_reg2_okay > 0) +
         (cov_cx_reg3_slverr > 0) + (cov_cx_inv_slverr > 0);
    h2 = (cov_rd_reg0 > 0) + (cov_rd_reg1 > 0) + (cov_rd_reg2 > 0) +
         (cov_rd_reg3 > 0) + (cov_rd_invalid > 0) +
         (cov_rd_okay > 0) + (cov_rd_slverr > 0) +
         (cov_cx_rdreg0_okay > 0) + (cov_cx_rdreg1_okay > 0) + (cov_cx_rdreg2_okay > 0) +
         (cov_cx_rdreg3_okay > 0) + (cov_cx_rdinv_slverr > 0) +
         (cov_cx_reg3_deadbeef > 0);
    h3 = (cov_strb_byte0 > 0) + (cov_strb_byte1 > 0) + (cov_strb_byte2 > 0) +
         (cov_strb_byte3 > 0) + (cov_strb_low_half > 0) + (cov_strb_high_half > 0) +
         (cov_strb_full > 0);
    h4 = (cov_b_imm > 0) + (cov_b_1cyc > 0) + (cov_b_multi > 0) +
         (cov_r_imm > 0) + (cov_r_1cyc > 0) + (cov_r_multi > 0);
    h5 = (cov_seq_b2b_write > 0) + (cov_seq_b2b_read > 0) +
         (cov_seq_wr_then_rd > 0) + (cov_seq_rd_ovl_wr > 0);

    p1 = h1 * 100.0 / 12;
    p2 = h2 * 100.0 / 13;
    p3 = h3 * 100.0 / 7;
    p4 = h4 * 100.0 / 6;
    p5 = h5 * 100.0 / 4;
    hit_all  = h1 + h2 + h3 + h4 + h5;
    bins_all = 12 + 13 + 7 + 6 + 4;
    avg_cov  = (p1 + p2 + p3 + p4 + p5) / 5.0;
    all_cov  = hit_all * 100.0 / bins_all;

    $display("");
    $display("========================================");
    $display("  AXI4-Lite Functional Coverage Report");
    $display("========================================");

    $display("\n  [1] Write Transactions  : %0.1f%% (%0d/12 bins)", p1, h1);
    $display("      REG0 writes         : %0d", cov_wr_reg0);
    $display("      REG1 writes         : %0d", cov_wr_reg1);
    $display("      REG2 writes         : %0d", cov_wr_reg2);
    $display("      REG3 writes (R/O)   : %0d", cov_wr_reg3);
    $display("      Invalid wr addr     : %0d", cov_wr_invalid);
    $display("      OKAY responses      : %0d", cov_wr_okay);
    $display("      SLVERR responses    : %0d", cov_wr_slverr);
    $display("      x REG0/1/2 OKAY     : %0d / %0d / %0d",
             cov_cx_reg0_okay, cov_cx_reg1_okay, cov_cx_reg2_okay);
    $display("      x REG3 SLVERR       : %0d", cov_cx_reg3_slverr);
    $display("      x invalid SLVERR    : %0d", cov_cx_inv_slverr);
    if (cov_ill_reg0_slverr + cov_ill_reg1_slverr + cov_ill_reg2_slverr +
        cov_ill_reg3_okay + cov_ill_inv_okay > 0)
      $display("      !! ILLEGAL hits    : R0_SLVERR=%0d R1_SLVERR=%0d R2_SLVERR=%0d R3_OKAY=%0d INV_OKAY=%0d",
               cov_ill_reg0_slverr, cov_ill_reg1_slverr,
               cov_ill_reg2_slverr, cov_ill_reg3_okay, cov_ill_inv_okay);

    $display("\n  [2] Read Transactions   : %0.1f%% (%0d/13 bins)", p2, h2);
    $display("      REG0 reads          : %0d", cov_rd_reg0);
    $display("      REG1 reads          : %0d", cov_rd_reg1);
    $display("      REG2 reads          : %0d", cov_rd_reg2);
    $display("      REG3 reads          : %0d", cov_rd_reg3);
    $display("      Invalid rd addr     : %0d", cov_rd_invalid);
    $display("      OKAY responses      : %0d", cov_rd_okay);
    $display("      SLVERR responses    : %0d", cov_rd_slverr);
    $display("      x REG0/1/2/3 OKAY   : %0d / %0d / %0d / %0d",
             cov_cx_rdreg0_okay, cov_cx_rdreg1_okay,
             cov_cx_rdreg2_okay, cov_cx_rdreg3_okay);
    $display("      x invalid SLVERR    : %0d", cov_cx_rdinv_slverr);
    $display("      x REG3 = DEADBEEF   : %0d", cov_cx_reg3_deadbeef);
    if (cov_ill_rdreg3_slverr > 0)
      $display("      !! ILLEGAL hits    : R3_SLVERR=%0d", cov_ill_rdreg3_slverr);

    $display("\n  [3] Write Byte Strobes  : %0.1f%% (%0d/7 bins)", p3, h3);
    $display("      byte0 only (4'h1)   : %0d", cov_strb_byte0);
    $display("      byte1 only (4'h2)   : %0d", cov_strb_byte1);
    $display("      byte2 only (4'h4)   : %0d", cov_strb_byte2);
    $display("      byte3 only (4'h8)   : %0d", cov_strb_byte3);
    $display("      low  half  (4'h3)   : %0d", cov_strb_low_half);
    $display("      high half  (4'hC)   : %0d", cov_strb_high_half);
    $display("      full word  (4'hF)   : %0d", cov_strb_full);

    $display("\n  [4] Back-pressure       : %0.1f%% (%0d/6 bins)", p4, h4);
    $display("      B immediate         : %0d", cov_b_imm);
    $display("      B 1-cycle wait      : %0d", cov_b_1cyc);
    $display("      B multi-cycle wait  : %0d", cov_b_multi);
    $display("      R immediate         : %0d", cov_r_imm);
    $display("      R 1-cycle wait      : %0d", cov_r_1cyc);
    $display("      R multi-cycle wait  : %0d", cov_r_multi);

    $display("\n  [5] Sequence Patterns   : %0.1f%% (%0d/4 bins)", p5, h5);
    $display("      B2B writes (B->AW 2 edges) : %0d", cov_seq_b2b_write);
    $display("      B2B reads  (R->AR 2 edges) : %0d", cov_seq_b2b_read);
    $display("      Write then read (ordered)  : %0d", cov_seq_wr_then_rd);
    $display("      Read overlapping a write   : %0d", cov_seq_rd_ovl_wr);

    $display("\n  Info only (not counted as bins):");
    $display("      write data all-zero : %0d", cov_wr_allzero);
    $display("      write data all-ones : %0d", cov_wr_allones);
    $display("      read data all-zero  : %0d", cov_rd_zero);
    $display("      read data DEADBEEF  : %0d", cov_rd_deadbeef);
    $display("      other WSTRB values  : %0d", cov_strb_other);

    $display("\n----------------------------------------");
    $display("  TOTAL (average of 5 groups) : %0.1f%%", avg_cov);
    $display("  TOTAL (bins hit / all bins) : %0.1f%% (%0d/%0d)",
             all_cov, hit_all, bins_all);
    $display("========================================");

    // Gaps: every counted bin with zero hits
    $display("\n  Gaps to improve:");
    n_gaps = 0;
    gap("G1 REG0 write",            cov_wr_reg0);
    gap("G1 REG1 write",            cov_wr_reg1);
    gap("G1 REG2 write",            cov_wr_reg2);
    gap("G1 REG3 write",            cov_wr_reg3);
    gap("G1 invalid-address write", cov_wr_invalid);
    gap("G1 write OKAY",            cov_wr_okay);
    gap("G1 write SLVERR",          cov_wr_slverr);
    gap("G1 REG0 x OKAY",           cov_cx_reg0_okay);
    gap("G1 REG1 x OKAY",           cov_cx_reg1_okay);
    gap("G1 REG2 x OKAY",           cov_cx_reg2_okay);
    gap("G1 REG3 x SLVERR",         cov_cx_reg3_slverr);
    gap("G1 invalid x SLVERR",      cov_cx_inv_slverr);
    gap("G2 REG0 read",             cov_rd_reg0);
    gap("G2 REG1 read",             cov_rd_reg1);
    gap("G2 REG2 read",             cov_rd_reg2);
    gap("G2 REG3 read",             cov_rd_reg3);
    gap("G2 invalid-address read",  cov_rd_invalid);
    gap("G2 read OKAY",             cov_rd_okay);
    gap("G2 read SLVERR",           cov_rd_slverr);
    gap("G2 REG0 x OKAY",           cov_cx_rdreg0_okay);
    gap("G2 REG1 x OKAY",           cov_cx_rdreg1_okay);
    gap("G2 REG2 x OKAY",           cov_cx_rdreg2_okay);
    gap("G2 REG3 x OKAY",           cov_cx_rdreg3_okay);
    gap("G2 invalid x SLVERR",      cov_cx_rdinv_slverr);
    gap("G2 REG3 x DEADBEEF",       cov_cx_reg3_deadbeef);
    gap("G3 WSTRB 4'h1",            cov_strb_byte0);
    gap("G3 WSTRB 4'h2",            cov_strb_byte1);
    gap("G3 WSTRB 4'h4",            cov_strb_byte2);
    gap("G3 WSTRB 4'h8",            cov_strb_byte3);
    gap("G3 WSTRB 4'h3",            cov_strb_low_half);
    gap("G3 WSTRB 4'hC",            cov_strb_high_half);
    gap("G3 WSTRB 4'hF",            cov_strb_full);
    gap("G4 B immediate",           cov_b_imm);
    gap("G4 B 1-cycle wait",        cov_b_1cyc);
    gap("G4 B multi-cycle wait",    cov_b_multi);
    gap("G4 R immediate",           cov_r_imm);
    gap("G4 R 1-cycle wait",        cov_r_1cyc);
    gap("G4 R multi-cycle wait",    cov_r_multi);
    gap("G5 back-to-back writes",   cov_seq_b2b_write);
    gap("G5 back-to-back reads",    cov_seq_b2b_read);
    gap("G5 write then read",       cov_seq_wr_then_rd);
    gap("G5 read overlapping write", cov_seq_rd_ovl_wr);
    if (n_gaps == 0)
      $display("    (none: all %0d counted bins hit)", bins_all);
    $display("");

  endtask

endmodule : axi_lite_coverage
