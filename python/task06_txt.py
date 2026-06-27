import h5py
import numpy as np
import os
import sys

# ── 모델 경로 ──────────────────────────────────────────
if len(sys.argv) >= 2:
    filename = sys.argv[1]
else:
    models = sorted([f for f in os.listdir('./models') if f.endswith('.h5')])
    filename = f'./models/{models[-1]}'
    print(f"모델 자동 선택: {filename}")

OUT = './npu_weights'
os.makedirs(OUT, exist_ok=True)

# ── 양자화 헬퍼 ──────────────────────────────────────────
def q_int8(arr):
    """float × 128, clip → int8, 2자리 hex용 uint8 반환"""
    return np.clip(np.round(arr * 128), -128, 127).astype(np.int8).view(np.uint8)

def q_int16(arr):
    """float × 256, clip → int16, 4자리 hex용 uint16 반환"""
    return np.clip(np.round(arr * 256), -32768, 32767).astype(np.int16).view(np.uint16)

with h5py.File(filename, 'r') as f:

    # ════════════════════════════════════════════════════
    # Conv0  (1→8ch, 3×3)
    # 변경: & 0xFF → q_int8 / bias ×128 int8 → ×256 int16(%04x) / 경로 npu_weights/conv0_*
    # ════════════════════════════════════════════════════
    w0 = f['model_weights']['conv2d']['sequential']['conv2d']['kernel'][:]  # (3,3,1,8)
    w0_q = q_int8(w0)       # (3,3,1,8) uint8
    filters0 = np.transpose(w0_q[:, :, 0, :], (2, 0, 1))  # (8,3,3)
    for i in range(8):
        np.savetxt(f'{OUT}/conv0_weight_{i}.txt', filters0[i], fmt='%02x', delimiter=' ')

    b0 = f['model_weights']['conv2d']['sequential']['conv2d']['bias'][:]    # (8,)
    b0_q = q_int16(b0)      # uint16
    np.savetxt(f'{OUT}/conv0_bias.txt', b0_q, fmt='%04x', delimiter=' ')

    # ════════════════════════════════════════════════════
    # Conv1  (8→16ch, 3×3)
    # 변경: 동일 (& 0xFF → q_int8 / bias int16 / 파일명 conv1_*)
    # ════════════════════════════════════════════════════
    w1 = f['model_weights']['conv2d_1']['sequential']['conv2d_1']['kernel'][:]  # (3,3,8,16)
    w1_q = q_int8(w1)
    filters1 = np.transpose(w1_q, (2, 0, 1, 3)).reshape(72, 16)  # (72,16)
    for i in range(72):
        np.savetxt(f'{OUT}/conv1_weight_{i}.txt', filters1[i], fmt='%02x', delimiter=' ')

    b1 = f['model_weights']['conv2d_1']['sequential']['conv2d_1']['bias'][:]
    b1_q = q_int16(b1)
    np.savetxt(f'{OUT}/conv1_bias.txt', b1_q, fmt='%04x', delimiter=' ')

    # ════════════════════════════════════════════════════
    # Conv2  (16→32ch, 3×3)
    # 변경: 동일 (파일명 conv2_*)
    # ════════════════════════════════════════════════════
    w2 = f['model_weights']['conv2d_2']['sequential']['conv2d_2']['kernel'][:]  # (3,3,16,32)
    w2_q = q_int8(w2)
    filters2 = np.transpose(w2_q, (2, 0, 1, 3)).reshape(144, 32)  # (144,32)
    for i in range(144):
        np.savetxt(f'{OUT}/conv2_weight_{i}.txt', filters2[i], fmt='%02x', delimiter=' ')

    b2 = f['model_weights']['conv2d_2']['sequential']['conv2d_2']['bias'][:]
    b2_q = q_int16(b2)
    np.savetxt(f'{OUT}/conv2_bias.txt', b2_q, fmt='%04x', delimiter=' ')

    # ════════════════════════════════════════════════════
    # Dense0  (1152→64, ReLU)
    # 변경: & 0xFF → q_int8 / 파일명 dense0_weight.txt, dense0_bias.txt
    # ════════════════════════════════════════════════════
    dw0 = f['model_weights']['dense']['sequential']['dense']['kernel'][:]   # (1152,64)
    dw0_q = q_int8(dw0)
    np.savetxt(f'{OUT}/dense0_weight.txt', dw0_q, fmt='%02x', delimiter=' ')

    db0 = f['model_weights']['dense']['sequential']['dense']['bias'][:]     # (64,)
    db0_q = q_int8(db0)
    np.savetxt(f'{OUT}/dense0_bias.txt', db0_q, fmt='%02x', delimiter=' ')

    # ════════════════════════════════════════════════════
    # Dense1  (64→9, softmax)
    # 변경: & 0xFF → q_int8 / 파일명 dense1_weight.txt, dense1_bias.txt
    # ════════════════════════════════════════════════════
    dw1 = f['model_weights']['dense_1']['sequential']['dense_1']['kernel'][:]  # (64,9)
    dw1_q = q_int8(dw1)
    np.savetxt(f'{OUT}/dense1_weight.txt', dw1_q, fmt='%02x', delimiter=' ')

    db1 = f['model_weights']['dense_1']['sequential']['dense_1']['bias'][:]    # (9,)
    db1_q = q_int8(db1)
    np.savetxt(f'{OUT}/dense1_bias.txt', db1_q, fmt='%02x', delimiter=' ')

print(f"\n완료: {OUT}/ 에 저장됨")
print(f"파일 수: {len(os.listdir(OUT))}개")
print(f"\n다음 단계:")
print(f"  cp {OUT}/*.txt <Vivado_sim_dir>/")
