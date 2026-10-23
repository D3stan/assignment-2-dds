`timescale 1ns / 1ps

module tb_fsm;

    // -------------------------------------------------------------
    // Image Dimensions & Clock Parameters
    // -------------------------------------------------------------
    localparam int IMG_COLS     = 88;
    localparam int IMG_ROWS     = 288;
    localparam int TOTAL_PIXELS = IMG_COLS * IMG_ROWS; // 25,344
    localparam time CLK_PERIOD  = 10ns;

    // -------------------------------------------------------------
    // DUT Interface Signals
    // -------------------------------------------------------------
    logic clk;
    logic rst;

    // Handshake
    logic start;
    logic finish;

    // Read / Write ports
    logic rd_en;
    logic wr_en;

    // Cache / buffer control
    logic rd_ready;
    logic shift;

    // Status / Control inputs to DUT
    logic rd_row_end; // Asserted when rd_col == 88
    logic wr_row_end; // Asserted when wr_col == 88
    logic wr_col_end; // Asserted when wr_row == 87

    // -------------------------------------------------------------
    // Datapath Emulation Registers
    // -------------------------------------------------------------
    int unsigned rd_addr;
    int unsigned wr_addr;

    int unsigned rd_col;
    int unsigned rd_row;

    int unsigned wr_col;
    int unsigned wr_row;

    // -------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------
    fsm dut (
        .clk        (clk),
        .rst        (rst),
        .rd_en      (rd_en),
        .wr_en      (wr_en),
        .start      (start),
        .finish     (finish),
        .rd_ready   (rd_ready),
        .shift      (shift),
        .rd_row_end (rd_row_end),
        .wr_row_end (wr_row_end),
        .wr_col_end (wr_col_end)
    );

    // -------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // -------------------------------------------------------------
    // Datapath Emulation: Address and Coordinate Counters
    // Counts: 0..88 inclusive
    // -------------------------------------------------------------
    always_ff @(posedge clk or negedge rst) begin
        if (~rst) begin
            rd_addr <= '0;
            rd_col  <= '0;
            rd_row  <= '0;

            wr_addr <= '0;
            wr_col  <= '0;
            wr_row  <= '0;
        end else begin
            // ---------------------------------------------------------
            // Write Column & Address Logic
            // ---------------------------------------------------------
            if (wr_col >= IMG_COLS) begin
                // Wrap wr_col back to 0 after hitting 88
                wr_col <= '0;
                wr_row <= wr_row + 1'b1;
            end else if (wr_en) begin
                wr_addr <= wr_addr + 1'b1;
                wr_col  <= wr_col + 1'b1;
            end

            // ---------------------------------------------------------
            // Read Column & Address Logic
            // rd_col wraps to 0 whenever wr_col wraps (hits 88), 
            // or after the initial FETCH row completes via shift.
            // ---------------------------------------------------------
            if ((wr_col >= IMG_COLS) || (shift && (wr_addr == 0))) begin
                rd_col <= '0;
                rd_row <= rd_row + 1'b1;
            end else if (rd_en) begin
                rd_addr <= rd_addr + 1'b1;
                rd_col  <= rd_col + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------
    // Status Signal Decoding
    // -------------------------------------------------------------
    assign rd_row_end = (rd_col == IMG_COLS); // 1 when rd_col == 88
    assign wr_row_end = (wr_col == IMG_COLS); // 1 when wr_col == 88
    assign wr_col_end = (wr_row == 87);       // 1 when wr_row == 87

    // -------------------------------------------------------------
    // Simulation Stimulus & Monitor
    // -------------------------------------------------------------
    initial begin
        $display("==========================================================");
        $display("[%0t ns] Starting FSM Image Stream Simulation (88 x 288)", $time);
        $display("==========================================================");

        // 1. Asynchronous Reset
        rst   = 1'b0;
        start = 1'b0;
        #(CLK_PERIOD * 3);
        @(negedge clk);
        rst   = 1'b1;
        @(posedge clk);
        $display("[%0t ns] Reset released. System in IDLE.", $time);

        // 2. Pulse Start
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        $display("[%0t ns] 'start' asserted. Image processing started.", $time);

        // 3. Monitor Execution & Guard against lockups
        fork
            begin : timeout_guard
                #(CLK_PERIOD * (TOTAL_PIXELS * 3 + 1000));
                $error("[%0t ns] ERROR: Simulation timed out before FSM finished!", $time);
                $stop;
            end

            begin : completion_monitor
                int reported_row = 0;
                while (!finish) begin
                    @(posedge clk);
                    // Log periodic row completions
                    if (wr_row_end && (wr_row != reported_row)) begin
                        $display("[%0t ns] Finished row %0d / %0d (rd_addr=%0d, wr_addr=%0d)",
                                 $time, wr_row + 1, IMG_ROWS, rd_addr, wr_addr);
                        reported_row = wr_row;
                    end
                end

                $display("----------------------------------------------------------");
                $display("[%0t ns] 'finish' signal detected!", $time);
                $display("Total Pixels Read:    %0d", rd_addr);
                $display("Total Pixels Written: %0d", wr_addr);
                $display("Final wr_row:         %0d", wr_row);
                $display("----------------------------------------------------------");

                // Verify return to IDLE after completion
                repeat (3) @(posedge clk);
                if (!rd_en && !wr_en && !shift) begin
                    $display("[%0t ns] SUCCESS: FSM returned cleanly to IDLE.", $time);
                end else begin
                    $error("[%0t ns] ERROR: FSM signals remained active in IDLE.", $time);
                end

                disable timeout_guard;
            end
        join

        $display("==========================================================");
        $display("[%0t ns] Simulation completed successfully.", $time);
        $display("==========================================================");
        $finish;
    end

endmodule
