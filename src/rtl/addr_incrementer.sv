/*
  Contributors:
    * Bert
  Description:
    * addr_incrementer
    rd_inc - advance read  counter by one word
    wr_inc - advance write counter by one word
    clr    - reset both counters to 0 (e.g. on start)

    wr_col counts 0..87 and wraps. rd_col counts 0..88 and holds
    at 88; it goes back to 0 (and rd_row advances) only when
    wr_col wraps from 87 to 0.

    The counters do not wrap at the end of the frame. after the
    last word, rd_row becomes 288 and rd_img_end goes high.
*/
module addr_incrementer (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        clr,

    input  logic        rd_inc,
    input  logic        wr_inc,

    // read side
    output logic [14:0] rd_addr,
    output logic [6:0]  rd_col,     // 0..88
    output logic [8:0]  rd_row,     // 0..288

    // write side
    output logic [14:0] wr_addr,
    output logic [6:0]  wr_col,
    output logic [8:0]  wr_row,

    // flags
    output logic        rd_row_beg,
    output logic        rd_row_end,
    output logic        rd_img_end
);

    // write wraps from 87 to 0 on this cycle
    logic wr_wrap;
    assign wr_wrap = wr_inc && (wr_col == 7'd87);

    // read counters
    // rd_col counts 0..88 and stops at 88. It only goes back to 0
    // (and rd_row only advances) when the write counter wraps.
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            rd_col <= 7'd0;
            rd_row <= 9'd0;
        end else if (clr) begin
            rd_col <= 7'd0;
            rd_row <= 9'd0;
        end else if (wr_wrap) begin
            rd_col <= 7'd0;
            rd_row <= rd_row + 9'd1;
        end else if (rd_inc && rd_col != 7'd88) begin
            rd_col <= rd_col + 7'd1;
        end
    end

    // write counters
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            wr_col <= 7'd0;
            wr_row <= 9'd0;
        end else if (clr) begin
            wr_col <= 7'd0;
            wr_row <= 9'd0;
        end else if (wr_inc) begin
            if (wr_col == 7'd87) begin
                wr_col <= 7'd0;
                wr_row <= wr_row + 9'd1;
            end else begin
                wr_col <= wr_col + 7'd1;
            end
        end
    end

    // addresses
    assign rd_addr = rd_row * 15'd88 + rd_col;
    assign wr_addr = wr_row * 15'd88 + wr_col;

    // flags
    assign rd_row_beg = (rd_col == 7'd0);
    assign rd_row_end = (rd_col == 7'd87);
    assign rd_img_end = (rd_addr >= 15'd25344);   // 288 * 88

endmodule