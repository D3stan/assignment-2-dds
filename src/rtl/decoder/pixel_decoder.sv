module pixel_decoder #(
    parameter int IMG_WIDTH = 352,
    parameter int IMG_HEIGHT = 288,
    parameter int PIXEL_WIDTH = 8,
    parameter int WINDOW_WIDTH = 6,
    parameter int IMG_WIDTH_WORDS = IMG_WIDTH / 4
) (
    input logic [PIXEL_WIDTH*WINDOW_WIDTH-1:0] row_above,
    input logic [PIXEL_WIDTH*WINDOW_WIDTH-1:0] row_center,
    input logic [PIXEL_WIDTH*WINDOW_WIDTH-1:0] row_below,

    input logic [$clog2(IMG_HEIGHT)-1:0] row_idx,
    input logic [$clog2(IMG_WIDTH_WORDS)-1:0] col_idx,

    output logic [PIXEL_WIDTH-1:0] p000, p001, p002, p010, p011, p012, p020, p021, p022,
    output logic [PIXEL_WIDTH-1:0] p100, p101, p102, p110, p111, p112, p120, p121, p122,
    output logic [PIXEL_WIDTH-1:0] p200, p201, p202, p210, p211, p212, p220, p221, p222,
    output logic [PIXEL_WIDTH-1:0] p300, p301, p302, p310, p311, p312, p320, p321, p322
);

    localparam int WORD_W = 4 * PIXEL_WIDTH;

    typedef logic [5:0][PIXEL_WIDTH-1:0] strip_t;
    typedef logic [$clog2(IMG_WIDTH_WORDS)-1:0] cidx_t;

    // 6 pixel strip with replicated borders for leftmost/rightmost pixels
    function automatic strip_t get_strip(input strip_t r, input cidx_t c);
        logic [3:0][PIXEL_WIDTH-1:0] w;
        logic [PIXEL_WIDTH-1:0]      left, right;

        w     = r[4:1];
        left  = (c == '0)                  ? w[0] : r[0];
        right = (c == IMG_WIDTH_WORDS - 1) ? w[3] : r[5];

        return strip_t'{right, w[3], w[2], w[1], w[0], left};
    endfunction

    strip_t top_row, bot_row;
    strip_t t, m, b;


    // replicate top/bottom row for first/last row of the image
    assign top_row = strip_t'((row_idx == 0)              ? row_center : row_above);
    assign bot_row = strip_t'((row_idx == IMG_HEIGHT - 1) ? row_center : row_below);

    assign t = get_strip(top_row, col_idx);
    assign m = get_strip(row_center, col_idx);
    assign b = get_strip(bot_row, col_idx);

    // Window 0: pixel 0,1,2
    assign {p000, p001, p002} = {t[0], t[1], t[2]};
    assign {p010, p011, p012} = {m[0], m[1], m[2]};
    assign {p020, p021, p022} = {b[0], b[1], b[2]};

    // Window 1: pixel 1,2,3
    assign {p100, p101, p102} = {t[1], t[2], t[3]};
    assign {p110, p111, p112} = {m[1], m[2], m[3]};
    assign {p120, p121, p122} = {b[1], b[2], b[3]};

    // Window 2: pixel 2,3,4
    assign {p200, p201, p202} = {t[2], t[3], t[4]};
    assign {p210, p211, p212} = {m[2], m[3], m[4]};
    assign {p220, p221, p222} = {b[2], b[3], b[4]};

    // Window 3: pixel 3,4,5
    assign {p300, p301, p302} = {t[3], t[4], t[5]};
    assign {p310, p311, p312} = {m[3], m[4], m[5]};
    assign {p320, p321, p322} = {b[3], b[4], b[5]};

endmodule
