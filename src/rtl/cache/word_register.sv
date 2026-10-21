module word_register #(
    parameter int WORD_LENGTH = 8*4
)(
    input   logic                       clk,
    input   logic                       rst,

    input   logic                       load_en,
    input   logic [WORD_LENGTH-1 : 0]   in_word,

    output  logic [WORD_LENGTH-1 : 0]   out_word
);

    always_ff @(posedge clk or negedge rst) begin
        if (!rst)
            out_word <= '0;
        else if (load_en)
            out_word <= in_word;
    end

endmodule