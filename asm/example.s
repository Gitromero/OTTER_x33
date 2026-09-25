# Example program: sums 1..10 into x10, shows the sum on the 7-seg display,
# then copies the switches to the LEDs forever.
#   make sim PROG=example        (assembles asm/example.s -> mem/example.mem)
#   make wave
    li   x5, 0x11000000     # MMIO base: +0x00 switches, +0x20 LEDs, +0x40 7-seg
    li   x10, 0             # sum
    li   x11, 10            # counter
loop:
    add  x10, x10, x11
    addi x11, x11, -1
    bnez x11, loop
    sw   x10, 0x40(x5)      # 7-seg <= 55 (0x37)
echo:
    lw   x6, 0(x5)          # read switches
    sw   x6, 0x20(x5)       # write LEDs
    j    echo
