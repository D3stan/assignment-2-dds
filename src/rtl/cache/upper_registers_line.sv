module upper_registers_line #(
    parameter int IMG_PX_WIDTH = 352,
    parameter int WORDS_PER_LINE = IMG_PX_WIDTH/4,
    parameter int BITS_PER_LINE = IMG_PX_WIDTH * 8,
    parameter int WORD_LENGTH = 8*4
)(
    input logic                         clk,
    input logic                         rst,

    input logic                         shift_en,
    input logic [BITS_PER_LINE-1 : 0]   in_word,
    
    output logic [BITS_PER_LINE-1 : 0]  out_words
);

    genvar i;
    generate
        for (i = 0; i < WORDS_PER_LINE; i++) begin : for_word_registers_upper
            word_register #(
                .WORD_LENGTH (WORD_LENGTH)
            ) u_word_registers (  
                .clk        (clk),
                .rst        (rst),
                .load_en    (shift_en[i]),
                .in_word    (in_word[i*WORD_LENGTH +: WORD_LENGTH]),
                .out_word   (out_words[i*WORD_LENGTH +: WORD_LENGTH])
            );
        end
    endgenerate

endmodule