`timescale 1ns/1ps

module tb_axi_apb_bridge_top;

  // ------------------------------------------------------------
  // 1. Parameters
  // ------------------------------------------------------------
  localparam int ADDR_WIDTH      = 32;
  localparam int DATA_WIDTH      = 32;
  localparam int NUM_APB_SLAVES = 1;
  localparam int FIFO_DEPTH      = 4;
  localparam int STRB_WIDTH      = DATA_WIDTH/8;

  // ------------------------------------------------------------
  // 2. Signals & Clocks
  // ------------------------------------------------------------
  logic ACLK = 0;
  logic PCLK = 0;
  logic ARESETn, PRESETn;

  // Clock Generation
  always #5   ACLK = ~ACLK;   // 100MHz
  always #10  PCLK = ~PCLK;   //  50MHz

  // AXI4-Lite Signals
  logic [ADDR_WIDTH-1:0] AWADDR;
  logic                  AWVALID, AWREADY;
  logic [DATA_WIDTH-1:0] WDATA;
  logic [STRB_WIDTH-1:0] WSTRB;
  logic                  WVALID, WREADY;
  logic [1:0]            BRESP;
  logic                  BVALID, BREADY;

  logic [ADDR_WIDTH-1:0] ARADDR;
  logic                  ARVALID, ARREADY;
  logic [DATA_WIDTH-1:0] RDATA;
  logic [1:0]            RRESP;
  logic                  RVALID, RREADY;

  // APB Signals
  logic [ADDR_WIDTH-1:0]      PADDR;
  logic [DATA_WIDTH-1:0]      PWDATA;
  logic [NUM_APB_SLAVES-1:0]  PSEL;
  logic                        PENABLE;
  logic                        PWRITE;
  logic [DATA_WIDTH-1:0]      PRDATA;
  logic [NUM_APB_SLAVES-1:0]  PREADY;
  logic [NUM_APB_SLAVES-1:0]  PSLVERR;

  // ------------------------------------------------------------
  // 3. DUT Instantiation
  // ------------------------------------------------------------
  axi_apb_bridge_top #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH),
    .NUM_APB_SLAVES (NUM_APB_SLAVES),
    .FIFO_DEPTH     (FIFO_DEPTH)
  ) dut (
    .ACLK     (ACLK),
    .ARESETn  (ARESETn),

    .AWADDR   (AWADDR),
    .AWVALID  (AWVALID),
    .AWREADY  (AWREADY),

    .WDATA    (WDATA),
    .WSTRB    (WSTRB),
    .WVALID   (WVALID),
    .WREADY   (WREADY),

    .BRESP    (BRESP),
    .BVALID   (BVALID),
    .BREADY   (BREADY),

    .ARADDR   (ARADDR),
    .ARVALID  (ARVALID),
    .ARREADY  (ARREADY),

    .RDATA    (RDATA),
    .RRESP    (RRESP),
    .RVALID   (RVALID),
    .RREADY   (RREADY),

    .PCLK     (PCLK),
    .PRESETn  (PRESETn),

    .PADDR    (PADDR),
    .PWDATA   (PWDATA),
    .PSEL     (PSEL),
    .PENABLE  (PENABLE),
    .PWRITE   (PWRITE),
    .PRDATA   (PRDATA),
    .PREADY   (PREADY),
    .PSLVERR  (PSLVERR)
  );

  // ------------------------------------------------------------
  // 4. Simple APB Slave Model (controllable PREADY)
  // ------------------------------------------------------------
  logic [DATA_WIDTH-1:0] mem [0:15];

  always_comb begin
    if (PSEL[0] && !PWRITE) PRDATA = mem[PADDR[5:2]];
    else                    PRDATA = '0;
  end

  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      for (int i = 0; i < 16; i++) mem[i] <= '0;
    end else begin
      if (PSEL[0] && PENABLE && PWRITE && PREADY[0]) begin
        mem[PADDR[5:2]] <= PWDATA;
        $display("[%0t] APB WRITE: addr=0x%08h data=0x%08h", $time, PADDR, PWDATA);
      end
    end
  end

  assign PSLVERR[0] = 1'b0;

  // ------------------------------------------------------------
  // 5. Handshake counters (ONLY driven here!)
  // ------------------------------------------------------------
  int unsigned b_hs_count;
  int unsigned r_hs_count;

  always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
      b_hs_count <= 0;
      r_hs_count <= 0;
    end else begin
      if (BVALID && BREADY) b_hs_count <= b_hs_count + 1;
      if (RVALID && RREADY) r_hs_count <= r_hs_count + 1;
    end
  end

  // ------------------------------------------------------------
  // 6. FULL RESET TASK (call before each test)
  // ------------------------------------------------------------
  task automatic system_reset(
    input int unsigned aclk_cycles = 5,
    input int unsigned pclk_cycles = 3
  );
    int unsigned k;
    begin
      // Drive safe AXI defaults (avoid an old transaction staying alive)
      AWADDR  = '0; AWVALID = 1'b0;
      WDATA   = '0; WSTRB   = '0; WVALID = 1'b0;
      BREADY  = 1'b0;

      ARADDR  = '0; ARVALID = 1'b0;
      RREADY  = 1'b0;

      // Default APB behavior during reset
      PREADY[0] = 1'b1;

      // Assert resets (async active-low)
      ARESETn = 1'b0;
      PRESETn = 1'b0;

      // Hold reset for a few cycles in BOTH domains
      for (k = 0; k < aclk_cycles; k++) @(posedge ACLK);
      for (k = 0; k < pclk_cycles; k++) @(posedge PCLK);

      // Release resets
      ARESETn = 1'b1;
      PRESETn = 1'b1;

      // Give time for CDC/FIFOs to settle
      repeat (10) @(posedge ACLK);
      repeat (5)  @(posedge PCLK);

      // (Optional explicit clear; PRESETn already clears mem in always_ff)
      // for (int i = 0; i < 16; i++) mem[i] = '0;

      $display("[%0t] FULL RESET DONE (ACLK=%0d cycles, PCLK=%0d cycles)",
               $time, aclk_cycles, pclk_cycles);
    end
  endtask

  // ------------------------------------------------------------
  // 7. AXI Tasks
  // ------------------------------------------------------------
  task automatic axi_read_addr(input [ADDR_WIDTH-1:0] addr);
    begin
      @(posedge ACLK);
      ARADDR  <= addr;
      ARVALID <= 1'b1;
      RREADY <=1'b1;

      wait (ARREADY);
      @(posedge ACLK);
      ARVALID <= 1'b0;

      $display("[%0t] AR accepted: addr=0x%08h", $time, addr);
    end
  endtask

  task automatic axi_read(
    input [ADDR_WIDTH-1:0] addr,
    input int unsigned     MAX_CYCLES = 200
  );
    int unsigned cycles;
    bit ar_done;
    begin
      ar_done = 0;

      @(posedge ACLK);
      ARADDR  <= addr;
      ARVALID <= 1'b1;

      for (cycles = 0; cycles < MAX_CYCLES; cycles++) begin
        @(posedge ACLK);
        if (ARVALID && ARREADY) begin
          ar_done  = 1;
          ARVALID <= 1'b0;
          break;
        end
      end

      if (!ar_done) begin
        ARVALID <= 1'b0;
        $display("[%0t] AR BLOCKED (no accept within %0d cycles): addr=0x%08h",
                 $time, MAX_CYCLES, addr);
      end else begin
        $display("[%0t] AR ACCEPTED (no R wait): addr=0x%08h", $time, addr);
      end
    end
  endtask

  task automatic axi_write(
    input [ADDR_WIDTH-1:0] addr,
    input [DATA_WIDTH-1:0] data,
    input int unsigned     MAX_CYCLES = 200
  );
    int unsigned cycles;
    bit aw_done, w_done;
    begin
      aw_done = 0;
      w_done  = 0;

      @(posedge ACLK);
      AWADDR  <= addr;
      AWVALID <= 1'b1;

      WDATA   <= data;
      WSTRB   <= '1;
      WVALID  <= 1'b1;

      for (cycles = 0; cycles < MAX_CYCLES; cycles++) begin
        @(posedge ACLK);

        if (!aw_done && AWVALID && AWREADY) begin
          aw_done  = 1;
          AWVALID <= 1'b0;
        end

        if (!w_done && WVALID && WREADY) begin
          w_done  = 1;
          WVALID <= 1'b0;
        end

        if (aw_done && w_done) break;
      end

      if (!(aw_done && w_done)) begin
        AWVALID <= 1'b0;
        WVALID  <= 1'b0;
        $display("[%0t] AXI WRITE CMD BLOCKED: addr=0x%08h data=0x%08h (AW=%0b W=%0b)",
                 $time, addr, data, aw_done, w_done);
      end else begin
        $display("[%0t] AXI WRITE CMD ACCEPTED: addr=0x%08h data=0x%08h",
                 $time, addr, data);
      end
    end
  endtask

  task automatic wait_for_writes(input int unsigned N);
    int unsigned got;
    begin
      got = 0;
      while (got < N) begin
        @(posedge ACLK);
        if (BVALID && BREADY) begin
          $display("[%0t] B handshake: BRESP=%0h (%0d/%0d)",
                   $time, BRESP, got+1, N);
          got++;
        end
      end
    end
  endtask

  task automatic wait_for_reads(input int unsigned N);
    int unsigned got;
    begin
      got = 0;
      while (got < N) begin
        @(posedge ACLK);
        if (RVALID && RREADY) begin
          $display("[%0t] R handshake: RDATA=0x%08h RRESP=%0h (%0d/%0d)",
                   $time, RDATA, RRESP, got+1, N);
          got++;
        end
      end
    end
  endtask

  // ------------------------------------------------------------
  // 8. Watchdog
  // ------------------------------------------------------------
  initial begin
    #800000; // 800us
    $error("TIMEOUT: Testbench hung unexpectedly.");
    $finish;
  end

  // ------------------------------------------------------------
  // 9. Main Test
  // ------------------------------------------------------------
  int i;
  int unsigned b0, r0; // baselines

  logic [ADDR_WIDTH-1:0] arb_wr_addr [0:3];
  logic [DATA_WIDTH-1:0] arb_wr_data [0:3];
  logic [ADDR_WIDTH-1:0] arb_rd_addr [0:3];

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_axi_apb_bridge_top);

    // Init arbitration vectors
    arb_wr_addr[0] = 32'h0000_0100; arb_wr_data[0] = 32'h1111_0001;
    arb_wr_addr[1] = 32'h0000_0104; arb_wr_data[1] = 32'h1111_0002;
    arb_wr_addr[2] = 32'h0000_0108; arb_wr_data[2] = 32'h1111_0003;
    arb_wr_addr[3] = 32'h0000_010C; arb_wr_data[3] = 32'h1111_0004;

    arb_rd_addr[0] = 32'h0000_0100;
    arb_rd_addr[1] = 32'h0000_0104;
    arb_rd_addr[2] = 32'h0000_0108;
    arb_rd_addr[3] = 32'h0000_010C;

    $display("--- START SIMULATION ---");

    // ============================================================
    // TEST 0  (reset before test)
    // ============================================================
    system_reset();

    $display("\n==================================================");
    $display("TEST 0: READ request while system is empty (APB stalled)");
    $display("==================================================\n");

    @(posedge PCLK);
    PREADY[0] = 1'b0;
    $display("[%0t] APB stalled: PREADY[0]=0", $time);

    axi_read_addr(32'h0000_0040);

    repeat (30) @(posedge ACLK);
    if (RVALID === 1'b0) $display("[%0t] PASS: No RVALID while APB stalled.", $time);
    else                 $error("[%0t] FAIL: RVALID asserted while APB stalled!", $time);

    // Release APB so system won't stay stuck
    @(posedge PCLK);
    PREADY[0] = 1'b1;
    $display("[%0t] APB released after TEST 0: PREADY[0]=1", $time);

    repeat (20) @(posedge ACLK);

    // ============================================================
    // TEST 1 (reset before test)
    // ============================================================
    system_reset();

    $display("\n==================================================");
    $display("TEST 1: APB STALL + 6 WRITES, RELEASE AFTER 5TH");
    $display("==================================================\n");

    b0 = b_hs_count;

    @(posedge PCLK);
    PREADY[0] = 1'b0;
    $display("[%0t] APB stalled for TEST 1: PREADY[0]=0", $time);

    BREADY = 1'b0;
    RREADY = 1'b0;

    axi_write(32'h0000_0100, 32'hAAAA_0001);
    axi_write(32'h0000_0104, 32'hAAAA_0002);
    axi_write(32'h0000_0108, 32'hAAAA_0003);
    axi_write(32'h0000_010C, 32'hAAAA_0004);

    axi_write(32'h0000_0110, 32'hAAAA_0005);

    // wait 20 cycles from the 5th issue, then release APB
    repeat (20) @(posedge ACLK);
    @(posedge PCLK);
    PREADY[0] = 1'b1;
    $display("[%0t] APB released 20 cycles after 5th write: PREADY[0]=1", $time);

    axi_write(32'h0000_0114, 32'hAAAA_0006);

    // Drain B responses
    repeat (100) @(negedge ACLK);
    BREADY = 1'b1;

    // wait enough time for 6 writes to drain
    repeat (150) @(posedge ACLK);

    $display("[%0t] TEST 1 summary: new B handshakes = %0d",
             $time, (b_hs_count - b0));

    // ============================================================
    // TEST 2 (reset before test)
    // ============================================================
    system_reset();

    $display("\n==================================================");
    $display("TEST 2: ARBITRATION (SIMULTANEOUS READ & WRITE)");
    $display("==================================================\n");

    b0 = b_hs_count;
    r0 = r_hs_count;

    @(posedge PCLK);
    PREADY[0] = 1'b0;
    $display("[%0t] APB stalled for TEST 2: PREADY[0]=0", $time);

    BREADY = 1'b0;
    RREADY = 1'b0;

    // Queue 4 writes + 4 reads interleaved
    for (i = 0; i < 4; i++) begin
      axi_write(arb_wr_addr[i], arb_wr_data[i]);
      axi_read (arb_rd_addr[i]);
    end

    // Release APB
    repeat (5)  @(posedge PCLK);
    @(posedge PCLK);
    PREADY[0] = 1'b1;
    $display("[%0t] APB released for TEST 2: PREADY[0]=1", $time);

    // Now consume responses
    @(posedge ACLK);
    BREADY = 1'b1;
    RREADY = 1'b1;

    // We expect 4 B + 4 R if all commands were accepted.
    wait_for_writes(4);
    wait_for_reads(4);
    repeat (1)  @(posedge PCLK);
    $display("[%0t] TEST 2 summary: new B=%0d new R=%0d",
             $time, (b_hs_count - b0), (r_hs_count - r0));

    // Check memory contains what we wrote
    for (i = 0; i < 4; i++) begin
      if (mem[arb_rd_addr[i][5:2]] !== arb_wr_data[i]) begin
        $error("TEST 2 FAIL: mem[%0d]=0x%08h expected=0x%08h",
               arb_rd_addr[i][5:2], mem[arb_rd_addr[i][5:2]], arb_wr_data[i]);
      end else begin
        $display("TEST 2 PASS: mem[%0d]=0x%08h",
                 arb_rd_addr[i][5:2], mem[arb_rd_addr[i][5:2]]);
      end
    end
    repeat (20)  @(posedge PCLK);
    $display("\n--- ALL TESTS FINISHED ---");
    $finish;
  end

endmodule
