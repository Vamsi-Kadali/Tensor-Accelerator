import serial
import time

# ── Config ────────────────────────────────────────────────────────────────────
PORT      = 'COM6'
BAUD      = 921_600
MAX_DIM   = 64
MAX_DEPTH = 8
ACC_BITS  = 38
TX_BYTES  = (ACC_BITS + 7) // 8

_HW_DIM_MAX = MAX_DIM
_HW_DEP_MAX = MAX_DEPTH

OPS = {
    'matmul'    : 0b000,
    'add'       : 0b001,
    'sub'       : 0b010,
    'hadamard'  : 0b011,
    'row_accum' : 0b100,
    'col_accum' : 0b101,
}

OPS_NEED_B = {'matmul', 'add', 'sub', 'hadamard'}

# ── Serial ────────────────────────────────────────────────────────────────────
ser = serial.Serial(PORT, baudrate=BAUD, timeout=5)
print(f"Opened {PORT} at {BAUD} baud")

_a_ready = False
_b_ready = False

def _mark_a_ready(): global _a_ready; _a_ready = True
def _mark_b_ready(): global _b_ready; _b_ready = True
def _mark_a_dirty(): global _a_ready; _a_ready = False
def _mark_b_dirty(): global _b_ready; _b_ready = False

# ── Validation ────────────────────────────────────────────────────────────────
def _validate_run_params(M, K, N, D):
    if not (1 <= M <= _HW_DIM_MAX): raise ValueError("M out of range")
    if not (1 <= K <= _HW_DIM_MAX): raise ValueError("K out of range")
    if not (1 <= N <= _HW_DIM_MAX): raise ValueError("N out of range")
    if not (1 <= D <= _HW_DEP_MAX): raise ValueError("D out of range")

# ── Addressing ────────────────────────────────────────────────────────────────
def flat_addr(d, r, c):
    return d * MAX_DIM * MAX_DIM + r * MAX_DIM + c

# ── UART Ops ──────────────────────────────────────────────────────────────────
def write_A(d, r, c, val):
    addr = flat_addr(d, r, c)
    v = val & 0xFFFF
    ser.write(bytes([0x01, addr>>8, addr&0xFF, v>>8, v&0xFF]))
    if ser.read(1) != b'\xAA':
        raise RuntimeError("WRITE_A failed")

def write_B(d, r, c, val):
    addr = flat_addr(d, r, c)
    v = val & 0xFFFF
    ser.write(bytes([0x02, addr>>8, addr&0xFF, v>>8, v&0xFF]))
    if ser.read(1) != b'\xAA':
        raise RuntimeError("WRITE_B failed")

def uart_run(op, M, K, N, D):
    _validate_run_params(M, K, N, D)
    ser.write(bytes([0x03, OPS[op], M, K, N, D]))
    if ser.read(1) != b'\xAA':
        raise RuntimeError("RUN failed")

def read_C(d, r, c):
    addr = flat_addr(d, r, c)
    ser.write(bytes([0x04, addr>>8, addr&0xFF]))
    raw = ser.read(TX_BYTES)
    val = int.from_bytes(raw, 'big')
    if val >= (1 << (ACC_BITS - 1)):
        val -= (1 << ACC_BITS)
    return val

# ── Load ──────────────────────────────────────────────────────────────────────
def load_tensor_A(T, D, R, C):
    _mark_a_dirty()
    total = D*R*C
    count = 0

    start = time.time()

    for d in range(D):
        for i in range(R):
            for j in range(C):
                write_A(d,i,j,T[d][i][j])
                count += 1

                if count % 1000 == 0:
                    elapsed = time.time() - start
                    print(f"  A load: {count}/{total} ({elapsed:.1f}s)")

    _mark_a_ready()

def load_tensor_B(T, D, R, C):
    _mark_b_dirty()
    total = D*R*C
    count = 0

    start = time.time()

    for d in range(D):
        for i in range(R):
            for j in range(C):
                write_B(d,i,j,T[d][i][j])
                count += 1

                if count % 1000 == 0:
                    elapsed = time.time() - start
                    print(f"  B load: {count}/{total} ({elapsed:.1f}s)")

    _mark_b_ready()

def read_tensor_C(D, M, N):
    return [[[read_C(d,i,j) for j in range(N)] for i in range(M)] for d in range(D)]

# ── Generators ────────────────────────────────────────────────────────────────
def gen_matrix(r,c,mode):
    if mode=="zeros": return [[0]*c for _ in range(r)]
    if mode=="max": return [[32767]*c for _ in range(r)]
    if mode=="min": return [[-32768]*c for _ in range(r)]
    if mode=="alt": return [[32767 if (i+j)%2==0 else -32768 for j in range(c)] for i in range(r)]

# ── EXTREME TEST ──────────────────────────────────────────────────────────────
def run_extreme():
    print("\n🔥 EXTREME TEST (64x64) 🔥")

    modes = ["zeros","max","min","alt"]

    for mode in modes:
        print(f"\n=== MODE: {mode} ===")

        M=K=N=64
        D=4

        A = [gen_matrix(M,K,mode) for _ in range(D)]
        B = [gen_matrix(K,N,mode) for _ in range(D)]

        print("\nLoading A...")
        load_tensor_A(A,D,M,K)

        print("Loading B...")
        load_tensor_B(B,D,K,N)

        print("Running MATMUL...")
        start = time.time()
        uart_run("matmul",M,K,N,D)
        print(f"  Compute done in {time.time()-start:.2f}s")

        print("Reading output...")
        start = time.time()
        C = read_tensor_C(D,M,N)
        print(f"  Read done in {time.time()-start:.2f}s")

        print(f"Sample output [0][0][0] = {C[0][0][0]}")

    print("\n✅ DONE")

# ── MAIN ──────────────────────────────────────────────────────────────────────
def main():
    while True:
        cmd = input("\nEnter 'stress' or 'quit': ").strip()

        if cmd == "stress":
            run_extreme()

        elif cmd == "quit":
            break

    ser.close()

if __name__ == "__main__":
    main()