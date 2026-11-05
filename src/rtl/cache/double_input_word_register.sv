module double_input_word_register #(
    parameter int WORD_LENGTH = 8*4
)(
    input   logic                       clk,
    input   logic                       rst_n,

    input   logic                       load_x_en,
    input   logic                       load_y_en,

    input   logic [WORD_LENGTH-1 : 0]   in_x_word,
    input   logic [WORD_LENGTH-1 : 0]   in_y_word,

    output  logic [WORD_LENGTH-1 : 0]   out_word
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            out_word <= '0;
        else if (load_y_en)     // y has priority: a fetch in the same cycle of a shift wins
            out_word <= in_y_word;
        else if (load_x_en)
            out_word <= in_x_word;
    end

endmodule