module bottom_registers_line #(
    parameter  int WORDS_PER_LINE = 88,
    parameter  int WORD_LENGTH    = 32,

    localparam int BITS_PER_LINE  = WORDS_PER_LINE * WORD_LENGTH
)(
    input logic                         clk,
    input logic                         rst_n,

    input logic [WORDS_PER_LINE-1 : 0]  fetch_en,
    input logic [WORD_LENGTH-1 : 0]     in_word,

    output logic [BITS_PER_LINE-1 : 0]  out_words
);

    genvar i;
    generate
        for (i = 0; i < WORDS_PER_LINE; i++) begin : for_word_registers
            word_register #(
                .WORD_LENGTH (WORD_LENGTH)
            ) u_word_registers (
                .clk        (clk),
                .rst_n      (rst_n),
                .load_en    (fetch_en[i]),
                .in_word    (in_word),
                .out_word   (out_words[i*WORD_LENGTH +: WORD_LENGTH])
            );
        end
    endgenerate

endmodule
