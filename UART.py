import serial

# ── Config ────────────────────────────────────────────────────────────────────
PORT      = 'COM3'
BAUD      = 115_200
MAX_DIM   = 16
MAX_DEPTH = 4
ACC_BITS  = 36
TX_BYTES  = (ACC_BITS + 7) // 8   # 5 bytes per READ_C response

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
def _mark_b_dirty(): global _b_ready; _b_ready = False
def _mark_a_ready(): global _a_ready; _a_ready = True
def _mark_b_ready(): global _b_ready; _b_ready = True

# ── Flat address ──────────────────────────────────────────────────────────────
def flat_addr(depth_idx, row, col):
    """
    Compute the flat BRAM address for element [depth_idx][row][col].
    For 2D use (D=1), pass depth_idx=0 — equivalent to the original row*MAX_DIM+col.
    """
    return depth_idx * MAX_DIM * MAX_DIM + row * MAX_DIM + col

# ── Low-level UART protocol ───────────────────────────────────────────────────
# Address is now always 2 bytes (addr_hi, addr_lo) to support ADDR_W > 8 bits.

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
    """
    Load a 3D tensor into bram_A.
    tensor[d][row][col], shape [D][A_rows][A_cols].
    For a 2D matrix pass D=1 and tensor as a 3D list with one depth slice,
    or use the convenience wrapper load_matrix_A below.
    """
    _mark_a_dirty()
    for d in range(D):
        for i in range(A_rows):
            for j in range(A_cols):
                write_A(d, i, j, int(tensor[d][i][j]))
    _mark_a_ready()

def load_tensor_B(tensor, D, B_rows, B_cols):
    """Load a 3D tensor into bram_B."""
    _mark_b_dirty()
    for d in range(D):
        for i in range(B_rows):
            for j in range(B_cols):
                write_B(d, i, j, int(tensor[d][i][j]))
    _mark_b_ready()

def load_matrix_A(matrix, A_rows, A_cols):
    """Convenience wrapper: load a single 2D matrix as depth slice 0."""
    load_tensor_A([[matrix[i] for i in range(A_rows)]], 1, A_rows, A_cols)

def load_matrix_B(matrix, B_rows, B_cols):
    """Convenience wrapper: load a single 2D matrix as depth slice 0."""
    load_tensor_B([[matrix[i] for i in range(B_rows)]], 1, B_rows, B_cols)

def read_tensor_C(D, M, N):
    """Read the full result tensor back from bram_C.  Returns list[D][M][N]."""
    result = []
    for d in range(D):
        slice_ = []
        for i in range(M):
            row = [read_C(d, i, j) for j in range(N)]
            slice_.append(row)
        result.append(slice_)
    return result

def read_matrix_C(M, N):
    """Convenience wrapper: read depth slice 0 only."""
    return read_tensor_C(1, M, N)[0]

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
    """Get a D-slice tensor from the user, one matrix per depth slice."""
    tensor = []
    for d in range(D):
        print(f"\n  Depth slice {d} of {D-1}:")
        tensor.append(get_matrix_from_user(f"{name}[{d}]", rows, cols))
    return tensor

def get_dimensions(op_name, D):
    print()
    A_rows = get_int("  Rows of A: ", lo=1, hi=MAX_DIM)
    A_cols = get_int("  Cols of A: ", lo=1, hi=MAX_DIM)

    if op_name == 'matmul':
        B_rows = A_cols
        print(f"  Rows of B fixed to {B_rows} (must equal cols of A)")
        B_cols = get_int("  Cols of B: ", lo=1, hi=MAX_DIM)
        M, K, N = A_rows, A_cols, B_cols

    elif op_name in ('add', 'sub', 'hadamard'):
        B_rows, B_cols = A_rows, A_cols
        print(f"  B shape fixed to {B_rows}x{B_cols} (must match A)")
        M, K, N = A_rows, A_cols, A_cols

    elif op_name == 'row_accum':
        B_rows, B_cols = None, None
        M, K, N = A_rows, A_cols, A_cols

    elif op_name == 'col_accum':
        B_rows, B_cols = None, None
        M, K, N = A_rows, A_cols, A_cols

    else:
        B_rows, B_cols = None, None
        M, K, N = A_rows, A_cols, A_cols

    return M, K, N, A_rows, A_cols, B_rows, B_cols

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
            M, K, N, A_rows, A_cols, B_rows, B_cols = get_dimensions(op_name, D)
        except KeyboardInterrupt:
            print("\n  Cancelled"); continue

        # Input data
        try:
            if D == 1:
                A_mat = get_matrix_from_user("A", A_rows, A_cols)
                A_tensor = [A_mat]
                B_tensor = None
                if B_rows is not None:
                    B_mat = get_matrix_from_user("B", B_rows, B_cols)
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
            C_tensor = read_tensor_C(D, M, N)
            print("done")

        except RuntimeError as e:
            print(f"\n  ERROR: {e}")
            print("  Buffers marked dirty — reload before next run.")
            continue

        # Display
        display_tensor(A_tensor, "A")
        if B_tensor is not None:
            display_tensor(B_tensor, "B")
        display_tensor(C_tensor, "C  (result)")
        print()

    ser.close()
    print("Closed port. Bye.")

if __name__ == '__main__':
    main()