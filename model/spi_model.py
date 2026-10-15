"""
Cycle-accurate Python model of mcp3008_spi_master.v, register-for-register,
to validate the FSM logic before running it through iverilog on the Mac.
"""

S_IDLE, S_SETUP, S_LOW, S_HIGH = range(4)


def simulate_spi(channel, adc_value, sclk_div=14, max_cycles=2000):
    """
    channel: 0-7, which MCP3008 channel we're commanding
    adc_value: the 10-bit value (0-1023) we pretend the ADC returns on MISO,
               fed bit-by-bit MSB-first at exactly the cycles the master samples it
    Returns (mosi_sequence_by_idx, captured_adc_data, total_cycles_busy)
    """
    state = S_IDLE
    sclk = 0
    cs_n = 1
    mosi = 0
    busy = 0
    data_valid = 0
    bit_cnt = 0
    mosi_shift = 0
    miso_shift = 0
    adc_data = 0
    div_cnt = 0

    mosi_log = {}   # idx -> mosi value sampled at that rising edge
    started = False
    result = None

    for cycle in range(max_cycles):
        start_pulse = (cycle == 0)  # fire 'start' on cycle 0

        # ---- clock divider (mirrors the always-block using OLD busy) ----
        old_busy = busy
        if old_busy:
            if div_cnt == sclk_div - 1:
                new_div_cnt = 0
                sclk_tick = 1
            else:
                new_div_cnt = div_cnt + 1
                sclk_tick = 0
        else:
            new_div_cnt = 0
            sclk_tick = 0

        # ---- main FSM (using OLD state values on the RHS, like nonblocking assigns) ----
        new_state = state
        new_sclk = sclk
        new_cs_n = cs_n
        new_mosi = mosi
        new_busy = busy
        new_data_valid = 0
        new_bit_cnt = bit_cnt
        new_mosi_shift = mosi_shift
        new_miso_shift = miso_shift
        new_adc_data = adc_data

        if state == S_IDLE:
            new_sclk = 0
            new_cs_n = 1
            if start_pulse:
                new_cs_n = 0
                new_mosi_shift = (1 << 4) | (1 << 3) | channel  # start,sgl/diff,D2D1D0
                new_bit_cnt = 0
                new_miso_shift = 0
                new_busy = 1
                new_state = S_SETUP

        elif state == S_SETUP:
            new_mosi = (mosi_shift >> 4) & 1
            mosi_log[0] = new_mosi
            if sclk_tick:
                new_state = S_LOW

        elif state == S_LOW:
            if sclk_tick:
                new_sclk = 1
                if bit_cnt >= 7:
                    # get the correct MISO bit for this data-phase index (7..16 -> B9..B0)
                    data_bit_index = 9 - (bit_cnt - 7)  # idx7->B9 ... idx16->B0
                    miso_bit = (adc_value >> data_bit_index) & 1
                    new_miso_shift = ((miso_shift << 1) | miso_bit) & 0x3FF
                new_state = S_HIGH

        elif state == S_HIGH:
            if sclk_tick:
                new_sclk = 0
                if bit_cnt == 16:
                    new_adc_data = miso_shift
                    new_data_valid = 1
                    new_busy = 0
                    new_cs_n = 1
                    new_state = S_IDLE
                    result = miso_shift
                else:
                    new_bit_cnt = bit_cnt + 1
                    if bit_cnt < 4:
                        bit_val = (mosi_shift >> (3 - bit_cnt)) & 1
                        new_mosi = bit_val
                        mosi_log[bit_cnt + 1] = bit_val
                    new_state = S_LOW

        # ---- commit ----
        state, sclk, cs_n, mosi, busy, data_valid = (
            new_state, new_sclk, new_cs_n, new_mosi, new_busy, new_data_valid)
        bit_cnt, mosi_shift, miso_shift, adc_data = (
            new_bit_cnt, new_mosi_shift, new_miso_shift, new_adc_data)
        div_cnt = new_div_cnt

        if result is not None:
            return mosi_log, result, cycle + 1

    return mosi_log, None, None


if __name__ == "__main__":
    for channel in range(8):
        test_value = 0x2B3  # 691 decimal, arbitrary known "fake ADC reading"
        mosi_log, captured, cycles = simulate_spi(channel, test_value)
        expected_mosi = [1, 1, (channel >> 2) & 1, (channel >> 1) & 1, channel & 1]
        actual_mosi = [mosi_log[i] for i in range(5)]
        ok_mosi = actual_mosi == expected_mosi
        ok_data = captured == test_value
        print(f"channel={channel}  mosi_bits={actual_mosi} (expected {expected_mosi})  "
              f"ok_mosi={ok_mosi}  captured=0x{captured:03X} expected=0x{test_value:03X} "
              f"ok_data={ok_data}  total_cycles={cycles}")
