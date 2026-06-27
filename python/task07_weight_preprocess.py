"""
preprocess_weights.py
=====================
Verilog NPU용 weight 전처리 스크립트

수행 작업:
  1. Conv bias + BN을 folding하여 통합 bias 생성
  2. Conv weight를 Verilog $readmemh 호환 형태로 재정리
  3. Dense weight/bias 그대로 복사
  4. 출력 파일을 ./npu_weights/ 에 저장

양자화 포맷:
  - Conv weight  : Q1.7  (8-bit signed, × 128)
  - Conv bias    : Q1.7  (8-bit signed, × 128)
  - BN scale     : Q8.8  (16-bit signed, × 256)
  - BN offset    : Q8.8  (16-bit signed, × 256)
  - Folded bias  : Q8.8  (16-bit signed)
  - Dense weight : Q1.7  (8-bit signed, × 128)
  - Dense bias   : Q1.7  (8-bit signed, × 128)

BN Folding 공식:
  folded_bias[oc] = round(bn_scale[oc] * conv_bias[oc] / 128) + bn_offset[oc]
  (conv weight는 그대로 사용, Verilog MAC 후 BN scale/offset 적용 불필요)

출력 파일 목록:
  npu_weights/
    conv0_weight_N.txt   (N=0~7)   : 3x3 kernel, out_ch=N, 한 줄에 값 1개 (9줄)
    conv0_bias.txt                 : 8값, 16-bit hex, folded (BN folded)
    conv1_weight_N.txt   (N=0~71)  : 파일 내 16값 (out_ch 0~15), 변환 없음
    conv1_bias.txt                 : 16값, 16-bit hex, folded
    conv2_weight_N.txt   (N=0~143) : 파일 내 32값 (out_ch 0~31), 변환 없음
    conv2_bias.txt                 : 32값, 16-bit hex, folded
    dense0_weight.txt              : 1152행 × 64열, 8-bit hex
    dense0_bias.txt                : 64값, 8-bit hex
    dense1_weight.txt              : 64행 × 9열, 8-bit hex
    dense1_bias.txt                : 9값, 8-bit hex
"""

import os

# ── 경로 설정 ──────────────────────────────────────────────
IN_DIR      = './weights'           # 원본 weight 폴더
IN_CORE_DIR = './weights/core'      # bias, BN, 통합 weight 폴더
OUT_DIR     = './npu_weights'       # 출력 폴더
os.makedirs(OUT_DIR, exist_ok=True)


# ── 유틸리티 ───────────────────────────────────────────────
def read_hex8(path):
    """8-bit hex 파일 읽기 → signed int list"""
    vals = []
    with open(path) as f:
        for line in f:
            for h in line.strip().split():
                v = int(h, 16)
                vals.append(v - 256 if v >= 128 else v)
    return vals

def read_hex16(path):
    """16-bit hex 파일 읽기 → signed int list"""
    vals = []
    with open(path) as f:
        for line in f:
            for h in line.strip().split():
                v = int(h, 16)
                vals.append(v - 65536 if v >= 32768 else v)
    return vals

def to_hex8(v):
    """signed int → 2자리 hex (8-bit 마스크)"""
    return f'{int(v) & 0xFF:02x}'

def to_hex16(v):
    """signed int → 4자리 hex (16-bit 마스크)"""
    return f'{int(v) & 0xFFFF:04x}'

def write_lines(path, lines):
    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n')


# ── BN Folding 함수 ────────────────────────────────────────
def fold_bias(conv_bias, bn_scale, bn_offset):
    """
    folded_bias[oc] = round(bn_scale[oc] * conv_bias[oc] / 128) + bn_offset[oc]
    입력: Q1.7, Q8.8, Q8.8  →  출력: Q8.8 (16-bit signed)
    """
    result = []
    for oc in range(len(conv_bias)):
        fb = round(bn_scale[oc] * conv_bias[oc] / 128) + bn_offset[oc]
        assert -32768 <= fb <= 32767, f"folded_bias overflow at ch{oc}: {fb}"
        result.append(fb)
    return result


# ══════════════════════════════════════════════════════════
# 1. Conv0  (1ch → 8ch, 3×3)
# ══════════════════════════════════════════════════════════
print("[1/4] Conv0 처리 중...")

conv0_bias   = read_hex8 (f'{IN_CORE_DIR}/conv2d_bias.txt')   # 8값
bn0_scale    = read_hex16(f'{IN_CORE_DIR}/bn0_scale.txt')     # 8값
bn0_offset   = read_hex16(f'{IN_CORE_DIR}/bn0_offset.txt')    # 8값
folded0_bias = fold_bias(conv0_bias, bn0_scale, bn0_offset)

# weight: conv2d_weight_N.txt (3×3, 공백구분 3줄) → 9줄 1값씩으로 변환
for n in range(8):
    src = f'{IN_DIR}/conv2d_weight_{n}.txt'
    vals = read_hex8(src)   # 9값 (3×3)
    assert len(vals) == 9, f"conv0 weight_{n}: 값 수 오류 ({len(vals)})"
    write_lines(f'{OUT_DIR}/conv0_weight_{n}.txt', [to_hex8(v) for v in vals])

write_lines(f'{OUT_DIR}/conv0_bias.txt', [to_hex16(v) for v in folded0_bias])
print(f"  weight: 8파일, bias folded: {folded0_bias}")


# ══════════════════════════════════════════════════════════
# 2. Conv1  (8ch → 16ch, 3×3)
#    conv2d_1_weight_N.txt: N = in_ch*9 + kernel_pos, 파일내 16값 = out_ch
# ══════════════════════════════════════════════════════════
print("[2/4] Conv1 처리 중...")

conv1_bias   = read_hex8 (f'{IN_CORE_DIR}/conv2d_1_bias.txt')  # 16값
bn1_scale    = read_hex16(f'{IN_CORE_DIR}/bn1_scale.txt')      # 16값
bn1_offset   = read_hex16(f'{IN_CORE_DIR}/bn1_offset.txt')     # 16값
folded1_bias = fold_bias(conv1_bias, bn1_scale, bn1_offset)

for n in range(72):
    src = f'{IN_DIR}/conv2d_1_weight_{n}.txt'
    vals = read_hex8(src)   # 16값
    assert len(vals) == 16, f"conv1 weight_{n}: 값 수 오류 ({len(vals)})"
    write_lines(f'{OUT_DIR}/conv1_weight_{n}.txt', [to_hex8(v) for v in vals])

write_lines(f'{OUT_DIR}/conv1_bias.txt', [to_hex16(v) for v in folded1_bias])
print(f"  weight: 72파일, bias folded: {folded1_bias}")


# ══════════════════════════════════════════════════════════
# 3. Conv2  (16ch → 32ch, 3×3)
#    conv2d_2_weight_N.txt: N = in_ch*9 + kernel_pos, 파일내 32값 = out_ch
# ══════════════════════════════════════════════════════════
print("[3/4] Conv2 처리 중...")

conv2_bias   = read_hex8 (f'{IN_CORE_DIR}/conv2d_2_bias.txt')  # 32값
bn2_scale    = read_hex16(f'{IN_CORE_DIR}/bn2_scale.txt')      # 32값
bn2_offset   = read_hex16(f'{IN_CORE_DIR}/bn2_offset.txt')     # 32값
folded2_bias = fold_bias(conv2_bias, bn2_scale, bn2_offset)

for n in range(144):
    src = f'{IN_DIR}/conv2d_2_weight_{n}.txt'
    vals = read_hex8(src)   # 32값
    assert len(vals) == 32, f"conv2 weight_{n}: 값 수 오류 ({len(vals)})"
    write_lines(f'{OUT_DIR}/conv2_weight_{n}.txt', [to_hex8(v) for v in vals])

write_lines(f'{OUT_DIR}/conv2_bias.txt', [to_hex16(v) for v in folded2_bias])
print(f"  weight: 144파일, bias folded 범위: [{min(folded2_bias)}, {max(folded2_bias)}]")


# ══════════════════════════════════════════════════════════
# 4. Dense  (bias는 BN 없으므로 그대로)
# ══════════════════════════════════════════════════════════
print("[4/4] Dense 처리 중...")

# Dense0: 1152×64
d0_w_vals = read_hex8(f'{IN_DIR}/dense_weights.txt')   # 1152*64 = 73728값
assert len(d0_w_vals) == 1152 * 64, f"dense0 weight 크기 오류: {len(d0_w_vals)}"
rows = []
for r in range(1152):
    row = [to_hex8(d0_w_vals[r * 64 + c]) for c in range(64)]
    rows.append(' '.join(row))
write_lines(f'{OUT_DIR}/dense0_weight.txt', rows)

d0_bias = read_hex8(f'{IN_CORE_DIR}/dense_bias.txt')   # 64값
write_lines(f'{OUT_DIR}/dense0_bias.txt', [to_hex8(v) for v in d0_bias])
print(f"  dense0 weight: 1152×64, bias: 64값")

# Dense1: 64×9
d1_w_vals = read_hex8(f'{IN_DIR}/dense_1_weights.txt')  # 64*9 = 576값
assert len(d1_w_vals) == 64 * 9, f"dense1 weight 크기 오류: {len(d1_w_vals)}"
rows = []
for r in range(64):
    row = [to_hex8(d1_w_vals[r * 9 + c]) for c in range(9)]
    rows.append(' '.join(row))
write_lines(f'{OUT_DIR}/dense1_weight.txt', rows)

d1_bias = read_hex8(f'{IN_CORE_DIR}/dense_1_bias.txt')  # 9값
write_lines(f'{OUT_DIR}/dense1_bias.txt', [to_hex8(v) for v in d1_bias])
print(f"  dense1 weight: 64×9, bias: 9값")


# ══════════════════════════════════════════════════════════
# 완료 요약
# ══════════════════════════════════════════════════════════
print()
print("=" * 50)
print("전처리 완료! 출력 파일 목록:")
files = sorted(os.listdir(OUT_DIR))
total = len(files)
for fn in files[:10]:
    print(f"  {OUT_DIR}/{fn}")
if total > 10:
    print(f"  ... 외 {total - 10}개")
print(f"  총 {total}개 파일")
print()
print("비트폭 요약 (Verilog 설계 참고):")
print("  Conv weight : 8-bit signed  (Q1.7)")
print("  Conv bias   : 16-bit signed (Q8.8, BN folded)")
print("  Dense weight: 8-bit signed  (Q1.7)")
print("  Dense bias  : 8-bit signed  (Q1.7)")
print()
print("MAC 누산기 최소 비트폭:")
print("  Conv0 (9항)  : 20-bit")
print("  Conv1 (72항) : 23-bit")
print("  Conv2 (144항): 24-bit")
print("  Dense0(1152항): 27-bit")
print("  Dense1(64항) : 22-bit")