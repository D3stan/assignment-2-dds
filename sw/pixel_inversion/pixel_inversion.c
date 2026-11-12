/*
 * Contributors:
 *   - Dovydas Liutkus (dovli@dtu.dk)
 * Description:
 *   - Drives the Student_area_0 pixel-inversion accelerator.
 *   - Receives image pixels from UART, writes to ibuf, triggers processing,
 *     polls for completion.
 *   - Sends processed pixels back over UART (currently disabled for faster simulation)
 */

#include <stdint.h>
#include "soc_ctrl.h"
#include "uart.h"

/* ------------------------------------------------------------------ */
/* Accelerator register addresses (Student_area_0 @ 0x01050000)       */
/* ------------------------------------------------------------------ */
#define ACCEL_BASE          0x01050000u

#define ACCEL_CSR           ((volatile uint32_t *)(ACCEL_BASE + 0x00u))
#define ACCEL_DMA_CFG       ((volatile uint32_t *)(ACCEL_BASE + 0x04u))
#define ACCEL_DMA_LEN       ((volatile uint32_t *)(ACCEL_BASE + 0x08u))
#define ACCEL_DMA_CTRL_STAT ((volatile uint32_t *)(ACCEL_BASE + 0x0Cu))
#define ACCEL_OBUF_ADDR     ((volatile uint32_t *)(ACCEL_BASE + 0x10u))
#define ACCEL_OBUF_DATA     ((volatile uint32_t *)(ACCEL_BASE + 0x14u))

/* CSR bit positions */
#define CSR_DATA_READY  (1u << 0)
#define CSR_DONE        (1u << 1)

/* DMA CTRL_STAT bit positions */
#define DMA_CTRL_START  (1u << 0)
#define DMA_CTRL_BUSY   (1u << 1)
#define DMA_CTRL_IRQ_EN (1u << 2)
#define DMA_CTRL_DONE   (1u << 3)

/* ------------------------------------------------------------------ */
/* Frame geometry                                                      */
/* ------------------------------------------------------------------ */
#define FRAME_WIDTH     352u
#define FRAME_HEIGHT    288u
#define TOTAL_PIXELS    (FRAME_WIDTH * FRAME_HEIGHT)  // 101376
#define PIXELS_PER_WORD 4u
#define BUF_DEPTH       (TOTAL_PIXELS / PIXELS_PER_WORD)  // 25344

/* ------------------------------------------------------------------ */
/* Receive one byte from UART (polling)                               */
/* ------------------------------------------------------------------ */
static inline uint8_t uart_read_byte(void)
{
    while (!(LSR & 0x1u)) {}        // Wait for RX data ready
    return (uint8_t)(RBR_THR_DLL & 0xFFu);
}

static inline void uart_write_byte(uint8_t b)
{
    while (!(LSR & 0x20u)) {}       // Wait for TX holding register empty
    RBR_THR_DLL = b;
}

int main(void)
{
    ss_init(0);
    uart_init();
    IIR_FCR = 0x07u; /* FIFO enable + RX reset + TX reset */

#ifdef SIM_FAST_UART
    /* Override baud divisor for fast simulation.
     * divisor=2 → 100 MHz / (16×2) = 3.125 Mbaud (320 ns/bit).
     * Testbench must be compiled with +define+SIM_FAST_UART to match.
     * NOTE: divisor=1 is unusable — iBAUDOUTN gets stuck at 0 and RX never fires. */
    LCR = (1u << 7) | 3u;  /* enable DLAB */
    RBR_THR_DLL = 2u;       /* divisor = 2 → 100 MHz / (16×2) = 3.125 Mbaud (320 ns/bit) */
    LCR = 3u;               /* disable DLAB */
#endif

#ifdef SIM_FAST_UART
    *ACCEL_DMA_CFG = 32u;  /* 32 clocks per bit in fast simulation */
#else
    *ACCEL_DMA_CFG = 432u; /* 432 clocks per bit for standard UART */
#endif

    /* Start DMA streaming transfer for entire frame:
     * - Ingests UART RX -> DMA Packer -> pixel_acc (streaming in)
     * - Transmits pixel_acc -> DMA Unpacker -> UART TX (streaming out) */
    *ACCEL_DMA_LEN = BUF_DEPTH;
    *ACCEL_DMA_CTRL_STAT = DMA_CTRL_START | DMA_CTRL_IRQ_EN;

    /* Wait for streaming processing to complete (no CPU polling of pixels) */
    while (!(*ACCEL_DMA_CTRL_STAT & DMA_CTRL_DONE) && !(*ACCEL_CSR & CSR_DONE)) {
        __asm__ volatile ("wfi");
    }

    while (1) {
        __asm__ volatile ("wfi");
    }
    
    return 0;
}
