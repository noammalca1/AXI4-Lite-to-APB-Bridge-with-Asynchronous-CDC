// ============================================================================
// AXI4-Lite ↔ APB Bridge Top
//  - AXI4-Lite slave interface in ACLK domain
//  - APB master interface in PCLK domain
//  - Asynchronous FIFOs for CDC (ACLK ↔ PCLK)
//  - Simple arbiter in APB domain that merges write/read commands
//    into a single request stream for the APB master FSM.
// ============================================================================

module axi_apb_bridge_top #(
  parameter int ADDR_WIDTH     = 32,   // Width of AXI/APB address bus
  parameter int DATA_WIDTH     = 32,   // Width of AXI/APB data bus
  parameter int NUM_APB_SLAVES = 4,    // Number of APB slaves (PSEL width)
  parameter int FIFO_DEPTH     = 4     // Depth of async FIFOs (must be power of 2)
)(
  // --------------------------------------------------------------------------
  // AXI4-Lite Clock & Reset
  // --------------------------------------------------------------------------
  input  logic                        ACLK,          // AXI clock
  input  logic                        ARESETn,       // AXI async active-low reset

  // --------------------------------------------------------------------------
  // AXI4-Lite Write Address Channel
  // --------------------------------------------------------------------------
  input  logic [ADDR_WIDTH-1:0]       AWADDR,
  input  logic                        AWVALID,
  output logic                        AWREADY,

  // --------------------------------------------------------------------------
  // AXI4-Lite Write Data Channel
  // --------------------------------------------------------------------------
  input  logic [DATA_WIDTH-1:0]       WDATA,
  input  logic [(DATA_WIDTH/8)-1:0]   WSTRB, //apb protocol doesnt support wstrb
  input  logic                        WVALID,
  output logic                        WREADY,

  // --------------------------------------------------------------------------
  // AXI4-Lite Write Response Channel
  // --------------------------------------------------------------------------
  output logic [1:0]                  BRESP,
  output logic                        BVALID,
  input  logic                        BREADY,

  // --------------------------------------------------------------------------
  // AXI4-Lite Read Address Channel
  // --------------------------------------------------------------------------
  input  logic [ADDR_WIDTH-1:0]       ARADDR,
  input  logic                        ARVALID,
  output logic                        ARREADY,

  // --------------------------------------------------------------------------
  // AXI4-Lite Read Data Channel
  // --------------------------------------------------------------------------
  output logic [DATA_WIDTH-1:0]       RDATA,
  output logic [1:0]                  RRESP,
  output logic                        RVALID,
  input  logic                        RREADY,

  // --------------------------------------------------------------------------
  // APB Clock & Reset
  // --------------------------------------------------------------------------
  input  logic                        PCLK,          // APB clock
  input  logic                        PRESETn,       // APB async active-low reset

  // --------------------------------------------------------------------------
  // APB Master Interface
  // --------------------------------------------------------------------------
  output logic [ADDR_WIDTH-1:0]       PADDR,         // APB address
  output logic [DATA_WIDTH-1:0]       PWDATA,        // APB write data
  output logic [NUM_APB_SLAVES-1:0]   PSEL,          // APB slave select (one-hot)
  output logic                        PENABLE,       // APB enable
  output logic                        PWRITE,        // APB write =1, read =0
  input  logic [DATA_WIDTH-1:0]       PRDATA,        // APB read data (from external mux)
  input  logic [NUM_APB_SLAVES-1:0]   PREADY,        // APB ready from slaves
  input  logic [NUM_APB_SLAVES-1:0]   PSLVERR        // APB error from slaves
);

  // ==========================================================================
  // Local parameters for FIFO payload widths
  // ==========================================================================
  localparam int STRB_WIDTH   = DATA_WIDTH / 8;
  localparam int WR_CMD_WIDTH = ADDR_WIDTH + DATA_WIDTH + STRB_WIDTH; // {addr, wdata, wstrb}
  localparam int RD_CMD_WIDTH = ADDR_WIDTH;                           // {addr}
  localparam int WR_RSP_WIDTH = 1;                                    // {error}
  localparam int RD_RSP_WIDTH = 1 + DATA_WIDTH;                       // {rdata, error}

  // ==========================================================================
  // Internal signals: AXI slave ↔ bridge (ACLK domain side of FIFOs)
  // ==========================================================================

  // Write-command stream from AXI slave to write_cmd FIFO
  logic                        wr_cmd_valid_s;
  logic                        wr_cmd_ready_s;
  logic [ADDR_WIDTH-1:0]       wr_cmd_addr_s;
  logic [DATA_WIDTH-1:0]       wr_cmd_wdata_s;
  logic [STRB_WIDTH-1:0]       wr_cmd_wstrb_s;

  // Write-response stream from write_rsp FIFO back to AXI slave
  logic                        wr_rsp_valid_s;
  logic                        wr_rsp_ready_s;
  logic                        wr_rsp_resp_s; // This holds the error bit

  // Read-command stream from AXI slave to read_cmd FIFO
  logic                        rd_cmd_valid_s;
  logic                        rd_cmd_ready_s;
  logic [ADDR_WIDTH-1:0]       rd_cmd_addr_s;

  // Read-response stream from read_rsp FIFO back to AXI slave
  logic                        rd_rsp_valid_s;
  logic                        rd_rsp_ready_s;
  logic [DATA_WIDTH-1:0]       rd_rsp_rdata_s;
  logic                        rd_rsp_resp_s; // This holds the error bit

  // ==========================================================================
  // Instantiate AXI4-Lite Slave Front-End (ACLK domain)
  // ==========================================================================
  axi_lite_slave #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) u_axi_lite_slave (
    // AXI clock + reset
    .ACLK        (ACLK),
    .ARESETn     (ARESETn),

    // AXI Write Address Channel
    .AWADDR      (AWADDR),
    .AWVALID     (AWVALID),
    .AWREADY     (AWREADY),

    // AXI Write Data Channel
    .WDATA       (WDATA),
    .WSTRB       (WSTRB),
    .WVALID      (WVALID),
    .WREADY      (WREADY),

    // AXI Write Response Channel
    .BRESP       (BRESP),
    .BVALID      (BVALID),
    .BREADY      (BREADY),

    // AXI Read Address Channel
    .ARADDR      (ARADDR),
    .ARVALID     (ARVALID),
    .ARREADY     (ARREADY),

    // AXI Read Data Channel
    .RDATA       (RDATA),
    .RRESP       (RRESP),
    .RVALID      (RVALID),
    .RREADY      (RREADY),

    // Write-command interface toward FIFO (ACLK side)
    .wr_cmd_valid(wr_cmd_valid_s),
    .wr_cmd_ready(wr_cmd_ready_s),
    .wr_cmd_addr (wr_cmd_addr_s),
    .wr_cmd_wdata(wr_cmd_wdata_s),
    .wr_cmd_wstrb(wr_cmd_wstrb_s),

    // Write response from APB side (ACLK side)
    .wr_rsp_valid(wr_rsp_valid_s),
    .wr_rsp_ready(wr_rsp_ready_s),
    .wr_rsp_error(wr_rsp_resp_s),

    // Read-command interface toward FIFO (ACLK side)
    .rd_cmd_valid(rd_cmd_valid_s),
    .rd_cmd_ready(rd_cmd_ready_s),
    .rd_cmd_addr (rd_cmd_addr_s),

    // Read response from APB side (ACLK side)
    .rd_rsp_valid(rd_rsp_valid_s),
    .rd_rsp_ready(rd_rsp_ready_s),
    .rd_rsp_rdata(rd_rsp_rdata_s),
    .rd_rsp_error(rd_rsp_resp_s)
  );

  // ==========================================================================
  // Async FIFOs: ACLK → PCLK (commands) and PCLK → ACLK (responses)
  // ==========================================================================

  // -----------------------------
  // Write-command FIFO (ACLK→PCLK)
  // -----------------------------
  logic                        wr_cmd_fifo_full;
  logic                        wr_cmd_fifo_empty;
  logic [WR_CMD_WIDTH-1:0]     wr_cmd_fifo_rdata;
  logic                        wr_cmd_rd_en_pclk;

  // AXI side: ready = FIFO not full
  assign wr_cmd_ready_s = ~wr_cmd_fifo_full;

  async_fifo #(
    .DATA_W      (WR_CMD_WIDTH),
    .FIFO_DEPTH  (FIFO_DEPTH)
  ) u_wr_cmd_fifo (
    .wr_clk   (ACLK),
    .wr_rst_n (ARESETn),
    .rd_clk   (PCLK),
    .rd_rst_n (PRESETn),

    // Write side (ACLK domain)
    .wr_en    (wr_cmd_valid_s && wr_cmd_ready_s),
    .wr_data  ({wr_cmd_addr_s, wr_cmd_wdata_s, wr_cmd_wstrb_s}),
    .full     (wr_cmd_fifo_full),

    // Read side (PCLK domain)
    .rd_en    (wr_cmd_rd_en_pclk),
    .rd_data  (wr_cmd_fifo_rdata),
    .empty    (wr_cmd_fifo_empty)
  );

  // Decode write-command payload in PCLK domain
  wire [ADDR_WIDTH-1:0] wr_cmd_addr_pclk  =
        wr_cmd_fifo_rdata[WR_CMD_WIDTH-1 : WR_CMD_WIDTH-ADDR_WIDTH];
  wire [DATA_WIDTH-1:0] wr_cmd_wdata_pclk =
        wr_cmd_fifo_rdata[STRB_WIDTH +: DATA_WIDTH];
  wire [STRB_WIDTH-1:0] wr_cmd_wstrb_pclk =
        wr_cmd_fifo_rdata[STRB_WIDTH-1:0];

  // -----------------------------
  // Read-command FIFO (ACLK→PCLK)
  // -----------------------------
  logic                        rd_cmd_fifo_full;
  logic                        rd_cmd_fifo_empty;
  logic [RD_CMD_WIDTH-1:0]     rd_cmd_fifo_rdata;
  logic                        rd_cmd_rd_en_pclk;

  // AXI side: ready = FIFO not full
  assign rd_cmd_ready_s = ~rd_cmd_fifo_full;

  async_fifo #(
    .DATA_W      (RD_CMD_WIDTH),
    .FIFO_DEPTH  (FIFO_DEPTH)
  ) u_rd_cmd_fifo (
    .wr_clk   (ACLK),
    .wr_rst_n (ARESETn),
    .rd_clk   (PCLK),
    .rd_rst_n (PRESETn),

    // Write side (ACLK domain)
    .wr_en    (rd_cmd_valid_s && rd_cmd_ready_s),
    .wr_data  (rd_cmd_addr_s),
    .full     (rd_cmd_fifo_full),

    // Read side (PCLK domain)
    .rd_en    (rd_cmd_rd_en_pclk),
    .rd_data  (rd_cmd_fifo_rdata),
    .empty    (rd_cmd_fifo_empty)
  );

  // Decode read-command payload in PCLK domain
  wire [ADDR_WIDTH-1:0] rd_cmd_addr_pclk =
        rd_cmd_fifo_rdata[ADDR_WIDTH-1:0];

  // Response interface from APB master FSM
  logic                        apb_rsp_valid;
  logic [DATA_WIDTH-1:0]       apb_rsp_rdata;
  logic                        apb_rsp_ready;
  logic                        apb_rsp_is_write;
  logic [1:0]                  apb_rsp_resp;

  logic                        apb_rsp_is_read;
  assign apb_rsp_is_read = ~apb_rsp_is_write;

  // -----------------------------
  // Write-response FIFO (PCLK→ACLK)
  // -----------------------------
  logic                        wr_rsp_fifo_full;
  logic                        wr_rsp_fifo_empty;
  logic [WR_RSP_WIDTH-1:0]     wr_rsp_fifo_rdata;
  logic                        wr_rsp_fifo_wr_en_pclk;
  logic                        wr_rsp_fifo_rd_en_aclk;

  wire [WR_RSP_WIDTH-1:0]      wr_rsp_fifo_wr_data = {apb_rsp_resp[1]};

  // AXI side view of write response
  assign wr_rsp_valid_s           = ~wr_rsp_fifo_empty;
  assign wr_rsp_resp_s            = wr_rsp_fifo_rdata[0];
  assign wr_rsp_fifo_rd_en_aclk   = wr_rsp_valid_s && wr_rsp_ready_s;

  async_fifo #(
    .DATA_W      (WR_RSP_WIDTH),
    .FIFO_DEPTH  (FIFO_DEPTH)
  ) u_wr_rsp_fifo (
    .wr_clk   (PCLK),
    .wr_rst_n (PRESETn),
    .rd_clk   (ACLK),
    .rd_rst_n (ARESETn),

    // Write side (PCLK domain)
    .wr_en    (wr_rsp_fifo_wr_en_pclk),
    .wr_data  (wr_rsp_fifo_wr_data),
    .full     (wr_rsp_fifo_full),

    // Read side (ACLK domain)
    .rd_en    (wr_rsp_fifo_rd_en_aclk),
    .rd_data  (wr_rsp_fifo_rdata),
    .empty    (wr_rsp_fifo_empty)
  );

  // -----------------------------
  // Read-response FIFO (PCLK→ACLK)
  // -----------------------------
  logic                        rd_rsp_fifo_full;
  logic                        rd_rsp_fifo_empty;
  logic [RD_RSP_WIDTH-1:0]     rd_rsp_fifo_rdata;
  logic                        rd_rsp_fifo_wr_en_pclk;
  logic                        rd_rsp_fifo_rd_en_aclk;

  wire [RD_RSP_WIDTH-1:0]      rd_rsp_fifo_wr_data = {apb_rsp_rdata, apb_rsp_resp[1]};

  // AXI side view of read response
  assign rd_rsp_valid_s           = ~rd_rsp_fifo_empty;
  assign rd_rsp_resp_s            = rd_rsp_fifo_rdata[0];
  assign rd_rsp_rdata_s           = rd_rsp_fifo_rdata[RD_RSP_WIDTH-1:1];
  assign rd_rsp_fifo_rd_en_aclk   = rd_rsp_valid_s && rd_rsp_ready_s;

  async_fifo #(
    .DATA_W      (RD_RSP_WIDTH),
    .FIFO_DEPTH  (FIFO_DEPTH)
  ) u_rd_rsp_fifo (
    .wr_clk   (PCLK),
    .wr_rst_n (PRESETn),
    .rd_clk   (ACLK),
    .rd_rst_n (ARESETn),

    // Write side (PCLK domain)
    .wr_en    (rd_rsp_fifo_wr_en_pclk),
    .wr_data  (rd_rsp_fifo_wr_data),
    .full     (rd_rsp_fifo_full),

    // Read side (ACLK domain)
    .rd_en    (rd_rsp_fifo_rd_en_aclk),
    .rd_data  (rd_rsp_fifo_rdata),
    .empty    (rd_rsp_fifo_empty)
  );

  // ==========================================================================
  // APB-domain arbiter + connection to APB master FSM (PCLK domain)
  // ==========================================================================
  logic                        apb_req_valid;
  logic                        apb_req_is_write;
  logic [ADDR_WIDTH-1:0]       apb_req_addr;
  logic [DATA_WIDTH-1:0]       apb_req_wdata;
  logic [NUM_APB_SLAVES-1:0]   apb_req_psel_onehot;
  logic                        apb_req_ready;

  always_comb begin
    apb_req_valid        = 1'b0;
    apb_req_is_write     = 1'b0;
    apb_req_addr         = '0;
    apb_req_wdata        = '0;
    apb_req_psel_onehot  = '0;
    wr_cmd_rd_en_pclk    = 1'b0;
    rd_cmd_rd_en_pclk    = 1'b0;

    if (!wr_cmd_fifo_empty) begin
      apb_req_valid            = 1'b1;
      apb_req_is_write         = 1'b1;
      apb_req_addr             = wr_cmd_addr_pclk;
      apb_req_wdata            = wr_cmd_wdata_pclk;
      apb_req_psel_onehot      = '0;
      apb_req_psel_onehot[0]   = 1'b1;

      if (apb_req_ready)
        wr_cmd_rd_en_pclk = 1'b1;

    end else if (!rd_cmd_fifo_empty) begin
      apb_req_valid            = 1'b1;
      apb_req_is_write         = 1'b0;
      apb_req_addr             = rd_cmd_addr_pclk;
      apb_req_wdata            = '0;
      apb_req_psel_onehot      = '0;
      apb_req_psel_onehot[0]   = 1'b1;

      if (apb_req_ready)
        rd_cmd_rd_en_pclk = 1'b1;
    end
  end

  // Response routing from APB master FSM into the two response FIFOs
  // FIX: Separate 'ready' calculation from 'valid' check to prevent DEADLOCK.
  // The FSM needs to know apb_rsp_ready=1 to proceed, so it cannot depend on valid.
  always_comb begin
    // 1. Calculate Ready independent of Valid
    if (apb_rsp_is_read)
       apb_rsp_ready = ~rd_rsp_fifo_full;
    else
       apb_rsp_ready = ~wr_rsp_fifo_full;

    // 2. Drive Write Enables based on Valid AND Ready
    wr_rsp_fifo_wr_en_pclk   = 1'b0;
    rd_rsp_fifo_wr_en_pclk   = 1'b0;

    if (apb_rsp_valid && apb_rsp_ready) begin
      if (apb_rsp_is_read) begin
          rd_rsp_fifo_wr_en_pclk = 1'b1;
      end else begin
          wr_rsp_fifo_wr_en_pclk = 1'b1;
      end
    end
  end

  // ==========================================================================
  // FIX: qualify PREADY/PSLVERR by currently selected slave (PSEL)
  // This prevents "phantom completes" when other slaves drive PREADY/PSLVERR.
  // ==========================================================================
  logic PREADY_sel;
  logic PSLVERR_sel;

  assign PREADY_sel  = |(PREADY  & PSEL);
  assign PSLVERR_sel = |(PSLVERR & PSEL);

  // ==========================================================================
  // APB Master FSM
  // ==========================================================================
  apb_master_fsm #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .NUM_APB_SLAVES (NUM_APB_SLAVES)
  ) u_apb_master_fsm (
    .PCLK            (PCLK),
    .PRESETn         (PRESETn),

    // Request from bridge
    .req_valid       (apb_req_valid),
    .req_is_write    (apb_req_is_write),
    .req_addr        (apb_req_addr),
    .req_wdata       (apb_req_wdata),
    .req_psel_onehot (apb_req_psel_onehot),
    .req_ready       (apb_req_ready),

    // APB bus
    .PADDR           (PADDR),
    .PWDATA          (PWDATA),
    .PSEL            (PSEL),
    .PENABLE         (PENABLE),
    .PWRITE          (PWRITE),
    .PRDATA          (PRDATA),
    .PREADY          (PREADY_sel),
    .PSLVERR         (PSLVERR_sel),

    // Response back to bridge
    .rsp_valid       (apb_rsp_valid),
    .rsp_is_write    (apb_rsp_is_write),
    .rsp_rdata       (apb_rsp_rdata),
    .rsp_resp        (apb_rsp_resp),
    .rsp_ready       (apb_rsp_ready)
  );

endmodule
