import serial

# ── Config ────────────────────────────────────────────────────────────────────
PORT      = 'COM3'
BAUD      = 115_200
MAX_DIM   = 16
MAX_DEPTH = 4
ACC_BITS  = 36
TX_BYTES  = (ACC_BITS + 7) // 8   # 5 bytes per READ_C response

# Hardware bit-width limits (must match uart_tensor_bridge parameters)
# DIM_W  = $clog2(MAX_DIM+1)  = 5 bits  → M, K, N max = 2^5 - 1 = 31, but
#           hardware parameter MAX_DIM=16 is the real ceiling.
# DEP_W  = $clog2(MAX_DEPTH+1)= 3 bits  → D max = 2^3 - 1 = 7, but
#           hardware parameter MAX_DEPTH=4 is the real ceiling.
# We guard against both: value must fit in one byte AND be <= the parameter.
_HW_DIM_MAX = MAX_DIM    # 16
_HW_DEP_MAX = MAX_DEPTH  # 4

OPS = {
    'matmul'    : 0b000,
    'add'       : 0b001,
    'sub'       : 0b010,
    'hadamard'  : 0b011,
    'row_accum' : 0b100,
    'col_accum' : 0b101,
}

OPS_NEED_B = {'matmul', 'add', 'sub', 'hadamard'}

# ── Serial open ───────────────────────────────────────────────────────────────
try:
    ser = serial.Serial(PORT, baudrate=BAUD, timeout=5)
    print(f"Opened {PORT} at {BAUD} baud")
except serial.SerialException as e:
    print(f"Could not open port: {e}")
    exit(1)

# ── Load-state tracking ───────────────────────────────────────────────────────
_a_ready = False
_b_ready = False

def _mark_a_dirty(): global _a_ready; _a_ready = False
def _mark_b_ready(): global _b_ready; _b_ready = True
def _mark_a_ready(): global _a_ready; _a_ready = True
def _mark_b_dirty(): global _b_ready; _b_ready = False

# ── Hardware parameter guards ─────────────────────────────────────────────────

def _check_dim(name, val):
    """Verify a matrix dimension fits in the hardware DIM_W field."""
    if not (1 <= val <= _HW_DIM_MAX):
        raise ValueError(
            f"{name}={val} out of hardware range [1..{_HW_DIM_MAX}]. "
            f"Resynthesize with larger MAX_DIM to increase this limit."
        )

def _check_dep(val):
    """Verify depth fits in the hardware DEP_W field."""
    if not (1 <= val <= _HW_DEP_MAX):
        raise ValueError(
            f"D={val} out of hardware range [1..{_HW_DEP_MAX}]. "
            f"Resynthesize with larger MAX_DEPTH to increase this limit."
        )

def _check_byte(name, val):
    """Final safety net: value must fit in one unsigned byte for UART packing."""
    if not (0 <= val <= 255):
        raise ValueError(f"{name}={val} does not fit in a single protocol byte.")

def _validate_run_params(M, K, N, D):
    """Full guard on all RUN parameters before touching the serial port."""
    _check_dim('M', M)
    _check_dim('K', K)
    _check_dim('N', N)
    _check_dep(D)
    # Belt-and-suspenders: also verify each fits in the byte we'll send
    for name, val in [('M', M), ('K', K), ('N', N), ('D', D)]:
        _check_byte(name, val)

# ── Flat address ──────────────────────────────────────────────────────────────

def flat_addr(depth_idx, row, col):
    return depth_idx * MAX_DIM * MAX_DIM + row * MAX_DIM + col

# ── Low-level UART protocol ───────────────────────────────────────────────────

def write_A(depth_idx, row, col, value):
    """WRITE_A: [0x01][addr_hi][addr_lo][data_hi][data_lo] → ACK(0xAA)"""
    addr = flat_addr(depth_idx, row, col)
    v16  = value & 0xFFFF
    ser.write(bytes([
        0x01,
        (addr >> 8) & 0xFF, addr & 0xFF,
        (v16  >> 8) & 0xFF, v16  & 0xFF
    ]))
    ack = ser.read(1)
    if ack != b'\xAA':
        raise RuntimeError(
            f"write_A(d={depth_idx},r={row},c={col}) no ACK, got "
            f"{ack.hex() if ack else 'timeout'}"
        )

def write_B(depth_idx, row, col, value):
    """WRITE_B: [0x02][addr_hi][addr_lo][data_hi][data_lo] → ACK(0xAA)"""
    addr = flat_addr(depth_idx, row, col)
    v16  = value & 0xFFFF
    ser.write(bytes([
        0x02,
        (addr >> 8) & 0xFF, addr & 0xFF,
        (v16  >> 8) & 0xFF, v16  & 0xFF
    ]))
    ack = ser.read(1)
    if ack != b'\xAA':
        raise RuntimeError(
            f"write_B(d={depth_idx},r={row},c={col}) no ACK, got "
            f"{ack.hex() if ack else 'timeout'}"
        )

def uart_run(op_name, op_bits, M, K, N, D):
    """RUN: [0x03][op][M][K][N][D] → ACK(0xAA) after tensor_top done."""
    global _a_ready, _b_ready

    # Hardware parameter guard — raises ValueError before touching serial
    _validate_run_params(M, K, N, D)

    if not _a_ready:
        raise RuntimeError(
            "RUN blocked: bram_A was not successfully loaded. Load A first."
        )
    if op_name in OPS_NEED_B and not _b_ready:
        raise RuntimeError(
            f"RUN blocked: op '{op_name}' requires B but bram_B was not loaded."
        )

    ser.write(bytes([0x03, op_bits, M, K, N, D]))
    ack = ser.read(1)
    if ack != b'\xAA':
        raise RuntimeError(f"RUN no ACK, got {ack.hex() if ack else 'timeout'}")

    _a_ready = False
    _b_ready = False

def read_C(depth_idx, row, col):
    """READ_C: [0x04][addr_hi][addr_lo] → TX_BYTES bytes MSB-first → signed ACC-bit int"""
    addr = flat_addr(depth_idx, row, col)
    ser.write(bytes([0x04, (addr >> 8) & 0xFF, addr & 0xFF]))
    raw  = ser.read(TX_BYTES)
    if len(raw) < TX_BYTES:
        raise RuntimeError(
            f"read_C(d={depth_idx},r={row},c={col}) timeout, "
            f"got {len(raw)} of {TX_BYTES} bytes"
        )
    val = int.from_bytes(raw, byteorder='big')
    if val >= (1 << (ACC_BITS - 1)):
        val -= (1 << ACC_BITS)
    return val

# ── Tensor / matrix load helpers ──────────────────────────────────────────────

def load_tensor_A(tensor, D, A_rows, A_cols):
    _mark_a_dirty()
    for d in range(D):
        for i in range(A_rows):
            for j in range(A_cols):
                write_A(d, i, j, int(tensor[d][i][j]))
    _mark_a_ready()

def load_tensor_B(tensor, D, B_rows, B_cols):
    _mark_b_dirty()
    for d in range(D):
        for i in range(B_rows):
            for j in range(B_cols):
                write_B(d, i, j, int(tensor[d][i][j]))
    _mark_b_ready()

def load_matrix_A(matrix, A_rows, A_cols):
    load_tensor_A([[matrix[i] for i in range(A_rows)]], 1, A_rows, A_cols)

def load_matrix_B(matrix, B_rows, B_cols):
    load_tensor_B([[matrix[i] for i in range(B_rows)]], 1, B_rows, B_cols)

def read_tensor_C(D, M, N):
    """Read full result tensor [D][M][N] from bram_C."""
    result = []
    for d in range(D):
        slice_ = []
        for i in range(M):
            row = [read_C(d, i, j) for j in range(N)]
            slice_.append(row)
        result.append(slice_)
    return result

def read_matrix_C(M, N):
    return read_tensor_C(1, M, N)[0]

# ── Accumulation result readers ───────────────────────────────────────────────
# ROW_ACCUM: hardware writes the same sum to all N cols of each row.
#   Logical result is M×1.  We read column 0 only for each row.
# COL_ACCUM: hardware writes the same sum to all M rows of each col.
#   Logical result is 1×N.  We read row 0 only for each col.

def read_tensor_C_row_accum(D, M):
    """
    Read ROW_ACCUM result: shape [D][M][1].
    Returns a 3-D list where result[d][i][0] is the sum of row i in slice d.
    """
    result = []
    for d in range(D):
        slice_ = []
        for i in range(M):
            slice_.append([read_C(d, i, 0)])   # col 0 holds the canonical sum
        result.append(slice_)
    return result

def read_tensor_C_col_accum(D, N):
    """
    Read COL_ACCUM result: shape [D][1][N].
    Returns a 3-D list where result[d][0][j] is the sum of column j in slice d.
    """
    result = []
    for d in range(D):
        row = [read_C(d, 0, j) for j in range(N)]  # row 0 holds the canonical sums
        result.append([row])
    return result

# ── Display ───────────────────────────────────────────────────────────────────

def display_matrix(matrix, name):
    rows = len(matrix)
    cols = len(matrix[0])
    print(f"\n  {name}  ({rows}x{cols}):")
    for row in matrix:
        print("    " + "  ".join(f"{v:10d}" for v in row))

def display_tensor(tensor, name):
    D = len(tensor)
    if D == 1:
        display_matrix(tensor[0], f"{name}[0]")
        return
    for d in range(D):
        display_matrix(tensor[d], f"{name}[{d}]")

# ── User input helpers ────────────────────────────────────────────────────────

def get_int(prompt, lo=None, hi=None):
    while True:
        try:
            v = int(input(prompt))
            if lo is not None and v < lo:
                print(f"    Must be >= {lo}"); continue
            if hi is not None and v > hi:
                print(f"    Must be <= {hi}"); continue
            return v
        except ValueError:
            print("    Enter an integer")

def get_matrix_from_user(name, rows, cols):
    print(f"\n  Enter {name} ({rows}x{cols}), one row per line, space-separated integers:")
    matrix = []
    for i in range(rows):
        while True:
            try:
                raw = input(f"    row {i}: ").split()
                if len(raw) != cols:
                    print(f"    Need exactly {cols} values"); continue
                row = [int(x) for x in raw]
                for x in row:
                    if x < -32768 or x > 32767:
                        raise ValueError(f"{x} out of 16-bit signed range")
                matrix.append(row)
                break
            except ValueError as e:
                print(f"    {e}, try again")
    return matrix

def get_tensor_from_user(name, D, rows, cols):
    tensor = []
    for d in range(D):
        print(f"\n  Depth slice {d} of {D-1}:")
        tensor.append(get_matrix_from_user(f"{name}[{d}]", rows, cols))
    return tensor

def get_dimensions(op_name, D):
    """
    Return (M, K, N, A_rows, A_cols, B_rows, B_cols, C_read_rows, C_read_cols).

    C_read_rows / C_read_cols are the LOGICAL result dimensions — what Python
    will actually read back:
      matmul    : M × N
      add/sub/
      hadamard  : M × N  (same shape as A)
      row_accum : M × 1  (one sum per row — hardware replicates across cols,
                           we only read col 0)
      col_accum : 1 × N  (one sum per col — hardware replicates across rows,
                           we only read row 0)
    """
    print()
    A_rows = get_int("  Rows of A (M): ", lo=1, hi=MAX_DIM)
    A_cols = get_int("  Cols of A: ",     lo=1, hi=MAX_DIM)

    if op_name == 'matmul':
        B_rows = A_cols
        print(f"  Rows of B fixed to {B_rows} (must equal cols of A)")
        B_cols      = get_int("  Cols of B (N): ", lo=1, hi=MAX_DIM)
        M, K, N     = A_rows, A_cols, B_cols
        B_r, B_c    = B_rows, B_cols
        C_r, C_c    = M, N

    elif op_name in ('add', 'sub', 'hadamard'):
        B_rows, B_cols = A_rows, A_cols
        print(f"  B shape fixed to {B_rows}x{B_cols} (must match A)")
        M, K, N     = A_rows, A_cols, A_cols
        B_r, B_c    = B_rows, B_cols
        C_r, C_c    = M, N

    elif op_name == 'row_accum':
        # A is M×K; result is M×1 (sum across K columns per row)
        # Hardware needs K as K_len, N=K (tile iteration uses N_len for col bound)
        M, K, N     = A_rows, A_cols, A_cols
        B_r, B_c    = None, None
        C_r, C_c    = M, 1            # logical: one sum per row

    elif op_name == 'col_accum':
        # A is K×N; result is 1×N (sum down K rows per column)
        # Hardware iterates rows 0..M_len-1 as the K dimension
        M, K, N     = A_rows, A_cols, A_cols
        B_r, B_c    = None, None
        C_r, C_c    = 1, N            # logical: one sum per col

    else:
        M, K, N     = A_rows, A_cols, A_cols
        B_r, B_c    = None, None
        C_r, C_c    = M, N

    return M, K, N, A_rows, A_cols, B_r, B_c, C_r, C_c

# ── Main interactive loop ─────────────────────────────────────────────────────

def main():
    print("=" * 54)
    print("   Tensor Accelerator — UART Control  (3D enabled)")
    print("=" * 54)
    print(f"  Port      : {PORT}")
    print(f"  Baud      : {BAUD}")
    print(f"  MaxDim    : {MAX_DIM}x{MAX_DIM}")
    print(f"  MaxDepth  : {MAX_DEPTH}")
    print()

    while True:
        print("-" * 54)
        print("  Operations:")
        for name, code in OPS.items():
            print(f"    {name:<12}  (op={code:03b})")
        print("    quit")
        print("-" * 54)

        op_name = input("Select operation: ").strip().lower()

        if op_name == 'quit':
            break
        if op_name not in OPS:
            print(f"  Unknown op '{op_name}', try again")
            continue

        # Depth
        try:
            D = get_int("  Depth (number of matrix slices, 1 = 2D): ",
                        lo=1, hi=MAX_DEPTH)
        except KeyboardInterrupt:
            print("\n  Cancelled"); continue

        try:
            M, K, N, A_rows, A_cols, B_rows, B_cols, C_rows, C_cols = \
                get_dimensions(op_name, D)
        except KeyboardInterrupt:
            print("\n  Cancelled"); continue

        # Validate hardware parameters now, before any UART traffic
        try:
            _validate_run_params(M, K, N, D)
        except ValueError as e:
            print(f"\n  Parameter error: {e}")
            continue

        # Input data
        try:
            if D == 1:
                A_mat    = get_matrix_from_user("A", A_rows, A_cols)
                A_tensor = [A_mat]
                B_tensor = None
                if B_rows is not None:
                    B_mat    = get_matrix_from_user("B", B_rows, B_cols)
                    B_tensor = [B_mat]
            else:
                A_tensor = get_tensor_from_user("A", D, A_rows, A_cols)
                B_tensor = None
                if B_rows is not None:
                    B_tensor = get_tensor_from_user("B", D, B_rows, B_cols)
        except KeyboardInterrupt:
            print("\n  Cancelled"); continue

        # Load → run → read
        try:
            shape_str = f"[{D}x{A_rows}x{A_cols}]"
            print(f"\n  Loading A {shape_str}...", end=' ', flush=True)
            load_tensor_A(A_tensor, D, A_rows, A_cols)
            print("done")

            if B_tensor is not None:
                shape_b = f"[{D}x{B_rows}x{B_cols}]"
                print(f"  Loading B {shape_b}...", end=' ', flush=True)
                load_tensor_B(B_tensor, D, B_rows, B_cols)
                print("done")

            print("  Running...", end=' ', flush=True)
            uart_run(op_name, OPS[op_name], M, K, N, D)
            print("done")

            print("  Reading C...", end=' ', flush=True)

            # Use the correct reader for accumulation ops to avoid
            # reading redundant replicated values from hardware
            if op_name == 'row_accum':
                C_tensor = read_tensor_C_row_accum(D, M)
            elif op_name == 'col_accum':
                C_tensor = read_tensor_C_col_accum(D, N)
            else:
                C_tensor = read_tensor_C(D, C_rows, C_cols)

            print("done")

        except (RuntimeError, ValueError) as e:
            print(f"\n  ERROR: {e}")
            print("  Buffers marked dirty — reload before next run.")
            continue

        # Display
        display_tensor(A_tensor, "A")
        if B_tensor is not None:
            display_tensor(B_tensor, "B")

        # Label result with correct logical shape annotation
        if op_name == 'row_accum':
            display_tensor(C_tensor, f"C  row_accum result ({D}x{M}x1)")
        elif op_name == 'col_accum':
            display_tensor(C_tensor, f"C  col_accum result ({D}x1x{N})")
        else:
            display_tensor(C_tensor, "C  (result)")
        print()

    ser.close()
    print("Closed port. Bye.")

if __name__ == '__main__':
    main()