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

    cache #(
        .IMG_PX_WIDTH    (IMG_WIDTH * 4)
    ) u_cache (
        .clk                (),
        .rst                (),
        .shift_en           (),
        .in_word            (),
        .fetch_en           (),
        .fetch_pos          (),
        .output_bits_top    (),
        .output_bits_middle (),
        .output_bits_bottom ()
    );

    fsm #(

    ) u_fsm (
        .clk        (),
        .rst        (),
        .rd_en      (),
        .wr_en      (),
        .start      (),
        .finish     (),
        .shift      (), 
        .rd_row_end (),
        .wr_row_end (),
        .wr_col_end () 
    );

    pixel_decoder #(

    ) u_pixel_decoder (
        .row_above  (),
        .row_center (),
        .row_below  (),
        .row_idx    (),
        .col_idx    (),
        .p00        (),
        .p01        (),
        .p02        (),
        .p10        (),
        .p11        (),
        .p12        (),
        .p20        (),
        .p21        (),
        .p22        ()
    );


    addr_incrementer #(

    ) u_addr_incrementer (
        .clk        (),
        .rst_n      (),
        .rd_inc     (),
        .wr_inc     (),
        .rd_addr    (),
        .rd_col     (),
        .rd_row     (),
        .wr_addr    (),
        .wr_col     (),
        .wr_row     (),
        .rd_row_end (),
        .wr_row_end (),
        .wr_col_end ()
    );


    sobel_alu #(

    ) u_sobel_alu1 (
        .p00        (),
        .p01        (),
        .p02        (),
        .p10        (),
        .p11        (),
        .p12        (),
        .p20        (),
        .p21        (),
        .p22        (),
        .pixel_out  ()
    );


    sobel_alu #(

    ) u_sobel_alu2 (
        .p00        (),
        .p01        (),
        .p02        (),
        .p10        (),
        .p11        (),
        .p12        (),
        .p20        (),
        .p21        (),
        .p22        (),
        .pixel_out  ()
    );


    sobel_alu #(

    ) u_sobel_alu3 (
        .p00        (),
        .p01        (),
        .p02        (),
        .p10        (),
        .p11        (),
        .p12        (),
        .p20        (),
        .p21        (),
        .p22        (),
        .pixel_out  ()
    );


    sobel_alu #(

    ) u_sobel_alu4 (
        .p00        (),
        .p01        (),
        .p02        (),
        .p10        (),
        .p11        (),
        .p12        (),
        .p20        (),
        .p21        (),
        .p22        (),
        .pixel_out  ()
    );

endmodule