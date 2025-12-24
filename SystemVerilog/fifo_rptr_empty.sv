// Read-side pointer + EMPTY logic for async FIFO
// FIFO_DEPTH must be a power of two.
module fifo_rptr_empty #(
  parameter int unsigned FIFO_DEPTH = 4  // FIFO depth (must be power of two)
) (
  input  logic                            rd_clk,
  input  logic                            rd_rst_n,        // async active-low reset
  input  logic                            rd_en,           // read request
  input  logic [$clog2(FIFO_DEPTH):0]     wptr_gray_sync,  // write pointer (Gray), synchronized into rd_clk domain

  output logic [$clog2(FIFO_DEPTH):0]     rptr_bin,        // read pointer (binary, with extra MSB)
  output logic [$clog2(FIFO_DEPTH):0]     rptr_gray,       // read pointer (Gray)
  output logic [$clog2(FIFO_DEPTH)-1:0]   rd_addr,         // read address to RAM
  output logic                            empty            // FIFO empty (in read domain)
);

  // --------- Derived widths ---------
  localparam int unsigned ADDR_BITS = $clog2(FIFO_DEPTH);  // address bits
  localparam int unsigned PTR_BITS  = ADDR_BITS + 1;       // extra wrap bit

  // --------- Sanity check: FIFO_DEPTH is a power of two ---------
  initial begin
    if (FIFO_DEPTH < 2 || (FIFO_DEPTH & (FIFO_DEPTH - 1)) != 0) begin
      $fatal(1, "FIFO_DEPTH (%0d) must be a power of two >= 2", FIFO_DEPTH);
    end
  end

  // --------- Next-state signals ---------
  logic [PTR_BITS-1:0] rbin_next;
  logic [PTR_BITS-1:0] rgray_next;

  // Advance only when read is requested and not empty
  wire r_inc = rd_en & ~empty;

  // Compute next binary and Gray pointers
  always_comb begin
    rbin_next  = rptr_bin + r_inc;
    // Gray encode: g = b ^ (b >> 1)
    rgray_next = (rbin_next >> 1) ^ rbin_next;
  end

  // EMPTY detection (classic async FIFO rule in Gray space):
  // Empty if the *next* read Gray equals the synchronized write Gray.
  wire empty_next = (rgray_next == wptr_gray_sync);

  // --------- Registers ---------
  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      rptr_bin  <= '0;
      rptr_gray <= '0;
      empty     <= 1'b1;  // FIFO is empty after reset
    end else begin
      rptr_bin  <= rbin_next;
      rptr_gray <= rgray_next;
      empty     <= empty_next;
    end
  end

  // Read address: low ADDR_BITS of the binary read pointer
  assign rd_addr = rptr_bin[ADDR_BITS-1:0];

endmodule
