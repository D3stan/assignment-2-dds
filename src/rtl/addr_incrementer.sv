/*
  Contributors:
    * Bert
  Description:
    * addr_incrementer
    rd_inc - advance read  counter by one word
    wr_inc - advance write counter by one word

    wr_col counts 0..87 and wraps. rd_col counts 0..88 and holds
    at 88; it goes back to 0 (and rd_row advances) only when
    wr_col wraps from 87 to 0.

   .
*/
module addr_incrementer (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        rd_inc,
    input  logic        wr_inc,

    input  logic        wr_wrap,
    input  logic        rd_wrap,

    // read side
    output logic [14:0] rd_addr,
    output logic [6:0]  rd_col,     // 0..88
    output logic [8:0]  rd_row,     // 0..288

    // write side
    output logic [14:0] wr_addr,
    output logic [6:0]  wr_col,
    output logic [8:0]  wr_row,

    // flags
    output logic        rd_row_end,
    output logic        wr_row_end,
    output logic        wr_col_end
);

    // read counters
    // rd_col counts 0..88 and stops at 88. It only goes back to 0
    // (and rd_row only advances) when the write counter wraps.
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            rd_col <= 7'd0;
            rd_row <= 9'd0;
        end else if (rd_wrap) begin
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
        end else if(wr_wrap) begin 
            wr_col <= 7'd0;
            wr_row <= wr_row + 9'd1;
        end else if (wr_inc) begin
            wr_col <= wr_col + 7'd1;
        end
    end

    // addresses
    always_comb begin : wr_addr_update
        automatic logic [15:0] wr_row_x3  = wr_row << 1;
        automatic logic [15:0] wr_row_x11 = (wr_row << 3) + wr_row_x3 + wr_row;
        
        wr_addr = (wr_row_x11 << 3) + wr_col;
    end
    always_comb begin : rd_addr_update
        automatic logic [15:0] rd_row_x3  = rd_row << 1;
        automatic logic [15:0] rd_row_x11 = (rd_row << 3) + rd_row_x3 + rd_row;
        
        rd_addr = (rd_row_x11 << 3) + rd_col;
    end
    
    // flags
    assign rd_row_end = (rd_col == 7'd88);
    assign wr_row_end = (wr_col == 7'd87);
    assign wr_col_end = (wr_row == 9'd287);   

endmodule
