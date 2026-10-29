## hardware improvements
Instead of using a multiplier to calculate the address, we can use a shift and add method

original code in src/rtl/addr_incrementer.sv:
```
    assign rd_addr = rd_row * 15'd88 + rd_col;
```