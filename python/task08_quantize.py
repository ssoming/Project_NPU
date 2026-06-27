"""
task08_quantize.py
==================
BN 없는 새 모델 → NPU용 가중치 txt 파일 생성 (task06 + task07 통합)

수정 사항 (기존 대비):
  - BatchNormalization 없음 → fold_bias 불필요
  - & 0xFF 대신 np.clip(-128,127) 사용 → 부호 반전 버그 수정
  - 출력 파일: ./npu_weights/ (Vivado sim 디렉토리에 복사)

양자화 포맷:
  Conv weight : int8, ×128  (float × 128, clip to [-128,127])
  Conv bias   : int16, ×256 (float × 256, clip to [-32768,32767])
  Dense weight: int8, ×128  (float × 128, clip to [-128,127])
  Dense bias  : int8, ×128  (float × 128, clip to [-128,127])

사용법:
  python3 task08_quantize.py <model.h5>
  python3 task08_quantize.py models/wafer_cnn_0.XXX.h5
"""

import sys, os
import h5py
import numpy as np

# ── 모델 경로 ───────────────────────────────────────────────────
if len(sys.argv) < 2:
    # 가장 최신 h5 파일 자동 선택
    models = sorted([f for f in os.listdir('./models') if f.endswith('.h5')])
    if not models:
        print("사용법: python3 task08_quantize.py models/wafer_cnn_0.XXX.h5")
        sys.exit(1)
    MODEL_PATH = f'./models/{models[-1]}'
    print(f"모델 자동 선택: {MODEL_PATH}")
else:
    MODEL_PATH = sys.argv[1]

OUT_DIR = './npu_weights'
os.makedirs(OUT_DIR, exist_ok=True)

# ── 유틸리티 ────────────────────────────────────────────────────
def to_int8(arr):
    """float → int8 (×128, clip)"""
    return np.clip(np.round(arr * 128), -128, 127).astype(np.int8)

def to_int16(arr):
    """float → int16 (×256, clip)"""
    return np.clip(np.round(arr * 256), -32768, 32767).astype(np.int16)

def hex8(v):
    """int8 → 2자리 hex (& 0xFF 방식이 아닌 view 방식)"""
    return f'{np.int8(v).view(np.uint8):02x}'

def hex16(v):
    """int16 → 4자리 hex"""
    return f'{np.int16(v).view(np.uint16):04x}'

def write_lines(path, lines):
    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n')

# ── 모델 로드 ───────────────────────────────────────────────────
print(f"\n[모델 로드] {MODEL_PATH}")
with h5py.File(MODEL_PATH, 'r') as f:
    mw = f['model_weights']

    # Conv0: kernel (3,3,1,8), bias (8,)
    c0k = mw['conv2d']['sequential']['conv2d']['kernel'][:]   # (3,3,1,8)
    c0b = mw['conv2d']['sequential']['conv2d']['bias'][:]     # (8,)

    # Conv1: kernel (3,3,8,16), bias (16,)
    c1k = mw['conv2d_1']['sequential']['conv2d_1']['kernel'][:]  # (3,3,8,16)
    c1b = mw['conv2d_1']['sequential']['conv2d_1']['bias'][:]    # (16,)

    # Conv2: kernel (3,3,16,32), bias (32,)
    c2k = mw['conv2d_2']['sequential']['conv2d_2']['kernel'][:]  # (3,3,16,32)
    c2b = mw['conv2d_2']['sequential']['conv2d_2']['bias'][:]    # (32,)

    # Dense0: kernel (1152,64), bias (64,)
    d0w = mw['dense']['sequential']['dense']['kernel'][:]     # (1152,64)
    d0b = mw['dense']['sequential']['dense']['bias'][:]       # (64,)

    # Dense1: kernel (64,9), bias (9,)
    d1w = mw['dense_1']['sequential']['dense_1']['kernel'][:] # (64,9)
    d1b = mw['dense_1']['sequential']['dense_1']['bias'][:]   # (9,)

print(f"  Conv0 kernel: {c0k.shape}  bias: {c0b.shape}")
print(f"  Conv1 kernel: {c1k.shape}  bias: {c1b.shape}")
print(f"  Conv2 kernel: {c2k.shape}  bias: {c2b.shape}")
print(f"  Dense0: {d0w.shape}, Dense1: {d1w.shape}")

# ════════════════════════════════════════════════════════════════
# 1. Conv0  (1→8ch, 3×3)
#    conv0_weight_N.txt (N=0~7): 9줄, 1값씩  → $readmemh(start=N*9, end=N*9+8)
#    conv0_bias.txt: 8값, int16 hex (4자리)
# ════════════════════════════════════════════════════════════════
print("\n[1/3] Conv0 처리 중...")
w0_q = to_int8(c0k)  # (3,3,1,8) int8

for oc in range(8):
    kernel_vals = w0_q[:, :, 0, oc].flatten()  # (9,) 행→행 순서
    lines = [hex8(v) for v in kernel_vals]
    write_lines(f'{OUT_DIR}/conv0_weight_{oc}.txt', lines)

b0_q = to_int16(c0b)  # (8,) int16
write_lines(f'{OUT_DIR}/conv0_bias.txt', [hex16(v) for v in b0_q])
print(f"  weight range: [{c0k.min():.4f}, {c0k.max():.4f}]  ×128→int8 ok")
print(f"  bias (×256): {b0_q.tolist()}")

# ════════════════════════════════════════════════════════════════
# 2. Conv1  (8→16ch, 3×3)
#    conv1_weight_N.txt (N=0~71): 16값 (out_ch 0~15)
#    N = in_ch*9 + kernel_pos
# ════════════════════════════════════════════════════════════════
print("\n[2/3] Conv1 처리 중...")
# c1k shape: (3,3,8,16) = (kH, kW, in_ch, out_ch)
# N = ic*9+k where k=kH*3+kW
for ic in range(8):
    for k in range(9):
        kH, kW = k // 3, k % 3
        N = ic * 9 + k
        kernel_vals = c1k[kH, kW, ic, :]  # (16,) - 16 out channels
        q_vals = to_int8(kernel_vals)
        lines = [hex8(v) for v in q_vals]
        write_lines(f'{OUT_DIR}/conv1_weight_{N}.txt', lines)

b1_q = to_int16(c1b)
write_lines(f'{OUT_DIR}/conv1_bias.txt', [hex16(v) for v in b1_q])

overflow = (np.abs(c1k * 128) > 127).sum()
print(f"  weight range: [{c1k.min():.4f}, {c1k.max():.4f}]  overflow(×128>127): {overflow}/{c1k.size}")

# ════════════════════════════════════════════════════════════════
# 3. Conv2  (16→32ch, 3×3)
#    conv2_weight_N.txt (N=0~143): 32값 (out_ch 0~31)
#    N = in_ch*9 + kernel_pos
# ════════════════════════════════════════════════════════════════
print("\n[3/3] Conv2 처리 중...")
for ic in range(16):
    for k in range(9):
        kH, kW = k // 3, k % 3
        N = ic * 9 + k
        kernel_vals = c2k[kH, kW, ic, :]  # (32,)
        q_vals = to_int8(kernel_vals)
        lines = [hex8(v) for v in q_vals]
        write_lines(f'{OUT_DIR}/conv2_weight_{N}.txt', lines)

b2_q = to_int16(c2b)
write_lines(f'{OUT_DIR}/conv2_bias.txt', [hex16(v) for v in b2_q])

overflow = (np.abs(c2k * 128) > 127).sum()
print(f"  weight range: [{c2k.min():.4f}, {c2k.max():.4f}]  overflow(×128>127): {overflow}/{c2k.size}")

# ════════════════════════════════════════════════════════════════
# 4. Dense0  (1152→64, ReLU)
#    dense0_weight.txt: 1152행 × 64열
#    dense0_bias.txt: 64값, int8 hex
# ════════════════════════════════════════════════════════════════
print("\n[Dense0] 처리 중...")
d0w_q = to_int8(d0w)  # (1152,64)
rows = []
for r in range(1152):
    row = ' '.join(hex8(v) for v in d0w_q[r])
    rows.append(row)
write_lines(f'{OUT_DIR}/dense0_weight.txt', rows)

d0b_q = to_int8(d0b)
write_lines(f'{OUT_DIR}/dense0_bias.txt', [hex8(v) for v in d0b_q])

overflow = (np.abs(d0w * 128) > 127).sum()
print(f"  weight range: [{d0w.min():.4f}, {d0w.max():.4f}]  overflow: {overflow}/{d0w.size}")

# ════════════════════════════════════════════════════════════════
# 5. Dense1  (64→9, no ReLU)
#    dense1_weight.txt: 64행 × 9열
#    dense1_bias.txt: 9값, int8 hex
# ════════════════════════════════════════════════════════════════
print("\n[Dense1] 처리 중...")
d1w_q = to_int8(d1w)  # (64,9)
rows = []
for r in range(64):
    row = ' '.join(hex8(v) for v in d1w_q[r])
    rows.append(row)
write_lines(f'{OUT_DIR}/dense1_weight.txt', rows)

d1b_q = to_int8(d1b)
write_lines(f'{OUT_DIR}/dense1_bias.txt', [hex8(v) for v in d1b_q])

overflow = (np.abs(d1w * 128) > 127).sum()
print(f"  weight range: [{d1w.min():.4f}, {d1w.max():.4f}]  overflow: {overflow}/{d1w.size}")

# ════════════════════════════════════════════════════════════════
# 완료
# ════════════════════════════════════════════════════════════════
files = sorted(os.listdir(OUT_DIR))
print(f"\n{'='*50}")
print(f"완료! {OUT_DIR}/ 에 {len(files)}개 파일 생성")
print(f"\n다음 단계:")
print(f"  cp {OUT_DIR}/*.txt <Vivado_sim_dir>/")
print(f"  → Vivado에서 시뮬레이션 재실행")
