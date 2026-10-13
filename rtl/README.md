# Winograd RTL Datapath Modules
- `input_transform.sv`: Input transform unit (B^T * d * B)
- `winograd_mul_array.sv`: Parameterizable element-wise multiplier engine
- `channel_accumulator.sv`: Multi-channel partial sum accumulator
- `output_transform.sv`: Output transform unit (A^T * M * A)
- `controller.sv`: Datapath controller & FSM
- `winograd_accelerator_top.sv`: Top-level accelerator core
