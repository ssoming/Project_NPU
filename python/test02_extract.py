# -*- coding: utf-8 -*-

import os
import numpy as np
import pandas as pd
from tensorflow.keras.models import load_model


# ============================================================
# 설정
# ============================================================

MODEL_PATH = './models/wafer_cnn_0.952.h5'
OUT_DIR = './fpga_params'

INPUT_SCALE = 128
WEIGHT_SCALE = 64
ACT_SCALE = 128

# BatchNorm 고정소수점 계수용 shift
# y_int = ((x_int * bn_mul) >> BN_SHIFT) + bn_add
BN_SHIFT = 16

os.makedirs(OUT_DIR, exist_ok=True)


# ============================================================
# 유틸
# ============================================================

def quantize_int8(x, scale=64):
    """
    float weight -> signed int8
    검증에서 가장 좋았던 방식:
        round(weight * 64)
        clip(-128, 127)
    """
    q = np.round(x * scale).astype(np.int32)
    overflow_count = int(np.sum((q < -128) | (q > 127)))
    q = np.clip(q, -128, 127)
    return q.astype(np.int32), overflow_count


def to_hex_signed(value, bits):
    """
    signed integer를 2's complement hex 문자열로 변환.
    bits=8  -> 2자리
    bits=32 -> 8자리
    bits=64 -> 16자리
    """
    value = int(value)
    mask = (1 << bits) - 1
    hex_width = bits // 4
    return format(value & mask, f'0{hex_width}x')


def save_1d_dec(path, arr):
    arr = np.array(arr).reshape(-1)
    np.savetxt(path, arr, fmt='%d')


def save_1d_hex(path, arr, bits):
    arr = np.array(arr).reshape(-1)
    with open(path, 'w', encoding='utf-8') as f:
        for v in arr:
            f.write(to_hex_signed(v, bits) + '\n')


def save_2d_hex(path, arr, bits=8):
    arr = np.array(arr)
    with open(path, 'w', encoding='utf-8') as f:
        for row in arr:
            row_hex = [to_hex_signed(v, bits) for v in row]
            f.write(' '.join(row_hex) + '\n')


def get_bn_params(layer):
    weights = layer.get_weights()

    if len(weights) == 4:
        gamma, beta, moving_mean, moving_var = weights
    else:
        raise ValueError(f'{layer.name}: BatchNorm weight 개수가 예상과 다릅니다. len={len(weights)}')

    return (
        gamma.astype(np.float64),
        beta.astype(np.float64),
        moving_mean.astype(np.float64),
        moving_var.astype(np.float64),
        float(layer.epsilon)
    )


# ============================================================
# Conv/Dense 저장
# ============================================================

def export_conv2d(layer, input_scale, scale_rows):
    """
    Conv2D 저장.
    Keras weight shape:
        (KH, KW, Cin, Cout)

    저장 방식:
        layer_w_oc00_ic00.txt : KH x KW hex
        layer_w_oc00_ic01.txt : KH x KW hex
        ...
        layer_bias_dec.txt
        layer_bias_hex64.txt
    """

    layer_dir = os.path.join(OUT_DIR, layer.name)
    os.makedirs(layer_dir, exist_ok=True)

    weights = layer.get_weights()
    w_float = weights[0]
    b_float = weights[1] if len(weights) >= 2 else None

    KH, KW, Cin, Cout = w_float.shape

    w_q, overflow_count = quantize_int8(w_float, WEIGHT_SCALE)

    # weight 저장
    for co in range(Cout):
        for ci in range(Cin):
            kernel = w_q[:, :, ci, co]
            path = os.path.join(layer_dir, f'{layer.name}_w_oc{co:02d}_ic{ci:02d}.txt')
            save_2d_hex(path, kernel, bits=8)

    # 전체 flat 저장도 같이 생성
    # 순서: kh -> kw -> ci -> co
    flat_path = os.path.join(layer_dir, f'{layer.name}_weight_flat_kh_kw_ci_co_hex.txt')
    save_1d_hex(flat_path, w_q.reshape(-1), bits=8)

    # bias scale
    acc_scale = input_scale * WEIGHT_SCALE

    if b_float is not None:
        b_q = np.round(b_float * acc_scale).astype(np.int64)

        save_1d_dec(os.path.join(layer_dir, f'{layer.name}_bias_dec.txt'), b_q)
        save_1d_hex(os.path.join(layer_dir, f'{layer.name}_bias_hex64.txt'), b_q, bits=64)
    else:
        b_q = np.zeros(Cout, dtype=np.int64)

    # Conv2D는 현재 모델에서 relu activation을 포함한다고 가정
    # 검증 코드와 동일하게 requantize하지 않고 acc_scale 유지
    output_scale = acc_scale

    scale_rows.append({
        'layer': layer.name,
        'type': 'Conv2D',
        'input_scale': input_scale,
        'weight_scale': WEIGHT_SCALE,
        'bias_scale': acc_scale,
        'output_scale': output_scale,
        'weight_shape': str(w_float.shape),
        'weight_overflow_count': overflow_count,
        'note': 'weight int8 hex, bias int64; output scale kept as acc_scale'
    })

    print(f'[Conv2D] {layer.name}')
    print(f'  weight shape   : {w_float.shape}')
    print(f'  input scale    : {input_scale}')
    print(f'  bias scale     : {acc_scale}')
    print(f'  output scale   : {output_scale}')
    print(f'  overflow count : {overflow_count}')

    return output_scale


def export_dense(layer, input_scale, scale_rows):
    """
    Dense 저장.
    Keras weight shape:
        (input_dim, output_dim)

    저장 방식:
        dense_w_out00.txt : 해당 output neuron의 모든 input weight
        dense_bias_dec.txt
        dense_bias_hex64.txt
    """

    layer_dir = os.path.join(OUT_DIR, layer.name)
    os.makedirs(layer_dir, exist_ok=True)

    weights = layer.get_weights()
    w_float = weights[0]
    b_float = weights[1] if len(weights) >= 2 else None

    input_dim, output_dim = w_float.shape

    w_q, overflow_count = quantize_int8(w_float, WEIGHT_SCALE)

    # output neuron별 저장
    # Keras Dense: output[j] = sum_i input[i] * W[i, j] + b[j]
    for out_idx in range(output_dim):
        one_output_weights = w_q[:, out_idx]
        path = os.path.join(layer_dir, f'{layer.name}_w_out{out_idx:02d}.txt')
        save_1d_hex(path, one_output_weights, bits=8)

    # 전체 flat 저장
    # 순서: input index -> output index
    flat_path = os.path.join(layer_dir, f'{layer.name}_weight_flat_in_out_hex.txt')
    save_1d_hex(flat_path, w_q.reshape(-1), bits=8)

    # bias scale
    acc_scale = input_scale * WEIGHT_SCALE

    if b_float is not None:
        b_q = np.round(b_float * acc_scale).astype(np.int64)

        save_1d_dec(os.path.join(layer_dir, f'{layer.name}_bias_dec.txt'), b_q)
        save_1d_hex(os.path.join(layer_dir, f'{layer.name}_bias_hex64.txt'), b_q, bits=64)
    else:
        b_q = np.zeros(output_dim, dtype=np.int64)

    # 검증 코드와 동일하게 requantize하지 않음
    output_scale = acc_scale

    scale_rows.append({
        'layer': layer.name,
        'type': 'Dense',
        'input_scale': input_scale,
        'weight_scale': WEIGHT_SCALE,
        'bias_scale': acc_scale,
        'output_scale': output_scale,
        'weight_shape': str(w_float.shape),
        'weight_overflow_count': overflow_count,
        'note': 'weight int8 hex, bias int64; output scale kept as acc_scale'
    })

    print(f'[Dense] {layer.name}')
    print(f'  weight shape   : {w_float.shape}')
    print(f'  input scale    : {input_scale}')
    print(f'  bias scale     : {acc_scale}')
    print(f'  output scale   : {output_scale}')
    print(f'  overflow count : {overflow_count}')

    return output_scale


def export_batchnorm(layer, input_scale, scale_rows):
    """
    BatchNormalization을 고정소수점 affine으로 저장.

    Keras inference:
        y = gamma * (x - mean) / sqrt(var + eps) + beta

    이를
        y = a * x + c

    형태로 바꾸면:
        a = gamma / sqrt(var + eps)
        c = beta - mean * a

    x_int는 input_scale 기준,
    y_int는 ACT_SCALE 기준으로 만들고 싶으므로:

        y_int = round((x_int / input_scale * a + c) * ACT_SCALE)

    Verilog용 근사:
        y_int = ((x_int * bn_mul) >>> BN_SHIFT) + bn_add

    여기서:
        bn_mul = round(a * ACT_SCALE / input_scale * 2^BN_SHIFT)
        bn_add = round(c * ACT_SCALE)
    """

    layer_dir = os.path.join(OUT_DIR, layer.name)
    os.makedirs(layer_dir, exist_ok=True)

    gamma, beta, mean, var, eps = get_bn_params(layer)

    a = gamma / np.sqrt(var + eps)
    c = beta - mean * a

    bn_mul = np.round(a * ACT_SCALE / input_scale * (1 << BN_SHIFT)).astype(np.int64)
    bn_add = np.round(c * ACT_SCALE).astype(np.int64)

    save_1d_dec(os.path.join(layer_dir, f'{layer.name}_bn_mul_dec.txt'), bn_mul)
    save_1d_dec(os.path.join(layer_dir, f'{layer.name}_bn_add_dec.txt'), bn_add)

    save_1d_hex(os.path.join(layer_dir, f'{layer.name}_bn_mul_hex32.txt'), bn_mul, bits=32)
    save_1d_hex(os.path.join(layer_dir, f'{layer.name}_bn_add_hex32.txt'), bn_add, bits=32)

    # float 참고용도 같이 저장
    np.savetxt(os.path.join(layer_dir, f'{layer.name}_gamma.txt'), gamma)
    np.savetxt(os.path.join(layer_dir, f'{layer.name}_beta.txt'), beta)
    np.savetxt(os.path.join(layer_dir, f'{layer.name}_moving_mean.txt'), mean)
    np.savetxt(os.path.join(layer_dir, f'{layer.name}_moving_var.txt'), var)
    np.savetxt(os.path.join(layer_dir, f'{layer.name}_a_float.txt'), a)
    np.savetxt(os.path.join(layer_dir, f'{layer.name}_c_float.txt'), c)

    output_scale = ACT_SCALE

    scale_rows.append({
        'layer': layer.name,
        'type': 'BatchNormalization',
        'input_scale': input_scale,
        'weight_scale': '',
        'bias_scale': '',
        'output_scale': output_scale,
        'weight_shape': str(gamma.shape),
        'weight_overflow_count': '',
        'note': f'y_int = ((x_int * bn_mul) >>> {BN_SHIFT}) + bn_add'
    })

    print(f'[BatchNorm] {layer.name}')
    print(f'  input scale  : {input_scale}')
    print(f'  output scale : {output_scale}')
    print(f'  BN_SHIFT     : {BN_SHIFT}')

    return output_scale


# ============================================================
# 전체 모델 순회
# ============================================================

def export_all():
    model = load_model(MODEL_PATH)
    model.summary()

    scale_rows = []

    current_scale = INPUT_SCALE

    for layer in model.layers:
        class_name = layer.__class__.__name__

        if class_name in ['InputLayer', 'Dropout']:
            continue

        if class_name == 'Conv2D':
            current_scale = export_conv2d(layer, current_scale, scale_rows)

        elif class_name == 'BatchNormalization':
            current_scale = export_batchnorm(layer, current_scale, scale_rows)

        elif class_name == 'MaxPooling2D':
            scale_rows.append({
                'layer': layer.name,
                'type': 'MaxPooling2D',
                'input_scale': current_scale,
                'weight_scale': '',
                'bias_scale': '',
                'output_scale': current_scale,
                'weight_shape': '',
                'weight_overflow_count': '',
                'note': 'scale unchanged'
            })

            print(f'[MaxPool] {layer.name}')
            print(f'  scale unchanged: {current_scale}')

        elif class_name == 'Flatten':
            scale_rows.append({
                'layer': layer.name,
                'type': 'Flatten',
                'input_scale': current_scale,
                'weight_scale': '',
                'bias_scale': '',
                'output_scale': current_scale,
                'weight_shape': '',
                'weight_overflow_count': '',
                'note': 'scale unchanged; Keras order = H -> W -> C'
            })

            print(f'[Flatten] {layer.name}')
            print(f'  scale unchanged: {current_scale}')

        elif class_name == 'Dense':
            current_scale = export_dense(layer, current_scale, scale_rows)

        else:
            raise NotImplementedError(f'{layer.name} / {class_name} layer는 아직 처리하지 않았습니다.')

    scale_df = pd.DataFrame(scale_rows)
    scale_csv_path = os.path.join(OUT_DIR, 'scale_table.csv')
    scale_df.to_csv(scale_csv_path, index=False, encoding='utf-8-sig')

    print('\n======================================')
    print('Export 완료')
    print('======================================')
    print('출력 폴더:', OUT_DIR)
    print('scale table:', scale_csv_path)

    print('\n중요 입력 변환:')
    print('Keras 입력 0.0 -> FPGA 입력 0')
    print('Keras 입력 0.5 -> FPGA 입력 64')
    print('Keras 입력 1.0 -> FPGA 입력 128')

    print('\n원본 wafer 값이 0,1,2라면:')
    print('0 -> 0')
    print('1 -> 64')
    print('2 -> 128')


if __name__ == '__main__':
    export_all()