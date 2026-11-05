`timescale 1ns/1ps
// ============================================================================
//  tb_cache.sv  -  Black-box testbench for module `cache`
// ----------------------------------------------------------------------------
//  The DUT is treated as a black box: the TB keeps its own reference model of
//  the three rows (top / middle / bottom), drives the protocol below and, after
//  every clock edge, compares every output word against the model.
//
//  Protocol under test (one image line = WORDS_PER_LINE words):
//    1) fetch_pos = 2'b10                -> word 0 loaded in the 1st bottom reg (leftmost)
//    2) fetch_pos = 2'b01                -> word 1 loaded in the 2nd bottom reg
//    3) shift_x_en = 1, fetch_pos = 2'b01 (same cycle) for words 2 .. N-1
//       (shift_x is a left ROTATION: the leftmost word re-enters on the right)
//    4) shift_x_en = 1, fetch_pos = 2'b00 twice -> N rotations in total: the
//       bottom row is in order and top/middle made a full turn (aligned again)
//    5) shift_y_en = 1                   -> rows move up, then restart from 1)
//
//  Phases:
//    P1  reset, then N_LINES lines streamed back-to-back (exactly the protocol)
//    P2  reset from a dirty state, same stream with random idle cycles
//        (enables low, fetch_pos = 00/11, garbage on in_word -> must hold)
//    P3  reset asserted in the middle of a line, then 3 lines back-to-back
//
// ============================================================================
module tb_cache;

  // --------------------------------------------------------------------------
  // DUT parameters (same defaults as the module)
  // --------------------------------------------------------------------------
  localparam int IMG_PX_WIDTH    = 352;
  localparam int BYTE            = 8;
  localparam int PIXELS_PER_WORD = 4;

  localparam int WORD_LENGTH     = BYTE * PIXELS_PER_WORD;
  localparam int WORDS_PER_LINE  = IMG_PX_WIDTH / PIXELS_PER_WORD;
  localparam int OUTPUT_BITS     = IMG_PX_WIDTH * BYTE;

  // --------------------------------------------------------------------------
  // Test knobs
  // --------------------------------------------------------------------------
  localparam int CLK_PERIOD = 10;   // ns
  localparam int N_LINES    = 6;    // image lines streamed in P1 / P2
  localparam int STALL_PCT  = 20;   // P2: probability (%) of an idle cycle before each operation
  localparam int MAX_PRINT  = 25;   // max number of mismatch messages printed
  localparam bit CHECK_NO_X = 1'b1; // flag any X/Z on the outputs after reset
  localparam bit VERBOSE    = 1'b1; // print milestone OK messages

  // --------------------------------------------------------------------------
  // Assumptions on the black box  (*** adapt to your spec ***)
  // --------------------------------------------------------------------------
  // A1: register 0 (leftmost, i.e. the oldest word of the line) is mapped on the
  //     MSBs of output_bits_*. Set to 0 if word 0 is on bits [WORD_LENGTH-1:0].
  localparam bit WORD0_AT_MSB = 1'b0;

  // A2: indexes (0 = leftmost) of the registers written by fetch_pos 10 / 01.
  //     After 2 loads + (N-2) shift&load + 2 pure rotations, word 0 is exactly
  //     in register 0 and the bottom row holds the whole line in order.
  localparam int POS_1ST = 0;   // fetch_pos = 2'b10
  localparam int POS_2ND = 1;   // fetch_pos = 2'b01

  // A3: shift_x_en shifts top and middle too ("leftward shift on every line").
  //     Set to 0 if only the bottom row shifts.
  localparam bit SHIFT_X_ALL_ROWS = 1'b1;

  // A4: what enters the rightmost register of a row on a left shift
  localparam int FILL_DONT_CARE = 0, FILL_ZERO = 1, FILL_ROTATE = 2;
  localparam int SHIFT_FILL = FILL_ROTATE;

  // A5: bottom row content after shift_y_en
  localparam int BOT_DONT_CARE = 0, BOT_ZERO = 1, BOT_HOLD = 2;
  localparam int BOTTOM_AFTER_SHIFT_Y = BOT_HOLD;

  // --------------------------------------------------------------------------
  // DUT signals and instance
  // --------------------------------------------------------------------------
  typedef logic [WORD_LENGTH-1:0] word_t;
  typedef logic [OUTPUT_BITS-1:0] row_t;

  logic   clk = 1'b0;
  logic   rst_n;
  logic   shift_x_en;
  logic   shift_y_en;
  word_t  in_word;
  logic [1:0] fetch_pos;
  row_t   output_bits_top;
  row_t   output_bits_middle;
  row_t   output_bits_bottom;

  cache #(
    .IMG_PX_WIDTH    (IMG_PX_WIDTH),
    .BYTE            (BYTE),
    .PIXELS_PER_WORD (PIXELS_PER_WORD)
  ) dut (
    .clk                (clk),
    .rst_n              (rst_n),
    .shift_x_en         (shift_x_en),
    .shift_y_en         (shift_y_en),
    .in_word            (in_word),
    .fetch_pos          (fetch_pos),
    .output_bits_top    (output_bits_top),
    .output_bits_middle (output_bits_middle),
    .output_bits_bottom (output_bits_bottom)
  );

  always #(CLK_PERIOD/2) clk = ~clk;

  // --------------------------------------------------------------------------
  // Reference model
  // --------------------------------------------------------------------------
  localparam int TOP = 0, MID = 1, BOT = 2;

  word_t exp_w  [3][WORDS_PER_LINE];   // expected word per row/register
  bit    exp_ok [3][WORDS_PER_LINE];   // 1 = expected value known -> checked
  word_t img    [N_LINES][WORDS_PER_LINE];

  int    errors = 0;
  int    printed = 0;
  int    checks = 0;
  int    cycle  = 0;
  string ctx    = "";

  function automatic void model_reset();
    for (int r = 0; r < 3; r++)
      for (int i = 0; i < WORDS_PER_LINE; i++) begin
        exp_w [r][i] = '0;
        exp_ok[r][i] = 1'b1;
      end
  endfunction

  function automatic void model_shift_left(input int r);
    word_t w0 = exp_w [r][0];
    bit    k0 = exp_ok[r][0];
    for (int i = 0; i < WORDS_PER_LINE-1; i++) begin
      exp_w [r][i] = exp_w [r][i+1];
      exp_ok[r][i] = exp_ok[r][i+1];
    end
    case (SHIFT_FILL)
      FILL_ZERO:   begin exp_w[r][WORDS_PER_LINE-1] = '0; exp_ok[r][WORDS_PER_LINE-1] = 1'b1; end
      FILL_ROTATE: begin exp_w[r][WORDS_PER_LINE-1] = w0; exp_ok[r][WORDS_PER_LINE-1] = k0;   end
      default:     begin exp_ok[r][WORDS_PER_LINE-1] = 1'b0; end
    endcase
  endfunction

  // Effect of one rising edge with the given inputs (rst_n = 1)
  function automatic void model_step(input bit sx, input bit sy,
                                     input word_t w, input logic [1:0] fp);
    if (sy) begin
      for (int i = 0; i < WORDS_PER_LINE; i++) begin
        exp_w [TOP][i] = exp_w [MID][i];  exp_ok[TOP][i] = exp_ok[MID][i];
        exp_w [MID][i] = exp_w [BOT][i];  exp_ok[MID][i] = exp_ok[BOT][i];
        case (BOTTOM_AFTER_SHIFT_Y)
          BOT_ZERO: begin exp_w[BOT][i] = '0; exp_ok[BOT][i] = 1'b1; end
          BOT_HOLD: ; // unchanged
          default:  exp_ok[BOT][i] = 1'b0;
        endcase
      end
    end else if (sx) begin
      model_shift_left(BOT);
      if (SHIFT_X_ALL_ROWS) begin
        model_shift_left(MID);
        model_shift_left(TOP);
      end
    end
    // load happens after the shift (new word lands in the freed register)
    if (fp == 2'b10) begin exp_w[BOT][POS_1ST] = w; exp_ok[BOT][POS_1ST] = 1'b1; end
    if (fp == 2'b01) begin exp_w[BOT][POS_2ND] = w; exp_ok[BOT][POS_2ND] = 1'b1; end
  endfunction

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------
  function automatic string row_name(input int r);
    return (r == TOP) ? "top" : (r == MID) ? "middle" : "bottom";
  endfunction

  function automatic row_t row_vec(input int r);
    return (r == TOP) ? output_bits_top : (r == MID) ? output_bits_middle : output_bits_bottom;
  endfunction

  function automatic word_t get_word(input row_t v, input int idx);
    int lsb;
    lsb = WORD0_AT_MSB ? (WORDS_PER_LINE-1-idx) * WORD_LENGTH : idx * WORD_LENGTH;
    return v[lsb +: WORD_LENGTH];
  endfunction

  // Random word, with the 16 MSBs tagged {line+1, index} to ease debugging
  localparam int TAG_SH = (WORD_LENGTH >= 16) ? WORD_LENGTH - 16 : 0;
  function automatic word_t make_word(input int line, input int idx);
    word_t w = '0;
    for (int b = 0; b < WORD_LENGTH; b += 32) w = (w << 32) | word_t'($urandom);
    if (WORD_LENGTH >= 16)
      w = (w & ~(word_t'(16'hFFFF) << TAG_SH)) | (word_t'({8'(line+1), 8'(idx)}) << TAG_SH);
    return w;
  endfunction

  function automatic word_t rand_word();
    word_t w = '0;
    for (int b = 0; b < WORD_LENGTH; b += 32) w = (w << 32) | word_t'($urandom);
    return w;
  endfunction

  task automatic fail(input string msg);
    errors++;
    if (printed < MAX_PRINT)
      $display("[%0t | cyc %0d] ERROR (%s): %s", $time, cycle, ctx, msg);
    else if (printed == MAX_PRINT)
      $display("... further errors suppressed (see final count)");
    printed++;
  endtask

  // Compare every known word of every row with the model
  task automatic check_outputs();
    row_t  v;
    word_t got;
    string hint;
    for (int r = 0; r < 3; r++) begin
      v = row_vec(r);
      if (CHECK_NO_X && $isunknown(v))
        fail($sformatf("X/Z on output_bits_%s", row_name(r)));
      for (int i = 0; i < WORDS_PER_LINE; i++) begin
        if (exp_ok[r][i]) begin
          checks++;
          got = get_word(v, i);
          if (got !== exp_w[r][i]) begin
            // debugging hint: is the value expected somewhere else in the row?
            hint = "";
            for (int j = 0; j < WORDS_PER_LINE; j++)
              if (hint == "" && exp_ok[r][j] && j != i && got === exp_w[r][j] && got !== '0)
                hint = $sformatf("  <- value expected at word[%0d] (offset %0d: order/shift issue?)", j, j - i);
            fail($sformatf("output_bits_%s word[%0d] = 0x%h, expected 0x%h%s",
                           row_name(r), i, got, exp_w[r][i], hint));
          end
        end
      end
    end
  endtask

  // Model-independent check: row r holds exactly image line `line`
  task automatic check_row_is_line(input int r, input int line, input string what);
    int   bad = 0;
    row_t v   = row_vec(r);
    for (int i = 0; i < WORDS_PER_LINE; i++)
      if (get_word(v, i) !== img[line][i]) bad++;
    if (bad != 0)
      fail($sformatf("MILESTONE '%s': output_bits_%s differs from image line %0d in %0d/%0d words",
                     what, row_name(r), line, bad, WORDS_PER_LINE));
    else if (VERBOSE)
      $display("[%0t] OK  %s", $time, what);
  endtask

  // --------------------------------------------------------------------------
  // Driver: called right after a falling edge. Inputs are applied on the
  // falling edge, sampled by the DUT on the rising edge, and outputs are
  // checked on the next falling edge.
  // --------------------------------------------------------------------------
  task automatic drive(input bit sx, input bit sy, input word_t w, input logic [1:0] fp);
    shift_x_en = sx;
    shift_y_en = sy;
    in_word    = w;
    fetch_pos  = fp;
    @(posedge clk);
    model_step(sx, sy, w, fp);
    cycle++;
    @(negedge clk);
    check_outputs();
  endtask

  // Idle cycle: no enable, fetch_pos 00 or 11, garbage on in_word -> must hold
  task automatic idle_cycle();
    string save = ctx;
    ctx = {"idle cycle before ", save};
    drive(1'b0, 1'b0, rand_word(), $urandom_range(1) ? 2'b11 : 2'b00);
    ctx = save;
  endtask

  task automatic maybe_stall(input bit stalls);
    if (stalls)
      while ($urandom_range(99) < STALL_PCT) idle_cycle();
  endtask

  // Reset with random activity on the inputs: reset must win
  task automatic apply_reset(input int n_cycles);
    ctx   = "reset";
    rst_n = 1'b0;
    model_reset();
    repeat (n_cycles) begin
      shift_x_en = $urandom_range(1);
      shift_y_en = $urandom_range(1);
      in_word    = rand_word();
      fetch_pos  = 2'($urandom_range(3));
      @(posedge clk);
      cycle++;
      @(negedge clk);
      check_outputs();
    end
    shift_x_en = 1'b0;
    shift_y_en = 1'b0;
    in_word    = '0;
    fetch_pos  = 2'b00;
    rst_n      = 1'b1;
    // one idle cycle out of reset: everything must still be empty
    ctx = "first cycle after reset";
    drive(1'b0, 1'b0, rand_word(), 2'b00);
  endtask

  function automatic void gen_image();
    for (int l = 0; l < N_LINES; l++)
      for (int i = 0; i < WORDS_PER_LINE; i++)
        img[l][i] = make_word(l, i);
  endfunction

  // Stream one full image line into the bottom row, then shift up
  task automatic stream_line(input int l, input bit stalls, input int n_words = WORDS_PER_LINE);
    ctx = $sformatf("line %0d, word 0 -> 1st bottom reg (fetch_pos=10)", l);
    maybe_stall(stalls);
    drive(1'b0, 1'b0, img[l][0], 2'b10);

    ctx = $sformatf("line %0d, word 1 -> 2nd bottom reg (fetch_pos=01)", l);
    maybe_stall(stalls);
    drive(1'b0, 1'b0, img[l][1], 2'b01);

    for (int k = 2; k < n_words; k++) begin
      ctx = $sformatf("line %0d, word %0d: shift_x + load 2nd reg", l, k);
      maybe_stall(stalls);
      drive(1'b1, 1'b0, img[l][k], 2'b01);
    end
    if (n_words == WORDS_PER_LINE) begin   // skipped for a partial line (used before a reset)
      // two pure rotations: N rotations in total -> bottom in order, upper rows aligned
      for (int k = 0; k < 2; k++) begin
        ctx = $sformatf("line %0d, final rotation %0d (shift_x, fetch_pos=00)", l, k);
        maybe_stall(stalls);
        drive(1'b1, 1'b0, rand_word(), 2'b00);
      end
      check_row_is_line(BOT, l, $sformatf("line %0d fully assembled in bottom row", l));
      if (l > 0)
        check_row_is_line(MID, l-1, $sformatf("line %0d loaded: middle row still = line %0d", l, l-1));

      ctx = $sformatf("line %0d: shift_y", l);
      maybe_stall(stalls);
      drive(1'b0, 1'b1, rand_word(), 2'b00);

      check_row_is_line(MID, l, $sformatf("after shift_y: middle row = line %0d", l));
      // N rotations per line -> the upper rows are back in order before shift_y
      if (l > 0)
        check_row_is_line(TOP, l-1, $sformatf("after shift_y: top row    = line %0d", l-1));
    end
  endtask

  // --------------------------------------------------------------------------
  // Main sequence
  // --------------------------------------------------------------------------
  initial begin
`ifdef DUMP_VCD
    $dumpfile("tb_cache.vcd");
    $dumpvars(0, tb_cache);
`endif
    $timeformat(-9, 0, " ns", 0);
    // Random seed: set it from the simulator (xsim: -sv_seed <n>,
    // Questa/Verilator: +verilator+seed+<n> / -sv_seed <n>)

    if (IMG_PX_WIDTH % PIXELS_PER_WORD != 0)
      $display("WARNING: IMG_PX_WIDTH is not a multiple of PIXELS_PER_WORD");

    $display("=== tb_cache: %0d words/line, %0d-bit words, %0d-bit rows ===",
             WORDS_PER_LINE, WORD_LENGTH, OUTPUT_BITS);

    // inputs idle, reset asserted from time 0
    rst_n = 1'b0; shift_x_en = 1'b0; shift_y_en = 1'b0; in_word = '0; fetch_pos = 2'b00;
    @(posedge clk);
    @(negedge clk);

    // ---- P1: protocol exactly as specified, back-to-back -------------------
    $display("\n--- P1: reset + %0d lines back-to-back ---", N_LINES);
    gen_image();
    apply_reset(4);
    for (int l = 0; l < N_LINES; l++) stream_line(l, 1'b0);

    // ---- P2: reset from dirty state + random idle cycles --------------------
    $display("\n--- P2: reset from non-empty state + %0d lines with %0d%% idle cycles ---",
             N_LINES, STALL_PCT);
    gen_image();
    apply_reset(3);
    for (int l = 0; l < N_LINES; l++) stream_line(l, 1'b1);

    // ---- P3: reset in the middle of a line -----------------------------------
    $display("\n--- P3: reset in the middle of a line, then 3 lines ---");
    gen_image();
    stream_line(0, 1'b0);
    stream_line(1, 1'b0, WORDS_PER_LINE / 2);
    apply_reset(2);
    for (int l = 0; l < 3 && l < N_LINES; l++) stream_line(l, 1'b0);

    // ---- report ---------------------------------------------------------------
    $display("\n==============================================================");
    if (errors == 0)
      $display(" TEST PASSED  (%0d cycles, %0d word comparisons)", cycle, checks);
    else
      $display(" TEST FAILED  (%0d errors, %0d cycles, %0d word comparisons)", errors, cycle, checks);
    $display("==============================================================");
    $finish;
  end

  // Watchdog
  initial begin
    #(CLK_PERIOD * 100000);
    $display("TIMEOUT");
    $finish;
  end

endmodule