@ ============================================================
@ Lights Out Puzzle – BBC micro:bit v2
@ Architecture: ARM Cortex-M4 (nRF52833)
@
@ Rules & Controls :
@ Button A = move cursor (left→right, top→bottom)
@ Button B = toggle cell + all 4 neighbours
@ Long press A (>400ms) = reseed new puzzle
@ Win condition = all LEDs off → celebration spiral
@
@ ============================================================

    .syntax unified
    .cpu    cortex-m4
    .thumb

    @ memory mapped register base addresses
    .equ GPIO0_BASE,        0x50000000
    .equ GPIO1_BASE,        0x50000300
    .equ CLOCK_BASE,        0x40000000
    .equ TIMER0_BASE,       0x40008000

    @ offsets inside the CLOCK peripheral registers
    .equ CLOCK_HFCLKSTART,      0x000
    .equ CLOCK_HFCLKSTARTED,    0x100

    @ Offsets from base addresses  
    .equ GPIO_OUTSET,       0x508
    .equ GPIO_OUTCLR,       0x50C
    .equ GPIO_IN,           0x510
    .equ GPIO_DIRSET,       0x518
    .equ GPIO_PIN_CNF,      0x700

    @ offsets inside the CLOCK peripheral registers
    .equ TIMER_START,       0x000 @ start timer
    .equ TIMER_CLEAR,       0x00C @ end timer and reset
    .equ TIMER_CAPTURE0,    0x040 @ enter the captures time stap into a register
    .equ TIMER_CAPTURE1,    0x044 @ another register for the same functionality
    .equ TIMER_MODE,        0x504 @ selecting b/w time counter & event counter
    .equ TIMER_BITMODE,     0x508 @ select n for an n-bit timer
    .equ TIMER_PRESCALER,   0x510 @ Slows down timer
    .equ TIMER_CC0,         0x540 @ timer values stored
    .equ TIMER_CC1,         0x544 @ same functionality another register

    @ GPIO pin configuration
    .equ BTN_PIN_CNF,   0x0000000C
    .equ OUT_PIN_CNF,   0x00000001
    
    @ Bit Masks - define which physical pins control what
    .equ ROW1_MASK,  (1 << 21)
    .equ ROW2_MASK,  (1 << 22)
    .equ ROW3_MASK,  (1 << 15)
    .equ ROW4_MASK,  (1 << 24)
    .equ ROW5_MASK,  (1 << 19)
    .equ COL1_MASK,  (1 << 28)
    .equ COL2_MASK,  (1 << 11)
    .equ COL3_MASK,  (1 << 31)
    .equ COL4_MASK,  (1 <<  5)
    .equ COL5_MASK,  (1 << 30)
    .equ BTN_A_MASK, (1 << 14)
    .equ BTN_B_MASK, (1 << 23)

    @ Combined masks
    .equ GPIO0_ROW_MASK, (ROW1_MASK|ROW2_MASK|ROW3_MASK|ROW4_MASK|ROW5_MASK)
    .equ GPIO0_COL_MASK, (COL1_MASK|COL2_MASK|COL3_MASK|COL5_MASK)
    .equ GPIO0_OUT_MASK, (GPIO0_ROW_MASK|GPIO0_COL_MASK)
    .equ GPIO1_OUT_MASK, COL4_MASK

    @ Timing Constraints
    .equ DEBOUNCE,       640000
    .equ LONG_PRESS,   12800000
    .equ MUX_SLICE,      80000
    .equ BLINK_PERIOD,       40
    .equ FLASH_DELAY,   3200000
    .equ BTN_RELEASED,       1
    .equ BTN_PRESSED,        0


@ *** .data 

    .section .data @Mutable variables stored in RAM
    .align 2 @ Align to 2^2 = 4 bytes

@ grid[5] – one byte per row, 5-bit column mask
@ bit 0 = col 0 (left), bit 4 = col 4 (right)
grid:           .byte 0,0,0,0,0
                .align 2

cursor_pos:     .word 0         @ 0..24 (row*5+col)
blink_ctr:      .word 0
blink_state:    .word 1
lfsr:           .word 0xACE1    @ LFSR seed (must be nonzero)


@ *** .rodata
    .section .rodata
    .align 2

row_masks:
    .word ROW1_MASK
    .word ROW2_MASK
    .word ROW3_MASK
    .word ROW4_MASK
    .word ROW5_MASK

col_gpio0:
    .word COL1_MASK
    .word COL2_MASK
    .word COL3_MASK
    .word 0
    .word COL5_MASK

col_gpio1:
    .word 0, 0, 0
    .word COL4_MASK
    .word 0

@ Clockwise spiral order for win animation (row,col pairs)
spiral_seq:
    .byte 0,0, 0,1, 0,2, 0,3, 0,4
    .byte 1,4, 2,4, 3,4, 4,4
    .byte 4,3, 4,2, 4,1, 4,0
    .byte 3,0, 2,0, 1,0
    .byte 1,1, 1,2, 1,3
    .byte 2,3, 3,3
    .byte 3,2, 3,1
    .byte 2,1
    .byte 2,2
    .equ SPIRAL_LEN, 25


@ *** .text 
    .section .text
    .align 2

    .global main
    .global __isr_vector

    .org 0x00000000
__isr_vector:
    .word _stack_top
    .word Reset_Handler + 1

    .thumb_func
Reset_Handler:
main:
    bl  clock_init
    bl  gpio_init
    bl  timer0_init
    bl  new_puzzle
    bl  main_loop
    b   .


@ *** clock_init
    .thumb_func
clock_init:
    ldr r0, =CLOCK_BASE
    mov r1, #0
    str r1, [r0, #CLOCK_HFCLKSTARTED]
    mov r1, #1
    str r1, [r0, #CLOCK_HFCLKSTART]
ci_poll:
    ldr r1, [r0, #CLOCK_HFCLKSTARTED]
    cmp r1, #1
    bne ci_poll
    bx  lr


@ *** gpio_init
    .thumb_func
gpio_init:
    push {lr}
    ldr  r0, =GPIO0_BASE
    ldr  r1, =GPIO0_OUT_MASK
    str  r1, [r0, #GPIO_DIRSET]
    ldr  r0, =GPIO1_BASE
    ldr  r1, =GPIO1_OUT_MASK
    str  r1, [r0, #GPIO_DIRSET]
    ldr  r0, =GPIO0_BASE
    ldr  r1, =(GPIO_PIN_CNF + 14 * 4)
    ldr  r2, =BTN_PIN_CNF
    str  r2, [r0, r1]
    ldr  r1, =(GPIO_PIN_CNF + 23 * 4)
    str  r2, [r0, r1]
    bl   leds_all_off
    pop  {pc}


@ *** timer0_init – 32-bit, prescaler=0 (16 MHz)
    .thumb_func

timer0_init:
    ldr r0, =TIMER0_BASE
    mov r1, #0
    str r1, [r0, #TIMER_MODE]
    mov r1, #3
    str r1, [r0, #TIMER_BITMODE]
    mov r1, #0
    str r1, [r0, #TIMER_PRESCALER]
    mov r1, #1
    str r1, [r0, #TIMER_CLEAR]
    str r1, [r0, #TIMER_START]
    bx  lr


@ *** delay_ticks  r0=ticks

    .thumb_func
delay_ticks:
    push {r4, r5, lr}
    mov  r4, r0
    ldr  r5, =TIMER0_BASE
    mov  r0, #1
    str  r0, [r5, #TIMER_CAPTURE0]
    ldr  r2, [r5, #TIMER_CC0]
dt_loop:
    str  r0, [r5, #TIMER_CAPTURE0]
    ldr  r3, [r5, #TIMER_CC0]
    sub  r3, r3, r2
    cmp  r3, r4
    blt  dt_loop
    pop  {r4, r5, pc}


@ *** delay_soft  r0=iters
    .thumb_func
delay_soft:
ds:  subs r0, r0, #1
    bne  ds
    bx   lr


@ *** leds_all_off
    .thumb_func
leds_all_off:
    ldr r0, =GPIO0_BASE
    ldr r1, =GPIO0_ROW_MASK
    str r1, [r0, #GPIO_OUTCLR]
    ldr r1, =GPIO0_COL_MASK
    str r1, [r0, #GPIO_OUTSET]
    ldr r0, =GPIO1_BASE
    ldr r1, =COL4_MASK
    str r1, [r0, #GPIO_OUTSET]
    bx  lr


@ *** light_row_mask  r0=row  r1=5-bit col mask
    .thumb_func
light_row_mask:
    push {r4, r5, r6, lr}
    mov  r4, r0
    mov  r5, r1
    bl   leds_all_off
    ldr  r0, =row_masks
    lsl  r6, r4, #2
    ldr  r1, [r0, r6]
    ldr  r0, =GPIO0_BASE
    str  r1, [r0, #GPIO_OUTSET]
    mov  r6, #0
lrm_loop:
    cmp  r6, #5
    bge  lrm_done
    lsr  r0, r5, r6
    tst  r0, #1
    beq  lrm_next
    ldr  r0, =col_gpio0
    lsl  r1, r6, #2
    ldr  r1, [r0, r1]
    cmp  r1, #0
    beq  lrm_g1
    ldr  r0, =GPIO0_BASE
    str  r1, [r0, #GPIO_OUTCLR]
    b    lrm_next
lrm_g1:
    ldr  r0, =col_gpio1
    lsl  r1, r6, #2
    ldr  r1, [r0, r1]
    cmp  r1, #0
    beq  lrm_next
    ldr  r0, =GPIO1_BASE
    str  r1, [r0, #GPIO_OUTCLR]
lrm_next:
    add  r6, r6, #1
    b    lrm_loop
lrm_done:
    pop  {r4, r5, r6, pc}


@ *** lfsr_next – advances LFSR, returns next bit in r0
@       16-bit Galois LFSR, taps at bits 15,13,12,10
    .thumb_func
lfsr_next:
    ldr  r0, =lfsr
    ldr  r1, [r0]
    and  r2, r1, #1         @ output bit
    lsr  r1, r1, #1
    cmp  r2, #1
    it   eq
    eoreq r1, r1, #0xB400   @ feedback polynomial
    str  r1, [r0]
    mov  r0, r2
    bx   lr


@ *** new_puzzle
@       Generates a solvable random puzzle by starting with
@       all-off grid and applying 10 random toggle operations.
@       This guarantees the puzzle is always solvable.

    .thumb_func
new_puzzle:
    push {r4, r5, lr}

    @ Clear grid
    ldr  r0, =grid
    mov  r1, #0
    strb r1, [r0, #0]
    strb r1, [r0, #1]
    strb r1, [r0, #2]
    strb r1, [r0, #3]
    strb r1, [r0, #4]

    @ Apply 10 random toggles (ensures solvability)
    mov  r4, #10
np_loop:
    cmp  r4, #0
    beq  np_done

    @ Pick random row (0..4): 3 LFSR bits, mask to 0..4
np_row:
    bl   lfsr_next
    bl   lfsr_next
    bl   lfsr_next
    ldr  r5, =lfsr
    ldr  r5, [r5]
    and  r5, r5, #0x7
    cmp  r5, #5
    bge  np_row             @ reject 5,6,7 and re-draw

    @ Pick random col (0..4)
np_col:
    bl   lfsr_next
    bl   lfsr_next
    bl   lfsr_next
    ldr  r1, =lfsr
    ldr  r1, [r1]
    and  r1, r1, #0x7
    cmp  r1, #5
    bge  np_col

    @ Apply toggle at (r5, r1)
    mov  r0, r5
    bl   toggle_cell

    subs r4, r4, #1
    b    np_loop

np_done:
    @ Reset cursor to top-left
    ldr  r0, =cursor_pos
    mov  r1, #0
    str  r1, [r0]
    pop  {r4, r5, pc}


@ *** toggle_cell  r0=row  r1=col
@       Toggles the cell at (row,col) AND its 4 neighbours.
@       Neighbours that are out of bounds are skipped.
    .thumb_func
toggle_cell:
    push {r4, r5, r6, r7, lr}
    mov  r4, r0             @ r4 = row
    mov  r5, r1             @ r5 = col

    @ Toggle (row, col) itself
    mov  r0, r4
    mov  r1, r5
    bl   flip_bit

    @ Up: (row-1, col)
    subs r0, r4, #1
    blt  tc_skip_up
    mov  r1, r5
    bl   flip_bit
tc_skip_up:

    @ Down: (row+1, col)
    add  r0, r4, #1
    cmp  r0, #5
    bge  tc_skip_dn
    mov  r1, r5
    bl   flip_bit
tc_skip_dn:

    @ Left: (row, col-1)
    subs r1, r5, #1
    blt  tc_skip_lt
    mov  r0, r4
    bl   flip_bit
tc_skip_lt:

    @ Right: (row, col+1)
    add  r1, r5, #1
    cmp  r1, #5
    bge  tc_skip_rt
    mov  r0, r4
    bl   flip_bit
tc_skip_rt:

    pop  {r4, r5, r6, r7, pc}


@ *** flip_bit  r0=row  r1=col
@       Flips bit col in grid[row].

    .thumb_func
flip_bit:
    ldr  r2, =grid
    ldrb r3, [r2, r0]
    mov  r12, #1
    lsl  r12, r12, r1
    eor  r3, r3, r12
    and  r3, r3, #0x1F
    strb r3, [r2, r0]
    bx   lr


@ *** check_win – returns r0=1 if all grid bytes are 0

    .thumb_func
check_win:
    ldr  r0, =grid
    ldrb r1, [r0, #0]
    ldrb r2, [r0, #1]
    orr  r1, r1, r2
    ldrb r2, [r0, #2]
    orr  r1, r1, r2
    ldrb r2, [r0, #3]
    orr  r1, r1, r2
    ldrb r2, [r0, #4]
    orr  r1, r1, r2
    cmp  r1, #0
    ite  eq
    moveq r0, #1
    movne r0, #0
    bx   lr


@ *** display_frame
@       Multiplexes all 5 rows for one full pass.
@       Cursor position blinks via blink_state.

    .thumb_func
display_frame:
    push {r4, r5, r6, r7, lr}

    ldr  r4, =cursor_pos
    ldr  r4, [r4]
    mov  r5, r4
    mov  r6, #5
    udiv r5, r5, r6         @ r5 = cursor row (pos / 5)
    mul  r6, r5, r6
    sub  r6, r4, r6         @ r6 = cursor col (pos % 5)

    ldr  r7, =blink_state
    ldr  r7, [r7]

    mov  r4, #0             @ row counter
df_row:
    cmp  r4, #5
    bge  df_done

    ldr  r0, =grid
    ldrb r1, [r0, r4]       @ col mask from grid

    @ Apply cursor blink
    cmp  r4, r5             @ cursor row?
    bne  df_no_cursor

    @ Set or clear cursor bit based on blink_state
    mov  r0, #1
    lsl  r0, r0, r6         @ bit for cursor col
    cmp  r7, #1
    ite  eq
    orreq r1, r1, r0        @ blink ON: set bit
    bicne r1, r1, r0        @ blink OFF: clear bit (show dark)

df_no_cursor:
    mov  r0, r4
    bl   light_row_mask
    ldr  r0, =MUX_SLICE
    bl   delay_ticks
    add  r4, r4, #1
    b    df_row

df_done:
    pop  {r4, r5, r6, r7, pc}


@ *** update_blink

    .thumb_func
update_blink:
    ldr  r0, =blink_ctr
    ldr  r1, [r0]
    add  r1, r1, #1
    cmp  r1, #BLINK_PERIOD
    blt  ub_store
    mov  r1, #0
    ldr  r2, =blink_state
    ldr  r3, [r2]
    eor  r3, r3, #1
    str  r3, [r2]
ub_store:
    str  r1, [r0]
    bx   lr


@ *** win_animation – spiral LEDs on one by one

    .thumb_func
win_animation:
    push {r4, r5, lr}

    @ Clear grid first
    ldr  r0, =grid
    mov  r1, #0
    strb r1, [r0, #0]
    strb r1, [r0, #1]
    strb r1, [r0, #2]
    strb r1, [r0, #3]
    strb r1, [r0, #4]

    @ Light LEDs one by one in spiral order
    mov  r4, #0             @ index into spiral_seq
wa_loop:
    cmp  r4, #SPIRAL_LEN
    bge  wa_done

    ldr  r5, =spiral_seq
    lsl  r0, r4, #1
    add  r5, r5, r0
    ldrb r0, [r5]           @ row
    ldrb r1, [r5, #1]       @ col

    @ Set this cell in grid
    ldr  r2, =grid
    ldrb r3, [r2, r0]
    mov  r12, #1
    lsl  r12, r12, r1
    orr  r3, r3, r12
    strb r3, [r2, r0]

    @ Show updated grid for a moment
    mov  r5, #8             @ multiplex passes
wa_mux:
    cmp  r5, #0
    beq  wa_next_led
    bl   display_frame
    subs r5, r5, #1
    b    wa_mux

wa_next_led:
    add  r4, r4, #1
    b    wa_loop

wa_done:
    @ Flash all LEDs 3 times
    mov  r4, #3
wa_flash:
    cmp  r4, #0
    beq  wa_end
    ldr  r0, =GPIO0_BASE
    ldr  r1, =GPIO0_ROW_MASK
    str  r1, [r0, #GPIO_OUTSET]
    ldr  r1, =GPIO0_COL_MASK
    str  r1, [r0, #GPIO_OUTCLR]
    ldr  r0, =GPIO1_BASE
    ldr  r1, =COL4_MASK
    str  r1, [r0, #GPIO_OUTCLR]
    ldr  r0, =FLASH_DELAY
    bl   delay_soft
    bl   leds_all_off
    ldr  r0, =FLASH_DELAY
    bl   delay_soft
    subs r4, r4, #1
    b    wa_flash

wa_end:
    pop  {r4, r5, pc}


@ *** read_btn_a
@       Returns r0: 0=none  1=short  2=long

    .thumb_func
read_btn_a:
    push {r4, lr}
    ldr  r0, =GPIO0_BASE
    ldr  r1, [r0, #GPIO_IN]
    ldr  r0, =BTN_A_MASK
    tst  r1, r0
    bne  rba_none
    ldr  r0, =DEBOUNCE
    bl   delay_soft
    ldr  r0, =GPIO0_BASE
    ldr  r1, [r0, #GPIO_IN]
    ldr  r0, =BTN_A_MASK
    tst  r1, r0
    bne  rba_none
    ldr  r4, =LONG_PRESS
rba_wait:
    subs r4, r4, #1
    beq  rba_long
    ldr  r0, =GPIO0_BASE
    ldr  r1, [r0, #GPIO_IN]
    ldr  r0, =BTN_A_MASK
    tst  r1, r0
    beq  rba_wait
    mov  r0, #1
    pop  {r4, pc}
rba_long:
rba_long_rel:
    ldr  r0, =GPIO0_BASE
    ldr  r1, [r0, #GPIO_IN]
    ldr  r0, =BTN_A_MASK
    tst  r1, r0
    beq  rba_long_rel
    mov  r0, #2
    pop  {r4, pc}
rba_none:
    mov  r0, #0
    pop  {r4, pc}


@ *** read_btn_b
@       Returns r0: 0=none  1=short  2=long

    .thumb_func
read_btn_b:
    push {r4, lr}
    ldr  r0, =GPIO0_BASE
    ldr  r1, [r0, #GPIO_IN]
    ldr  r0, =BTN_B_MASK
    tst  r1, r0
    bne  rbb_none
    ldr  r0, =DEBOUNCE
    bl   delay_soft
    ldr  r0, =GPIO0_BASE
    ldr  r1, [r0, #GPIO_IN]
    ldr  r0, =BTN_B_MASK
    tst  r1, r0
    bne  rbb_none
    ldr  r4, =LONG_PRESS
rbb_wait:
    subs r4, r4, #1
    beq  rbb_long
    ldr  r0, =GPIO0_BASE
    ldr  r1, [r0, #GPIO_IN]
    ldr  r0, =BTN_B_MASK
    tst  r1, r0
    beq  rbb_wait
    mov  r0, #1
    pop  {r4, pc}
rbb_long:
rbb_long_rel:
    ldr  r0, =GPIO0_BASE
    ldr  r1, [r0, #GPIO_IN]
    ldr  r0, =BTN_B_MASK
    tst  r1, r0
    beq  rbb_long_rel
    mov  r0, #2
    pop  {r4, pc}
rbb_none:
    mov  r0, #0
    pop  {r4, pc}


@ *** main_loop

    .thumb_func
main_loop:
    push {lr}

ml_top:
    bl   display_frame
    bl   update_blink

    @ Check win
    bl   check_win
    cmp  r0, #1
    bne  ml_btns
    bl   win_animation
    bl   new_puzzle
    b    ml_top

ml_btns:
    @ Button A
    bl   read_btn_a
    cmp  r0, #1
    beq  ml_a_short
    cmp  r0, #2
    beq  ml_a_long
    b    ml_btn_b

ml_a_short:
    @ Move cursor forward (wraps 0..24)
    ldr  r0, =cursor_pos
    ldr  r1, [r0]
    add  r1, r1, #1
    cmp  r1, #25
    it   ge
    movge r1, #0
    str  r1, [r0]
    b    ml_btn_b

ml_a_long:
    @ New puzzle
    bl   new_puzzle
    b    ml_top

ml_btn_b:
    bl   read_btn_b
    cmp  r0, #1
    bne  ml_top

    @ Toggle cell at cursor
    ldr  r0, =cursor_pos
    ldr  r0, [r0]
    mov  r1, #5
    udiv r2, r0, r1         @ row = pos / 5
    mul  r3, r2, r1
    sub  r3, r0, r3         @ col = pos % 5
    mov  r0, r2
    mov  r1, r3
    bl   toggle_cell
    b    ml_top

    pop  {pc}


@ *** Stack

    .section .stack, "aw", %nobits
    .align 3
    .space  2048
_stack_top:

    .end