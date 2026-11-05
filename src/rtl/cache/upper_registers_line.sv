module upper_registers_line #(
    parameter  int WORDS_PER_LINE = 88,
    parameter  int WORD_LENGTH    = 32,

    localparam int BITS_PER_LINE  = WORDS_PER_LINE * WORD_LENGTH
)(
    input logic                         clk,
    input logic                         rst_n,

    input logic                         shift_x_en,
    input logic                         shift_y_en,

    input logic [BITS_PER_LINE-1 : 0]   in_word,

    output logic [BITS_PER_LINE-1 : 0]  out_words
);

    logic [BITS_PER_LINE+WORD_LENGTH-1 : 0] chain;

    assign chain[BITS_PER_LINE +: WORD_LENGTH] = '0;
    assign out_words = chain[BITS_PER_LINE-1 : 0];

    genvar i;
    generate
        for (i = 0; i < WORDS_PER_LINE; i++) begin : for_word_registers_upper
            double_input_word_register #(
                .WORD_LENGTH (WORD_LENGTH)
            ) u_double_input_word_register (
                .clk        (clk),
                .rst_n      (rst_n),

                .load_x_en  (shift_x_en),
                .load_y_en  (shift_y_en),

                .in_x_word  (chain[(i+1)*WORD_LENGTH +: WORD_LENGTH]),
                .in_y_word  (in_word[i*WORD_LENGTH +: WORD_LENGTH]),

                .out_word   (chain[i*WORD_LENGTH +: WORD_LENGTH])
            );
        end
    endgenerate

endmodule
