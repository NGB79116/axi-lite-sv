// ============================================================
// Module  : axi_lite_coverage
// Purpose : Functional coverage monitor for axi_lite_slave
//           Written for Icarus Verilog (iverilog) compatibility.
//           No covergroup — uses integer counters + always blocks.
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
// ============================================================

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

  // Latch write address at AW handshake (mirrors DUT behavior)
  logic [ADDR_W-1:0] cov_waddr;
  logic [ADDR_W-1:0] cov_raddr;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cov_waddr <= '0;
      cov_raddr <= '0;
    end else begin
      if (aw_hs) cov_waddr <= s_awaddr;
      if (ar_hs) cov_raddr <= s_araddr;
    end
  end

  // ──────────────────────────────────────────────────────
  // COVERAGE GROUP 1 — Write Transactions
  // Sampled at B-channel handshake
  // ──────────────────────────────────────────────────────

  // Which registers were written
  integer cov_wr_reg0,  cov_wr_reg1,  cov_wr_reg2;
  integer cov_wr_reg3,  cov_wr_invalid;
  // Which responses were seen
  integer cov_wr_okay,  cov_wr_slverr;
  // Data edge cases
  integer cov_wr_allzero, cov_wr_allones;
  // Cross: addr x resp (legal combinations)
  integer cov_cx_reg0_okay,  cov_cx_reg1_okay,  cov_cx_reg2_okay;
  integer cov_cx_reg3_slverr, cov_cx_inv_slverr;
  // Illegal cross hits (should stay 0)
  integer cov_ill_reg0_slverr, cov_ill_reg1_slverr, cov_ill_reg2_slverr;
  integer cov_ill_reg3_okay,   cov_ill_inv_okay;

  initial begin
    cov_wr_reg0=0; cov_wr_reg1=0; cov_wr_reg2=0;
    cov_wr_reg3=0; cov_wr_invalid=0;
    cov_wr_okay=0; cov_wr_slverr=0;
    cov_wr_allzero=0; cov_wr_allones=0;
    cov_cx_reg0_okay=0; cov_cx_reg1_okay=0; cov_cx_reg2_okay=0;
    cov_cx_reg3_slverr=0; cov_cx_inv_slverr=0;
    cov_ill_reg0_slverr=0; cov_ill_reg1_slverr=0; cov_ill_reg2_slverr=0;
    cov_ill_reg3_okay=0; cov_ill_inv_okay=0;
  end

  always_ff @(posedge clk) begin
    if (rst_n && b_hs) begin

      // Address bins
      case (cov_waddr)
        4'h0: cov_wr_reg0    = cov_wr_reg0    + 1;
        4'h4: cov_wr_reg1    = cov_wr_reg1    + 1;
        4'h8: cov_wr_reg2    = cov_wr_reg2    + 1;
        4'hC: cov_wr_reg3    = cov_wr_reg3    + 1;
        default: cov_wr_invalid = cov_wr_invalid + 1;
      endcase

      // Response bins
      if (s_bresp == 2'b00) cov_wr_okay   = cov_wr_okay   + 1;
      if (s_bresp == 2'b10) cov_wr_slverr = cov_wr_slverr + 1;

      // Data pattern bins (sample at B time — wdata was latched)
      if (s_wdata == 32'h0000_0000) cov_wr_allzero = cov_wr_allzero + 1;
      if (s_wdata == 32'hFFFF_FFFF) cov_wr_allones  = cov_wr_allones  + 1;

      // Cross: addr x resp — legal
      if (cov_waddr == 4'h0 && s_bresp == 2'b00) cov_cx_reg0_okay    = cov_cx_reg0_okay    + 1;
      if (cov_waddr == 4'h4 && s_bresp == 2'b00) cov_cx_reg1_okay    = cov_cx_reg1_okay    + 1;
      if (cov_waddr == 4'h8 && s_bresp == 2'b00) cov_cx_reg2_okay    = cov_cx_reg2_okay    + 1;
      if (cov_waddr == 4'hC && s_bresp == 2'b10) cov_cx_reg3_slverr  = cov_cx_reg3_slverr  + 1;
      if (cov_waddr  > 4'h8 && cov_waddr != 4'hC && s_bresp == 2'b10)
        cov_cx_inv_slverr = cov_cx_inv_slverr + 1;

      // Cross: illegal combinations — these should stay 0
      if (cov_waddr == 4'h0 && s_bresp == 2'b10) begin
        cov_ill_reg0_slverr = cov_ill_reg0_slverr + 1;
        $display("[COV ILLEGAL] REG0 write returned SLVERR at %0t", $time);
      end
      if (cov_waddr == 4'h4 && s_bresp == 2'b10) begin
        cov_ill_reg1_slverr = cov_ill_reg1_slverr + 1;
        $display("[COV ILLEGAL] REG1 write returned SLVERR at %0t", $time);
      end
      if (cov_waddr == 4'h8 && s_bresp == 2'b10) begin
        cov_ill_reg2_slverr = cov_ill_reg2_slverr + 1;
        $display("[COV ILLEGAL] REG2 write returned SLVERR at %0t", $time);
      end
      if (cov_waddr == 4'hC && s_bresp == 2'b00) begin
        cov_ill_reg3_okay = cov_ill_reg3_okay + 1;
        $display("[COV ILLEGAL] REG3 (R/O) write returned OKAY at %0t", $time);
      end

    end
  end

  // ──────────────────────────────────────────────────────
  // COVERAGE GROUP 2 — Read Transactions
  // Sampled at R-channel handshake
  // ──────────────────────────────────────────────────────

  integer cov_rd_reg0, cov_rd_reg1, cov_rd_reg2;
  integer cov_rd_reg3, cov_rd_invalid;
  integer cov_rd_okay, cov_rd_slverr;
  integer cov_rd_deadbeef, cov_rd_zero;
  integer cov_cx_rdreg0_okay, cov_cx_rdreg1_okay, cov_cx_rdreg2_okay;
  integer cov_cx_rdreg3_okay, cov_cx_rdinv_slverr;
  integer cov_ill_rdreg3_slverr;
  integer cov_cx_reg3_deadbeef;

  initial begin
    cov_rd_reg0=0; cov_rd_reg1=0; cov_rd_reg2=0;
    cov_rd_reg3=0; cov_rd_invalid=0;
    cov_rd_okay=0; cov_rd_slverr=0;
    cov_rd_deadbeef=0; cov_rd_zero=0;
    cov_cx_rdreg0_okay=0; cov_cx_rdreg1_okay=0; cov_cx_rdreg2_okay=0;
    cov_cx_rdreg3_okay=0; cov_cx_rdinv_slverr=0;
    cov_ill_rdreg3_slverr=0; cov_cx_reg3_deadbeef=0;
  end

  always_ff @(posedge clk) begin
    if (rst_n && r_hs) begin

      // Address bins
      case (cov_raddr)
        4'h0: cov_rd_reg0    = cov_rd_reg0    + 1;
        4'h4: cov_rd_reg1    = cov_rd_reg1    + 1;
        4'h8: cov_rd_reg2    = cov_rd_reg2    + 1;
        4'hC: cov_rd_reg3    = cov_rd_reg3    + 1;
        default: cov_rd_invalid = cov_rd_invalid + 1;
      endcase

      // Response bins
      if (s_rresp == 2'b00) cov_rd_okay   = cov_rd_okay   + 1;
      if (s_rresp == 2'b10) cov_rd_slverr = cov_rd_slverr + 1;

      // Data pattern bins
      if (s_rdata == 32'hDEAD_BEEF) cov_rd_deadbeef = cov_rd_deadbeef + 1;
      if (s_rdata == 32'h0000_0000) cov_rd_zero      = cov_rd_zero     + 1;

      // Cross: addr x resp
      if (cov_raddr == 4'h0 && s_rresp == 2'b00) cov_cx_rdreg0_okay  = cov_cx_rdreg0_okay  + 1;
      if (cov_raddr == 4'h4 && s_rresp == 2'b00) cov_cx_rdreg1_okay  = cov_cx_rdreg1_okay  + 1;
      if (cov_raddr == 4'h8 && s_rresp == 2'b00) cov_cx_rdreg2_okay  = cov_cx_rdreg2_okay  + 1;
      if (cov_raddr == 4'hC && s_rresp == 2'b00) cov_cx_rdreg3_okay  = cov_cx_rdreg3_okay  + 1;
      if (cov_raddr != 4'h0 && cov_raddr != 4'h4 &&
          cov_raddr != 4'h8 && cov_raddr != 4'hC &&
          s_rresp == 2'b10)                       cov_cx_rdinv_slverr = cov_cx_rdinv_slverr + 1;

      // REG3 must return DEADBEEF
      if (cov_raddr == 4'hC && s_rdata == 32'hDEAD_BEEF)
        cov_cx_reg3_deadbeef = cov_cx_reg3_deadbeef + 1;

      // Illegal: REG3 read should never get SLVERR
      if (cov_raddr == 4'hC && s_rresp == 2'b10) begin
        cov_ill_rdreg3_slverr = cov_ill_rdreg3_slverr + 1;
        $display("[COV ILLEGAL] REG3 read returned SLVERR at %0t", $time);
      end

    end
  end

  // ──────────────────────────────────────────────────────
  // COVERAGE GROUP 3 — Write Byte Strobes
  // Sampled at W-channel handshake
  // ──────────────────────────────────────────────────────

  integer cov_strb_byte0, cov_strb_byte1, cov_strb_byte2, cov_strb_byte3;
  integer cov_strb_low_half, cov_strb_high_half, cov_strb_full, cov_strb_other;

  initial begin
    cov_strb_byte0=0; cov_strb_byte1=0; cov_strb_byte2=0; cov_strb_byte3=0;
    cov_strb_low_half=0; cov_strb_high_half=0; cov_strb_full=0; cov_strb_other=0;
  end

  always_ff @(posedge clk) begin
    if (rst_n && w_hs) begin
      case (s_wstrb)
        4'b0001: cov_strb_byte0     = cov_strb_byte0     + 1;
        4'b0010: cov_strb_byte1     = cov_strb_byte1     + 1;
        4'b0100: cov_strb_byte2     = cov_strb_byte2     + 1;
        4'b1000: cov_strb_byte3     = cov_strb_byte3     + 1;
        4'b0011: cov_strb_low_half  = cov_strb_low_half  + 1;
        4'b1100: cov_strb_high_half = cov_strb_high_half + 1;
        4'b1111: cov_strb_full      = cov_strb_full      + 1;
        default: cov_strb_other     = cov_strb_other     + 1;
      endcase
    end
  end

  // ──────────────────────────────────────────────────────
  // COVERAGE GROUP 4 — Back-pressure Timing
  // How many cycles before BREADY/RREADY asserted
  // ──────────────────────────────────────────────────────

  integer cov_b_imm,  cov_b_1cyc,  cov_b_multi;   // BVALID wait cycles
  integer cov_r_imm,  cov_r_1cyc,  cov_r_multi;   // RVALID wait cycles
  integer b_wait_cnt, r_wait_cnt;

  initial begin
    cov_b_imm=0; cov_b_1cyc=0; cov_b_multi=0;
    cov_r_imm=0; cov_r_1cyc=0; cov_r_multi=0;
    b_wait_cnt=0; r_wait_cnt=0;
  end

  always_ff @(posedge clk or negedge rst_n) begin
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

  always_ff @(posedge clk) begin
    if (rst_n && b_hs) begin
      if      (b_wait_cnt == 0)   cov_b_imm   = cov_b_imm   + 1;
      else if (b_wait_cnt == 1)   cov_b_1cyc  = cov_b_1cyc  + 1;
      else                        cov_b_multi = cov_b_multi  + 1;
    end
    if (rst_n && r_hs) begin
      if      (r_wait_cnt == 0)   cov_r_imm   = cov_r_imm   + 1;
      else if (r_wait_cnt == 1)   cov_r_1cyc  = cov_r_1cyc  + 1;
      else                        cov_r_multi = cov_r_multi  + 1;
    end
  end

  // ──────────────────────────────────────────────────────
  // COVERAGE GROUP 5 — Transaction Sequence Patterns
  // Tests 9 (back-to-back write), 10 (b2b read), 11 (wr→rd)
  // ──────────────────────────────────────────────────────

  integer cov_seq_b2b_write, cov_seq_b2b_read, cov_seq_wr_then_rd;
  logic   prev_b_hs, prev_r_hs;

  initial begin
    cov_seq_b2b_write=0; cov_seq_b2b_read=0; cov_seq_wr_then_rd=0;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      prev_b_hs <= 1'b0;
      prev_r_hs <= 1'b0;
    end else begin
      prev_b_hs <= b_hs;
      prev_r_hs <= r_hs;
    end
  end

  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (prev_b_hs && aw_hs) cov_seq_b2b_write   = cov_seq_b2b_write   + 1;
      if (prev_r_hs && ar_hs) cov_seq_b2b_read     = cov_seq_b2b_read    + 1;
      if (prev_b_hs && ar_hs) cov_seq_wr_then_rd   = cov_seq_wr_then_rd  + 1;
    end
  end

  // ──────────────────────────────────────────────────────
  // Coverage percentage helpers
  // hit/total gives the % for each bin group
  // ──────────────────────────────────────────────────────
  function automatic real pct(input integer hit, input integer total);
    if (total == 0) return 0.0;
    return (hit * 100.0) / total;
  endfunction

  function automatic real bins_hit(
    input integer b0, b1, b2, b3, b4, b5, b6, b7,
    input integer total_bins);
    integer hit;
    hit = (b0>0)+(b1>0)+(b2>0)+(b3>0)+(b4>0)+(b5>0)+(b6>0)+(b7>0);
    return (hit * 100.0) / total_bins;
  endfunction

  // ──────────────────────────────────────────────────────
  // Print coverage report
  // ──────────────────────────────────────────────────────
  task automatic print_coverage();
    real wr_cov, rd_cov, strb_cov, bp_cov, seq_cov, total_cov;

    // Write coverage: 5 addr bins + 2 resp bins + 5 legal cross bins = 12 bins
    // Count which bins were hit
    wr_cov = bins_hit(
      (cov_wr_reg0    > 0) ? 1 : 0,
      (cov_wr_reg1    > 0) ? 1 : 0,
      (cov_wr_reg2    > 0) ? 1 : 0,
      (cov_wr_reg3    > 0) ? 1 : 0,
      (cov_wr_invalid > 0) ? 1 : 0,
      (cov_wr_okay    > 0) ? 1 : 0,
      (cov_wr_slverr  > 0) ? 1 : 0,
      0, 7);

    // Read coverage: 5 addr bins + 2 resp bins = 7 bins
    rd_cov = bins_hit(
      (cov_rd_reg0    > 0) ? 1 : 0,
      (cov_rd_reg1    > 0) ? 1 : 0,
      (cov_rd_reg2    > 0) ? 1 : 0,
      (cov_rd_reg3    > 0) ? 1 : 0,
      (cov_rd_invalid > 0) ? 1 : 0,
      (cov_rd_okay    > 0) ? 1 : 0,
      (cov_rd_slverr  > 0) ? 1 : 0,
      0, 7);

    // Strobe coverage: 7 bins
    strb_cov = bins_hit(
      (cov_strb_byte0     > 0) ? 1 : 0,
      (cov_strb_byte1     > 0) ? 1 : 0,
      (cov_strb_byte2     > 0) ? 1 : 0,
      (cov_strb_byte3     > 0) ? 1 : 0,
      (cov_strb_low_half  > 0) ? 1 : 0,
      (cov_strb_high_half > 0) ? 1 : 0,
      (cov_strb_full      > 0) ? 1 : 0,
      0, 7);

    // Back-pressure: 6 bins (3 write + 3 read)
    bp_cov = bins_hit(
      (cov_b_imm   > 0) ? 1 : 0,
      (cov_b_1cyc  > 0) ? 1 : 0,
      (cov_b_multi > 0) ? 1 : 0,
      (cov_r_imm   > 0) ? 1 : 0,
      (cov_r_1cyc  > 0) ? 1 : 0,
      (cov_r_multi > 0) ? 1 : 0,
      0, 0, 6);

    // Sequence: 3 bins
    seq_cov = bins_hit(
      (cov_seq_b2b_write  > 0) ? 1 : 0,
      (cov_seq_b2b_read   > 0) ? 1 : 0,
      (cov_seq_wr_then_rd > 0) ? 1 : 0,
      0, 0, 0, 0, 0, 3);

    total_cov = (wr_cov + rd_cov + strb_cov + bp_cov + seq_cov) / 5.0;

    $display("");
    $display("========================================");
    $display("  AXI4-Lite Functional Coverage Report");
    $display("========================================");

    $display("\n  [1] Write Transactions  : %0.1f%%", wr_cov);
    $display("      REG0 writes         : %0d", cov_wr_reg0);
    $display("      REG1 writes         : %0d", cov_wr_reg1);
    $display("      REG2 writes         : %0d", cov_wr_reg2);
    $display("      REG3 writes (R/O)   : %0d", cov_wr_reg3);
    $display("      Invalid wr addr     : %0d", cov_wr_invalid);
    $display("      OKAY responses      : %0d", cov_wr_okay);
    $display("      SLVERR responses    : %0d", cov_wr_slverr);
    if (cov_ill_reg0_slverr + cov_ill_reg1_slverr + cov_ill_reg2_slverr +
        cov_ill_reg3_okay > 0)
      $display("      !! ILLEGAL hits    : R0_SLVERR=%0d R1_SLVERR=%0d R2_SLVERR=%0d R3_OKAY=%0d",
               cov_ill_reg0_slverr, cov_ill_reg1_slverr,
               cov_ill_reg2_slverr, cov_ill_reg3_okay);

    $display("\n  [2] Read Transactions   : %0.1f%%", rd_cov);
    $display("      REG0 reads          : %0d", cov_rd_reg0);
    $display("      REG1 reads          : %0d", cov_rd_reg1);
    $display("      REG2 reads          : %0d", cov_rd_reg2);
    $display("      REG3 reads          : %0d", cov_rd_reg3);
    $display("      Invalid rd addr     : %0d", cov_rd_invalid);
    $display("      OKAY responses      : %0d", cov_rd_okay);
    $display("      SLVERR responses    : %0d", cov_rd_slverr);
    $display("      DEADBEEF returned   : %0d", cov_rd_deadbeef);

    $display("\n  [3] Write Byte Strobes  : %0.1f%%", strb_cov);
    $display("      byte0 only (4'h1)   : %0d", cov_strb_byte0);
    $display("      byte1 only (4'h2)   : %0d", cov_strb_byte1);
    $display("      byte2 only (4'h4)   : %0d", cov_strb_byte2);
    $display("      byte3 only (4'h8)   : %0d", cov_strb_byte3);
    $display("      low  half  (4'h3)   : %0d", cov_strb_low_half);
    $display("      high half  (4'hC)   : %0d", cov_strb_high_half);
    $display("      full word  (4'hF)   : %0d", cov_strb_full);

    $display("\n  [4] Back-pressure       : %0.1f%%", bp_cov);
    $display("      B immediate         : %0d", cov_b_imm);
    $display("      B 1-cycle wait      : %0d", cov_b_1cyc);
    $display("      B multi-cycle wait  : %0d", cov_b_multi);
    $display("      R immediate         : %0d", cov_r_imm);
    $display("      R 1-cycle wait      : %0d", cov_r_1cyc);
    $display("      R multi-cycle wait  : %0d", cov_r_multi);

    $display("\n  [5] Sequence Patterns   : %0.1f%%", seq_cov);
    $display("      Back-to-back writes : %0d", cov_seq_b2b_write);
    $display("      Back-to-back reads  : %0d", cov_seq_b2b_read);
    $display("      Write then read     : %0d", cov_seq_wr_then_rd);

    $display("\n----------------------------------------");
    $display("  TOTAL (avg bin coverage): %0.1f%%", total_cov);
    $display("========================================");

    // Gaps to close
    $display("\n  Gaps to improve:");
    if (cov_strb_byte1 == 0) $display("    - Add strobe test: 4'h2 (byte1 only)");
    if (cov_strb_byte2 == 0) $display("    - Add strobe test: 4'h4 (byte2 only)");
    if (cov_strb_byte3 == 0) $display("    - Add strobe test: 4'h8 (byte3 only)");
    if (cov_strb_low_half == 0)  $display("    - Add strobe test: 4'h3 (low half)");
    if (cov_strb_high_half == 0) $display("    - Add strobe test: 4'hC (high half)");
    if (cov_b_1cyc == 0 && cov_b_multi == 0)
      $display("    - Add delayed s_bready test (back-pressure)");
    if (cov_r_1cyc == 0 && cov_r_multi == 0)
      $display("    - Add delayed s_rready test (back-pressure)");
    $display("");

  endtask

endmodule : axi_lite_coverage
