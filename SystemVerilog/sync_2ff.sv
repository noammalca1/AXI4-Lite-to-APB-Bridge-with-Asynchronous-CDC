module sync_2ff #(parameter int unsigned WIDTH = 4)
  (
  input  logic                 clk,       // destination clock
  input  logic                 rst_n,     // async active-low reset (in destination domain)
  input  logic [WIDTH-1:0]     din_async, // from source clock domain
  output logic [WIDTH-1:0]     dout_sync  // synchronized into 'clk' domain
);

  logic [WIDTH-1:0] d1_q, d2_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      d1_q <= '0;
      d2_q <= '0;
    end
    else begin
      d1_q <= din_async; // may go metastable briefly
      d2_q <= d1_q;      // resolves by next cycle
    end
  end

  assign dout_sync = d2_q;

endmodule
