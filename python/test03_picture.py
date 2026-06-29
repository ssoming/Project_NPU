# -*- coding: utf-8 -*-

import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from sklearn.preprocessing import LabelEncoder


# ============================================================
# 설정
# ============================================================

X_PATH = './data/X.npy'
Y_PATH = './data/y.npy'

OUT_DIR = './mem/input_images_by_class'

# 각 class마다 몇 개씩 저장할지
N_PER_CLASS = 3

# 이미지 크기
IMG_H = 48
IMG_W = 48

# FPGA 입력 scale
# Keras 입력 0.0, 0.5, 1.0 -> FPGA 입력 0, 64, 128
INPUT_SCALE = 128

os.makedirs(OUT_DIR, exist_ok=True)


# ============================================================
# 데이터 로드
# ============================================================

X = np.load(X_PATH)
y = np.load(Y_PATH)

print('X shape:', X.shape)
print('y shape:', y.shape)
print('X min/max:', np.min(X), np.max(X))
print('X unique:', np.unique(X)[:20])

le = LabelEncoder()
y_encoded = le.fit_transform(y)
class_names = le.classes_

print('\nClass names:')
for i, name in enumerate(class_names):
    print(i, name)


# ============================================================
# 입력값을 FPGA용 0, 64, 128로 변환
# ============================================================

def quantize_image_for_fpga(img):
    """
    img 값에 따라 자동 변환.

    경우 1:
        img = 0.0, 0.5, 1.0
        -> img * 128

    경우 2:
        img = 0, 1, 2
        -> img / 2 * 128

    결과:
        0, 64, 128
    """

    img = img.astype(np.float32)

    max_val = np.max(img)

    if max_val <= 1.0:
        img_q = np.round(img * INPUT_SCALE).astype(np.int16)
    else:
        img_q = np.round(img / 2.0 * INPUT_SCALE).astype(np.int16)

    return img_q


def save_mem_hex(path, img_q):
    """
    48x48 이미지를 Vivado $readmemh용 hex 파일로 저장.
    한 줄에 픽셀 하나.
    """

    img_q = img_q.reshape(IMG_H, IMG_W)

    with open(path, 'w', encoding='utf-8') as f:
        for h in range(IMG_H):
            for w in range(IMG_W):
                value = int(img_q[h, w])
                f.write(f'{value & 0xffff:04x}\n')


def save_preview_png(path, img):
    """
    확인용 이미지 저장.
    """
    plt.figure(figsize=(3, 3))
    plt.imshow(img.reshape(IMG_H, IMG_W), cmap='gray')
    plt.axis('off')
    plt.tight_layout()
    plt.savefig(path, dpi=150)
    plt.close()


# ============================================================
# 각 class별로 input_image.mem 생성
# ============================================================

records = []

for class_idx, class_name in enumerate(class_names):
    class_dir = os.path.join(OUT_DIR, f'{class_idx}_{class_name}')
    os.makedirs(class_dir, exist_ok=True)

    indices = np.where(y_encoded == class_idx)[0]

    print(f'\n[{class_idx}] {class_name}: {len(indices)} samples')

    selected = indices[:N_PER_CLASS]

    for sample_num, data_idx in enumerate(selected):
        img = X[data_idx].reshape(IMG_H, IMG_W)
        img_q = quantize_image_for_fpga(img)

        mem_name = f'input_{class_idx}_{class_name}_{sample_num}_idx{data_idx}.mem'
        png_name = f'preview_{class_idx}_{class_name}_{sample_num}_idx{data_idx}.png'

        mem_path = os.path.join(class_dir, mem_name)
        png_path = os.path.join(class_dir, png_name)

        save_mem_hex(mem_path, img_q)
        save_preview_png(png_path, img)

        records.append({
            'class_idx': class_idx,
            'class_name': class_name,
            'sample_num': sample_num,
            'data_idx': int(data_idx),
            'mem_path': mem_path.replace('\\', '/'),
            'png_path': png_path.replace('\\', '/'),
            'fpga_min': int(np.min(img_q)),
            'fpga_max': int(np.max(img_q)),
            'fpga_unique': str(np.unique(img_q).tolist())
        })

        print(f'  saved: {mem_path}')
        print(f'    fpga unique: {np.unique(img_q)}')


# ============================================================
# 목록 csv 저장
# ============================================================

df = pd.DataFrame(records)
csv_path = os.path.join(OUT_DIR, 'input_image_list.csv')
df.to_csv(csv_path, index=False, encoding='utf-8-sig')

print('\n======================================')
print('완료')
print('======================================')
print('저장 폴더:', OUT_DIR)
print('목록 CSV:', csv_path)