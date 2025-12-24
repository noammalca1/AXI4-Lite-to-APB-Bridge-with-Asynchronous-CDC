module apb_master_fsm #(
    parameter ADDR_WIDTH      = 32,
    parameter DATA_WIDTH      = 32,
    parameter NUM_APB_SLAVES  = 1
)(
    input  logic                      PCLK,
    input  logic                      PRESETn,

    // Request (from Command FIFO)
    input  logic                      req_valid,
    input  logic                      req_is_write,
    input  logic [ADDR_WIDTH-1:0]     req_addr,
    input  logic [DATA_WIDTH-1:0]     req_wdata,
    input  logic [NUM_APB_SLAVES-1:0] req_psel_onehot,
    output logic                      req_ready,

    // APB Interface
    output logic [ADDR_WIDTH-1:0]     PADDR,
    output logic [DATA_WIDTH-1:0]     PWDATA,
    output logic [NUM_APB_SLAVES-1:0] PSEL,
    output logic                      PWRITE,
    output logic                      PENABLE,
    input  logic [DATA_WIDTH-1:0]     PRDATA,
    input  logic                      PREADY,
    input  logic                      PSLVERR,

    // Response (to Response FIFO)
    output logic                      rsp_valid,
    output logic                      rsp_is_write,
    output logic [DATA_WIDTH-1:0]     rsp_rdata,
    output logic [1:0]                rsp_resp,
    input  logic                      rsp_ready
);

  // Response codes
  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;

  // 1. FSM States
  typedef enum logic [1:0] {
    ST_IDLE,
    ST_SETUP,
    ST_ACCESS,
    ST_RSP_WAIT  // NEW: State to hold result if FIFO is full
  } state_t;

  state_t state, state_n;

  // 2. Latched Request (Current Transaction)
  logic                      is_write_q;
  logic [ADDR_WIDTH-1:0]     addr_q;
  logic [DATA_WIDTH-1:0]     wdata_q;
  logic [NUM_APB_SLAVES-1:0] psel_q;

  // 3. Pending Result Registers (Latch & Drop mechanism)
  // These store the result from the slave while we wait for FIFO space.
  logic                      pend_valid_q,   pend_valid_n;
  logic [DATA_WIDTH-1:0]     pend_rdata_q,   pend_rdata_n;
  logic [1:0]                pend_resp_q,    pend_resp_n;

  // 4. Output Response Registers
  logic                      rsp_valid_q,    rsp_valid_n;
  logic                      rsp_is_write_q, rsp_is_write_n;
  logic [DATA_WIDTH-1:0]     rsp_rdata_q,    rsp_rdata_n;
  logic [1:0]                rsp_resp_q,     rsp_resp_n;

  // ==========================================================================
  // Combinational FSM Logic
  // ==========================================================================
  always_comb begin
    // Defaults
    state_n = state;
    req_ready = 1'b0;

    // APB Outputs (Default: driven by latched request)
    PADDR   = addr_q;
    PWDATA  = wdata_q;
    PWRITE  = is_write_q;
    PSEL    = '0;    // Driven active only in SETUP/ACCESS
    PENABLE = 1'b0;  // Driven active only in ACCESS

    // Response Next-State Logic (Hold previous by default)
    rsp_valid_n    = rsp_valid_q;
    rsp_is_write_n = rsp_is_write_q;
    rsp_rdata_n    = rsp_rdata_q;
    rsp_resp_n     = rsp_resp_q;

    // Pending Logic (Hold previous by default)
    pend_valid_n   = pend_valid_q;
    pend_rdata_n   = pend_rdata_q;
    pend_resp_n    = pend_resp_q;

    case (state)

      // --------------------------------------------------------------------
      // ST_IDLE
      // --------------------------------------------------------------------
      ST_IDLE: begin
        // Only accept new request if we aren't currently trying to push a response
        // (This flow control check is simple; optimization possible)
        if (!rsp_valid_q && !pend_valid_q) begin
          req_ready = 1'b1;
          if (req_valid) begin
            state_n = ST_SETUP;
          end
        end
      end

      // --------------------------------------------------------------------
      // ST_SETUP
      // --------------------------------------------------------------------
      ST_SETUP: begin
        PSEL    = psel_q; // Assert Select
        PENABLE = 1'b0;   // De-assert Enable
        state_n = ST_ACCESS;
      end

      // --------------------------------------------------------------------
      // ST_ACCESS
      // --------------------------------------------------------------------
      ST_ACCESS: begin
        PSEL    = psel_q; // Keep Select
        PENABLE = 1'b1;   // Assert Enable

        if (PREADY) begin
          // --- APB TRANSACTION COMPLETE ---
          // The slave has finished. We MUST drop PENABLE next cycle.

          // Path A: Optimization - If FIFO has space NOW, push immediately.
          if (rsp_ready) begin
            rsp_valid_n    = 1'b1;
            rsp_is_write_n = is_write_q;
            rsp_resp_n     = PSLVERR ? RESP_SLVERR : RESP_OKAY;
            if (!is_write_q) rsp_rdata_n = PRDATA;
            
            // Transaction done, result handled. Go to IDLE.
            // (Note: To support back-to-back, you could check req_valid here
            // and jump to SETUP, but IDLE is safer for now).
            state_n = ST_IDLE;
          end
          
          // Path B: Backpressure - FIFO is FULL. Latch and Wait.
          else begin
            pend_valid_n = 1'b1;
            pend_resp_n  = PSLVERR ? RESP_SLVERR : RESP_OKAY;
            if (!is_write_q) pend_rdata_n = PRDATA;
            // Note: We don't need to save 'is_write' separately in pend
            // because 'is_write_q' stays stable until we take a NEW request.
            
            // Go to Wait State to drop APB signals
            state_n = ST_RSP_WAIT;
          end
        end
      end

      // --------------------------------------------------------------------
      // ST_RSP_WAIT (New)
      // --------------------------------------------------------------------
      ST_RSP_WAIT: begin
        // APB signals are all 0 (Defaults applied at top of always_comb).
        // PSEL=0, PENABLE=0. Safe!

        // We are just waiting for the Response FIFO to accept our pending data.
        if (rsp_ready) begin
          // Push the pending data
          rsp_valid_n    = 1'b1;
          rsp_is_write_n = is_write_q; 
          rsp_rdata_n    = pend_rdata_q;
          rsp_resp_n     = pend_resp_q;

          // Clear pending flag
          pend_valid_n   = 1'b0;

          // Done.
          state_n = ST_IDLE;
        end
      end

    endcase
  end

  // ==========================================================================
  // Sequential Logic
  // ==========================================================================
  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      state          <= ST_IDLE;
      is_write_q     <= 1'b0;
      addr_q         <= '0;
      wdata_q        <= '0;
      psel_q         <= '0;
      
      rsp_valid_q    <= 1'b0;
      rsp_is_write_q <= 1'b0;
      rsp_resp_q     <= RESP_OKAY;
      rsp_rdata_q    <= '0;

      pend_valid_q   <= 1'b0;
      pend_rdata_q   <= '0;
      pend_resp_q    <= RESP_OKAY;
    end
    else begin
      state <= state_n;

      // Request Capture
      if (state == ST_IDLE && req_ready && req_valid) begin
        is_write_q <= req_is_write;
        addr_q     <= req_addr;
        wdata_q    <= req_wdata;
        psel_q     <= req_psel_onehot;
      end

      // Response Output Update
      rsp_valid_q    <= rsp_valid_n;
      rsp_is_write_q <= rsp_is_write_n;
      rsp_resp_q     <= rsp_resp_n;
      rsp_rdata_q    <= rsp_rdata_n;

      // Clear valid after handshake
      if (rsp_valid_q && rsp_ready) begin
        rsp_valid_q <= 1'b0;
      end

      // Pending Registers Update
      pend_valid_q   <= pend_valid_n;
      pend_rdata_q   <= pend_rdata_n;
      pend_resp_q    <= pend_resp_n;
    end
  end

  // Assignments
  assign rsp_valid    = rsp_valid_q;
  assign rsp_is_write = rsp_is_write_q;
  assign rsp_rdata    = rsp_rdata_q;
  assign rsp_resp     = rsp_resp_q;

endmodule
