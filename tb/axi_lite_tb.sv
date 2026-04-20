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
//   TEST 9  - Back-to-back write transactions
//   TEST 10 - Back-to-back read transactions
//   TEST 11 - Write then immediate read (no gap)
//   TEST 12 - Randomized write/read sequence
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
  // Task: axi_write
  //   Performs a complete AXI-Lite write transaction.
  //   AW and W channels driven simultaneously.
  //   Waits for B channel response.
  //   Returns bresp in output argument.
  // ──────────────────────────────────────────────
  task axi_write;
    input  [ADDR_W-1:0]   addr;
    input  [DATA_W-1:0]   data;
    input  [DATA_W/8-1:0] strb;
    output [1:0]          resp;
    integer timeout;
    begin
      // Drive AW and W simultaneously
      @(posedge clk); #1;
      s_awaddr  = addr;
      s_awvalid = 1;
      s_wdata   = data;
      s_wstrb   = strb;
      s_wvalid  = 1;

      // Wait for both AW and W to be accepted
      timeout = 20;
      while (!(s_awready && s_wready) && timeout > 0) begin
        @(posedge clk); #1;
        timeout = timeout - 1;
      end
      @(posedge clk); #1;
      s_awvalid = 0;
      s_wvalid  = 0;

      // Wait for write response (B channel)
      s_bready = 1;
      timeout  = 20;
      while (!s_bvalid && timeout > 0) begin
        @(posedge clk);
        timeout = timeout - 1;
      end
      @(posedge clk); #1;
      resp     = s_bresp;
      s_bready = 0;
      @(posedge clk);
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
    integer timeout;
    begin
      // Drive AR channel
      @(posedge clk); #1;
      s_araddr  = addr;
      s_arvalid = 1;

      // Wait for address accepted
      timeout = 20;
      while (!s_arready && timeout > 0) begin
        @(posedge clk); #1;
        timeout = timeout - 1;
      end
      @(posedge clk); #1;
      s_arvalid = 0;

      // Wait for read data (R channel)
      s_rready = 1;
      timeout  = 20;
      while (!s_rvalid && timeout > 0) begin
        @(posedge clk);
        timeout = timeout - 1;
      end
      @(posedge clk); #1;
      data     = s_rdata;
      resp     = s_rresp;
      s_rready = 0;
      @(posedge clk);
    end
  endtask

  // ──────────────────────────────────────────────
  // Task: check
  // ──────────────────────────────────────────────
  task check;
    input [127:0] label;
    input         condition;
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
    input [127:0]   label;
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
    // Write only lower byte (strobe = 4'b0001)
    axi_write(4'h0, 32'h0000_00AB, 4'h1, wr_resp);
    axi_read(4'h0, rd_data, rd_resp);
    // Upper 3 bytes should still be FF, lower byte = AB
    check_data("partial byte write", rd_data, 32'hFFFF_FFAB);

    // ─────────────────────────────
    // TEST 9: Back-to-back writes
    // ─────────────────────────────
    $display("\n--- TEST 9: Back-to-Back Writes ---");
    apply_reset();
    axi_write(4'h0, 32'h0000_0001, 4'hF, wr_resp);
    check("B2B write 1 OKAY", wr_resp === RESP_OKAY);
    axi_write(4'h4, 32'h0000_0002, 4'hF, wr_resp);
    check("B2B write 2 OKAY", wr_resp === RESP_OKAY);
    axi_write(4'h8, 32'h0000_0003, 4'hF, wr_resp);
    check("B2B write 3 OKAY", wr_resp === RESP_OKAY);
    axi_read(4'h0, rd_data,  rd_resp); check_data("B2B REG0", rd_data,  32'h1);
    axi_read(4'h4, rd_data,  rd_resp); check_data("B2B REG1", rd_data,  32'h2);
    axi_read(4'h8, rd_data,  rd_resp); check_data("B2B REG2", rd_data,  32'h3);

    // ─────────────────────────────
    // TEST 10: Back-to-back reads
    // ─────────────────────────────
    $display("\n--- TEST 10: Back-to-Back Reads ---");
    // Registers still hold values from TEST 9
    axi_read(4'h0, rd_data,  rd_resp); check_data("B2B rd REG0", rd_data, 32'h1);
    axi_read(4'h4, rd_data,  rd_resp); check_data("B2B rd REG1", rd_data, 32'h2);
    axi_read(4'h8, rd_data,  rd_resp); check_data("B2B rd REG2", rd_data, 32'h3);

    // ─────────────────────────────
    // TEST 11: Write then immediate read
    // ─────────────────────────────
    $display("\n--- TEST 11: Write then Immediate Read ---");
    apply_reset();
    axi_write(4'h0, 32'hDEAD_C0DE, 4'hF, wr_resp);
    axi_read (4'h0, rd_data, rd_resp);
    check_data("immediate readback", rd_data, 32'hDEAD_C0DE);

    // ─────────────────────────────
    // TEST 12: Randomized sequence
    // ─────────────────────────────
    $display("\n--- TEST 12: Randomized Write/Read Sequence ---");
    apply_reset();
    shadow_regs[0] = 0;
    shadow_regs[1] = 0;
    shadow_regs[2] = 0;

    for (i = 0; i < 20; i = i + 1) begin
      rand_addr = ($random % 3) * 4;   // 0x0, 0x4, or 0x8 only
      rand_data = $random;

      // Write
      axi_write(rand_addr[ADDR_W-1:0], rand_data, 4'hF, wr_resp);
      shadow_regs[rand_addr/4] = rand_data;

      // Read back immediately
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
    // Final report
    // ─────────────────────────────
    $display("\n========================================");
    $display("  RESULTS: %0d PASSED  |  %0d FAILED",
             pass_count, fail_count);
    $display("========================================");
    if (fail_count == 0)
      $display("  ** ALL TESTS PASSED **");
    else
      $display("  ** %0d TEST(S) FAILED **", fail_count);
    $display("========================================\n");

    $finish;
  end

  // ──────────────────────────────────────────────
  // Timeout watchdog
  // ──────────────────────────────────────────────
  initial begin
    #500_000;
    $display("[TIMEOUT] Simulation exceeded limit!");
    $finish;
  end

endmodule : axi_lite_tb
