// ============================================================
//  pixel_acc - STUDENT MODULE
//
//  You are given direct read access to ibuf and write access
//  to obuf. Both are synchronous BRAMs with 1-cycle read latency.
//
//  Interface:
//    start  - pulsed high for 1 cycle to begin processing
//    finish - assert high for 1 cycle when all output words
//             have been written to obuf
//
//  ibuf read port:
//    Set ibuf_rd_en=1 and ibuf_rd_addr to the word you want.
//    ibuf_rd_data is valid on the NEXT clock cycle.
//
//  obuf write port:
//    Set obuf_wr_en=1, obuf_wr_addr, obuf_wr_data on the same cycle.
//    The word is written on the rising edge.
//
//  Parameters:
//    BUF_AW    - address width (ibuf/obuf have 2^BUF_AW words)
//    BUF_DEPTH - total number of words in each buffer
//    IMG_WIDTH - frame width in words (= pixels per row / 4)
// ============================================================
module pixel_acc #(
    parameter int BUF_AW    = 15,
    parameter int BUF_DEPTH = 25344,
    parameter int IMG_WIDTH = 88      // 352 pixels / 4 pixels-per-word
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // ibuf read port
    output logic                  ibuf_rd_en,
    output logic [BUF_AW-1:0]     ibuf_rd_addr,
    input  logic [31:0]           ibuf_rd_data,

    // obuf write port
    output logic                  obuf_wr_en,
    output logic [BUF_AW-1:0]     obuf_wr_addr,
    output logic [31:0]           obuf_wr_data,

    // handshake
    input  logic                  start,
    output logic                  finish
);

    // auxiliary signals
    logic shift_en;
    logic fetch_en;
    logic [6:0] fetch_pos;
    logic [IMG_WIDTH*4*8-1:0] output_bits_top;
    logic [IMG_WIDTH*4*8-1:0] output_bits_middle;
    logic [IMG_WIDTH*4*8-1:0] output_bits_bottom;
    // ----------------------------------------
    logic rd_row_end;
    logic wr_row_end;
    logic wr_col_end;
    logic wr_en;
    logic rd_en;
    assign obuf_wr_en = wr_en;
    assign ibuf_rd_en = rd_en;
    // ----------------------------------------
    logic [$clog2(IMG_WIDTH/4)-1:0] wr_col;
    logic [8:0] wr_row;
    // ----------------------------------------
    logic [8*9-1:0] pixel0;
    logic [8*9-1:0] pixel1;
    logic [8*9-1:0] pixel2;
    logic [8*9-1:0] pixel3;
    // ----------------------------------------

    cache #(
        .IMG_PX_WIDTH    (IMG_WIDTH * 4)
    ) u_cache (
        .clk                (clk),
        .rst_n              (rst_n),
        .shift_en           (shift_en),
        .in_word            (ibuf_rd_data),
        .fetch_en           (rd_en),
        .fetch_pos          (fetch_pos),
        .output_bits_top    (output_bits_top),
        .output_bits_middle (output_bits_middle),
        .output_bits_bottom (output_bits_bottom)
    );

    fsm #(

    ) u_fsm (
        .clk        (clk),
        .rst_n      (rst_n),
        .rd_en      (rd_en),
        .wr_en      (wr_en),
        .start      (start),
        .finish     (finish),
        .shift      (shift_en), 
        .rd_row_end (rd_row_end),
        .wr_row_end (wr_row_end),
        .wr_col_end (wr_col_end) 
    );

    pixel_decoder #(

    ) u_pixel_decoder (
        .row_above  (output_bits_top),
        .row_center (output_bits_middle),
        .row_below  (output_bits_bottom),
        .row_idx    (wr_row),
        .col_idx    (wr_col),
        .p000       (pixel0[8*0 +: 8]),
        .p001       (pixel0[8*1 +: 8]),
        .p002       (pixel0[8*2 +: 8]),
        .p010       (pixel0[8*3 +: 8]),
        .p011       (pixel0[8*4 +: 8]),
        .p012       (pixel0[8*5 +: 8]),
        .p020       (pixel0[8*6 +: 8]),
        .p021       (pixel0[8*7 +: 8]),
        .p022       (pixel0[8*8 +: 8]),

        .p100       (pixel1[8*0 +: 8]),
        .p101       (pixel1[8*1 +: 8]),
        .p102       (pixel1[8*2 +: 8]),
        .p110       (pixel1[8*3 +: 8]),
        .p111       (pixel1[8*4 +: 8]),
        .p112       (pixel1[8*5 +: 8]),
        .p120       (pixel1[8*6 +: 8]),
        .p121       (pixel1[8*7 +: 8]),
        .p122       (pixel1[8*8 +: 8]),

        .p200       (pixel2[8*0 +: 8]),
        .p201       (pixel2[8*1 +: 8]),
        .p202       (pixel2[8*2 +: 8]),
        .p210       (pixel2[8*3 +: 8]),
        .p211       (pixel2[8*4 +: 8]),
        .p212       (pixel2[8*5 +: 8]),
        .p220       (pixel2[8*6 +: 8]),
        .p221       (pixel2[8*7 +: 8]),
        .p222       (pixel2[8*8 +: 8]),

        .p300       (pixel3[8*0 +: 8]),
        .p301       (pixel3[8*1 +: 8]),
        .p302       (pixel3[8*2 +: 8]),
        .p310       (pixel3[8*3 +: 8]),
        .p311       (pixel3[8*4 +: 8]),
        .p312       (pixel3[8*5 +: 8]),
        .p320       (pixel3[8*6 +: 8]),
        .p321       (pixel3[8*7 +: 8]),
        .p322       (pixel3[8*8 +: 8])
    );


    addr_incrementer #(

    ) u_addr_incrementer (
        .clk        (clk),
        .rst_n      (rst_n),
        .rd_inc     (rd_en),
        .wr_inc     (wr_en),
        .rd_addr    (ibuf_rd_addr),
        .rd_col     (fetch_pos),
        .rd_row     (),
        .wr_addr    (obuf_wr_addr),
        .wr_col     (wr_col),
        .wr_row     (wr_row),
        .rd_row_end (rd_row_end),
        .wr_row_end (wr_row_end),
        .wr_col_end (wr_col_end)
    );


    sobel_alu #(

    ) u_sobel_alu1 (
        .p00        (pixel0[8*0 +: 8]),
        .p01        (pixel0[8*1 +: 8]),
        .p02        (pixel0[8*2 +: 8]),
        .p10        (pixel0[8*3 +: 8]),
        .p11        (pixel0[8*4 +: 8]),
        .p12        (pixel0[8*5 +: 8]),
        .p20        (pixel0[8*6 +: 8]),
        .p21        (pixel0[8*7 +: 8]),
        .p22        (pixel0[8*8 +: 8]),
        .pixel_out  (obuf_wr_data[7:0])
    );


    sobel_alu #(

    ) u_sobel_alu2 (
        .p00        (pixel1[8*0 +: 8]),
        .p01        (pixel1[8*1 +: 8]),
        .p02        (pixel1[8*2 +: 8]),
        .p10        (pixel1[8*3 +: 8]),
        .p11        (pixel1[8*4 +: 8]),
        .p12        (pixel1[8*5 +: 8]),
        .p20        (pixel1[8*6 +: 8]),
        .p21        (pixel1[8*7 +: 8]),
        .p22        (pixel1[8*8 +: 8]),
        .pixel_out  (obuf_wr_data[15:8])
    );


    sobel_alu #(

    ) u_sobel_alu3 (
        .p00        (pixel2[8*0 +: 8]),
        .p01        (pixel2[8*1 +: 8]),
        .p02        (pixel2[8*2 +: 8]),
        .p10        (pixel2[8*3 +: 8]),
        .p11        (pixel2[8*4 +: 8]),
        .p12        (pixel2[8*5 +: 8]),
        .p20        (pixel2[8*6 +: 8]),
        .p21        (pixel2[8*7 +: 8]),
        .p22        (pixel2[8*8 +: 8]),
        .pixel_out  (obuf_wr_data[23:16])
    );


    sobel_alu #(

    ) u_sobel_alu4 (
        .p00        (pixel3[8*0 +: 8]),
        .p01        (pixel3[8*1 +: 8]),
        .p02        (pixel3[8*2 +: 8]),
        .p10        (pixel3[8*3 +: 8]),
        .p11        (pixel3[8*4 +: 8]),
        .p12        (pixel3[8*5 +: 8]),
        .p20        (pixel3[8*6 +: 8]),
        .p21        (pixel3[8*7 +: 8]),
        .p22        (pixel3[8*8 +: 8]),
        .pixel_out  (obuf_wr_data[31:24])
    );




endmodule