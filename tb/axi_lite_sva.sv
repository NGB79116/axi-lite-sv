// ============================================================
// Module  : axi_lite_sva
// Purpose : Protocol assertion monitor for axi_lite_slave
//           Written for Icarus Verilog (iverilog) compatibility.
//           No SVA property/assert property — uses always blocks.
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

  integer sva_fail_count;
  integer sva_pass_count;

  initial begin
    sva_fail_count = 0;
    sva_pass_count = 0;
  end

  // ──────────────────────────────────────────────────────
  // Sticky VALID trackers
  // Once VALID goes high it must stay high until READY.
  // ──────────────────────────────────────────────────────
  logic aw_valid_saw;   // AWVALID was seen high
  logic w_valid_saw;    // WVALID  was seen high
  logic ar_valid_saw;   // ARVALID was seen high

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_valid_saw <= 1'b0;
      w_valid_saw  <= 1'b0;
      ar_valid_saw <= 1'b0;
    end else begin
      // Set sticky when VALID rises
      if (s_awvalid) aw_valid_saw <= 1'b1;
      if (s_wvalid)  w_valid_saw  <= 1'b1;
      if (s_arvalid) ar_valid_saw <= 1'b1;
      // Clear sticky on handshake
      if (s_awvalid && s_awready) aw_valid_saw <= 1'b0;
      if (s_wvalid  && s_wready)  w_valid_saw  <= 1'b0;
      if (s_arvalid && s_arready) ar_valid_saw <= 1'b0;
    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 1 — VALID Stability
  // ──────────────────────────────────────────────────────
  always_ff @(posedge clk) begin
    if (rst_n) begin

      // AWVALID must not drop before AWREADY
      if (aw_valid_saw && !s_awvalid && !s_awready) begin
        $display("[SVA FAIL] AWVALID dropped before AWREADY at time %0t", $time);
        sva_fail_count = sva_fail_count + 1;
      end

      // WVALID must not drop before WREADY
      if (w_valid_saw && !s_wvalid && !s_wready) begin
        $display("[SVA FAIL] WVALID dropped before WREADY at time %0t", $time);
        sva_fail_count = sva_fail_count + 1;
      end

      // ARVALID must not drop before ARREADY
      if (ar_valid_saw && !s_arvalid && !s_arready) begin
        $display("[SVA FAIL] ARVALID dropped before ARREADY at time %0t", $time);
        sva_fail_count = sva_fail_count + 1;
      end

    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 2 — Slave VALID Stability
  // BVALID and RVALID must hold until master accepts.
  // ──────────────────────────────────────────────────────
  logic bvalid_saw;
  logic rvalid_saw;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bvalid_saw <= 1'b0;
      rvalid_saw <= 1'b0;
    end else begin
      if (s_bvalid) bvalid_saw <= 1'b1;
      if (s_rvalid) rvalid_saw <= 1'b1;
      if (s_bvalid && s_bready) bvalid_saw <= 1'b0;
      if (s_rvalid && s_rready) rvalid_saw <= 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (rst_n) begin

      // BVALID must not drop before BREADY
      if (bvalid_saw && !s_bvalid && !s_bready) begin
        $display("[SVA FAIL] BVALID dropped before BREADY at time %0t", $time);
        sva_fail_count = sva_fail_count + 1;
      end

      // RVALID must not drop before RREADY
      if (rvalid_saw && !s_rvalid && !s_rready) begin
        $display("[SVA FAIL] RVALID dropped before RREADY at time %0t", $time);
        sva_fail_count = sva_fail_count + 1;
      end

    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 3 — Address & Data Stability
  // Must not change while VALID is high, READY not yet seen.
  // ──────────────────────────────────────────────────────
  logic [ADDR_W-1:0]   prev_awaddr;
  logic [ADDR_W-1:0]   prev_araddr;
  logic [DATA_W-1:0]   prev_wdata;
  logic [DATA_W/8-1:0] prev_wstrb;

  always_ff @(posedge clk) begin
    prev_awaddr <= s_awaddr;
    prev_araddr <= s_araddr;
    prev_wdata  <= s_wdata;
    prev_wstrb  <= s_wstrb;
  end

  always_ff @(posedge clk) begin
    if (rst_n) begin

      // AWADDR must be stable while AWVALID=1, AWREADY=0
      if (aw_valid_saw && s_awvalid && !s_awready &&
          prev_awaddr !== s_awaddr) begin
        $display("[SVA FAIL] AWADDR changed while AWVALID=1, AWREADY=0 at %0t", $time);
        sva_fail_count = sva_fail_count + 1;
      end

      // ARADDR must be stable while ARVALID=1, ARREADY=0
      if (ar_valid_saw && s_arvalid && !s_arready &&
          prev_araddr !== s_araddr) begin
        $display("[SVA FAIL] ARADDR changed while ARVALID=1, ARREADY=0 at %0t", $time);
        sva_fail_count = sva_fail_count + 1;
      end

      // WDATA must be stable while WVALID=1, WREADY=0
      if (w_valid_saw && s_wvalid && !s_wready &&
          prev_wdata !== s_wdata) begin
        $display("[SVA FAIL] WDATA changed while WVALID=1, WREADY=0 at %0t", $time);
        sva_fail_count = sva_fail_count + 1;
      end

      // WSTRB must be stable while WVALID=1, WREADY=0
      if (w_valid_saw && s_wvalid && !s_wready &&
          prev_wstrb !== s_wstrb) begin
        $display("[SVA FAIL] WSTRB changed while WVALID=1, WREADY=0 at %0t", $time);
        sva_fail_count = sva_fail_count + 1;
      end

    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 4 — Reset Behavior
  // All slave outputs must be deasserted cycle after reset.
  // ──────────────────────────────────────────────────────
  logic rst_n_prev;

  always_ff @(posedge clk) begin
    rst_n_prev <= rst_n;
  end

  always_ff @(posedge clk) begin
    if (rst_n && !rst_n_prev) begin
      // One cycle after reset deasserted
      if (s_bvalid) begin
        $display("[SVA FAIL] s_bvalid not 0 after reset at time %0t", $time);
        sva_fail_count = sva_fail_count + 1;
      end
      if (s_rvalid) begin
        $display("[SVA FAIL] s_rvalid not 0 after reset at time %0t", $time);
        sva_fail_count = sva_fail_count + 1;
      end
      if (s_awready) begin
        $display("[SVA FAIL] s_awready not 0 after reset at time %0t", $time);
        sva_fail_count = sva_fail_count + 1;
      end
      if (s_arready) begin
        $display("[SVA FAIL] s_arready not 0 after reset at time %0t", $time);
        sva_fail_count = sva_fail_count + 1;
      end
    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 5 — Response Code Legality
  // Only OKAY (2'b00) and SLVERR (2'b10) are valid.
  // ──────────────────────────────────────────────────────
  always_ff @(posedge clk) begin
    if (rst_n) begin

      if (s_bvalid && s_bresp !== 2'b00 && s_bresp !== 2'b10) begin
        $display("[SVA FAIL] Illegal BRESP=2'b%b at time %0t", s_bresp, $time);
        sva_fail_count = sva_fail_count + 1;
      end

      if (s_rvalid && s_rresp !== 2'b00 && s_rresp !== 2'b10) begin
        $display("[SVA FAIL] Illegal RRESP=2'b%b at time %0t", s_rresp, $time);
        sva_fail_count = sva_fail_count + 1;
      end

    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 6 — Register-specific Response Rules
  // Checks response within a window after address handshake.
  // Uses a simple shift-register delay to observe B/R channel.
  // ──────────────────────────────────────────────────────

  // Latch address at handshake moment
  logic [ADDR_W-1:0] chk_waddr;
  logic [ADDR_W-1:0] chk_raddr;
  logic chk_w_pending;
  logic chk_r_pending;

  always_ff @(posedge clk or negedge rst_n) begin
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

  always_ff @(posedge clk) begin
    if (rst_n && s_bvalid && chk_w_pending) begin

      // Valid R/W registers must return OKAY
      if ((chk_waddr == 4'h0 || chk_waddr == 4'h4 || chk_waddr == 4'h8) &&
           s_bresp !== 2'b00) begin
        $display("[SVA FAIL] Write to valid reg 0x%h returned BRESP=2'b%b (expected OKAY) at %0t",
                 chk_waddr, s_bresp, $time);
        sva_fail_count = sva_fail_count + 1;
      end else begin
        sva_pass_count = sva_pass_count + 1;
      end

      // REG3 write must return SLVERR
      if (chk_waddr == 4'hC && s_bresp !== 2'b10) begin
        $display("[SVA FAIL] Write to REG3 (R/O) returned BRESP=2'b%b (expected SLVERR) at %0t",
                 s_bresp, $time);
        sva_fail_count = sva_fail_count + 1;
      end else if (chk_waddr == 4'hC) begin
        sva_pass_count = sva_pass_count + 1;
      end

    end
  end

  always_ff @(posedge clk) begin
    if (rst_n && s_rvalid && chk_r_pending) begin

      // REG3 read must return OKAY
      if (chk_raddr == 4'hC && s_rresp !== 2'b00) begin
        $display("[SVA FAIL] Read from REG3 returned RRESP=2'b%b (expected OKAY) at %0t",
                 s_rresp, $time);
        sva_fail_count = sva_fail_count + 1;
      end

      // REG3 read must return DEADBEEF
      if (chk_raddr == 4'hC && s_rdata !== 32'hDEAD_BEEF) begin
        $display("[SVA FAIL] REG3 returned 0x%08h (expected 0xDEAD_BEEF) at %0t",
                 s_rdata, $time);
        sva_fail_count = sva_fail_count + 1;
      end else if (chk_raddr == 4'hC) begin
        sva_pass_count = sva_pass_count + 1;
      end

    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 7 — WSTRB Safety
  // WSTRB must not be all-zero when WVALID is high.
  // ──────────────────────────────────────────────────────
  always_ff @(posedge clk) begin
    if (rst_n && s_wvalid && s_wstrb === 4'b0000) begin
      $display("[SVA FAIL] WVALID=1 but WSTRB=0 at time %0t", $time);
      sva_fail_count = sva_fail_count + 1;
    end
  end

  // ──────────────────────────────────────────────────────
  // SECTION 8 — Protocol Ordering
  // BVALID must not appear without prior AW+W handshakes.
  // RVALID must not appear without prior AR handshake.
  // ──────────────────────────────────────────────────────
  logic aw_done, w_done, ar_done;
  logic bvalid_prev, rvalid_prev;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_done    <= 1'b0;
      w_done     <= 1'b0;
      ar_done    <= 1'b0;
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

  always_ff @(posedge clk) begin
    if (rst_n) begin
      // BVALID just rose
      if (s_bvalid && !bvalid_prev && !(aw_done && w_done)) begin
        $display("[SVA FAIL] BVALID rose without completed AW+W handshakes at %0t", $time);
        sva_fail_count = sva_fail_count + 1;
      end
      // RVALID just rose
      if (s_rvalid && !rvalid_prev && !ar_done) begin
        $display("[SVA FAIL] RVALID rose without prior AR handshake at %0t", $time);
        sva_fail_count = sva_fail_count + 1;
      end
    end
  end

  // ──────────────────────────────────────────────────────
  // Final SVA report — call from tb with $finish trigger
  // or just let it print at simulation end via $finish
  // ──────────────────────────────────────────────────────
  final begin
    $display("");
    $display("========================================");
    $display("  SVA Monitor Report");
    $display("========================================");
    $display("  Assertion checks passed : %0d", sva_pass_count);
    $display("  Assertion checks FAILED : %0d", sva_fail_count);
    if (sva_fail_count == 0)
      $display("  ** ALL ASSERTIONS PASSED **");
    else
      $display("  ** %0d ASSERTION(S) FAILED **", sva_fail_count);
    $display("========================================");
  end

endmodule : axi_lite_sva
