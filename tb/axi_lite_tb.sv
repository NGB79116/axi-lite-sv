// ============================================================
// Module  : axi_lite_tb
// Description:
//   Self-checking testbench for AXI4-Lite Slave.
//
//   TEST 1  - Reset state
//   TEST 2  - Single register write + read back (REG0)
//   TEST 3  - Write all R/W registers, read all back
//   TEST 4  - Read-only register (REG3 = 0xDEAD_BEEF)
//   TEST 5  - Write to read-only register (expect SLVERR)
//   TEST 6  - Write to invalid address (expect SLVERR)
//   TEST 7  - Read from invalid address (expect SLVERR)
//   TEST 8  - Byte strobe partial write
//   TEST 9  - Consecutive writes (task-paced, idle cycles between)
//   TEST 10 - Consecutive reads (task-paced, idle cycles between)
//   TEST 11 - Write then read via the tasks
//   TEST 12 - Randomized write/read sequence
//   TEST 13 - Back-pressure (delayed BREADY/RREADY)
//   TEST 14 - Back-to-back reads with ARVALID held high
//   TEST 15 - AW/W skew (AW first, W first, together)
//   TEST 16 - Coverage gaps (write->read, 1-cycle B/R back-pressure, max-rate B2B writes)
// ============================================================

`timescale 1ns/1ps

module axi_lite_tb;

  // ──────────────────────────────────────────────
  // Parameters
  // ──────────────────────────────────────────────
  localparam int DATA_W    = 32;
  localparam int ADDR_W    = 4;
  localparam int CLK_PERIOD = 10;  // 10ns = 100MHz

  // AXI response codes
  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;

  // ──────────────────────────────────────────────
  // DUT signals
  // ──────────────────────────────────────────────
  logic              clk;
  logic              rst_n;

  // Write Address
  logic [ADDR_W-1:0] s_awaddr;
  logic              s_awvalid;
  logic              s_awready;

  // Write Data
  logic [DATA_W-1:0]   s_wdata;
  logic [DATA_W/8-1:0] s_wstrb;
  logic                s_wvalid;
  logic                s_wready;

  // Write Response
  logic [1:0]          s_bresp;
  logic                s_bvalid;
  logic                s_bready;

  // Read Address
  logic [ADDR_W-1:0]   s_araddr;
  logic                s_arvalid;
  logic                s_arready;

  // Read Data
  logic [DATA_W-1:0]   s_rdata;
  logic [1:0]          s_rresp;
  logic                s_rvalid;
  logic                s_rready;

  // ──────────────────────────────────────────────
  // Scoreboard
  // ──────────────────────────────────────────────
  integer pass_count;
  integer fail_count;

  // ──────────────────────────────────────────────
  // DUT instantiation
  // ──────────────────────────────────────────────
  axi_lite_slave #(
    .DATA_W (DATA_W),
    .ADDR_W (ADDR_W)
  ) u_dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .s_awaddr  (s_awaddr),
    .s_awvalid (s_awvalid),
    .s_awready (s_awready),
    .s_wdata   (s_wdata),
    .s_wstrb   (s_wstrb),
    .s_wvalid  (s_wvalid),
    .s_wready  (s_wready),
    .s_bresp   (s_bresp),
    .s_bvalid  (s_bvalid),
    .s_bready  (s_bready),
    .s_araddr  (s_araddr),
    .s_arvalid (s_arvalid),
    .s_arready (s_arready),
    .s_rdata   (s_rdata),
    .s_rresp   (s_rresp),
    .s_rvalid  (s_rvalid),
    .s_rready  (s_rready)
  );

  // ── SVA Monitor ──────────────────────────────────────
  axi_lite_sva #(.DATA_W(DATA_W),.ADDR_W(ADDR_W)) u_sva (
    .clk(clk), .rst_n(rst_n),
    .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
    .s_wdata(s_wdata),   .s_wstrb(s_wstrb),
    .s_wvalid(s_wvalid), .s_wready(s_wready),
    .s_bresp(s_bresp),   .s_bvalid(s_bvalid),   .s_bready(s_bready),
    .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
    .s_rdata(s_rdata),   .s_rresp(s_rresp),
    .s_rvalid(s_rvalid), .s_rready(s_rready)
  );

  // ── Coverage Monitor ──────────────────────────────────
  axi_lite_coverage #(.DATA_W(DATA_W),.ADDR_W(ADDR_W)) u_cov (
    .clk(clk), .rst_n(rst_n),
    .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
    .s_wdata(s_wdata),   .s_wstrb(s_wstrb),
    .s_wvalid(s_wvalid), .s_wready(s_wready),
    .s_bresp(s_bresp),   .s_bvalid(s_bvalid),   .s_bready(s_bready),
    .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
    .s_rdata(s_rdata),   .s_rresp(s_rresp),
    .s_rvalid(s_rvalid), .s_rready(s_rready)
  );

  // ──────────────────────────────────────────────
  // Clock
  // ──────────────────────────────────────────────
  initial clk = 0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // ──────────────────────────────────────────────
  // Task: apply_reset
  // ──────────────────────────────────────────────
  task apply_reset;
    begin
      rst_n     = 0;
      s_awvalid = 0; s_awaddr  = 0;
      s_wvalid  = 0; s_wdata   = 0; s_wstrb = 0;
      s_bready  = 0;
      s_arvalid = 0; s_araddr  = 0;
      s_rready  = 0;
      repeat(4) @(posedge clk);
      #1; rst_n = 1;
      @(posedge clk);
    end
  endtask

  // ──────────────────────────────────────────────
  // Handshake helpers
  //   READY is sampled right at @(posedge clk), i.e.
  //   the pre-edge value the handshake actually used.
  //   VALID (or READY) is dropped #1 after its own
  //   handshake. A timeout prints FAIL and counts it.
  //   Automatic: several run concurrently in fork.
  // ──────────────────────────────────────────────
  task automatic aw_wait_hs;     // caller has set AWVALID=1
    integer timeout;
    begin
      timeout = 20;
      @(posedge clk);
      while (!s_awready && timeout > 0) begin
        @(posedge clk); timeout = timeout - 1;
      end
      if (!s_awready) begin
        $display("  [FAIL] AW handshake timeout (AWADDR=0x%h) at %0t", s_awaddr, $time);
        fail_count = fail_count + 1;
      end
      #1; s_awvalid = 0;
    end
  endtask

  task automatic w_wait_hs;      // caller has set WVALID=1
    integer timeout;
    begin
      timeout = 20;
      @(posedge clk);
      while (!s_wready && timeout > 0) begin
        @(posedge clk); timeout = timeout - 1;
      end
      if (!s_wready) begin
        $display("  [FAIL] W handshake timeout (WDATA=0x%08h) at %0t", s_wdata, $time);
        fail_count = fail_count + 1;
      end
      #1; s_wvalid = 0;
    end
  endtask

  task automatic ar_wait_hs;     // caller has set ARVALID=1
    integer timeout;
    begin
      timeout = 20;
      @(posedge clk);
      while (!s_arready && timeout > 0) begin
        @(posedge clk); timeout = timeout - 1;
      end
      if (!s_arready) begin
        $display("  [FAIL] AR handshake timeout (ARADDR=0x%h) at %0t", s_araddr, $time);
        fail_count = fail_count + 1;
      end
      #1; s_arvalid = 0;
    end
  endtask

  task automatic b_wait_hs;      // caller has set BREADY=1
    output [1:0] resp;
    integer timeout;
    begin
      timeout = 20;
      @(posedge clk);
      while (!s_bvalid && timeout > 0) begin
        @(posedge clk); timeout = timeout - 1;
      end
      if (s_bvalid) resp = s_bresp;
      else begin
        resp = 2'bxx;
        $display("  [FAIL] B handshake timeout at %0t", $time);
        fail_count = fail_count + 1;
      end
      #1; s_bready = 0;
    end
  endtask

  task automatic r_wait_hs;      // caller has set RREADY=1
    output [DATA_W-1:0] data;
    output [1:0]        resp;
    integer timeout;
    begin
      timeout = 20;
      @(posedge clk);
      while (!s_rvalid && timeout > 0) begin
        @(posedge clk); timeout = timeout - 1;
      end
      if (s_rvalid) begin
        data = s_rdata;
        resp = s_rresp;
      end else begin
        data = 'x;
        resp = 2'bxx;
        $display("  [FAIL] R handshake timeout at %0t", $time);
        fail_count = fail_count + 1;
      end
      #1; s_rready = 0;
    end
  endtask

  // ──────────────────────────────────────────────
  // Task: axi_write_skew
  //   AW and W driven independently: each starts
  //   after its own delay (in cycles) and drops after
  //   its own handshake. Then waits for B.
  // ──────────────────────────────────────────────
  task automatic axi_write_skew;
    input  [ADDR_W-1:0]   addr;
    input  [DATA_W-1:0]   data;
    input  [DATA_W/8-1:0] strb;
    input  integer        aw_delay;
    input  integer        w_delay;
    output [1:0]          resp;
    begin
      @(posedge clk); #1;
      fork
        begin
          if (aw_delay > 0) begin repeat(aw_delay) @(posedge clk); #1; end
          s_awaddr  = addr;
          s_awvalid = 1;
          aw_wait_hs;
        end
        begin
          if (w_delay > 0) begin repeat(w_delay) @(posedge clk); #1; end
          s_wdata  = data;
          s_wstrb  = strb;
          s_wvalid = 1;
          w_wait_hs;
        end
      join

      // Wait for write response (B channel)
      s_bready = 1;
      b_wait_hs(resp);
      @(posedge clk);
    end
  endtask

  // ──────────────────────────────────────────────
  // Task: axi_write
  //   Performs a complete AXI-Lite write transaction.
  //   AW and W driven together, each dropped after
  //   its own handshake. Returns bresp.
  // ──────────────────────────────────────────────
  task axi_write;
    input  [ADDR_W-1:0]   addr;
    input  [DATA_W-1:0]   data;
    input  [DATA_W/8-1:0] strb;
    output [1:0]          resp;
    begin
      axi_write_skew(addr, data, strb, 0, 0, resp);
    end
  endtask

  // ──────────────────────────────────────────────
  // Task: axi_read
  //   Performs a complete AXI-Lite read transaction.
  //   Returns rdata and rresp.
  // ──────────────────────────────────────────────
  task axi_read;
    input  [ADDR_W-1:0] addr;
    output [DATA_W-1:0] data;
    output [1:0]        resp;
    begin
      // Drive AR channel
      @(posedge clk); #1;
      s_araddr  = addr;
      s_arvalid = 1;
      ar_wait_hs;

      // Wait for read data (R channel)
      s_rready = 1;
      r_wait_hs(data, resp);
      @(posedge clk);
    end
  endtask

  // ──────────────────────────────────────────────
  // Task: check
  // ──────────────────────────────────────────────
  task check;
    input string label;
    input        condition;
    begin
      if (condition) begin
        $display("  [PASS] %s", label);
        pass_count = pass_count + 1;
      end else begin
        $display("  [FAIL] %s", label);
        fail_count = fail_count + 1;
      end
    end
  endtask

  // ──────────────────────────────────────────────
  // Task: check_data — compare with display
  // ──────────────────────────────────────────────
  task check_data;
    input string       label;
    input [DATA_W-1:0] actual;
    input [DATA_W-1:0] expected;
    begin
      if (actual === expected) begin
        $display("  [PASS] %s  got=0x%08h", label, actual);
        pass_count = pass_count + 1;
      end else begin
        $display("  [FAIL] %s  got=0x%08h  exp=0x%08h",
                 label, actual, expected);
        fail_count = fail_count + 1;
      end
    end
  endtask

  // ──────────────────────────────────────────────
  // Continuous monitor: VALID/READY protocol check
  // AXI rule: once VALID is asserted, it must not
  // be deasserted until READY is seen.
  // ──────────────────────────────────────────────
  logic aw_valid_sticky, w_valid_sticky, ar_valid_sticky;

  always @(posedge clk) begin
    if (!rst_n) begin
      aw_valid_sticky <= 0;
      w_valid_sticky  <= 0;
      ar_valid_sticky <= 0;
    end else begin
      // Track if VALID was raised
      if (s_awvalid) aw_valid_sticky <= 1;
      if (s_wvalid)  w_valid_sticky  <= 1;
      if (s_arvalid) ar_valid_sticky <= 1;

      // Reset sticky once handshake completes
      if (s_awvalid && s_awready) aw_valid_sticky <= 0;
      if (s_wvalid  && s_wready)  w_valid_sticky  <= 0;
      if (s_arvalid && s_arready) ar_valid_sticky <= 0;

      // Assert: VALID must not drop before READY
      if (aw_valid_sticky && !s_awvalid && !s_awready) begin
        $display("  [ASSERT FAIL] AWVALID dropped before AWREADY at %0t", $time);
        fail_count = fail_count + 1;
      end
      if (w_valid_sticky && !s_wvalid && !s_wready) begin
        $display("  [ASSERT FAIL] WVALID dropped before WREADY at %0t", $time);
        fail_count = fail_count + 1;
      end
      if (ar_valid_sticky && !s_arvalid && !s_arready) begin
        $display("  [ASSERT FAIL] ARVALID dropped before ARREADY at %0t", $time);
        fail_count = fail_count + 1;
      end
    end
  end

  // ──────────────────────────────────────────────
  // TEST 14 handshake counter (passive)
  // Counts AR and R handshakes while enabled and
  // captures RDATA of the first two R beats.
  // ──────────────────────────────────────────────
  reg              t14_mon_en;
  integer          t14_ar_cnt;
  integer          t14_r_cnt;
  reg [DATA_W-1:0] t14_rdata [0:1];

  initial t14_mon_en = 0;

  always @(posedge clk) begin
    if (t14_mon_en) begin
      if (s_arvalid && s_arready)
        t14_ar_cnt = t14_ar_cnt + 1;
      if (s_rvalid && s_rready) begin
        if (t14_r_cnt < 2) t14_rdata[t14_r_cnt] = s_rdata;
        t14_r_cnt = t14_r_cnt + 1;
      end
    end
  end

  // ──────────────────────────────────────────────
  // Transaction monitor (passive), used by TESTs 13,
  // 15 and 16. Counts handshakes on all 5 channels,
  // records the last handshake time (ns) per channel,
  // and flags a BVALID seen before both the AW and W
  // handshakes were done on earlier edges.
  // ──────────────────────────────────────────────
  reg     txn_mon_en;
  integer txn_aw_cnt, txn_w_cnt, txn_b_cnt, txn_ar_cnt, txn_r_cnt;
  integer txn_aw_t,   txn_w_t,   txn_b_t,   txn_ar_t;
  integer txn_bvalid_t;            // first edge BVALID seen high
  reg     txn_aw_seen, txn_w_seen;
  reg     txn_b_early;

  initial txn_mon_en = 0;

  always @(posedge clk) begin
    if (txn_mon_en) begin
      // Check first: handshakes on this edge don't count yet
      if (s_bvalid && !(txn_aw_seen && txn_w_seen)) txn_b_early = 1;
      if (s_bvalid && txn_bvalid_t < 0)             txn_bvalid_t = $time;

      if (s_awvalid && s_awready) begin
        txn_aw_cnt = txn_aw_cnt + 1; txn_aw_seen = 1; txn_aw_t = $time;
      end
      if (s_wvalid && s_wready) begin
        txn_w_cnt = txn_w_cnt + 1;   txn_w_seen = 1;  txn_w_t = $time;
      end
      if (s_bvalid && s_bready) begin
        txn_b_cnt = txn_b_cnt + 1;   txn_b_t = $time;
        txn_aw_seen = 0; txn_w_seen = 0;
      end
      if (s_arvalid && s_arready) begin
        txn_ar_cnt = txn_ar_cnt + 1; txn_ar_t = $time;
      end
      if (s_rvalid && s_rready)
        txn_r_cnt = txn_r_cnt + 1;
    end
  end

  task txn_mon_start;
    begin
      txn_aw_cnt = 0; txn_w_cnt = 0; txn_b_cnt = 0;
      txn_ar_cnt = 0; txn_r_cnt = 0;
      txn_aw_t = -1;  txn_w_t = -1;  txn_b_t = -1;  txn_ar_t = -1;
      txn_bvalid_t = -1;
      txn_aw_seen = 0; txn_w_seen = 0;
      txn_b_early = 0;
      txn_mon_en  = 1;
    end
  endtask

  // ──────────────────────────────────────────────
  // Task: ar_hold_read2
  //   Two reads (0x0 then 0x4) with ARVALID held
  //   high between them; AR and R driven directly.
  //   rready_delay < 0 : RREADY high from the start
  //   rready_delay >= 0: RREADY low until RVALID,
  //                      then low for that many cycles
  // ──────────────────────────────────────────────
  task ar_hold_read2;
    input integer rready_delay;
    begin
      t14_ar_cnt   = 0;
      t14_r_cnt    = 0;
      t14_rdata[0] = 'x;
      t14_rdata[1] = 'x;

      @(posedge clk); #1;
      t14_mon_en = 1;
      s_araddr   = 4'h0;
      s_arvalid  = 1;
      s_rready   = (rready_delay < 0);

      fork
        // AR: sample at the edge, so s_arready is the
        // value the handshake actually used
        begin : t14_ar
          integer ta;
          ta = 0;
          @(posedge clk);
          while (!s_arready && ta < 20) begin
            @(posedge clk); ta = ta + 1;
          end
          #1; s_araddr = 4'h4;    // ARVALID stays high
          ta = 0;
          @(posedge clk);
          while (!s_arready && ta < 20) begin
            @(posedge clk); ta = ta + 1;
          end
          #1; s_arvalid = 0;
        end

        // R: optional back-pressure, then collect beats
        begin : t14_r
          integer tr;
          if (rready_delay >= 0) begin
            tr = 0;
            @(posedge clk);
            while (!s_rvalid && tr < 20) begin
              @(posedge clk); tr = tr + 1;
            end
            repeat(rready_delay) @(posedge clk);
            #1; s_rready = 1;
          end
          tr = 0;
          while (t14_r_cnt < 2 && tr < 20) begin
            @(posedge clk); tr = tr + 1;
          end
        end
      join

      #1;
      s_rready   = 0;
      t14_mon_en = 0;
      @(posedge clk);
    end
  endtask

  // ──────────────────────────────────────────────
  // Main test sequence
  // ──────────────────────────────────────────────
  reg [DATA_W-1:0] rd_data;
  reg [DATA_W-1:0] rd_data2;
  reg [1:0]        rd_resp;
  reg [1:0]        wr_resp;
  integer i;
  reg [ADDR_W-1:0] rand_addr;
  reg [DATA_W-1:0] rand_data;
  reg [DATA_W-1:0] shadow_regs [0:2];  // mirrors what we wrote
  integer cov_wr_rd_before;            // TEST 16 coverage bin snapshots
  integer cov_1cyc_before;
  integer t16_b_t;                     // TEST 16d first B handshake time

  initial begin
    $dumpfile("axi_lite_tb.vcd");
    $dumpvars(0, axi_lite_tb);

    pass_count = 0;
    fail_count = 0;
    shadow_regs[0] = 0;
    shadow_regs[1] = 0;
    shadow_regs[2] = 0;

    $display("========================================");
    $display("  AXI4-Lite Slave Testbench");
    $display("  DATA_W=%0d  ADDR_W=%0d", DATA_W, ADDR_W);
    $display("========================================");

    // ─────────────────────────────
    // TEST 1: Reset state
    // ─────────────────────────────
    $display("\n--- TEST 1: Reset State ---");
    apply_reset();
    check("s_awready=0 after reset", s_awready == 0);
    check("s_wready=0  after reset", s_wready  == 0);
    check("s_bvalid=0  after reset", s_bvalid  == 0);
    check("s_arready=0 after reset", s_arready == 0);
    check("s_rvalid=0  after reset", s_rvalid  == 0);

    // ─────────────────────────────
    // TEST 2: Single write + readback
    // ─────────────────────────────
    $display("\n--- TEST 2: Single Write + Readback (REG0) ---");
    apply_reset();
    axi_write(4'h0, 32'hCAFE_BABE, 4'hF, wr_resp);
    check("write OKAY response",  wr_resp === RESP_OKAY);
    axi_read(4'h0, rd_data, rd_resp);
    check_data("REG0 readback", rd_data, 32'hCAFE_BABE);
    check("read OKAY response",   rd_resp === RESP_OKAY);

    // ─────────────────────────────
    // TEST 3: Write all R/W registers
    // ─────────────────────────────
    $display("\n--- TEST 3: Write All R/W Registers ---");
    apply_reset();
    axi_write(4'h0, 32'hAAAA_AAAA, 4'hF, wr_resp);
    check("REG0 write OKAY", wr_resp === RESP_OKAY);
    axi_write(4'h4, 32'hBBBB_BBBB, 4'hF, wr_resp);
    check("REG1 write OKAY", wr_resp === RESP_OKAY);
    axi_write(4'h8, 32'hCCCC_CCCC, 4'hF, wr_resp);
    check("REG2 write OKAY", wr_resp === RESP_OKAY);

    axi_read(4'h0, rd_data, rd_resp);
    check_data("REG0 readback", rd_data, 32'hAAAA_AAAA);
    axi_read(4'h4, rd_data, rd_resp);
    check_data("REG1 readback", rd_data, 32'hBBBB_BBBB);
    axi_read(4'h8, rd_data, rd_resp);
    check_data("REG2 readback", rd_data, 32'hCCCC_CCCC);

    // ─────────────────────────────
    // TEST 4: Read-only register
    // ─────────────────────────────
    $display("\n--- TEST 4: Read-Only REG3 = 0xDEAD_BEEF ---");
    apply_reset();
    axi_read(4'hC, rd_data, rd_resp);
    check_data("REG3 = DEAD_BEEF", rd_data, 32'hDEAD_BEEF);
    check("REG3 read OKAY",        rd_resp === RESP_OKAY);

    // ─────────────────────────────
    // TEST 5: Write to read-only (SLVERR)
    // ─────────────────────────────
    $display("\n--- TEST 5: Write to Read-Only Reg (expect SLVERR) ---");
    apply_reset();
    axi_write(4'hC, 32'hDEAD_DEAD, 4'hF, wr_resp);
    check("write to RO returns SLVERR", wr_resp === RESP_SLVERR);
    // Verify REG3 still returns correct ID
    axi_read(4'hC, rd_data, rd_resp);
    check_data("REG3 unchanged after bad write", rd_data, 32'hDEAD_BEEF);

    // ─────────────────────────────
    // TEST 6: Invalid write address
    // ─────────────────────────────
    $display("\n--- TEST 6: Invalid Write Address (expect SLVERR) ---");
    apply_reset();
    axi_write(4'hE, 32'h1234_5678, 4'hF, wr_resp);
    check("invalid wr addr returns SLVERR", wr_resp === RESP_SLVERR);

    // ─────────────────────────────
    // TEST 7: Invalid read address
    // ─────────────────────────────
    $display("\n--- TEST 7: Invalid Read Address (expect SLVERR) ---");
    apply_reset();
    axi_read(4'hE, rd_data, rd_resp);
    check("invalid rd addr returns SLVERR", rd_resp === RESP_SLVERR);

    // ─────────────────────────────
    // TEST 8: Byte strobes
    // ─────────────────────────────
    $display("\n--- TEST 8: Byte Strobe Partial Write ---");
    apply_reset();
    // Write full value first
    axi_write(4'h0, 32'hFFFF_FFFF, 4'hF, wr_resp);
    // byte0 only → lower byte changes, upper 3 stay FF
    axi_write(4'h0, 32'h0000_00AB, 4'h1, wr_resp);
    axi_read(4'h0, rd_data, rd_resp);
    check_data("strobe byte0 only",  rd_data, 32'hFFFF_FFAB);

    axi_write(4'h0, 32'hFFFF_FFFF, 4'hF, wr_resp);  // reset to all F
    // byte1 only → bits[15:8] change
    axi_write(4'h0, 32'h0000_CD00, 4'h2, wr_resp);
    axi_read(4'h0, rd_data, rd_resp);
    check_data("strobe byte1 only",  rd_data, 32'hFFFF_CDFF);

    axi_write(4'h0, 32'hFFFF_FFFF, 4'hF, wr_resp);
    // byte2 only → bits[23:16] change
    axi_write(4'h0, 32'h00EF_0000, 4'h4, wr_resp);
    axi_read(4'h0, rd_data, rd_resp);
    check_data("strobe byte2 only",  rd_data, 32'hFFEF_FFFF);

    axi_write(4'h0, 32'hFFFF_FFFF, 4'hF, wr_resp);
    // byte3 only → bits[31:24] change
    axi_write(4'h0, 32'h12000000, 4'h8, wr_resp);
    axi_read(4'h0, rd_data, rd_resp);
    check_data("strobe byte3 only",  rd_data, 32'h12FF_FFFF);

    axi_write(4'h0, 32'hFFFF_FFFF, 4'hF, wr_resp);
    // low half (bytes 1:0) → bits[15:0] change
    axi_write(4'h0, 32'h0000_1234, 4'h3, wr_resp);
    axi_read(4'h0, rd_data, rd_resp);
    check_data("strobe low half",    rd_data, 32'hFFFF_1234);

    axi_write(4'h0, 32'hFFFF_FFFF, 4'hF, wr_resp);
    // high half (bytes 3:2) → bits[31:16] change
    axi_write(4'h0, 32'h5678_0000, 4'hC, wr_resp);
    axi_read(4'h0, rd_data, rd_resp);
    check_data("strobe high half",   rd_data, 32'h5678_FFFF);

    // ─────────────────────────────
    // TEST 9: Consecutive writes (not back-to-back on the bus)
    // ─────────────────────────────
    $display("\n--- TEST 9: Consecutive Writes ---");
    apply_reset();
    axi_write(4'h0, 32'h0000_0001, 4'hF, wr_resp);
    check("consecutive write 1 OKAY", wr_resp === RESP_OKAY);
    axi_write(4'h4, 32'h0000_0002, 4'hF, wr_resp);
    check("consecutive write 2 OKAY", wr_resp === RESP_OKAY);
    axi_write(4'h8, 32'h0000_0003, 4'hF, wr_resp);
    check("consecutive write 3 OKAY", wr_resp === RESP_OKAY);
    axi_read(4'h0, rd_data, rd_resp); check_data("consecutive REG0", rd_data, 32'h1);
    axi_read(4'h4, rd_data, rd_resp); check_data("consecutive REG1", rd_data, 32'h2);
    axi_read(4'h8, rd_data, rd_resp); check_data("consecutive REG2", rd_data, 32'h3);

    // ─────────────────────────────
    // TEST 10: Consecutive reads (not back-to-back on the bus)
    // ─────────────────────────────
    $display("\n--- TEST 10: Consecutive Reads ---");
    // Registers still hold values from TEST 9
    axi_read(4'h0, rd_data, rd_resp); check_data("consecutive read REG0", rd_data, 32'h1);
    axi_read(4'h4, rd_data, rd_resp); check_data("consecutive read REG1", rd_data, 32'h2);
    axi_read(4'h8, rd_data, rd_resp); check_data("consecutive read REG2", rd_data, 32'h3);

    // ─────────────────────────────
    // TEST 11: Write then read
    // ─────────────────────────────
    $display("\n--- TEST 11: Write then Read ---");
    apply_reset();
    axi_write(4'h0, 32'hDEAD_C0DE, 4'hF, wr_resp);
    axi_read (4'h0, rd_data, rd_resp);
    check_data("write-then-read readback", rd_data, 32'hDEAD_C0DE);

    // ─────────────────────────────
    // TEST 12: Randomized sequence
    // ─────────────────────────────
    $display("\n--- TEST 12: Randomized Write/Read Sequence ---");
    apply_reset();
    shadow_regs[0] = 0;
    shadow_regs[1] = 0;
    shadow_regs[2] = 0;

    for (i = 0; i < 20; i = i + 1) begin
      // $unsigned prevents negative modulo wrapping to 0xC (REG3)
      rand_addr = ($unsigned($random) % 3) * 4;  // 0x0, 0x4, or 0x8 only
      rand_data = $random;

      axi_write(rand_addr[ADDR_W-1:0], rand_data, 4'hF, wr_resp);
      shadow_regs[rand_addr/4] = rand_data;

      axi_read(rand_addr[ADDR_W-1:0], rd_data, rd_resp);

      if (rd_data === shadow_regs[rand_addr/4]) begin
        pass_count = pass_count + 1;
      end else begin
        $display("  [FAIL] RAND addr=0x%h got=0x%08h exp=0x%08h",
                 rand_addr, rd_data, shadow_regs[rand_addr/4]);
        fail_count = fail_count + 1;
      end
    end
    $display("  [INFO] 20 random write/read pairs completed");

    // ─────────────────────────────
    // TEST 13: Back-pressure
    // Delay s_bready and s_rready AFTER the write/read
    // address+data handshakes complete, exercising the
    // slave's VALID hold behavior on B and R channels.
    // This DUT's AW/W/AR accept in one cycle (ready pulses
    // once), so we use axi_write/axi_read then separately
    // drive a delayed-ready sequence on B and R only.
    // ─────────────────────────────
    $display("\n--- TEST 13: Back-Pressure (Delayed B/R READY) ---");
    apply_reset();
    txn_mon_start;

    // Write REG1 with normal task first (gets BVALID asserted)
    // Then verify BVALID holds by checking it 2 cycles later
    @(posedge clk); #1;
    s_awaddr  = 4'h4;
    s_awvalid = 1;
    s_wdata   = 32'hCAFE_F00D;
    s_wstrb   = 4'hF;
    s_wvalid  = 1;
    s_bready  = 0;    // hold low — slave must keep BVALID high

    // Each VALID drops right after its own handshake
    fork
      aw_wait_hs;
      w_wait_hs;
    join

    // Slave will now assert BVALID — wait for it
    begin : wait_bvalid
      integer t; t = 0;
      while (!s_bvalid && t < 10) begin
        @(posedge clk); t = t + 1;
      end
    end

    // BVALID is high — hold BREADY low for 3 more cycles (back-pressure)
    repeat(3) @(posedge clk);
    check("BVALID held during back-pressure", s_bvalid === 1'b1);

    // Now accept
    #1; s_bready = 1;
    @(posedge clk); #1;
    check("BP write OKAY resp", s_bresp === RESP_OKAY);
    s_bready = 0;
    @(posedge clk);

    // Verify the write
    axi_read(4'h4, rd_data, rd_resp);
    check_data("BP write readback", rd_data, 32'hCAFE_F00D);

    // Read REG1 — hold RREADY low after AR handshake
    @(posedge clk); #1;
    s_araddr  = 4'h4;
    s_arvalid = 1;
    s_rready  = 0;    // hold low

    // Wait for AR handshake, then drop ARVALID
    ar_wait_hs;

    // Slave will assert RVALID — wait for it
    begin : wait_rvalid
      integer t; t = 0;
      while (!s_rvalid && t < 10) begin
        @(posedge clk); t = t + 1;
      end
    end

    // RVALID is high — hold RREADY low for 3 more cycles
    repeat(3) @(posedge clk);
    check("RVALID held during back-pressure", s_rvalid === 1'b1);

    // Now accept
    #1; s_rready = 1;
    @(posedge clk); #1;
    check_data("BP read data",   s_rdata, 32'hCAFE_F00D);
    check("BP read OKAY resp",   s_rresp === RESP_OKAY);
    s_rready = 0;
    @(posedge clk);

    // No unintended extra transaction: 1 write, 2 reads
    repeat(10) @(posedge clk);
    txn_mon_en = 0;
    $display("  [INFO] handshakes AW=%0d W=%0d B=%0d AR=%0d R=%0d",
             txn_aw_cnt, txn_w_cnt, txn_b_cnt, txn_ar_cnt, txn_r_cnt);
    check("BP exactly one write (AW=W=B=1)",
          txn_aw_cnt == 1 && txn_w_cnt == 1 && txn_b_cnt == 1);
    check("BP exactly two reads (AR=R=2)",
          txn_ar_cnt == 2 && txn_r_cnt == 2);

    // ─────────────────────────────
    // TEST 14: Back-to-back reads, ARVALID held high
    //   axi_read drops ARVALID after each handshake,
    //   so AR and R are driven directly here.
    // ─────────────────────────────
    $display("\n--- TEST 14: B2B Reads with ARVALID Held High ---");
    apply_reset();
    axi_write(4'h0, 32'h1111_0000, 4'hF, wr_resp);
    check("T14 REG0 wr OKAY", wr_resp === RESP_OKAY);
    axi_write(4'h4, 32'h2222_0004, 4'hF, wr_resp);
    check("T14 REG1 wr OKAY", wr_resp === RESP_OKAY);

    // a) RREADY low for 3 cycles after RVALID
    ar_hold_read2(3);
    $display("  [INFO] a) AR handshakes=%0d  R handshakes=%0d",
             t14_ar_cnt, t14_r_cnt);
    check_data("T14a beat0 data", t14_rdata[0], 32'h1111_0000);
    check("T14a AR==R count", t14_ar_cnt == t14_r_cnt);

    // b) RREADY held high throughout
    ar_hold_read2(-1);
    $display("  [INFO] b) AR handshakes=%0d  R handshakes=%0d",
             t14_ar_cnt, t14_r_cnt);
    check_data("T14b beat0 data", t14_rdata[0], 32'h1111_0000);
    check("T14b AR==R count", t14_ar_cnt == t14_r_cnt);

    // ─────────────────────────────
    // TEST 15: AW/W skew
    //   AW and W driven on independent schedules.
    //   BVALID must not rise before both handshakes.
    // ─────────────────────────────
    $display("\n--- TEST 15: AW/W Skew ---");
    apply_reset();

    // a) AW 3 cycles before W
    txn_mon_start;
    axi_write_skew(4'h0, 32'hA0A0_0015, 4'hF, 0, 3, wr_resp);
    txn_mon_en = 0;
    $display("  [INFO] a) AW hs @%0d ns, W hs @%0d ns, BVALID first seen @%0d ns",
             txn_aw_t, txn_w_t, txn_bvalid_t);
    check("AW-first: BRESP OKAY", wr_resp === RESP_OKAY);
    check("AW-first: BVALID only after AW and W handshakes",
          !txn_b_early && txn_aw_cnt == 1 && txn_w_cnt == 1 && txn_b_cnt == 1);
    axi_read(4'h0, rd_data, rd_resp);
    check_data("AW-first: REG0 readback", rd_data, 32'hA0A0_0015);

    // b) W 3 cycles before AW
    txn_mon_start;
    axi_write_skew(4'h4, 32'hB1B1_0015, 4'hF, 3, 0, wr_resp);
    txn_mon_en = 0;
    $display("  [INFO] b) AW hs @%0d ns, W hs @%0d ns, BVALID first seen @%0d ns",
             txn_aw_t, txn_w_t, txn_bvalid_t);
    check("W-first: BRESP OKAY", wr_resp === RESP_OKAY);
    check("W-first: BVALID only after AW and W handshakes",
          !txn_b_early && txn_aw_cnt == 1 && txn_w_cnt == 1 && txn_b_cnt == 1);
    axi_read(4'h4, rd_data, rd_resp);
    check_data("W-first: REG1 readback", rd_data, 32'hB1B1_0015);

    // c) AW and W together
    txn_mon_start;
    axi_write_skew(4'h8, 32'hC2C2_0015, 4'hF, 0, 0, wr_resp);
    txn_mon_en = 0;
    $display("  [INFO] c) AW hs @%0d ns, W hs @%0d ns, BVALID first seen @%0d ns",
             txn_aw_t, txn_w_t, txn_bvalid_t);
    check("Together: BRESP OKAY", wr_resp === RESP_OKAY);
    check("Together: BVALID only after AW and W handshakes",
          !txn_b_early && txn_aw_cnt == 1 && txn_w_cnt == 1 && txn_b_cnt == 1);
    axi_read(4'h8, rd_data, rd_resp);
    check_data("Together: REG2 readback", rd_data, 32'hC2C2_0015);

    // ─────────────────────────────
    // TEST 16: Coverage gaps
    //   a) write followed by a read, as fast as possible
    //   b) B with exactly 1 cycle of BREADY back-pressure
    //   c) R with exactly 1 cycle of RREADY back-pressure
    //   d) back-to-back writes at the DUT's maximum rate
    // ─────────────────────────────
    $display("\n--- TEST 16: Coverage Gaps ---");
    apply_reset();
    axi_write(4'h8, 32'h5EED_0008, 4'hF, wr_resp);   // known REG2 for a-ii

    // a-i) Ordered: AR issued right after the B handshake
    cov_wr_rd_before = u_cov.cov_seq_wr_then_rd;
    txn_mon_start;
    @(posedge clk); #1;
    s_awaddr = 4'h0; s_awvalid = 1;
    s_wdata  = 32'h0DE1_0000; s_wstrb = 4'hF; s_wvalid = 1;
    fork
      aw_wait_hs;
      w_wait_hs;
    join
    s_bready = 1;
    b_wait_hs(wr_resp);
    s_araddr = 4'h0; s_arvalid = 1;     // same #1 slot as BREADY drop
    ar_wait_hs;
    s_rready = 1;
    r_wait_hs(rd_data, rd_resp);
    txn_mon_en = 0;
    $display("  [INFO] a-i) B hs @%0d ns, AR hs @%0d ns, gap %0d cycle(s)",
             txn_b_t, txn_ar_t, (txn_ar_t - txn_b_t) / CLK_PERIOD);
    if (u_cov.cov_seq_wr_then_rd > cov_wr_rd_before)
      $display("  [INFO] a-i) write-then-read bin HIT");
    else
      $display("  [INFO] a-i) write-then-read bin not hit");
    check("Ordered: write BRESP OKAY", wr_resp === RESP_OKAY);
    check_data("Ordered: read returns the value just written", rd_data, 32'h0DE1_0000);
    @(posedge clk);

    // a-ii) Overlapped: ARVALID raised while the write's B
    //   response is still outstanding. AXI gives no ordering
    //   guarantee between a read and a write to the same
    //   address on separate channels (the read may see the
    //   old or new value), so this read targets a DIFFERENT
    //   register (REG2) and its data is exactly predictable.
    cov_wr_rd_before = u_cov.cov_seq_rd_ovl_wr;
    txn_mon_start;
    @(posedge clk); #1;
    s_awaddr = 4'h4; s_awvalid = 1;
    s_wdata  = 32'h0DE2_0004; s_wstrb = 4'hF; s_wvalid = 1;
    fork
      aw_wait_hs;
      w_wait_hs;
    join
    s_bready  = 1;
    s_araddr  = 4'h8; s_arvalid = 1;    // AW/W done, B not yet accepted
    fork
      b_wait_hs(wr_resp);
      begin
        ar_wait_hs;
        s_rready = 1;
        r_wait_hs(rd_data, rd_resp);
      end
    join
    txn_mon_en = 0;
    $display("  [INFO] a-ii) B hs @%0d ns, AR hs @%0d ns, gap %0d cycle(s)",
             txn_b_t, txn_ar_t, (txn_ar_t - txn_b_t) / CLK_PERIOD);
    if (u_cov.cov_seq_rd_ovl_wr > cov_wr_rd_before)
      $display("  [INFO] a-ii) read-overlapping-write bin HIT");
    else
      $display("  [INFO] a-ii) read-overlapping-write bin not hit");
    check("Overlapped: write BRESP OKAY", wr_resp === RESP_OKAY);
    check_data("Overlapped: REG2 read data", rd_data, 32'h5EED_0008);
    check("Overlapped: REG2 read OKAY", rd_resp === RESP_OKAY);
    axi_read(4'h4, rd_data, rd_resp);
    check_data("Overlapped: REG1 readback after write", rd_data, 32'h0DE2_0004);

    // b) B with exactly 1 cycle of back-pressure:
    //    BVALID seen at one edge with BREADY low, then accepted
    cov_1cyc_before = u_cov.cov_b_1cyc;
    @(posedge clk); #1;
    s_awaddr = 4'h0; s_awvalid = 1;
    s_wdata  = 32'h1C1C_0000; s_wstrb = 4'hF; s_wvalid = 1;
    s_bready = 0;
    fork
      aw_wait_hs;
      w_wait_hs;
    join
    begin : t16_wait_bvalid
      integer t; t = 0;
      @(posedge clk);
      while (!s_bvalid && t < 20) begin
        @(posedge clk); t = t + 1;
      end
    end
    #1; s_bready = 1;
    b_wait_hs(wr_resp);
    check("B 1-cycle back-pressure: BRESP OKAY", wr_resp === RESP_OKAY);
    check("B 1-cycle back-pressure: coverage bin hit",
          u_cov.cov_b_1cyc == cov_1cyc_before + 1);

    // c) R with exactly 1 cycle of back-pressure
    cov_1cyc_before = u_cov.cov_r_1cyc;
    @(posedge clk); #1;
    s_araddr = 4'h0; s_arvalid = 1;
    s_rready = 0;
    ar_wait_hs;
    begin : t16_wait_rvalid
      integer t; t = 0;
      @(posedge clk);
      while (!s_rvalid && t < 20) begin
        @(posedge clk); t = t + 1;
      end
    end
    #1; s_rready = 1;
    r_wait_hs(rd_data, rd_resp);
    check_data("R 1-cycle back-pressure: read data", rd_data, 32'h1C1C_0000);
    check("R 1-cycle back-pressure: coverage bin hit",
          u_cov.cov_r_1cyc == cov_1cyc_before + 1);
    @(posedge clk);

    // d) Back-to-back writes at the DUT's maximum rate:
    //    the next AWVALID/WVALID is raised #1 after the
    //    B handshake, with no idle edge in between
    cov_1cyc_before = u_cov.cov_seq_b2b_write;
    txn_mon_start;
    @(posedge clk); #1;
    s_awaddr = 4'h4; s_awvalid = 1;
    s_wdata  = 32'hB2B0_0004; s_wstrb = 4'hF; s_wvalid = 1;
    fork
      aw_wait_hs;
      w_wait_hs;
    join
    s_bready = 1;
    b_wait_hs(wr_resp);
    t16_b_t = txn_b_t;
    check("B2B max rate: write 1 BRESP OKAY", wr_resp === RESP_OKAY);
    s_awaddr = 4'h8; s_awvalid = 1;     // same #1 slot as BREADY drop
    s_wdata  = 32'hB2B0_0008; s_wvalid = 1;
    fork
      aw_wait_hs;
      w_wait_hs;
    join
    s_bready = 1;
    b_wait_hs(wr_resp);
    txn_mon_en = 0;
    $display("  [INFO] d) B hs @%0d ns, next AW hs @%0d ns, gap %0d cycle(s)",
             t16_b_t, txn_aw_t, (txn_aw_t - t16_b_t) / CLK_PERIOD);
    check("B2B max rate: write 2 BRESP OKAY", wr_resp === RESP_OKAY);
    check("B2B max rate: back-to-back write bin hit",
          u_cov.cov_seq_b2b_write == cov_1cyc_before + 1);
    axi_read(4'h4, rd_data, rd_resp);
    check_data("B2B max rate: REG1 readback", rd_data, 32'hB2B0_0004);
    axi_read(4'h8, rd_data, rd_resp);
    check_data("B2B max rate: REG2 readback", rd_data, 32'hB2B0_0008);

    // ─────────────────────────────
    // Final report
    // ─────────────────────────────
    $display("\n========================================");
    $display("  RESULTS: %0d PASSED  |  %0d FAILED",
             pass_count, fail_count);
    $display("  MONITOR: %0d protocol violation(s)",
             u_sva.sva_fail_count);
    $display("========================================");
    if (fail_count == 0 && u_sva.sva_fail_count == 0)
      $display("  ** ALL TESTS PASSED **");
    else
      $display("  ** FAILED: %0d check(s), %0d monitor error(s) **",
               fail_count, u_sva.sva_fail_count);
    $display("========================================\n");

    u_cov.print_coverage();
    $finish;
  end

  // ──────────────────────────────────────────────
  // Timeout watchdog
  // ──────────────────────────────────────────────
  initial begin
    #500_000;
    $display("[TIMEOUT] Simulation exceeded limit!");
    $display("\n========================================");
    $display("  RESULTS: %0d PASSED  |  %0d FAILED (before timeout)",
             pass_count, fail_count);
    $display("  MONITOR: %0d protocol violation(s)",
             u_sva.sva_fail_count);
    $display("========================================");
    $display("  ** FAILED: simulation timeout **");
    $display("========================================\n");
    u_cov.print_coverage();
    $finish;
  end

endmodule : axi_lite_tb