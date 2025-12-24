module axi_lite_slave #(
  parameter int ADDR_WIDTH  = 32,  // Width of AXI address bus
  parameter int DATA_WIDTH  = 32   // Width of AXI data bus
)(
  // ------------------------------------------------------
  // AXI4-Lite Clock & Reset
  // ------------------------------------------------------
  input  logic                       ACLK,          // AXI clock domain
  input  logic                       ARESETn,       // AXI async active-low reset

  // ------------------------------------------------------
  // AXI4-Lite Write Address Channel
  // ------------------------------------------------------
  input  logic [ADDR_WIDTH-1:0]      AWADDR,        // Write address
  input  logic                       AWVALID,       // Address valid
  output logic                       AWREADY,       // Address ready (slave accepts AW)

  // ------------------------------------------------------
  // AXI4-Lite Write Data Channel
  // ------------------------------------------------------
  input  logic [DATA_WIDTH-1:0]      WDATA,         // Write data
  input  logic [(DATA_WIDTH/8)-1:0]  WSTRB,         // Byte strobes
  input  logic                       WVALID,        // Data valid
  output logic                       WREADY,        // Data ready (slave accepts W)

  // ------------------------------------------------------
  // AXI4-Lite Write Response Channel
  // ------------------------------------------------------
  output logic [1:0]                 BRESP,         // Write response code
  output logic                       BVALID,        // Write response valid
  input  logic                       BREADY,        // Master ready to accept B

  // ------------------------------------------------------
  // AXI4-Lite Read Address Channel
  // ------------------------------------------------------
  input  logic [ADDR_WIDTH-1:0]      ARADDR,        // Read address
  input  logic                       ARVALID,       // Address valid
  output logic                       ARREADY,       // Address ready

  // ------------------------------------------------------
  // AXI4-Lite Read Data Channel
  // ------------------------------------------------------
  output logic [DATA_WIDTH-1:0]      RDATA,         // Read data
  output logic [1:0]                 RRESP,         // Read response code
  output logic                       RVALID,        // Read data valid
  input  logic                       RREADY,        // Master ready to accept R

  // ======================================================
  // Write-command interface toward write_cmd FIFO
  // ======================================================
  output logic                       wr_cmd_valid,  // Valid command toward FIFO
  input  logic                       wr_cmd_ready,  // FIFO ready (i.e., not full)
  output logic [ADDR_WIDTH-1:0]      wr_cmd_addr,   // Write command address
  output logic [DATA_WIDTH-1:0]      wr_cmd_wdata,  // Write command data
  output logic [(DATA_WIDTH/8)-1:0]  wr_cmd_wstrb,  // Write command byte strobes

  // Write response returned from APB side (FIFO back to ACLK)
  input  logic                       wr_rsp_valid,  // Response valid (from response FIFO)
  output logic                       wr_rsp_ready,  // Pop response FIFO
  input  logic                       wr_rsp_error,  // 0 = OKAY, 1 = SLVERR

  // ======================================================
  // Read-command interface toward read_cmd FIFO
  // ======================================================
  output logic                       rd_cmd_valid,  // Valid read command
  input  logic                       rd_cmd_ready,  // FIFO ready (i.e., not full)
  output logic [ADDR_WIDTH-1:0]      rd_cmd_addr,   // Read command address

  // Read response returned from APB side (FIFO back to ACLK)
  input  logic                       rd_rsp_valid,  // Response valid (from response FIFO)
  output logic                       rd_rsp_ready,  // Pop response FIFO
  input  logic [DATA_WIDTH-1:0]      rd_rsp_rdata,  // Read data
  input  logic                       rd_rsp_error   // 0 = OKAY, 1 = SLVERR
);

  // -------------------------------------------------------
  // AXI response codes (AXI4-Lite)
  // -------------------------------------------------------
  localparam logic [1:0] AXI_RESP_OK     = 2'b00; // OKAY
  localparam logic [1:0] AXI_RESP_SLVERR = 2'b10; // SLVERR

  // -------------------------------------------------------
  // Local one-entry capture for AW and W
  // -------------------------------------------------------
  logic [ADDR_WIDTH-1:0]      awaddr_reg;
  logic                       awaddr_valid;

  logic [DATA_WIDTH-1:0]      wdata_reg;
  logic [(DATA_WIDTH/8)-1:0]  wstrb_reg;
  logic                       wdata_valid;

  // -------------------------------------------------------
  // Local one-entry capture for AR
  // -------------------------------------------------------
  logic [ADDR_WIDTH-1:0]      araddr_reg;
  logic                       araddr_valid;

  // -------------------------------------------------------
  // Write command enqueue handshake
  // -------------------------------------------------------
  wire have_wr_cmd    = awaddr_valid && wdata_valid;
  wire do_wr_enqueue  = have_wr_cmd && wr_cmd_ready; // push into write_cmd FIFO

  // -------------------------------------------------------
  // Read command enqueue handshake
  // -------------------------------------------------------
  wire have_rd_cmd    = araddr_valid;
  wire do_rd_enqueue  = have_rd_cmd && rd_cmd_ready; // push into read_cmd FIFO

  // =======================================================
  // Sequential: capture AW/W/AR inputs
  // =======================================================
  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      awaddr_reg   <= '0;
      awaddr_valid <= 1'b0;

      wdata_reg    <= '0;
      wstrb_reg    <= '0;
      wdata_valid  <= 1'b0;

      araddr_reg   <= '0;
      araddr_valid <= 1'b0;
    end else begin
      // Capture AW when handshake occurs
      if (AWREADY && AWVALID) begin
        awaddr_reg   <= AWADDR;
        awaddr_valid <= 1'b1;
      end

      // Capture W when handshake occurs
      if (WREADY && WVALID) begin
        wdata_reg    <= WDATA;
        wstrb_reg    <= WSTRB;
        wdata_valid  <= 1'b1;
      end

      // Capture AR when handshake occurs
      if (ARREADY && ARVALID) begin
        araddr_reg   <= ARADDR;
        araddr_valid <= 1'b1;
      end

      // Clear AW/W once we successfully enqueued a write command into the FIFO
      if (do_wr_enqueue) begin
        awaddr_valid <= 1'b0;
        wdata_valid  <= 1'b0;
      end

      // Clear AR once we successfully enqueued a read command into the FIFO
      if (do_rd_enqueue) begin
        araddr_valid <= 1'b0;
      end
    end
  end

  // =======================================================
  // Combinational: drive AXI handshakes and FIFO interfaces
  // =======================================================
  always_comb begin
    // ------------------------------
    // Default outputs
    // ------------------------------
    AWREADY = 1'b0;
    WREADY  = 1'b0;
    ARREADY = 1'b0;

    wr_cmd_valid = 1'b0;
    wr_cmd_addr  = awaddr_reg;
    wr_cmd_wdata = wdata_reg;
    wr_cmd_wstrb = wstrb_reg;

    rd_cmd_valid = 1'b0;
    rd_cmd_addr  = araddr_reg;

    // ------------------------------
    // Accept AW/W independently into local regs
    // ------------------------------
    if (!awaddr_valid) AWREADY = 1'b1;
    if (!wdata_valid)  WREADY  = 1'b1;
    if (!araddr_valid) ARREADY = 1'b1;

    // ------------------------------
    // Enqueue write command when we have both AW and W
    // ------------------------------
    wr_cmd_valid = have_wr_cmd;

    // ------------------------------
    // Enqueue read command when we have AR
    // ------------------------------
    rd_cmd_valid = have_rd_cmd;

	// ======================================================
    // Write Response Channel (Direct connection to FIFO)
    // ======================================================
    // 1. Drive AXI BVALID directly from the FIFO's valid signal
    BVALID = wr_rsp_valid;
    
    // 2. Drive BRESP based on the error bit stored in the FIFO
    BRESP  = wr_rsp_error ? AXI_RESP_SLVERR : AXI_RESP_OK;

    // 3. CRITICAL FIX: Pop the FIFO only upon a complete handshake!
    //    This ensures the data remains stable at the FIFO output (mem[0]) 
    //    until the Master actually accepts it.
    wr_rsp_ready = BVALID && BREADY;


    // ======================================================
    // Read Response Channel (Direct connection to FIFO)
    // ======================================================
    // 1. Drive AXI RVALID directly from the FIFO's valid signal
    RVALID = rd_rsp_valid;
    
    // 2. Drive RDATA and RRESP directly from the FIFO output data
    RDATA  = rd_rsp_rdata;
    RRESP  = rd_rsp_error ? AXI_RESP_SLVERR : AXI_RESP_OK;

    // 3. CRITICAL FIX: Pop the FIFO only upon a complete handshake!
    rd_rsp_ready = RVALID && RREADY;
  end

endmodule
