`timescale 1ns/1ps

module tb_pixel_decoder;

    // Small image, multiple of 4 wide, several words per row.
    localparam int W   = 16;
    localparam int H   = 6;
    localparam int PW  = 8;
    localparam int WW  = W / 4;   // words per row

    // Inputs
    logic [PW*W-1:0]      row_above;
    logic [PW*W-1:0]      row_center;
    logic [PW*W-1:0]      row_below;
    logic [$clog2(H)-1:0] row_idx;
    logic [$clog2(WW)-1:0] col_idx;

    // Outputs: pWRC = window W (0..3), row R (0 top..2 bottom), column C (0 left..2 right)
    logic [PW-1:0] p000, p001, p002, p010, p011, p012, p020, p021, p022;
    logic [PW-1:0] p100, p101, p102, p110, p111, p112, p120, p121, p122;
    logic [PW-1:0] p200, p201, p202, p210, p211, p212, p220, p221, p222;
    logic [PW-1:0] p300, p301, p302, p310, p311, p312, p320, p321, p322;

    pixel_decoder #(
        .IMG_WIDTH  (W),
        .IMG_HEIGHT (H),
        .PIXEL_WIDTH(PW)
    ) dut (
        .row_above(row_above), .row_center(row_center), .row_below(row_below),
        .row_idx(row_idx), .col_idx(col_idx),
        .p000(p000), .p001(p001), .p002(p002), .p010(p010), .p011(p011), .p012(p012), .p020(p020), .p021(p021), .p022(p022),
        .p100(p100), .p101(p101), .p102(p102), .p110(p110), .p111(p111), .p112(p112), .p120(p120), .p121(p121), .p122(p122),
        .p200(p200), .p201(p201), .p202(p202), .p210(p210), .p211(p211), .p212(p212), .p220(p220), .p221(p221), .p222(p222),
        .p300(p300), .p301(p301), .p302(p302), .p310(p310), .p311(p311), .p312(p312), .p320(p320), .p321(p321), .p322(p322)
    );

    // Flat view of the outputs: index = win*9 + r*3 + c, p000 in the LSBs.
    logic [36*PW-1:0] got_flat;
    assign got_flat = {
        p322, p321, p320, p312, p311, p310, p302, p301, p300,
        p222, p221, p220, p212, p211, p210, p202, p201, p200,
        p122, p121, p120, p112, p111, p110, p102, p101, p100,
        p022, p021, p020, p012, p011, p010, p002, p001, p000
    };

    function automatic logic [PW-1:0] got(int win, int r, int c);
        return got_flat[(win*9 + r*3 + c)*PW +: PW];
    endfunction

    // ------------------------------------------------------------------
    // Reference model (spec only): 3x3 neighbourhood of pixel (4*cidx+win),
    // top row replaced by center on row 0, bottom row replaced by center
    // on last row, columns clamped to [0, W-1].
    // ------------------------------------------------------------------
    function automatic logic [PW-1:0] expected(int win, int r, int c, int ridx, int cidx);
        int col;
        logic [PW*W-1:0] src;
        col = 4*cidx + win + c - 1;
        if (col < 0)     col = 0;
        if (col > W - 1) col = W - 1;
        case (r)
            0:       src = (ridx == 0)     ? row_center : row_above;
            1:       src = row_center;
            default: src = (ridx == H - 1) ? row_center : row_below;
        endcase
        return src[col*PW +: PW];
    endfunction

    int err_count = 0;
    int test_count = 0;

    // Compare all 36 outputs against the model for the current inputs.
    task automatic check_all(input string name);
        bit fail = 0;
        #1;
        test_count++;
        for (int w = 0; w < 4; w++)
            for (int r = 0; r < 3; r++)
                for (int c = 0; c < 3; c++) begin
                    if (got(w, r, c) !== expected(w, r, c, int'(row_idx), int'(col_idx))) begin
                        if (!fail) $error("[FAILED] %s (row_idx=%0d col_idx=%0d)", name, row_idx, col_idx);
                        $display("  p%0d%0d%0d: expected %h, got %h",
                                 w, r, c, expected(w, r, c, int'(row_idx), int'(col_idx)), got(w, r, c));
                        fail = 1;
                    end
                end
        if (fail) err_count++;
    endtask

    // Hard-coded check of one window (independent of the model).
    task automatic check_win(
        input int win,
        input logic [PW-1:0] e00, e01, e02,
        input logic [PW-1:0] e10, e11, e12,
        input logic [PW-1:0] e20, e21, e22,
        input string name
    );
        logic [PW-1:0] e [9];
        bit fail = 0;
        e = '{e00, e01, e02, e10, e11, e12, e20, e21, e22};
        #1;
        test_count++;
        for (int i = 0; i < 9; i++)
            if (got(win, i/3, i%3) !== e[i]) fail = 1;
        if (fail) begin
            err_count++;
            $error("[FAILED] %s", name);
            $display("--- Expected ---");
            $display("%h %h %h", e00, e01, e02);
            $display("%h %h %h", e10, e11, e12);
            $display("%h %h %h", e20, e21, e22);
            $display("--- Actual (window %0d) ---", win);
            $display("%h %h %h", got(win,0,0), got(win,0,1), got(win,0,2));
            $display("%h %h %h", got(win,1,0), got(win,1,1), got(win,1,2));
            $display("%h %h %h", got(win,2,0), got(win,2,1), got(win,2,2));
        end else begin
            $display("[PASSED] %s", name);
        end
    endtask

    task automatic load_pattern();
        // Above: A0..AF, Center: C0..CF, Below: B0..BF
        for (int i = 0; i < W; i++) begin
            row_above [i*PW +: PW] = 8'hA0 + i;
            row_center[i*PW +: PW] = 8'hC0 + i;
            row_below [i*PW +: PW] = 8'hB0 + i;
        end
    endtask

    task automatic load_random();
        for (int i = 0; i < W; i++) begin
            row_above [i*PW +: PW] = $urandom_range(0, 2**PW - 1);
            row_center[i*PW +: PW] = $urandom_range(0, 2**PW - 1);
            row_below [i*PW +: PW] = $urandom_range(0, 2**PW - 1);
        end
    endtask

    initial begin
        $display("=== STARTING PIXEL DECODER TESTS ===");
        load_pattern();

        // ---------------- Directed checks (hard-coded values) ----------------
        // Interior: row 2, word 1, window 2 -> center pixel col 6, cols 5..7
        row_idx = 2; col_idx = 1;
        check_win(2, 8'hA5, 8'hA6, 8'hA7,
                     8'hC5, 8'hC6, 8'hC7,
                     8'hB5, 8'hB6, 8'hB7, "Interior, word 1, window 2");

        // Word boundary: window 0 of word 1 reaches into word 0 (col 3)
        check_win(0, 8'hA3, 8'hA4, 8'hA5,
                     8'hC3, 8'hC4, 8'hC5,
                     8'hB3, 8'hB4, 8'hB5, "Left neighbour across word boundary");

        // Word boundary: window 3 of word 1 reaches into word 2 (col 8)
        check_win(3, 8'hA6, 8'hA7, 8'hA8,
                     8'hC6, 8'hC7, 8'hC8,
                     8'hB6, 8'hB7, 8'hB8, "Right neighbour across word boundary");

        // Top-left corner: window 0, row 0, word 0
        row_idx = 0; col_idx = 0;
        check_win(0, 8'hC0, 8'hC0, 8'hC1,
                     8'hC0, 8'hC0, 8'hC1,
                     8'hB0, 8'hB0, 8'hB1, "Top-left corner (0,0) win 0");

        // Top-right corner: window 3, row 0, last word
        row_idx = 0; col_idx = WW-1;
        check_win(3, 8'hCE, 8'hCF, 8'hCF,
                     8'hCE, 8'hCF, 8'hCF,
                     8'hBE, 8'hBF, 8'hBF, "Top-right corner win 3");

        // Bottom-left corner: window 0
        row_idx = H-1; col_idx = 0;
        check_win(0, 8'hA0, 8'hA0, 8'hA1,
                     8'hC0, 8'hC0, 8'hC1,
                     8'hC0, 8'hC0, 8'hC1, "Bottom-left corner win 0");

        // Bottom-right corner: window 3
        row_idx = H-1; col_idx = WW-1;
        check_win(3, 8'hAE, 8'hAF, 8'hAF,
                     8'hCE, 8'hCF, 8'hCF,
                     8'hCE, 8'hCF, 8'hCF, "Bottom-right corner win 3");

        // ---------------- Exhaustive positions, patterned data ----------------
        for (int r = 0; r < H; r++)
            for (int c = 0; c < WW; c++) begin
                row_idx = r; col_idx = c;
                check_all($sformatf("Pattern sweep (%0d,%0d)", r, c));
            end

        // ---------------- Exhaustive positions, random data ----------------
        for (int it = 0; it < 200; it++) begin
            load_random();
            for (int r = 0; r < H; r++)
                for (int c = 0; c < WW; c++) begin
                    row_idx = r; col_idx = c;
                    check_all($sformatf("Random iter %0d (%0d,%0d)", it, r, c));
                end
        end

        $display("=======================================");
        if (err_count == 0)
            $display("===  ALL %0d TESTS PASSED! :)", test_count);
        else
            $display("===  FINISHED WITH %0d FAILING TESTS OUT OF %0d", err_count, test_count);
        $display("=======================================");
        $finish;
    end

endmodule