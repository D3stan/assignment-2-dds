module pixel_decoder #(
    parameter int IMG_WIDTH   = 352,
    parameter int IMG_HEIGHT  = 288,
    parameter int PIXEL_WIDTH = 8
) (
    input logic [PIXEL_WIDTH*IMG_WIDTH-1:0] row_above,
    input logic [PIXEL_WIDTH*IMG_WIDTH-1:0] row_center,
    input logic [PIXEL_WIDTH*IMG_WIDTH-1:0] row_below,

    input logic [$clog2(IMG_HEIGHT)-1:0] row_idx,
    input logic [$clog2(IMG_WIDTH)-1:0]  col_idx,

    output logic [PIXEL_WIDTH-1:0] p00,
    output logic [PIXEL_WIDTH-1:0] p01,
    output logic [PIXEL_WIDTH-1:0] p02,
    output logic [PIXEL_WIDTH-1:0] p10,
    output logic [PIXEL_WIDTH-1:0] p11,
    output logic [PIXEL_WIDTH-1:0] p12,
    output logic [PIXEL_WIDTH-1:0] p20,
    output logic [PIXEL_WIDTH-1:0] p21,
    output logic [PIXEL_WIDTH-1:0] p22
);

    typedef logic [PIXEL_WIDTH*IMG_WIDTH-1:0] row_t;

    function automatic logic [PIXEL_WIDTH-1:0] get_pixel(
        input row_t row_data,
        input int unsigned col
    );
        get_pixel = row_data[PIXEL_WIDTH*col +: PIXEL_WIDTH];
    endfunction

    always_comb begin : decode_window
        int unsigned left_col;
        int unsigned center_col;
        int unsigned right_col;

        center_col = col_idx;
        left_col = (center_col == 0) ? 0 : center_col - 1;
        right_col = (center_col >= IMG_WIDTH - 1) ? IMG_WIDTH - 1 : center_col + 1;

        p00 = get_pixel((row_idx == 0) ? row_center : row_above, left_col);
        p01 = get_pixel((row_idx == 0) ? row_center : row_above, center_col);
        p02 = get_pixel((row_idx == 0) ? row_center : row_above, right_col);
        p10 = get_pixel(row_center, left_col);
        p11 = get_pixel(row_center, center_col);
        p12 = get_pixel(row_center, right_col);
        p20 = get_pixel((row_idx >= IMG_HEIGHT - 1) ? row_center : row_below, left_col);
        p21 = get_pixel((row_idx >= IMG_HEIGHT - 1) ? row_center : row_below, center_col);
        p22 = get_pixel((row_idx >= IMG_HEIGHT - 1) ? row_center : row_below, right_col);
    end

endmodule
