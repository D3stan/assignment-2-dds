module one_hot_decoder #(
    parameter  int WORDS_PER_LINE = 88,

    localparam int POS_WIDTH      = $clog2(WORDS_PER_LINE)
)(
    input   logic [POS_WIDTH-1 : 0]         fetch_pos,
    input   logic                           fetch_en,

    output  logic [WORDS_PER_LINE-1 : 0]    out
);

    always_comb begin
        out = '0;
        if (fetch_en)
            out[fetch_pos] = 1'b1;
    end

endmodule
