// ============================================================
// Module  : axi_lite_slave
// Description:
//   AXI4-Lite Slave Interface with 4-register memory map.
//   Implements all 5 AXI-Lite channels:
//     - Write Address  (AW)
//     - Write Data     (W)
//     - Write Response (B)
//     - Read Address   (AR)
//     - Read Data      (R)
//
// Register Map (byte-addressed):
//   0x00 - REG0 : Read/Write general purpose
//   0x04 - REG1 : Read/Write general purpose
//   0x08 - REG2 : Read/Write general purpose
//   0x0C - REG3 : Read-Only  status/ID register
//                 Returns 32'hDEAD_BEEF always
//
// AXI Response Codes:
//   2'b00 = OKAY   - transfer successful
//   2'b10 = SLVERR - slave error (bad address)
//
// VALID/READY Handshake Rule:
//   A transfer occurs when VALID=1 AND READY=1
//   on the same rising clock edge.
// ============================================================

module axi_lite_slave #(
  parameter int DATA_W = 32,
  parameter int ADDR_W = 4       // covers 0x00 to 0x0F
)(
  input  logic                clk,
  input  logic                rst_n,

  // ── Write Address Channel (AW) ────────────────
  input  logic [ADDR_W-1:0]   s_awaddr,
  input  logic                s_awvalid,
  output logic                s_awready,

  // ── Write Data Channel (W) ────────────────────
  input  logic [DATA_W-1:0]   s_wdata,
  input  logic [DATA_W/8-1:0] s_wstrb,    // byte write enables
  input  logic                s_wvalid,
  output logic                s_wready,

  // ── Write Response Channel (B) ────────────────
  output logic [1:0]          s_bresp,
  output logic                s_bvalid,
  input  logic                s_bready,

  // ── Read Address Channel (AR) ─────────────────
  input  logic [ADDR_W-1:0]   s_araddr,
  input  logic                s_arvalid,
  output logic                s_arready,

  // ── Read Data Channel (R) ─────────────────────
  output logic [DATA_W-1:0]   s_rdata,
  output logic [1:0]          s_rresp,
  output logic                s_rvalid,
  input  logic                s_rready
);

  // ──────────────────────────────────────────────
  // Local parameters & constants
  // ──────────────────────────────────────────────
  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;
  localparam logic [DATA_W-1:0] REG3_ID = 32'hDEAD_BEEF;

  // ──────────────────────────────────────────────
  // Register file (3 R/W + 1 R/O)
  // ──────────────────────────────────────────────
  logic [DATA_W-1:0] reg_file [0:2];   // REG0, REG1, REG2

  // ──────────────────────────────────────────────
  // Internal handshake captures
  // ──────────────────────────────────────────────
  logic [ADDR_W-1:0] wr_addr_r;        // latched write address
  logic [ADDR_W-1:0] rd_addr_r;        // latched read address
  logic              wr_addr_valid_r;  // write address received
  logic              wr_data_valid_r;  // write data received
  logic [DATA_W-1:0] wr_data_r;        // latched write data
  logic [DATA_W/8-1:0] wr_strb_r;     // latched write strobes

  // ──────────────────────────────────────────────
  // WRITE ADDRESS CHANNEL (AW)
  // Accept address as soon as master presents it.
  // Hold awready high by default (always ready).
  // ──────────────────────────────────────────────
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      s_awready      <= 1'b0;
      wr_addr_r      <= '0;
      wr_addr_valid_r <= 1'b0;
    end else begin
      // Default: deassert after one cycle
      s_awready <= 1'b0;

      if (s_awvalid && !wr_addr_valid_r) begin
        s_awready       <= 1'b1;       // acknowledge
        wr_addr_r       <= s_awaddr;   // latch address
        wr_addr_valid_r <= 1'b1;       // mark address captured
      end

      // Clear once write completes
      if (s_bvalid && s_bready)
        wr_addr_valid_r <= 1'b0;
    end
  end

  // ──────────────────────────────────────────────
  // WRITE DATA CHANNEL (W)
  // Accept data as soon as master presents it.
  // ──────────────────────────────────────────────
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      s_wready       <= 1'b0;
      wr_data_r      <= '0;
      wr_strb_r      <= '0;
      wr_data_valid_r <= 1'b0;
    end else begin
      s_wready <= 1'b0;

      if (s_wvalid && !wr_data_valid_r) begin
        s_wready        <= 1'b1;
        wr_data_r       <= s_wdata;
        wr_strb_r       <= s_wstrb;
        wr_data_valid_r <= 1'b1;
      end

      // Clear once write completes
      if (s_bvalid && s_bready)
        wr_data_valid_r <= 1'b0;
    end
  end

  // ──────────────────────────────────────────────
  // WRITE EXECUTION & RESPONSE CHANNEL (B)
  // Execute write once BOTH address and data
  // have been received. Then send response.
  // ──────────────────────────────────────────────
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      s_bvalid  <= 1'b0;
      s_bresp   <= RESP_OKAY;
      reg_file[0] <= '0;
      reg_file[1] <= '0;
      reg_file[2] <= '0;
    end else begin

      if (wr_addr_valid_r && wr_data_valid_r && !s_bvalid) begin
        // Both address and data are ready — perform write
        s_bvalid <= 1'b1;

        case (wr_addr_r)
          4'h0: begin
            // REG0 — write with byte strobes
            if (wr_strb_r[0]) reg_file[0][ 7: 0] <= wr_data_r[ 7: 0];
            if (wr_strb_r[1]) reg_file[0][15: 8] <= wr_data_r[15: 8];
            if (wr_strb_r[2]) reg_file[0][23:16] <= wr_data_r[23:16];
            if (wr_strb_r[3]) reg_file[0][31:24] <= wr_data_r[31:24];
            s_bresp <= RESP_OKAY;
          end
          4'h4: begin
            // REG1
            if (wr_strb_r[0]) reg_file[1][ 7: 0] <= wr_data_r[ 7: 0];
            if (wr_strb_r[1]) reg_file[1][15: 8] <= wr_data_r[15: 8];
            if (wr_strb_r[2]) reg_file[1][23:16] <= wr_data_r[23:16];
            if (wr_strb_r[3]) reg_file[1][31:24] <= wr_data_r[31:24];
            s_bresp <= RESP_OKAY;
          end
          4'h8: begin
            // REG2
            if (wr_strb_r[0]) reg_file[2][ 7: 0] <= wr_data_r[ 7: 0];
            if (wr_strb_r[1]) reg_file[2][15: 8] <= wr_data_r[15: 8];
            if (wr_strb_r[2]) reg_file[2][23:16] <= wr_data_r[23:16];
            if (wr_strb_r[3]) reg_file[2][31:24] <= wr_data_r[31:24];
            s_bresp <= RESP_OKAY;
          end
          4'hC: begin
            // REG3 — read only, return slave error on write
            s_bresp <= RESP_SLVERR;
          end
          default: begin
            // Invalid address — slave error
            s_bresp <= RESP_SLVERR;
          end
        endcase
      end

      // Deassert bvalid once master acknowledges
      if (s_bvalid && s_bready)
        s_bvalid <= 1'b0;
    end
  end

  // ──────────────────────────────────────────────
  // READ ADDRESS CHANNEL (AR)
  // ──────────────────────────────────────────────
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      s_arready <= 1'b0;
      rd_addr_r <= '0;
    end else begin
      s_arready <= 1'b0;

      if (s_arvalid && !s_rvalid) begin
        s_arready <= 1'b1;          // acknowledge
        rd_addr_r <= s_araddr;      // latch address
      end
    end
  end

  // ──────────────────────────────────────────────
  // READ DATA CHANNEL (R)
  // Return register value based on latched address.
  // ──────────────────────────────────────────────
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      s_rvalid <= 1'b0;
      s_rdata  <= '0;
      s_rresp  <= RESP_OKAY;
    end else begin

      if (s_arvalid && s_arready) begin
        // Address accepted — prepare read data
        s_rvalid <= 1'b1;

        case (s_araddr)
          4'h0:    begin s_rdata <= reg_file[0]; s_rresp <= RESP_OKAY;   end
          4'h4:    begin s_rdata <= reg_file[1]; s_rresp <= RESP_OKAY;   end
          4'h8:    begin s_rdata <= reg_file[2]; s_rresp <= RESP_OKAY;   end
          4'hC:    begin s_rdata <= REG3_ID;     s_rresp <= RESP_OKAY;   end
          default: begin s_rdata <= '0;          s_rresp <= RESP_SLVERR; end
        endcase
      end

      // Deassert rvalid once master acknowledges
      if (s_rvalid && s_rready)
        s_rvalid <= 1'b0;
    end
  end

endmodule : axi_lite_slave
