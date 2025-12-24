// Write-side pointer + FULL logic for async FIFO
// FIFO_DEPTH must be a power of two.
module fifo_wptr_full #(
  parameter int unsigned FIFO_DEPTH = 4   // FIFO depth (must be power of two)
) (
  input  logic                             wr_clk,
  input  logic                             wr_rst_n,       // async active-low
  input  logic                             wr_en,          // write request
  input  logic [$clog2(FIFO_DEPTH):0]      rptr_gray_sync, // read pointer (Gray) synchronized into wr_clk domain

  output logic [$clog2(FIFO_DEPTH):0]      wptr_bin,       // write pointer (binary, with extra MSB)
  output logic [$clog2(FIFO_DEPTH):0]      wptr_gray,      // write pointer (Gray)
  output logic [$clog2(FIFO_DEPTH)-1:0]    wr_addr,        // write address to RAM
  output logic                             full            // FIFO full (in write domain)
);

  // --------- Derived widths ---------
  localparam int unsigned ADDR_BITS = $clog2(FIFO_DEPTH);  // address bits
  localparam int unsigned PTR_BITS  = ADDR_BITS + 1;       // extra wrap bit

  // --------- Sanity check: FIFO_DEPTH is power of two ---------
  initial begin
    if (FIFO_DEPTH < 2 || (FIFO_DEPTH & (FIFO_DEPTH - 1)) != 0) begin
      $fatal(1, "FIFO_DEPTH (%0d) must be a power of two >= 2", FIFO_DEPTH);
    end
  end

  // --------- Next-state signals ---------
  logic [PTR_BITS-1:0] wbin_next;
  logic [PTR_BITS-1:0] wgray_next;

  // Increment only when write enabled and not full
  wire w_inc = wr_en & ~full;

  // Compute next binary and Gray pointers
  always_comb begin
    wbin_next  = wptr_bin + w_inc;
    // Gray encode: g = b ^ (b >> 1)
    wgray_next = (wbin_next >> 1) ^ wbin_next;
  end

  // FULL detection (classic async FIFO rule in Gray space):
  // Full if next write Gray equals read Gray with the top two bits inverted.
  wire [PTR_BITS-1:0] rgray_full_cmp = {
      ~rptr_gray_sync[PTR_BITS-1:PTR_BITS-2],
       rptr_gray_sync[PTR_BITS-3:0]
  };

  wire full_next = (wgray_next == rgray_full_cmp);

  // --------- Registers ---------
  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      wptr_bin  <= '0;
      wptr_gray <= '0;
      full      <= 1'b0;
    end else begin
      wptr_bin  <= wbin_next;
      wptr_gray <= wgray_next;
      full      <= full_next;
    end
  end

  // Write address is the low ADDR_BITS of the binary pointer
  assign wr_addr = wptr_bin[ADDR_BITS-1:0];

endmodule
