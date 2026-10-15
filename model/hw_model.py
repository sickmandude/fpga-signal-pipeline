"""
Cycle-accurate Python model of fir_filter_31tap_tm.v

This replicates the exact synchronous logic of the Verilog module,
register-for-register, so we can predict what the real iverilog/vvp
simulation will print, without needing the Verilog toolchain installed
in this sandbox.
"""

coeffs = [-178, -180, -100, 152, 590, 1036, 1137, 564, -703, -2213,
          -3181, -2903, -1216, 1297, 3528, 4416, 3528, 1297, -1216, -2903,
          -3181, -2213, -703, 564, 1137, 1036, 590, 152, -100, -180, -178]

assert len(coeffs) == 31

signal_fixed = [4883, 17901, 32767, 32767, 16959, -2302, -3736, -23620, -32768, -13927,
                -4556, 14682, 32767, 12356, 2304, -5528, -29217, -28075, -32768, -32768,
                14408, 17041, 31828, 17158, 13909, 1090, -30575, -27471, -32768, -22128,
                -5915, 32767, 31032, 20766, 27346, -12001, -17207, -32768, -32768, -17325]


def simulate(samples, n_extra_passes=1):
    """
    Simulate the hardware for len(samples) sample-loads, each held for
    31 clock cycles (one full tap pass), exactly like the testbench.
    Returns the list of sample_out values captured on cycles where
    out_valid is high, in order.
    """
    x = [0] * 31          # x0..x30 shift register
    tap = 0
    accumulator = 0
    out_valid_reg = 0
    outputs = []

    # sample_in is held constant for 31 cycles per entry, like the tb
    total_cycles = 31 * (len(samples) + n_extra_passes)

    def sample_in_at(cycle):
        idx = cycle // 31
        if idx >= len(samples):
            idx = len(samples) - 1
        return samples[idx]

    for cycle in range(total_cycles):
        s_in = sample_in_at(cycle)

        # ---- combinational mux (based on CURRENT/old tap) ----
        current_x = x[tap]
        current_h = coeffs[tap]
        mult_result = current_x * current_h

        # ---- compute next-state values using OLD state ----
        if tap == 30:
            new_x = [s_in] + x[0:30]
        else:
            new_x = x

        if tap == 0:
            new_accumulator = mult_result
        else:
            new_accumulator = accumulator + mult_result

        new_out_valid_reg = 1 if tap == 30 else 0

        new_tap = 0 if tap == 30 else tap + 1

        # ---- commit (posedge clk) ----
        x = new_x
        accumulator = new_accumulator
        out_valid_reg = new_out_valid_reg
        tap = new_tap

        # sample_out is a continuous (unclocked) view of accumulator >>> 15
        sample_out = accumulator >> 15  # Python >> on ints matches Verilog >>> (floor / arithmetic shift)

        if out_valid_reg:
            outputs.append(sample_out)

    return outputs


if __name__ == "__main__":
    hw_out = simulate(signal_fixed)
    print("Number of outputs:", len(hw_out))
    print(hw_out)
