`timescale 1ns / 1ps

module tb_top;

    // -------------------------------------------------------------------------
    // Signal Declarations
    // -------------------------------------------------------------------------
    logic        clk;
    logic        rst_n;       // Active-low reset

    // Handshake & Control
    logic        start;
    logic        finish;
    logic        shift;

    // Enables (Connected between FSM and Incrementer)
    logic        rd_en;
    logic        wr_en;

    // Address & Counter Outputs
    logic [14:0] rd_addr;
    logic [6:0]  rd_col;
    logic [8:0]  rd_row;

    logic [14:0] wr_addr;
    logic [6:0]  wr_col;
    logic [8:0]  wr_row;

    // End Flags
    logic        rd_row_end;
    logic        wr_row_end;
    logic        wr_col_end;

    logic wr_wrap;
    logic rd_wrap;

    // -------------------------------------------------------------------------
    // Clock Generation (100 MHz -> 10ns period)
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Module Instantiations
    // -------------------------------------------------------------------------

    // FSM Instance
    fsm u_fsm (
        .clk        (clk),
        .rst_n      (rst_n),        // Active-low reset input (~rst)
        .rd_en      (rd_en),
        .wr_en      (wr_en),
        .start      (start),
        .finish     (finish),
        .shift      (shift),
        .rd_row_end (rd_row_end),
        .wr_row_end (wr_row_end),
        .wr_col_end (wr_col_end),
        .wr_wrap    (wr_wrap),
        .rd_wrap    (rd_wrap)
    );

    // Address Incrementer Instance
    addr_incrementer u_addr_inc (
        .clk        (clk),
        .rst_n      (rst_n),
        .rd_inc     (rd_en),        // Driven by FSM's read enable
        .wr_inc     (wr_en),        // Driven by FSM's write enable
        .rd_addr    (rd_addr),
        .rd_col     (rd_col),
        .rd_row     (rd_row),
        .wr_addr    (wr_addr),
        .wr_col     (wr_col),
        .wr_row     (wr_row),
        .rd_row_end (rd_row_end),
        .wr_row_end (wr_row_end),
        .wr_col_end (wr_col_end),
        .wr_wrap    (wr_wrap),
        .rd_wrap    (rd_wrap)
    );

    // -------------------------------------------------------------------------
    // Test Sequence & Stimulus
    // -------------------------------------------------------------------------
    initial begin
        // Waveform dump for GTKWave/ModelSim/Vivado
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        // Initialize signals
        rst_n = 0;
        start = 0;

        // 1. Reset Sequence
        #20;
        rst_n = 1;
        #20;

        $display("[%0t ns] --- Starting FSM Simulation ---", $time);

        // 2. Pulse Start Handshake Signal
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // 3. Monitor Execution & Wait for Finish (with Watchdog)
        fork
            begin
                wait (finish == 1'b1);
                $display("[%0t ns] SUCCESS: 'finish' flag asserted!", $time);
                $display("[%0t ns] Final Counters: rd_row = %0d, wr_row = %0d", $time, rd_row, wr_row);
            end
            begin
                // Timeout safeguard (500,000 cycles / 5ms)
                #5000000;
                $error("[%0t ns] ERROR: Simulation Timed Out before finish!", $time);
            end
        join_any
        disable fork;

        // 4. Wrap up
        #100;
        $display("[%0t ns] --- Simulation Complete ---", $time);
        $finish;
    end

    // -------------------------------------------------------------------------
    // Real-Time Event Logging
    // -------------------------------------------------------------------------
    // Log key line transitions
    always @(posedge clk) begin
        if (shift) begin
            $display("[%0t ns] [EVENT] Shift Pulse | wr_row=%0d, rd_row=%0d", $time, wr_row, rd_row);
        end
    end

endmodule
