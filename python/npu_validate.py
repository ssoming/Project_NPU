"""
NPU 정수 모델 검증 스크립트
- X.npy / y.npy에서 테스트 세트 추출 (task04와 동일 split)
- 각 테스트 샘플을 NPU 정수 연산으로 추론
- 클래스별 정확도 리포트
"""

import os, sys
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from scipy.signal import convolve2d

SIM = "/home/ming/workspace_ondevice_2/Project_NPU/project_1/project_1.sim/sim_1/behav/xsim"

# ────────────────────────────────────────────────────────────────
# 가중치 파일 로더
# ────────────────────────────────────────────────────────────────
def load_hex8(path):
    v = []
    with open(path) as f:
        for line in f:
            for h in line.strip().split():
                x = int(h, 16)
                v.append(x - 256 if x >= 128 else x)
    return np.array(v, dtype=np.int32)

def load_hex16(path):
    v = []
    with open(path) as f:
        for line in f:
            for h in line.strip().split():
                x = int(h, 16)
                v.append(x - 65536 if x >= 32768 else x)
    return np.array(v, dtype=np.int32)

def relu_clamp(arr):
    return np.clip(arr, 0, 255).astype(np.uint8)

def shr7(arr):
    return arr >> 7

# ────────────────────────────────────────────────────────────────
# 가중치 로드 (한 번만)
# ────────────────────────────────────────────────────────────────
print("가중치 로드 중...", flush=True)

# Conv0: 1→8ch, 3×3
w0 = np.zeros((8, 9), dtype=np.int32)
for oc in range(8):
    w0[oc] = load_hex8(os.path.join(SIM, f"conv0_weight_{oc}.txt"))
b0 = load_hex16(os.path.join(SIM, "conv0_bias.txt"))   # (8,) int16

# Conv1: 8→16ch, 3×3
w1_flat = np.zeros(72 * 16, dtype=np.int32)
for n in range(72):
    vals = load_hex8(os.path.join(SIM, f"conv1_weight_{n}.txt"))
    w1_flat[n*16:(n+1)*16] = vals
b1 = load_hex16(os.path.join(SIM, "conv1_bias.txt"))   # (16,)

# Conv2: 16→32ch, 3×3
w2_flat = np.zeros(144 * 32, dtype=np.int32)
for n in range(144):
    vals = load_hex8(os.path.join(SIM, f"conv2_weight_{n}.txt"))
    w2_flat[n*32:(n+1)*32] = vals
b2 = load_hex16(os.path.join(SIM, "conv2_bias.txt"))   # (32,)

# Dense0: 1152→64
wd0 = load_hex8(os.path.join(SIM, "dense0_weight.txt")).reshape(1152, 64)
bd0 = load_hex8(os.path.join(SIM, "dense0_bias.txt"))  # (64,)

# Dense1: 64→9
wd1 = load_hex8(os.path.join(SIM, "dense1_weight.txt")).reshape(64, 9)
bd1 = load_hex8(os.path.join(SIM, "dense1_bias.txt"))  # (9,)

print("  완료")

# ────────────────────────────────────────────────────────────────
# NPU 정수 추론 함수 (1개 샘플, 배열 연산으로 가속)
# ────────────────────────────────────────────────────────────────
def maxpool2x2(feat):
    """(C, H, W) → (C, H/2, W/2)"""
    C, H, W = feat.shape
    return np.maximum(
        np.maximum(feat[:, 0::2, 0::2], feat[:, 0::2, 1::2]),
        np.maximum(feat[:, 1::2, 0::2], feat[:, 1::2, 1::2])
    )

def conv_layer(inp, w_flat, bias, IN_CH, N_OCH, IN_H, IN_W):
    """
    inp: (IN_CH, IN_H, IN_W) uint8
    w_flat[N*N_OCH + oc]: N = ic*9+k
    returns: (N_OCH, IN_H, IN_W) uint8 after ReLU + >>7
    """
    out = np.zeros((N_OCH, IN_H, IN_W), dtype=np.int64)
    kernel = np.array([[0,1,2],[3,4,5],[6,7,8]])
    for ic in range(IN_CH):
        for k in range(9):
            N = ic * 9 + k
            w_k = w_flat[N*N_OCH:(N+1)*N_OCH].astype(np.int64)  # (N_OCH,)
            kr, kc = k // 3, k % 3
            # 패딩=same: 입력 패딩
            inp_pad = np.pad(inp[ic], ((1,1),(1,1)), mode='constant').astype(np.int64)
            patch = inp_pad[kr:kr+IN_H, kc:kc+IN_W]  # (IN_H, IN_W)
            # out[oc] += patch * w_k[oc]
            out += patch[np.newaxis, :, :] * w_k[:, np.newaxis, np.newaxis]
    # bias 추가 + >>7 + relu
    out += bias[:, np.newaxis, np.newaxis].astype(np.int64)
    return relu_clamp(shr7(out))

def conv0_layer(img):
    """img: (48,48) uint8 → (8,48,48) uint8"""
    out = np.zeros((8, 48, 48), dtype=np.int64)
    inp_pad = np.pad(img, ((1,1),(1,1)), mode='constant').astype(np.int64)
    for oc in range(8):
        acc = int(b0[oc])
        for k in range(9):
            kr, kc = k // 3, k % 3
            patch = inp_pad[kr:kr+48, kc:kc+48]
            out[oc] += patch * int(w0[oc, k])
        out[oc] += int(b0[oc])
    # 이미 bias 한번 더 더했으므로 수정
    for oc in range(8):
        out[oc] -= int(b0[oc])  # bias가 두 번 들어갔으므로 한 번 빼기
    return relu_clamp(shr7(out))

def npu_infer(img_uint8):
    """
    img_uint8: (48,48) uint8
    returns: int, predicted class (0-8)
    """
    # Conv0
    c0 = np.zeros((8, 48, 48), dtype=np.int64)
    inp_pad = np.pad(img_uint8.astype(np.int64), ((1,1),(1,1)), mode='constant')
    for oc in range(8):
        c0[oc] = b0[oc]
        for k in range(9):
            kr, kc = k // 3, k % 3
            c0[oc] += inp_pad[kr:kr+48, kc:kc+48] * int(w0[oc, k])
    c0 = relu_clamp(shr7(c0))

    # MaxPool0
    p0 = maxpool2x2(c0)  # (8,24,24)

    # Conv1
    c1 = conv_layer(p0, w1_flat, b1, 8, 16, 24, 24)  # (16,24,24)

    # MaxPool1
    p1 = maxpool2x2(c1)  # (16,12,12)

    # Conv2
    c2 = conv_layer(p1, w2_flat, b2, 16, 32, 12, 12)  # (32,12,12)

    # MaxPool2
    p2 = maxpool2x2(c2)  # (32,6,6)

    # Dense0: 1152→64
    flat = p2.flatten().astype(np.int32)   # (1152,)
    d0_acc = bd0.astype(np.int32) + (flat @ wd0)   # (64,)
    d0 = relu_clamp(shr7(d0_acc))

    # Dense1: 64→9
    d1_acc = bd1.astype(np.int32) + (d0.astype(np.int32) @ wd1)  # (9,)
    logits = np.clip(shr7(d1_acc), -128, 127)

    return int(np.argmax(logits))

# ────────────────────────────────────────────────────────────────
# 데이터 로드 및 split
# ────────────────────────────────────────────────────────────────
print("\n데이터 로드 중...", flush=True)
X = np.load('./data/X.npy')
y = np.load('./data/y.npy')

le = LabelEncoder()
y_enc = le.fit_transform(y)
CLASS_NAMES = list(le.classes_)
print(f"  클래스: {CLASS_NAMES}")

X_train, X_test, y_train, y_test = train_test_split(
    X, y_enc, test_size=0.1, random_state=42, stratify=y_enc
)
print(f"  테스트 세트: {len(X_test)}개")

# ────────────────────────────────────────────────────────────────
# test_image.txt가 어느 샘플인지 확인
# ────────────────────────────────────────────────────────────────
print("\ntest_image.txt 샘플 탐색 중...", flush=True)
sim_img = []
with open(os.path.join(SIM, "test_image.txt")) as f:
    for line in f:
        h = line.strip()
        if h: sim_img.append(int(h, 16))
sim_img = np.array(sim_img, dtype=np.uint8)

found_idx = None
for scale_num, scale_den in [(255, 1), (128, 1), (127, 1)]:
    for i in range(len(X_test)):
        cand = (X_test[i] * scale_num / scale_den).clip(0, 255).astype(np.uint8).flatten()
        if np.array_equal(cand, sim_img):
            print(f"  매치! X_test[{i}] (scale={scale_num}/{scale_den}), 레이블={y_test[i]} ({CLASS_NAMES[y_test[i]]})")
            found_idx = i
            break
    if found_idx is not None:
        break

if found_idx is None:
    print("  정확한 매치 없음")
    # test_image.txt를 직접 추론
    print(f"  test_image.txt 추론: {npu_infer(sim_img.reshape(48,48))} (기대=2 Edge-Loc)")

# ────────────────────────────────────────────────────────────────
# 클래스별 N개씩 추론 (N_PER_CLASS개)
# ────────────────────────────────────────────────────────────────
N_PER_CLASS = 30  # 클래스당 샘플 수 (시간 절약)

print(f"\n클래스별 {N_PER_CLASS}개 샘플 추론 중...", flush=True)

total_correct = 0
total_count = 0
results = {}

for cls in range(9):
    cls_indices = np.where(y_test == cls)[0][:N_PER_CLASS]
    correct = 0
    preds = []
    for idx in cls_indices:
        img_u8 = (X_test[idx] * 255).astype(np.uint8)
        pred = npu_infer(img_u8)
        preds.append(pred)
        if pred == cls:
            correct += 1
    n = len(cls_indices)
    acc = correct / n * 100 if n > 0 else 0
    total_correct += correct
    total_count += n
    results[cls] = (correct, n, acc, preds)
    print(f"  cls {cls} ({CLASS_NAMES[cls]:10s}): {correct}/{n} = {acc:.1f}%  | preds={preds[:10]}")

print(f"\n전체 정확도: {total_correct}/{total_count} = {total_correct/total_count*100:.1f}%")

# ────────────────────────────────────────────────────────────────
# 클래스 2 (Edge-Loc) 상세 분석
# ────────────────────────────────────────────────────────────────
print(f"\n[클래스 2 Edge-Loc 상세]")
cls2_idx = np.where(y_test == 2)[0][:5]
for idx in cls2_idx:
    img_u8 = (X_test[idx] * 255).astype(np.uint8)
    pred = npu_infer(img_u8)
    print(f"  X_test[{idx}] → 예측={pred}({CLASS_NAMES[pred]}), 실제=2(Edge-Loc), {'PASS' if pred==2 else 'FAIL'}")
