module one_hot_decoder #(
    parameter int IMG_PX_WIDTH   = 352
    parameter int IMG_WORD_WIDTH = IMG_PX_WIDTH/4
)(
    input   logic [IMG_WORD_WIDTH-1 : 0]    fetch_pos,
    input   logic                           fetch_en,
    
    output  logic [IMG_WORD_WIDTH-1 : 0]    out
);

    always_comb begin
        out = '0;
        if (fetch_en)
            out[fetch_pos] = 1'b1;
    end

endmodule
