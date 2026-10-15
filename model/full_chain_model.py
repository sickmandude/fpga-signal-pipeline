"""
Cycle-accurate Python model of the FULL adc_fir_top.v chain:
sample_rate_timer -> mcp3008_spi_master -> scale -> fir_filter_31tap_tm_triggered

This lets us predict exactly what the real iverilog simulation should produce,
accounting for the real-world detail that the MCP3008 only has 10-bit
resolution, so we lose the bottom 6 bits of precision going through real
hardware compared to the original 16-bit signal_fixed reference.
"""

import numpy as np
from hw_model import coeffs, signal_fixed

CLK_FREQ = 27_000_000
SAMPLE_RATE = 10_000
SAMPLE_PERIOD_CYCLES = CLK_FREQ // SAMPLE_RATE  # 2700
SCLK_DIV = 14

S_IDLE, S_SETUP, S_LOW, S_HIGH = range(4)
F_IDLE, F_LOAD, F_RUN = range(3)


def adc_code_from_signal_fixed(value):
    """Inverse of the top-level's scaling: what 10-bit code would the ADC
    need to output so that (code-512)<<6 reconstructs `value` as closely
    as a 10-bit ADC can?"""
    code = round(value / 64) + 512
    return max(0, min(1023, code))


def reconstructed_sample_in(code):
    return (code - 512) * 64


def simulate_full_chain(signal, n_samples):
    codes = [adc_code_from_signal_fixed(v) for v in signal[:n_samples]]

    # ---- SPI master state ----
    spi_state = S_IDLE
    sclk = 0
    cs_n = 1
    busy_spi = 0
    div_cnt = 0
    bit_cnt = 0
    mosi_shift = 0
    miso_shift = 0
    adc_data = 0
    data_valid = 0

    # ---- FIR filter state ----
    fir_state = F_IDLE
    tap = 0
    x = [0] * 31
    accumulator = 0
    fir_out_valid = 0

    # ---- timer ----
    timer_count = 0

    outputs = []
    sample_idx = 0
    total_cycles = SAMPLE_PERIOD_CYCLES * (n_samples + 2)

    for cycle in range(total_cycles):
        # ---- timer ----
        tick = 0
        if timer_count == SAMPLE_PERIOD_CYCLES - 1:
            timer_count = 0
            tick = 1
        else:
            timer_count += 1

        start_spi = tick and (sample_idx < n_samples)
        channel = 0

        # ---- SPI clock divider ----
        old_busy_spi = busy_spi
        if old_busy_spi:
            if div_cnt == SCLK_DIV - 1:
                new_div_cnt = 0
                sclk_tick = 1
            else:
                new_div_cnt = div_cnt + 1
                sclk_tick = 0
        else:
            new_div_cnt = 0
            sclk_tick = 0

        new_spi_state = spi_state
        new_busy_spi = busy_spi
        new_bit_cnt = bit_cnt
        new_mosi_shift = mosi_shift
        new_miso_shift = miso_shift
        new_adc_data = adc_data
        new_data_valid = 0

        current_code = codes[sample_idx] if sample_idx < n_samples else 0

        if spi_state == S_IDLE:
            if start_spi:
                new_mosi_shift = (1 << 4) | (1 << 3) | channel
                new_bit_cnt = 0
                new_miso_shift = 0
                new_busy_spi = 1
                new_spi_state = S_SETUP
        elif spi_state == S_SETUP:
            if sclk_tick:
                new_spi_state = S_LOW
        elif spi_state == S_LOW:
            if sclk_tick:
                if bit_cnt >= 7:
                    data_bit_index = 9 - (bit_cnt - 7)
                    miso_bit = (current_code >> data_bit_index) & 1
                    new_miso_shift = ((miso_shift << 1) | miso_bit) & 0x3FF
                new_spi_state = S_HIGH
        elif spi_state == S_HIGH:
            if sclk_tick:
                if bit_cnt == 16:
                    new_adc_data = miso_shift
                    new_data_valid = 1
                    new_busy_spi = 0
                    new_spi_state = S_IDLE
                else:
                    new_bit_cnt = bit_cnt + 1
                    new_spi_state = S_LOW

        # ---- FIR filter ----
        current_x = x[tap]
        current_h = coeffs[tap]
        mult_result = current_x * current_h

        new_fir_state = fir_state
        new_tap = tap
        new_x = x
        new_accumulator = accumulator
        new_fir_out_valid = 0

        sample_in = (adc_data - 512) * 64  # combinational scale of CURRENT adc_data

        if fir_state == F_IDLE:
            if data_valid:  # 'start' = adc_data_valid; note: uses just-updated data_valid this cycle? see below
                new_x = [sample_in] + x[0:30]
                new_fir_state = F_LOAD
        elif fir_state == F_LOAD:
            new_tap = 0
            new_fir_state = F_RUN
        elif fir_state == F_RUN:
            if tap == 30:
                new_fir_state = F_IDLE
            else:
                new_tap = tap + 1

        if fir_state == F_RUN:
            if tap == 0:
                new_accumulator = mult_result
            else:
                new_accumulator = accumulator + mult_result

        if fir_state == F_RUN and tap == 30:
            new_fir_out_valid = 1

        # ---- commit everything (all using OLD values read above => synchronous) ----
        spi_state, busy_spi, bit_cnt, mosi_shift, miso_shift, adc_data, data_valid = (
            new_spi_state, new_busy_spi, new_bit_cnt, new_mosi_shift,
            new_miso_shift, new_adc_data, new_data_valid)
        div_cnt = new_div_cnt

        fir_state, tap, x, accumulator, fir_out_valid = (
            new_fir_state, new_tap, new_x, new_accumulator, new_fir_out_valid)

        timer_count = timer_count  # already updated above
        if tick:
            sample_idx += 1

        sample_out = accumulator >> 15
        if fir_out_valid:
            outputs.append(sample_out)

    return codes, outputs


if __name__ == "__main__":
    n = 20  # keep it modest; full sim is 2700*22 = ~59,400 cycles, fine for python
    codes, outputs = simulate_full_chain(signal_fixed, n)
    print("ADC codes fed in:", codes)
    print("Number of filtered outputs:", len(outputs))
    print("Filtered outputs:", outputs)
