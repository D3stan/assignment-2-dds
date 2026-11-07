`timescale 1ns/1ps

module tb_pixel_decoder;

    // Parameters matching the DUT defaults
    localparam int IMG_WIDTH       = 352;
    localparam int IMG_HEIGHT      = 288;
    localparam int PIXEL_WIDTH     = 8;
    localparam int WINDOW_WIDTH    = 6;
    localparam int IMG_WIDTH_WORDS = IMG_WIDTH / 4;

    // Local typedef for array indexing in the testbench
    typedef logic [WINDOW_WIDTH-1:0][PIXEL_WIDTH-1:0] strip_t;

    // DUT Inputs
    logic [PIXEL_WIDTH*WINDOW_WIDTH-1:0] row_above;
    logic [PIXEL_WIDTH*WINDOW_WIDTH-1:0] row_center;
    logic [PIXEL_WIDTH*WINDOW_WIDTH-1:0] row_below;
    logic [$clog2(IMG_HEIGHT)-1:0]      row_idx;
    logic [$clog2(IMG_WIDTH_WORDS)-1:0] col_idx;

    // DUT Outputs
    logic [PIXEL_WIDTH-1:0] p000, p001, p002, p010, p011, p012, p020, p021, p022;
    logic [PIXEL_WIDTH-1:0] p100, p101, p102, p110, p111, p112, p120, p121, p122;
    logic [PIXEL_WIDTH-1:0] p200, p201, p202, p210, p211, p212, p220, p221, p222;
    logic [PIXEL_WIDTH-1:0] p300, p301, p302, p310, p311, p312, p320, p321, p322;

    int error_count = 0;

    // Instantiate Design Under Test (DUT)
    pixel_decoder #(
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .WINDOW_WIDTH(WINDOW_WIDTH)
    ) dut (
        .row_above(row_above),
        .row_center(row_center),
        .row_below(row_below),
        .row_idx(row_idx),
        .col_idx(col_idx),
        .p000(p000), .p001(p001), .p002(p002), .p010(p010), .p011(p011), .p012(p012), .p020(p020), .p021(p021), .p022(p022),
        .p100(p100), .p101(p101), .p102(p102), .p110(p110), .p111(p111), .p112(p112), .p120(p120), .p121(p121), .p122(p122),
        .p200(p200), .p201(p201), .p202(p202), .p210(p210), .p211(p211), .p212(p212), .p220(p220), .p221(p221), .p222(p222),
        .p300(p300), .p301(p301), .p302(p302), .p310(p310), .p311(p311), .p312(p312), .p320(p320), .p321(p321), .p322(p322)
    );

    // Verification Task
    task check_window(
        input string window_name,
        input logic [PIXEL_WIDTH-1:0] exp0, exp1, exp2, // Top row
        input logic [PIXEL_WIDTH-1:0] exp3, exp4, exp5, // Mid row
        input logic [PIXEL_WIDTH-1:0] exp6, exp7, exp8, // Bot row
        input logic [PIXEL_WIDTH-1:0] act0, act1, act2,
        input logic [PIXEL_WIDTH-1:0] act3, act4, act5,
        input logic [PIXEL_WIDTH-1:0] act6, act7, act8
    );
        logic match;
        match = (exp0 == act0) && (exp1 == act1) && (exp2 == act2) &&
                (exp3 == act3) && (exp4 == act4) && (exp5 == act5) &&
                (exp6 == act6) && (exp7 == act7) && (exp8 == act8);

        if (!match) begin
            $display("[FAIL] %s Mismatch!", window_name);
            $display("       Expected (T): %h %h %h | Actual: %h %h %h", exp0, exp1, exp2, act0, act1, act2);
            $display("       Expected (M): %h %h %h | Actual: %h %h %h", exp3, exp4, exp5, act3, act4, act5);
            $display("       Expected (B): %h %h %h | Actual: %h %h %h", exp6, exp7, exp8, act6, act7, act8);
            error_count++;
        end else begin
            $display("[PASS] %s matches expected data.", window_name);
        end
    endtask

    // Stimulus Generation
    initial begin
        strip_t strip_above, strip_center, strip_below;

        // --- TEST 1: Standard Interior Region ---
        $display("\n================ TEST 1: Interior Pixel (row_idx=10, col_idx=5) ================");
        row_idx = 10;
        col_idx = 5;

        // Unique byte pattern for each pixel location:
        // Above:  A0, A1, A2, A3, A4, A5
        // Center: C0, C1, C2, C3, C4, C5
        // Below:  B0, B1, B2, B3, B4, B5
        strip_above  = {8'hA5, 8'hA4, 8'hA3, 8'hA2, 8'hA1, 8'hA0};
        strip_center = {8'hC5, 8'hC4, 8'hC3, 8'hC2, 8'hC1, 8'hC0};
        strip_below  = {8'hB5, 8'hB4, 8'hB3, 8'hB2, 8'hB1, 8'hB0};

        row_above  = strip_above;
        row_center = strip_center;
        row_below  = strip_below;
        #10;

        // Window 0 (pixels 0,1,2 from each strip)
        check_window("Window 0",
            8'hA0, 8'hA1, 8'hA2,
            8'hC0, 8'hC1, 8'hC2,
            8'hB0, 8'hB1, 8'hB2,
            p000, p001, p002, p010, p011, p012, p020, p021, p022
        );

        // Window 1 (pixels 1,2,3 from each strip)
        check_window("Window 1",
            8'hA1, 8'hA2, 8'hA3,
            8'hC1, 8'hC2, 8'hC3,
            8'hB1, 8'hB2, 8'hB3,
            p100, p101, p102, p110, p111, p112, p120, p121, p122
        );

        // Window 2 (pixels 2,3,4 from each strip)
        check_window("Window 2",
            8'hA2, 8'hA3, 8'hA4,
            8'hC2, 8'hC3, 8'hC4,
            8'hB2, 8'hB3, 8'hB4,
            p200, p201, p202, p210, p211, p212, p220, p221, p222
        );

        // Window 3 (pixels 3,4,5 from each strip)
        check_window("Window 3",
            8'hA3, 8'hA4, 8'hA5,
            8'hC3, 8'hC4, 8'hC5,
            8'hB3, 8'hB4, 8'hB5,
            p300, p301, p302, p310, p311, p312, p320, p321, p322
        );

        // --- TEST 2: Top Frame Boundary (row_idx = 0) ---
        $display("\n================ TEST 2: Top Boundary (row_idx=0) ================");
        row_idx = 0; // Top row should duplicate row_center instead of row_above
        col_idx = 5;
        #10;

        // Window 0 under vertical boundary clamping: top pixels should equal center pixels (8'hC0, 8'hC1, 8'hC2)
        check_window("Window 0 (Top Boundary)",
            8'hC0, 8'hC1, 8'hC2, // Replicated top row
            8'hC0, 8'hC1, 8'hC2,
            8'hB0, 8'hB1, 8'hB2,
            p000, p001, p002, p010, p011, p012, p020, p021, p022
        );

        // --- TEST 3: Left Column Boundary (col_idx = 0) ---
        $display("\n================ TEST 3: Left Boundary (col_idx=0) ================");
        row_idx = 10;
        col_idx = 0; // Left pixel of strip should clamp to w[0] (pixel 1)
        #10;

        // get_strip clamps r[0] to w[0] (which is A1/C1/B1)
        check_window("Window 0 (Left Boundary Clamping)",
            8'hA1, 8'hA1, 8'hA2, // index 0 clamped to A1
            8'hC1, 8'hC1, 8'hC2, // index 0 clamped to C1
            8'hB1, 8'hB1, 8'hB2, // index 0 clamped to B1
            p000, p001, p002, p010, p011, p012, p020, p021, p022
        );

        // --- Summary ---
        $display("\n==================================================");
        if (error_count == 0)
            $display("TEST SUCCESS: All pixel routing tests passed!");
        else
            $display("TEST FAILURE: Total errors = %0d", error_count);
        $display("==================================================\n");

        $finish;
    end

endmodule
