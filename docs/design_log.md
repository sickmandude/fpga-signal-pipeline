# Design log: problems we hit and how they were resolved

Chronological record of the real setbacks on this project, kept because the way each was found matters as much as the fix.

## 1. The time-multiplexed FIR assumed data arrives every 31 cycles

**Design:** the 31-tap FIR uses one multiplier (1 of the 20 MULT18X18 blocks on the GW1NR-9) and steps through the taps one per clock, accumulating the products. That saves multipliers but makes the filter a 31-cycle machine.

**Problem:** the first version (`fir_filter_31tap_tm.v`) was free-running. Its tap counter cycled continuously and it shifted its delay line at the end of every 31-cycle pass. That is correct when a new sample is available every 31 cycles, which is how it was tested. The real ADC delivers one sample every 2,700 cycles (10 kHz at 27 MHz), so the filter would have shifted in the same stale sample about 87 times per real sample, corrupting the output.

**Fix:** `fir_filter_31tap_tm_triggered.v`. The tap counter is replaced by a small FSM (IDLE / LOAD / RUN) that runs exactly one 31-tap pass per `start` pulse and shifts the delay line only on that pulse. Validated bit-exact against the free-running version (after accounting for the free-running version's spurious leading-zero output at start-up).

**Lesson:** a block that is correct in a testbench with an idealized input rate can be wrong against the real source. The timing assumption has to be part of the interface.

## 2. A latency measurement that was off by one, twice

**Goal:** report precise latency numbers. The Python cycle-accurate model predicted 33 cycles for the filter and 524 cycles end to end (ADC chip-select falling to filtered output valid).

**Problem:** the first testbenches used `$realtime` arithmetic and measured 32 and 525 cycles.

**Hypothesis 1 (wrong):** a blocking-versus-nonblocking race in the testbench. Switching the stimulus to nonblocking assignment changed nothing: still 32. That ruled the race out.

**Resolution:** replaced the time arithmetic with a plain integer that counts clock edges. This gave 33 and 524 cycles, matching the model exactly. The most likely cause of the original error is rounding in the printed real numbers combined with `$rtoi` truncating toward zero, though that was inferred and not isolated.

**Result:** 33 cycles (1.22 us) for the filter, 524 cycles (19.4 us) end to end, each confirmed two independent ways (Python model and Icarus Verilog edge counting). These are simulation numbers.

**Lesson:** when a measurement disagrees with a model, test the hypothesis before believing it, and prefer integer counters over real-number time in testbenches.

## 3. Choosing pins: voltage banks and board conflicts

The Tang Nano 9K's I/O is split into banks with different voltages. Bank 3 (pins 79-86 and, as found later from the schematic, the buttons and LEDs) runs at 1.8 V, which is unsafe for a 3.3 V MCP3008. Some pins are also taken by the on-board TF-card slot. The ADC lines were put on pins 25-28 (bank 2, 3.3 V, no on-board conflicts). The pin numbers were taken from the board's own pinout diagram, not guessed.

## 4. First place-and-route failed: unconstrained I/O

`nextpnr` stops with `Unconstrained IO` if any top-level port has no pin. The full top level exposed a 32-bit filtered output with nothing to read it, and constraining 32 pins was pointless. A thin debug wrapper that exposed only a valid-toggle LED and the sign bit was used first. The build then closed timing at 185.43 MHz post-route against a 27 MHz requirement (about 6.9x margin), using 154 LUT4, 1 MULT18X18 and about 430 flip-flops (figures from the debug-wrapper build).

## 5. Toolchain stumbles

- `gowin_pack` needs `-d GW1N-9C`, not `GW1NR-9C` (the latter has no chip database file).
- `gowin_pack` failed with a file-not-found traceback because the place-and-route step had not run yet, so the routed JSON did not exist.
- Re-running an old compiled simulation binary instead of recompiling gave identical output to the previous run. The tell was the identical output.

## 6. Hardware bring-up

- **Intermittent or dead input:** the pot appeared to do nothing, then changed unpredictably. Cause: the header pins were not soldered, so the connections were only resting in the holes. After soldering, the pot flipped the sign LED as expected.
- **Floating inputs read high:** an unconnected FPGA input with a pull-up reads 1, which can look like a signal. The ground-versus-3.3 V wiring tests were needed to see real changes.
- **LEDs are active low,** so writing 0 turns them on. This confused early readings.
- **Pin identity from the schematic:** S1 is pin 3 and S2 is pin 4. An earlier assumption had them swapped.

## 7. UART bring-up: two bugs

The FPGA transmitted on pin 17, the Mac read nothing. The symptom was the same for every test, so the work was ruling things out one at a time.

### What was ruled out, and how

| Hypothesis | Test | Result |
|---|---|---|
| Wrong pin | Probe design: pins 17/18 as inputs mirrored to LEDs, host sends zeros | Pin 18 is driven by the bridge (FPGA RX), so pin 17 is FPGA TX. Confirmed against the board schematic. |
| Wrong serial port / bridge path | Echo design wiring pin 18 straight to pin 17 | The echo returns on the second port, so FPGA TX does reach the host. |
| Wrong baud rate (FPGA side) | Edge-counter design: count falling edges on pin 17 over a 1.24 s window, show on LEDs | Count matched a correct 115200 stream (model: about 51,000; LEDs read 000011 = 49,152-65,535). |
| Wrong baud rate (bridge side) | FPGA times the low pulse of repeated 'U' (0x55) sent by the host | 234 clocks = 115200 baud. Bridge runs at the requested rate. |

### Bug 1: no power-on reset

State machines in the FPGA power up with all flip-flops at 0, which is not necessarily a valid state (synthesis may recode a state machine as one-hot, and all-zero is not a one-hot state). The UART transmitter never started and pin 17 stayed low. Simulation did not show it because the testbench applies a reset.

Found with LEDs showing "line seen low" and "line seen high" separately. Only "low" lit: the line was stuck, not toggling.

Fix: a 16-clock power-on reset counter that holds `rst_n` low at start-up.

### Bug 2: no idle gaps

With the reset fixed, the line toggled correctly (confirmed by the edge counter) and the bridge ran at the right baud, but a continuous stream of back-to-back bytes produced no data on the host. Sending one letter every 10 ms worked immediately. The bridge firmware appears to deliver received data only when the line goes quiet. Sparse frames (DECIM = 64, about 6 ms idle between frames) work. The smaller gaps at DECIM = 8 were not tested.

### Takeaways

- A testbench that applies reset hides power-up-state bugs. Hardware needs its own reset.
- Make the hardware report its own state (LEDs, counters) when you have no scope.
- A negative result is only as good as the test: several early "nothing received" scans ran against a design that was not actually transmitting.
