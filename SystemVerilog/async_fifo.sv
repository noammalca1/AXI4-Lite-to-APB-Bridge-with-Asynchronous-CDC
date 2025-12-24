
module async_fifo #(
  parameter int unsigned FIFO_DEPTH = 4,   // FIFO depth (must be power of 2)
  parameter int unsigned DATA_W      = 8
) (
  // Write domain
  input  logic                 wr_clk,
  input  logic                 wr_rst_n,   // async active-low
  input  logic                 wr_en,
  input  logic [DATA_W-1:0]    wr_data,
  output logic                 full,

  // Read domain
  input  logic                 rd_clk,
  input  logic                 rd_rst_n,   // async active-low
  input  logic                 rd_en,
  output logic [DATA_W-1:0]    rd_data,
  output logic                 empty
);

  // ---------------- Derived constants ----------------
  localparam int unsigned ADDR_BITS = $clog2(FIFO_DEPTH);
  localparam int unsigned PTR_BITS  = ADDR_BITS + 1;

  // Sanity: FIFO_DEPTH is power of two >= 2
  initial begin
    if (FIFO_DEPTH < 2 || (FIFO_DEPTH & (FIFO_DEPTH - 1)) != 0)
      $fatal(1, "FIFO_DEPTH (%0d) must be a power of two >= 2", FIFO_DEPTH);
  end

  // ---------------- FIFO memory ----------------
  // Simple dual-port RAM model: write @wr_clk, read @rd_clk
  logic [DATA_W-1:0] mem [0:FIFO_DEPTH-1];

  // ---------------- Write side ----------------
  logic [PTR_BITS-1:0]  wptr_bin,  wptr_gray;
  logic [ADDR_BITS-1:0] wr_addr;

  // Synchronized read pointer (Gray) into wr_clk domain
  logic [PTR_BITS-1:0]  rptr_gray_sync;

  // Write-pointer + FULL logic
  fifo_wptr_full #(.FIFO_DEPTH(FIFO_DEPTH)) u_wptr_full (
    .wr_clk         (wr_clk),
    .wr_rst_n       (wr_rst_n),
    .wr_en          (wr_en),
    .rptr_gray_sync (rptr_gray_sync),

    .wptr_bin       (wptr_bin),
    .wptr_gray      (wptr_gray),
    .wr_addr        (wr_addr),
    .full           (full)
  );

  // Actual write to memory
  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      // no need to reset RAM for functionality
    end else if (wr_en && !full) begin
      mem[wr_addr] <= wr_data;
    end
  end

  // ---------------- Read side ----------------
  logic [PTR_BITS-1:0]  rptr_bin,  rptr_gray;
  logic [ADDR_BITS-1:0] rd_addr;

  // Synchronized write pointer (Gray) into rd_clk domain
  logic [PTR_BITS-1:0]  wptr_gray_sync;

  // Read-pointer + EMPTY logic
  fifo_rptr_empty #(.FIFO_DEPTH(FIFO_DEPTH)) u_rptr_empty (
    .rd_clk         (rd_clk),
    .rd_rst_n       (rd_rst_n),
    .rd_en          (rd_en),
    .wptr_gray_sync (wptr_gray_sync),

    .rptr_bin       (rptr_bin),
    .rptr_gray      (rptr_gray),
    .rd_addr        (rd_addr),
    .empty          (empty)
  );

  // ---------------- FWFT Read: combinational data path ----------------
  assign rd_data = mem[rd_addr];

  // ---------------- CDC: 2FF synchronizers ----------------
  // rptr_gray -> wr_clk domain
  sync_2ff #(.WIDTH(PTR_BITS)) u_sync_rptr_to_wr (
    .clk       (wr_clk),
    .rst_n     (wr_rst_n),
    .din_async (rptr_gray),
    .dout_sync (rptr_gray_sync)
  );

  // wptr_gray -> rd_clk domain
  sync_2ff #(.WIDTH(PTR_BITS)) u_sync_wptr_to_rd (
    .clk       (rd_clk),
    .rst_n     (rd_rst_n),
    .din_async (wptr_gray),
    .dout_sync (wptr_gray_sync)
  );

endmodule
