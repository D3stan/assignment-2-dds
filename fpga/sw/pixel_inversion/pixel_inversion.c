/*
 * Contributors:
 *   - Dovydas Liutkus (dovli@dtu.dk)
 * Description:
 *   - Drives the Student_area_0 pixel-inversion accelerator.
 *   - Receives image pixels from UART, writes to ibuf, triggers processing,
 *     polls for completion.
 *   - Sends processed pixels back over UART
 */

#include <stdint.h>
#include "soc_ctrl.h"
#include "uart.h"

/* ------------------------------------------------------------------ */
/* Accelerator register addresses (Student_area_0 @ 0x01050000)       */
/* ------------------------------------------------------------------ */
#define ACCEL_BASE          0x01050000u
#define ACCEL_CSR           ((volatile uint32_t *)(ACCEL_BASE + 0x00u))
#define ACCEL_DMA_SRC       ((volatile uint32_t *)(ACCEL_BASE + 0x04u))
#define ACCEL_DMA_LEN       ((volatile uint32_t *)(ACCEL_BASE + 0x08u))
#define ACCEL_DMA_CTRL_STAT ((volatile uint32_t *)(ACCEL_BASE + 0x0Cu))
#define ACCEL_OBUF_ADDR     ((volatile uint32_t *)(ACCEL_BASE + 0x10u))
#define ACCEL_OBUF_DATA     ((volatile uint32_t *)(ACCEL_BASE + 0x14u))

/* DMA CTRL_STAT bit positions */
#define DMA_CTRL_START      (1u << 0)
#define DMA_CTRL_BUSY       (1u << 1)
#define DMA_CTRL_IRQ_EN     (1u << 2)
#define DMA_CTRL_DONE       (1u << 3)
#define DMA_CTRL_SRC_INC    (1u << 4)
#define DMA_CTRL_DST_INC    (1u << 5)

/* CSR bit positions */
#define CSR_DATA_READY  (1u << 0)
#define CSR_DONE        (1u << 1)

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

static uint32_t image_buffer[BUF_DEPTH];

int main(void)
{
    ss_init(0);
    uart_init(15000000u, 38400u);
    IIR_FCR = 0x07u; /* FIFO enable + RX reset + TX reset */

    /* Main command loop:
     *   't' -> ping, reply 'y'
     *   'w' -> receive image into DMEM, transfer to ibuf via DMA, run accelerator
     *   'r' -> send obuf back over UART (only if processing is done)
     */
    uint8_t result_ready = 0u;
    while (1) {
        uint8_t cmd = uart_read_byte();

        if (cmd == 't') {
            uart_write_byte('y');

        } else if (cmd == 'w') {
            result_ready = 0u;
            for (uint32_t i = 0u; i < BUF_DEPTH; i++) {
                uint32_t word = (uint32_t)uart_read_byte()
                              | ((uint32_t)uart_read_byte() <<  8)
                              | ((uint32_t)uart_read_byte() << 16)
                              | ((uint32_t)uart_read_byte() << 24);
                image_buffer[i] = word;
            }

            /* Transfer image from DMEM to ibuf via DMA */
            *ACCEL_DMA_SRC = (uint32_t)image_buffer;
            *ACCEL_DMA_LEN = BUF_DEPTH;
            *ACCEL_DMA_CTRL_STAT = DMA_CTRL_START | DMA_CTRL_SRC_INC | DMA_CTRL_DST_INC;

            /* Wait for DMA transfer to complete */
            while (!(*ACCEL_DMA_CTRL_STAT & DMA_CTRL_DONE)) {}

            *ACCEL_CSR = CSR_DATA_READY;
            while (!(*ACCEL_CSR & CSR_DONE)) {}
            result_ready = 1u;

        } else if (cmd == 'r' && result_ready) {
            *ACCEL_OBUF_ADDR = 0u;
            for (uint32_t i = 0u; i < BUF_DEPTH; i++) {
                uint32_t word = *ACCEL_OBUF_DATA;
                uart_write_byte((uint8_t)(word         & 0xFFu));
                uart_write_byte((uint8_t)((word >>  8) & 0xFFu));
                uart_write_byte((uint8_t)((word >> 16) & 0xFFu));
                uart_write_byte((uint8_t)((word >> 24) & 0xFFu));
            }
        }
    }

    return 0;
}
