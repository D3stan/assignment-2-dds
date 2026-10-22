`timescale 1ns/1ps

module tb_pixel_decoder;

    // Reduce image dimensions to make signals manageable for debugging.
    // The parameterized logic will behave identically.
    localparam int W = 6;
    localparam int H = 6;
    localparam int PW = 8;

    // Input signals
    logic [PW*W-1:0] row_above;
    logic [PW*W-1:0] row_center;
    logic [PW*W-1:0] row_below;
    logic [$clog2(H)-1:0] row_idx;
    logic [$clog2(W)-1:0] col_idx;

    // Output signals
    logic [PW-1:0] p00, p01, p02;
    logic [PW-1:0] p10, p11, p12;
    logic [PW-1:0] p20, p21, p22;

    // Device Under Test (DUT) instantiation
    pixel_decoder #(
        .IMG_WIDTH(W),
        .IMG_HEIGHT(H),
        .PIXEL_WIDTH(PW)
    ) dut (
        .row_above(row_above),
        .row_center(row_center),
        .row_below(row_below),
        .row_idx(row_idx),
        .col_idx(col_idx),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22)
    );

    // Helper function to pack an unpacked array into the flat vector 
    // expected by the module (little-endian, matching your get_pixel logic).
    function automatic logic [PW*W-1:0] pack_row(logic [PW-1:0] p [0:W-1]);
        logic [PW*W-1:0] res = '0;
        for (int i = 0; i < W; i++) begin
            res[i*PW +: PW] = p[i];
        end
        return res;
    endfunction

    // Temporary arrays for initialization
    logic [PW-1:0] r_a [0:W-1];
    logic [PW-1:0] r_c [0:W-1];
    logic [PW-1:0] r_b [0:W-1];
    
    int err_count = 0;

    // Task to verify outputs and print detailed mismatch reports
    task check_pixels(
        input logic [PW-1:0] exp_p00, exp_p01, exp_p02,
        input logic [PW-1:0] exp_p10, exp_p11, exp_p12,
        input logic [PW-1:0] exp_p20, exp_p21, exp_p22,
        input string test_name
    );
        #1; // Tiny delay to ensure combinational logic propagation
        
        if (p00 !== exp_p00 || p01 !== exp_p01 || p02 !== exp_p02 ||
            p10 !== exp_p10 || p11 !== exp_p11 || p12 !== exp_p12 ||
            p20 !== exp_p20 || p21 !== exp_p21 || p22 !== exp_p22) begin
            
            $error("[FAILED] %s", test_name);
            $display("--- Expected Window ---");
            $display("%h %h %h", exp_p00, exp_p01, exp_p02);
            $display("%h %h %h", exp_p10, exp_p11, exp_p12);
            $display("%h %h %h", exp_p20, exp_p21, exp_p22);
            $display("--- Actual Window ---");
            $display("%h %h %h", p00, p01, p02);
            $display("%h %h %h", p10, p11, p12);
            $display("%h %h %h", p20, p21, p22);
            $display("-----------------------");
            err_count++;
        end else begin
            $display("[PASSED] %s", test_name);
        end
    endtask

    initial begin
        $display("=== STARTING PIXEL DECODER TESTS ===");

        // Initialize rows with sequential patterns easy to spot in hex.
        // Row Above : A0, A1, A2, A3, A4, A5
        // Row Center: C0, C1, C2, C3, C4, C5
        // Row Below : B0, B1, B2, B3, B4, B5
        for (int i = 0; i < W; i++) begin
            r_a[i] = 8'hA0 + i;
            r_c[i] = 8'hC0 + i;
            r_b[i] = 8'hB0 + i;
        end
        
        row_above  = pack_row(r_a);
        row_center = pack_row(r_c);
        row_below  = pack_row(r_b);

        // =========================================================
        // CASE 1: Image Center (No boundary conditions)
        // =========================================================
        row_idx = 2; col_idx = 2;
        check_pixels(
            8'hA1, 8'hA2, 8'hA3,
            8'hC1, 8'hC2, 8'hC3,
            8'hB1, 8'hB2, 8'hB3,
            "1. Image Center (2,2)"
        );

        // =========================================================
        // CASE 2: Top-Left Corner
        // The 'above' row and the left column do not exist.
        // Clamp to Center row and column 0.
        // =========================================================
        row_idx = 0; col_idx = 0;
        check_pixels(
            8'hC0, 8'hC0, 8'hC1,
            8'hC0, 8'hC0, 8'hC1,
            8'hB0, 8'hB0, 8'hB1,
            "2. Top-Left Corner (0,0)"
        );

        // =========================================================
        // CASE 3: Top Edge
        // =========================================================
        row_idx = 0; col_idx = 3;
        check_pixels(
            8'hC2, 8'hC3, 8'hC4,
            8'hC2, 8'hC3, 8'hC4,
            8'hB2, 8'hB3, 8'hB4,
            "3. Top Edge (0,3)"
        );

        // =========================================================
        // CASE 4: Top-Right Corner
        // =========================================================
        row_idx = 0; col_idx = W-1;
        check_pixels(
            8'hC4, 8'hC5, 8'hC5,
            8'hC4, 8'hC5, 8'hC5,
            8'hB4, 8'hB5, 8'hB5,
            "4. Top-Right Corner (0,5)"
        );

        // =========================================================
        // CASE 5: Left Edge
        // =========================================================
        row_idx = 3; col_idx = 0;
        check_pixels(
            8'hA0, 8'hA0, 8'hA1,
            8'hC0, 8'hC0, 8'hC1,
            8'hB0, 8'hB0, 8'hB1,
            "5. Left Edge (3,0)"
        );

        // =========================================================
        // CASE 6: Right Edge
        // =========================================================
        row_idx = 3; col_idx = W-1;
        check_pixels(
            8'hA4, 8'hA5, 8'hA5,
            8'hC4, 8'hC5, 8'hC5,
            8'hB4, 8'hB5, 8'hB5,
            "6. Right Edge (3,5)"
        );

        // =========================================================
        // CASE 7: Bottom-Left Corner
        // =========================================================
        row_idx = H-1; col_idx = 0;
        check_pixels(
            8'hA0, 8'hA0, 8'hA1,
            8'hC0, 8'hC0, 8'hC1,
            8'hC0, 8'hC0, 8'hC1,
            "7. Bottom-Left Corner (5,0)"
        );

        // =========================================================
        // CASE 8: Bottom Edge
        // =========================================================
        row_idx = H-1; col_idx = 3;
        check_pixels(
            8'hA2, 8'hA3, 8'hA4,
            8'hC2, 8'hC3, 8'hC4,
            8'hC2, 8'hC3, 8'hC4,
            "8. Bottom Edge (5,3)"
        );

        // =========================================================
        // CASE 9: Bottom-Right Corner
        // =========================================================
        row_idx = H-1; col_idx = W-1;
        check_pixels(
            8'hA4, 8'hA5, 8'hA5,
            8'hC4, 8'hC5, 8'hC5,
            8'hC4, 8'hC5, 8'hC5,
            "9. Bottom-Right Corner (5,5)"
        );

        $display("=======================================");
        if (err_count == 0) begin
            $display("===  ALL TESTS PASSED! :)           ===");
        end else begin
            $display("=== FINISHED WITH %0d ERRORS!       ===", err_count);
        end
        $display("=======================================");
        
        $finish;
    end

endmodule