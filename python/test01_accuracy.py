# -*- coding: utf-8 -*-

import os
import numpy as np
import matplotlib.pyplot as plt

from tensorflow.keras.models import load_model
from tensorflow.keras.utils import to_categorical
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import classification_report, confusion_matrix

from numpy.lib.stride_tricks import sliding_window_view


# ============================================================
# 설정
# ============================================================

MODEL_PATH = './models/wafer_cnn_0.952.h5'
X_PATH = './data/X.npy'
Y_PATH = './data/y.npy'

TXT_DIR = './weights_txt_check'

# weight scale
# 128에서 정확도가 거의 랜덤이면 64 또는 32로 낮춰서 실험
WEIGHT_SCALE = 64

# BatchNorm 뒤, 또는 requantize 사용 시 activation scale
ACT_SCALE = 128

# 기존 trunc보다 round가 일반적으로 양자화 오차가 적음
ROUND_MODE = 'round'       # 'trunc' or 'round'

# wrap은 overflow 시 부호가 뒤집힐 수 있음
# 검증 단계에서는 clip 권장
OVERFLOW_MODE = 'clip'     # 'wrap' or 'clip'

# 현재 기존 평가 코드에서는 X를 정규화하지 않고 넣고 있으므로 1
# 만약 학습할 때 X / 255.0 또는 X / 2.0 했다면 수정 필요
FIRST_INPUT_SCALE = 128

# 정수 추론 샘플 수
# 느리면 50 또는 100으로 줄이세요.
# 전체 테스트셋을 보고 싶으면 None
N_INT_TEST = 50

# bias scale 처리 방식
# correct 권장
BIAS_MODE = 'correct'      # 'x128' or 'correct'

# 중요 실험 옵션
# False: Conv/Dense 누적값을 바로 다음 layer로 넘김
# True : Conv/Dense 출력마다 ACT_SCALE=128로 다시 맞춤
#
# 지금 정확도가 너무 낮으므로 일단 False로 둡니다.
USE_REQUANTIZE_AFTER_CONV_DENSE = False

DEBUG_FLOAT_BIAS = True
# Confusion Matrix 표시 여부
SHOW_CONFUSION_MATRIX = True


# ============================================================
# 양자화 / txt 저장 유틸
# ============================================================

def quantize_to_int8(x, scale=128, round_mode='round', overflow_mode='clip'):
    """
    float weight를 signed int8로 변환합니다.

    round_mode:
        'trunc': (x * scale).astype(int)
        'round': np.round(x * scale)

    overflow_mode:
        'wrap': & 0xFF 후 signed 해석
        'clip': -128 ~ 127로 saturation
    """

    if round_mode == 'trunc':
        q = (x * scale).astype(np.int32)
    elif round_mode == 'round':
        q = np.round(x * scale).astype(np.int32)
    else:
        raise ValueError("ROUND_MODE은 'trunc' 또는 'round'만 가능합니다.")

    overflow_count = int(np.sum((q < -128) | (q > 127)))

    if overflow_mode == 'wrap':
        q8 = q & 0xFF
        q8 = np.where(q8 >= 128, q8 - 256, q8)
    elif overflow_mode == 'clip':
        q8 = np.clip(q, -128, 127)
    else:
        raise ValueError("OVERFLOW_MODE은 'wrap' 또는 'clip'만 가능합니다.")

    return q8.astype(np.int32), overflow_count


def signed_to_hex_array(q):
    """
    signed int8 값을 00~ff hex 값으로 변환합니다.
    예:
        -20 -> ec
    """
    return (q.astype(np.int32) & 0xFF).reshape(-1)


def save_hex_txt(path, q_signed):
    """
    signed int8 배열을 hex txt로 저장합니다.
    """
    q_hex = signed_to_hex_array(q_signed)
    np.savetxt(path, q_hex, fmt='%02x')


def load_hex_txt_as_signed(path, shape):
    """
    hex txt를 다시 signed int8 값으로 복원합니다.
    예:
        ec -> 236 -> -20
    """
    hex_values = np.loadtxt(path, dtype=str)

    if hex_values.ndim == 0:
        hex_values = np.array([hex_values])

    raw = np.array([int(v, 16) for v in hex_values.reshape(-1)], dtype=np.int32)
    signed = np.where(raw >= 128, raw - 256, raw)

    return signed.reshape(shape).astype(np.int32)


def get_batchnorm_params(layer):
    """
    BatchNormalization 파라미터를 robust하게 가져옵니다.
    일반적으로는 gamma, beta, moving_mean, moving_var 순서입니다.
    """

    weights = layer.get_weights()

    if len(weights) == 4:
        gamma, beta, moving_mean, moving_var = weights

    elif len(weights) == 3:
        # scale=False 또는 center=False일 수 있음
        # 보통 이런 경우는 드물지만 방어적으로 처리
        moving_mean = weights[-2]
        moving_var = weights[-1]
        channels = moving_mean.shape[0]

        if layer.scale and not layer.center:
            gamma = weights[0]
            beta = np.zeros(channels, dtype=np.float32)
        elif layer.center and not layer.scale:
            gamma = np.ones(channels, dtype=np.float32)
            beta = weights[0]
        else:
            gamma = np.ones(channels, dtype=np.float32)
            beta = np.zeros(channels, dtype=np.float32)

    elif len(weights) == 2:
        moving_mean, moving_var = weights
        channels = moving_mean.shape[0]
        gamma = np.ones(channels, dtype=np.float32)
        beta = np.zeros(channels, dtype=np.float32)

    else:
        raise ValueError(f"{layer.name}: BatchNorm weight 개수가 예상과 다릅니다. len={len(weights)}")

    return gamma, beta, moving_mean, moving_var


def save_and_reload_txt_weights(model):
    """
    2번 과정:
    모델 weight/bias를 txt로 저장하고, 다시 읽어서 값이 같은지 확인합니다.
    BatchNormalization은 gamma/beta/mean/var를 params에 따로 저장합니다.
    """

    os.makedirs(TXT_DIR, exist_ok=True)

    txt_params = {}

    print("\n\n==============================")
    print("2. txt 저장 / 재로드 확인")
    print("==============================")

    for layer in model.layers:
        class_name = layer.__class__.__name__
        layer_name = layer.name
        weights = layer.get_weights()

        if len(weights) == 0:
            continue

        print(f"\nLayer: {layer_name} / {class_name}")

        # ------------------------------------------------------------
        # BatchNormalization 처리
        # ------------------------------------------------------------
        if class_name == 'BatchNormalization':
            gamma, beta, moving_mean, moving_var = get_batchnorm_params(layer)

            txt_params[layer_name] = {
                'gamma': gamma.astype(np.float64),
                'beta': beta.astype(np.float64),
                'moving_mean': moving_mean.astype(np.float64),
                'moving_var': moving_var.astype(np.float64),
                'epsilon': layer.epsilon
            }

            print("BatchNorm params")
            print("gamma shape      :", gamma.shape)
            print("beta shape       :", beta.shape)
            print("moving_mean shape:", moving_mean.shape)
            print("moving_var shape :", moving_var.shape)
            print("epsilon          :", layer.epsilon)

            continue

        # ------------------------------------------------------------
        # Conv2D / Dense weight 처리
        # ------------------------------------------------------------
        w_float = weights[0]

        w_q, overflow_count = quantize_to_int8(
            w_float,
            scale=WEIGHT_SCALE,
            round_mode=ROUND_MODE,
            overflow_mode=OVERFLOW_MODE
        )

        weight_path = os.path.join(TXT_DIR, f'{layer_name}_weight_hex.txt')
        shape_path = os.path.join(TXT_DIR, f'{layer_name}_weight_shape.txt')

        save_hex_txt(weight_path, w_q)
        np.savetxt(shape_path, np.array(w_float.shape), fmt='%d')

        w_loaded = load_hex_txt_as_signed(weight_path, w_float.shape)

        same = np.array_equal(w_q, w_loaded)

        print("weight shape       :", w_float.shape)
        print("weight txt check   :", same)
        print("weight overflow 개수:", overflow_count)

        if overflow_count > 0:
            print("주의: int8 범위(-128~127)를 넘은 weight가 있습니다.")
            print("      현재 OVERFLOW_MODE='clip'이면 saturation 처리됩니다.")

        if not same:
            print("오류: txt로 저장한 weight와 다시 읽은 weight가 다릅니다.")

        b_float = None
        b_x128 = None

        if len(weights) >= 2:
            b_float = weights[1]

            if ROUND_MODE == 'trunc':
                b_x128 = (b_float * WEIGHT_SCALE).astype(np.int64)
            else:
                b_x128 = np.round(b_float * WEIGHT_SCALE).astype(np.int64)

            bias_path = os.path.join(TXT_DIR, f'{layer_name}_bias_x{WEIGHT_SCALE}_dec.txt')
            np.savetxt(bias_path, b_x128.reshape(-1), fmt='%d')

            print("bias shape         :", b_float.shape)
            print("bias saved         :", bias_path)

        txt_params[layer_name] = {
            'weight': w_loaded,
            'bias_float': b_float,
            'bias_x128': b_x128,
            'weight_path': weight_path
        }

    return txt_params


# ============================================================
# scale / activation 유틸
# ============================================================

def get_bias_int(layer_name, b_float, b_x128, acc_scale):
    """
    bias 정수화 방식 선택.
    """

    if b_float is None:
        return None

    if BIAS_MODE == 'x128':
        return b_x128.astype(np.int64)

    elif BIAS_MODE == 'correct':
        if ROUND_MODE == 'trunc':
            return (b_float * acc_scale).astype(np.int64)
        else:
            return np.round(b_float * acc_scale).astype(np.int64)

    else:
        raise ValueError("BIAS_MODE은 'x128' 또는 'correct'만 가능합니다.")


def requantize(acc, from_scale, to_scale=128):
    """
    acc는 from_scale 기준 정수값입니다.
    이것을 다시 to_scale 기준 정수값으로 변환합니다.
    """
    return np.round(acc.astype(np.float64) * to_scale / from_scale).astype(np.int64)


def apply_activation_int(x, activation_name):
    """
    activation 처리.
    """
    if activation_name == 'relu':
        return np.maximum(x, 0)

    elif activation_name == 'linear':
        return x

    elif activation_name == 'softmax':
        # 최종 분류에서는 softmax를 생략해도 argmax 결과는 보통 동일합니다.
        return x

    elif activation_name == 'sigmoid':
        # 현재 다중분류 모델에서는 보통 사용하지 않음
        # 필요 시 fixed-point sigmoid 근사 구현 필요
        print("주의: sigmoid activation은 현재 정확한 fixed-point 구현이 아닙니다.")
        return x

    else:
        print("주의: 아직 처리하지 않은 activation입니다:", activation_name)
        return x


# ============================================================
# 정수 Conv / Pool / Dense / BatchNorm
# ============================================================

def conv2d_int(x, layer, params, x_scale):
    """
    정수 Conv2D 디버그용 안전 버전.
    sliding_window_view/tensordot 대신 직접 loop로 계산합니다.

    Keras Conv2D와 같은 cross-correlation 방식입니다.
    weight shape = (KH, KW, Cin, Cout)
    input shape  = (N, H, W, Cin)
    """

    w = params[layer.name]['weight'].astype(np.int64)

    b_float = params[layer.name]['bias_float']
    b_x128 = params[layer.name]['bias_x128']

    KH, KW, Cin, Cout = w.shape
    N, H, W, C = x.shape

    if C != Cin:
        raise ValueError(f"{layer.name}: 입력 channel {C}와 weight channel {Cin}이 다릅니다.")

    SH, SW = layer.strides
    padding = layer.padding

    if padding == 'same':
        out_h = int(np.ceil(H / SH))
        out_w = int(np.ceil(W / SW))

        pad_h = max((out_h - 1) * SH + KH - H, 0)
        pad_w = max((out_w - 1) * SW + KW - W, 0)

        pad_top = pad_h // 2
        pad_bottom = pad_h - pad_top
        pad_left = pad_w // 2
        pad_right = pad_w - pad_left

        x_pad = np.pad(
            x,
            ((0, 0), (pad_top, pad_bottom), (pad_left, pad_right), (0, 0)),
            mode='constant',
            constant_values=0
        )

    elif padding == 'valid':
        x_pad = x
        out_h = (H - KH) // SH + 1
        out_w = (W - KW) // SW + 1

    else:
        raise ValueError(f"{layer.name}: 지원하지 않는 padding입니다: {padding}")

    acc_scale = x_scale * WEIGHT_SCALE

    b_int = get_bias_int(layer.name, b_float, b_x128, acc_scale)

    out = np.zeros((N, out_h, out_w, Cout), dtype=np.int64)

    for n in range(N):
        for oh in range(out_h):
            for ow in range(out_w):
                ih = oh * SH
                iw = ow * SW

                patch = x_pad[n, ih:ih + KH, iw:iw + KW, :]  # (KH, KW, Cin)

                for co in range(Cout):
                    value = np.sum(patch.astype(np.int64) * w[:, :, :, co])

                    if b_float is not None:
                        if DEBUG_FLOAT_BIAS:
                            value += int(round(b_float[co] * acc_scale))
                        else:
                            if b_int is not None:
                                value += b_int[co]

                    out[n, oh, ow, co] = value

    if USE_REQUANTIZE_AFTER_CONV_DENSE:
        out = requantize(out, from_scale=acc_scale, to_scale=ACT_SCALE)
        out_scale = ACT_SCALE
    else:
        out_scale = acc_scale

    activation_name = layer.activation.__name__
    out = apply_activation_int(out, activation_name)

    return out.astype(np.int64), out_scale


def maxpool2d_int(x, layer, x_scale):
    """
    정수 MaxPooling2D.
    """

    N, H, W, C = x.shape

    PH, PW = layer.pool_size

    if layer.strides is None:
        SH, SW = layer.pool_size
    else:
        SH, SW = layer.strides

    padding = layer.padding

    if padding == 'same':
        out_h = int(np.ceil(H / SH))
        out_w = int(np.ceil(W / SW))

        pad_h = max((out_h - 1) * SH + PH - H, 0)
        pad_w = max((out_w - 1) * SW + PW - W, 0)

        pad_top = pad_h // 2
        pad_bottom = pad_h - pad_top
        pad_left = pad_w // 2
        pad_right = pad_w - pad_left

        x_pad = np.pad(
            x,
            ((0, 0), (pad_top, pad_bottom), (pad_left, pad_right), (0, 0)),
            mode='constant',
            constant_values=np.iinfo(np.int64).min
        )

    elif padding == 'valid':
        x_pad = x
        out_h = (H - PH) // SH + 1
        out_w = (W - PW) // SW + 1

    else:
        raise ValueError(f"{layer.name}: 지원하지 않는 padding입니다: {padding}")

    windows = sliding_window_view(x_pad, (PH, PW), axis=(1, 2))
    windows = windows[:, ::SH, ::SW, :, :, :]

    # windows shape: (N, OH, OW, C, PH, PW)
    out = np.max(windows, axis=(-1, -2))

    return out.astype(np.int64), x_scale


def dense_int(x, layer, params, x_scale):
    """
    정수 Dense.

    x shape      : (N, input_dim)
    weight shape : (input_dim, output_dim)
    """

    w = params[layer.name]['weight'].astype(np.int64)

    b_float = params[layer.name]['bias_float']
    b_x128 = params[layer.name]['bias_x128']

    acc_scale = x_scale * WEIGHT_SCALE

    acc = x.astype(np.int64) @ w.astype(np.int64)

    b_int = get_bias_int(layer.name, b_float, b_x128, acc_scale)

    if b_int is not None:
        acc = acc + b_int.reshape(1, -1)

    # ------------------------------------------------------------
    # Conv와 마찬가지로 기본적으로 requantize를 끕니다.
    # ------------------------------------------------------------
    if USE_REQUANTIZE_AFTER_CONV_DENSE:
        out = requantize(acc, from_scale=acc_scale, to_scale=ACT_SCALE)
        out_scale = ACT_SCALE
    else:
        out = acc
        out_scale = acc_scale

    activation_name = layer.activation.__name__
    out = apply_activation_int(out, activation_name)

    return out.astype(np.int64), out_scale


def batchnorm_int(x, layer, params, x_scale):
    """
    BatchNormalization 정수 시뮬레이션.

    Keras inference:
        y = gamma * (x - moving_mean) / sqrt(moving_var + epsilon) + beta

    여기서 x는 정수값이고, 실제 float 값은 x / x_scale 입니다.
    BatchNorm 적용 후 다시 ACT_SCALE 기준 정수로 바꿉니다.
    """

    p = params[layer.name]

    gamma = p['gamma']
    beta = p['beta']
    moving_mean = p['moving_mean']
    moving_var = p['moving_var']
    epsilon = p['epsilon']

    # y = a*x + c 형태
    a = gamma / np.sqrt(moving_var + epsilon)
    c = beta - moving_mean * a

    # Conv2D 뒤: (N, H, W, C)
    # Dense 뒤 : (N, C)
    reshape_shape = [1] * x.ndim
    reshape_shape[-1] = gamma.shape[0]

    a = a.reshape(reshape_shape)
    c = c.reshape(reshape_shape)

    # x_int / x_scale -> float
    y_float = (x.astype(np.float64) / x_scale) * a + c

    # 다시 ACT_SCALE 기준 정수
    y_int = np.round(y_float * ACT_SCALE).astype(np.int64)

    return y_int, ACT_SCALE


# ============================================================
# 정수 모델 실행
# ============================================================

def run_int_model(model, params, X_input):
    """
    txt에서 읽은 정수 weight를 사용해 FPGA식 정수 추론을 수행합니다.
    각 layer마다 min/max/zero ratio를 출력합니다.
    """

    x = np.round(X_input * FIRST_INPUT_SCALE).astype(np.int64)
    x_scale = FIRST_INPUT_SCALE

    print("\n\n==============================")
    print("3. Python 정수 CNN 추론")
    print("==============================")

    print("Input int min/max:", np.min(x), np.max(x), "scale:", x_scale)

    for layer in model.layers:
        class_name = layer.__class__.__name__

        if class_name in ['InputLayer', 'Dropout']:
            continue

        print(f"\nRunning: {layer.name:20s} {class_name:15s} input shape: {x.shape}")
        print("  before min/max:", np.min(x), np.max(x), "scale:", x_scale)

        if class_name == 'Conv2D':
            x, x_scale = conv2d_int(x, layer, params, x_scale)

        elif class_name == 'BatchNormalization':
            x, x_scale = batchnorm_int(x, layer, params, x_scale)

        elif class_name == 'MaxPooling2D':
            x, x_scale = maxpool2d_int(x, layer, x_scale)

        elif class_name == 'Flatten':
            x = x.reshape((x.shape[0], -1))

        elif class_name == 'Dense':
            x, x_scale = dense_int(x, layer, params, x_scale)

        elif class_name == 'Activation':
            activation_name = layer.activation.__name__
            x = apply_activation_int(x, activation_name)

        elif class_name == 'ReLU':
            x = np.maximum(x, 0)

        else:
            raise NotImplementedError(
                f"{layer.name} / {class_name} layer는 아직 int 시뮬레이션에 구현되어 있지 않습니다."
            )

        print("  after  min/max:", np.min(x), np.max(x), "scale:", x_scale)

        zero_ratio = np.mean(x == 0)
        print("  zero ratio:", zero_ratio)

        if np.max(np.abs(x)) > 1_000_000_000:
            print("  주의: 값이 매우 큽니다. scale 또는 bias 처리를 확인해야 합니다.")

    return x


# ============================================================
# 1. 데이터 로드 / 기존 float 모델 평가
# ============================================================

X = np.load(X_PATH)
y = np.load(Y_PATH)

le = LabelEncoder()
y_encoded = le.fit_transform(y)
y_onehot = to_categorical(y_encoded)
class_names = le.classes_

X = X.reshape(-1, 48, 48, 1)

print("X shape:", X.shape)
print("y shape:", y.shape)
print("class names:", class_names)
print("X min:", np.min(X), "X max:", np.max(X))

unique_values = np.unique(X)
if len(unique_values) <= 20:
    print("X unique values:", unique_values)
else:
    print("X unique 개수:", len(unique_values))
    print("X unique 일부:", unique_values[:20])

X_train, X_test, y_train, y_test = train_test_split(
    X,
    y_onehot,
    test_size=0.1,
    random_state=42,
    stratify=y_encoded
)

y_test_class = np.argmax(y_test, axis=1)

model = load_model(MODEL_PATH)
model.summary()

print("\n\n==============================")
print("1. Keras float 모델 평가")
print("==============================")

test_loss, test_acc = model.evaluate(X_test, y_test, verbose=0)
print(f"Float Test Accuracy : {test_acc:.4f}")
print(f"Float Test Loss     : {test_loss:.4f}")

y_pred_float = model.predict(X_test, verbose=0)
y_pred_float_class = np.argmax(y_pred_float, axis=1)

print("\n=== Float Classification Report ===")
print(classification_report(
    y_test_class,
    y_pred_float_class,
    target_names=class_names,
    digits=4,
    zero_division=0
))

# ============================================================
# 추가 진단: Keras fake quantization 테스트
# ============================================================

from tensorflow.keras.models import clone_model


def quant_dequant_weight(w, scale, round_mode='round', overflow_mode='clip'):
    """
    weight를 int8로 양자화했다가 다시 float로 복원합니다.
    Keras 안에서 직접 평가하기 위한 fake quantization입니다.
    """

    if round_mode == 'round':
        q = np.round(w * scale).astype(np.int32)
    else:
        q = (w * scale).astype(np.int32)

    overflow_count = int(np.sum((q < -128) | (q > 127)))

    if overflow_mode == 'clip':
        q = np.clip(q, -128, 127)
    elif overflow_mode == 'wrap':
        q = q & 0xFF
        q = np.where(q >= 128, q - 256, q)
    else:
        raise ValueError("overflow_mode은 'clip' 또는 'wrap'만 가능합니다.")

    w_dequant = q.astype(np.float32) / scale

    return w_dequant, overflow_count


def evaluate_fake_quant_model(model, X_test, y_test, scale):
    """
    Conv2D, Dense weight/bias를 정수화했다가 다시 float로 복원한 모델을 평가합니다.
    BatchNorm 파라미터는 그대로 둡니다.
    """

    fq_model = clone_model(model)
    fq_model.build(model.input_shape)
    fq_model.set_weights(model.get_weights())
    fq_model.compile(
        optimizer='adam',
        loss='categorical_crossentropy',
        metrics=['accuracy']
    )

    total_overflow = 0

    for layer in fq_model.layers:
        class_name = layer.__class__.__name__
        weights = layer.get_weights()

        if len(weights) == 0:
            continue

        # Conv2D / Dense만 weight quantization 확인
        if class_name in ['Conv2D', 'Dense']:
            new_weights = []

            # weight
            w = weights[0]
            w_dq, overflow_count = quant_dequant_weight(
                w,
                scale=scale,
                round_mode='round',
                overflow_mode='clip'
            )
            total_overflow += overflow_count
            new_weights.append(w_dq)

            # bias는 일단 float 그대로 둠
            # 여기서는 weight 정수화만으로 성능이 죽는지 확인하는 목적
            if len(weights) >= 2:
                new_weights.append(weights[1])

            layer.set_weights(new_weights)

    loss, acc = fq_model.evaluate(X_test, y_test, verbose=0)

    print("\n==============================")
    print(f"Fake Quant Test / scale = {scale}")
    print("==============================")
    print(f"Fake Quant Accuracy : {acc:.4f}")
    print(f"Fake Quant Loss     : {loss:.4f}")
    print(f"Weight overflow 개수: {total_overflow}")

    y_pred_fq = fq_model.predict(X_test[:N_INT_TEST], verbose=0)
    y_pred_fq_class = np.argmax(y_pred_fq, axis=1)

    same_with_float = np.mean(y_pred_fq_class == y_pred_float_class[:N_INT_TEST])
    print(f"Float vs FakeQuant same ratio on subset: {same_with_float:.4f}")

    return acc


print("\n\n==============================")
print("추가 진단: Fake Quantization")
print("==============================")

for test_scale in [128, 64, 32, 16]:
    evaluate_fake_quant_model(model, X_test, y_test, scale=test_scale)



# ============================================================
# 2. txt 저장 / 재로드
# ============================================================

txt_params = save_and_reload_txt_weights(model)

# ============================================================
# 추가 진단 2: Fake Quant Keras 출력 vs 직접 int CNN 출력 비교
# ============================================================

from tensorflow.keras.models import Model, clone_model


def build_fake_quant_model(model, scale=64):
    """
    Conv2D, Dense weight만 int8 quantize -> dequantize한 Keras 모델 생성.
    BatchNorm은 그대로 유지.
    """

    fq_model = clone_model(model)

    # 중요:
    # Sequential clone_model은 한 번 실제 입력을 넣어 호출해야 input/output이 정의됩니다.
    dummy_input = np.zeros((1, 48, 48, 1), dtype=np.float32)
    fq_model(dummy_input)

    fq_model.set_weights(model.get_weights())

    for layer in fq_model.layers:
        class_name = layer.__class__.__name__
        weights = layer.get_weights()

        if len(weights) == 0:
            continue

        if class_name in ['Conv2D', 'Dense']:
            new_weights = []

            # weight quantize -> dequantize
            w = weights[0]

            q = np.round(w * scale).astype(np.int32)
            q = np.clip(q, -128, 127)
            w_dq = q.astype(np.float32) / scale

            new_weights.append(w_dq)

            # bias는 float 그대로 유지
            if len(weights) >= 2:
                new_weights.append(weights[1])

            layer.set_weights(new_weights)

    return fq_model


def run_int_model_collect(model, params, X_input):
    """
    직접 만든 int CNN을 실행하면서 각 layer 출력을 float로 환산해서 저장.
    """

    x = np.round(X_input * FIRST_INPUT_SCALE).astype(np.int64)
    x_scale = FIRST_INPUT_SCALE

    outputs = {}

    for layer in model.layers:
        class_name = layer.__class__.__name__

        if class_name in ['InputLayer', 'Dropout']:
            continue

        if class_name == 'Conv2D':
            x, x_scale = conv2d_int(x, layer, params, x_scale)

        elif class_name == 'BatchNormalization':
            x, x_scale = batchnorm_int(x, layer, params, x_scale)

        elif class_name == 'MaxPooling2D':
            x, x_scale = maxpool2d_int(x, layer, x_scale)

        elif class_name == 'Flatten':
            x = x.reshape((x.shape[0], -1))

        elif class_name == 'Dense':
            x, x_scale = dense_int(x, layer, params, x_scale)

        elif class_name == 'Activation':
            activation_name = layer.activation.__name__
            x = apply_activation_int(x, activation_name)

        elif class_name == 'ReLU':
            x = np.maximum(x, 0)

        else:
            raise NotImplementedError(
                f"{layer.name} / {class_name} layer는 아직 int 시뮬레이션에 구현되어 있지 않습니다."
            )

        # int 값을 실제 float 값으로 환산해서 저장
        outputs[layer.name] = {
            'value': x.astype(np.float64) / x_scale,
            'scale': x_scale,
            'class_name': class_name
        }

    return outputs


def compare_layer_outputs(model, params, X_debug, scale=64):
    """
    Fake Quant Keras layer 출력과 직접 int CNN layer 출력을 비교.
    """

    print("\n\n==============================")
    print("추가 진단 2: Layer별 출력 비교")
    print("==============================")

    fq_model = build_fake_quant_model(model, scale=scale)

    target_layers = []
    target_names = []

    for layer in fq_model.layers:
        class_name = layer.__class__.__name__

        if class_name in ['InputLayer', 'Dropout']:
            continue

        target_layers.append(layer.output)
        target_names.append(layer.name)

    intermediate_model = Model(inputs=fq_model.inputs, outputs=target_layers)

    keras_outputs = intermediate_model.predict(X_debug, verbose=0)
    int_outputs = run_int_model_collect(model, params, X_debug)

    if not isinstance(keras_outputs, list):
        keras_outputs = [keras_outputs]

    for name, k_out in zip(target_names, keras_outputs):
        if name not in int_outputs:
            print(f"{name:25s}: int output 없음")
            continue

        i_out = int_outputs[name]['value']

        print(f"\nLayer: {name}")
        print("  Keras shape:", k_out.shape)
        print("  Int   shape:", i_out.shape)

        if k_out.shape != i_out.shape:
            print("  shape 다름 → 이 layer부터 구조가 다릅니다.")
            continue

        diff = k_out.astype(np.float64) - i_out.astype(np.float64)

        mae = np.mean(np.abs(diff))
        max_err = np.max(np.abs(diff))

        k_min, k_max = np.min(k_out), np.max(k_out)
        i_min, i_max = np.min(i_out), np.max(i_out)

        print(f"  Keras min/max : {k_min:.6f} / {k_max:.6f}")
        print(f"  Int   min/max : {i_min:.6f} / {i_max:.6f}")
        print(f"  MAE           : {mae:.6f}")
        print(f"  Max Error     : {max_err:.6f}")

        # 대략적인 방향성 비교
        k_flat = k_out.reshape(-1).astype(np.float64)
        i_flat = i_out.reshape(-1).astype(np.float64)

        if np.std(k_flat) > 1e-12 and np.std(i_flat) > 1e-12:
            corr = np.corrcoef(k_flat, i_flat)[0, 1]
            print(f"  Corr          : {corr:.6f}")
        else:
            print("  Corr          : 계산 불가")


# 비교용 샘플 수
X_debug = X_test[:3]

compare_layer_outputs(
    model=model,
    params=txt_params,
    X_debug=X_debug,
    scale=64
)

# ============================================================
# 추가 진단 3: 첫 Conv2D 특정 위치 값 직접 비교
# ============================================================

def debug_first_conv_single_point(model, params, X_sample, scale=64):
    print("\n\n==============================")
    print("추가 진단 3: 첫 Conv 단일 위치 비교")
    print("==============================")

    # fake quant Keras 모델
    fq_model = build_fake_quant_model(model, scale=scale)
    conv_layer = fq_model.get_layer('conv2d')

    conv_only = Model(inputs=fq_model.inputs, outputs=conv_layer.output)
    keras_conv_out = conv_only.predict(X_sample, verbose=0)

    # int conv 직접 계산
    first_layer = model.get_layer('conv2d')

    x_int = np.round(X_sample * FIRST_INPUT_SCALE).astype(np.int64)
    int_conv_out, int_scale = conv2d_int(
        x_int,
        first_layer,
        params,
        FIRST_INPUT_SCALE
    )

    int_conv_float = int_conv_out.astype(np.float64) / int_scale

    print("Keras conv out shape:", keras_conv_out.shape)
    print("Int conv out shape  :", int_conv_float.shape)

    # 몇 개 위치를 비교
    positions = [
        (0, 0, 0, 0),
        (0, 0, 0, 1),
        (0, 10, 10, 0),
        (0, 10, 10, 1),
        (0, 20, 20, 0),
        (0, 20, 20, 1),
    ]

    for pos in positions:
        n, h, w, c = pos
        k_val = keras_conv_out[n, h, w, c]
        i_val = int_conv_float[n, h, w, c]
        print(
            f"pos={pos} | "
            f"Keras={k_val:.6f} | "
            f"Int={i_val:.6f} | "
            f"diff={k_val - i_val:.6f}"
        )

    # 첫 번째 Conv weight 일부 확인
    original_layer = model.get_layer('conv2d')
    original_w = original_layer.get_weights()[0]
    q_w = params['conv2d']['weight']

    print("\n첫 Conv weight 확인")
    print("original weight min/max:", np.min(original_w), np.max(original_w))
    print("quant weight min/max   :", np.min(q_w), np.max(q_w))
    print("dequant weight min/max :", np.min(q_w / scale), np.max(q_w / scale))

    print("\n첫 Conv bias 확인")
    if len(original_layer.get_weights()) >= 2:
        original_b = original_layer.get_weights()[1]
        print("bias:", original_b)
    else:
        print("bias 없음")


debug_first_conv_single_point(
    model=model,
    params=txt_params,
    X_sample=X_test[:1],
    scale=64
)

# ============================================================
# 3. 정수 모델 평가
# ============================================================

if N_INT_TEST is None:
    X_int_test = X_test
    y_int_true = y_test_class
    y_float_subset_class = y_pred_float_class
else:
    X_int_test = X_test[:N_INT_TEST]
    y_int_true = y_test_class[:N_INT_TEST]
    y_float_subset_class = y_pred_float_class[:N_INT_TEST]

int_output = run_int_model(model, txt_params, X_int_test)
y_pred_int_class = np.argmax(int_output, axis=1)

int_acc = np.mean(y_pred_int_class == y_int_true)
float_subset_acc = np.mean(y_float_subset_class == y_int_true)
float_int_same = np.mean(y_float_subset_class == y_pred_int_class)

print("\n\n==============================")
print("결과 비교")
print("==============================")
print(f"Float accuracy on int subset : {float_subset_acc:.4f}")
print(f"Int accuracy on int subset   : {int_acc:.4f}")
print(f"Float vs Int same ratio      : {float_int_same:.4f}")

# print("\n=== Int Classification Report ===")
# print(classification_report(
#     y_int_true,
#     y_pred_int_class,
#     target_names=class_names,
#     digits=4,
#     zero_division=0
# ))

print(classification_report(
    y_int_true,
    y_pred_int_class,
    target_names=class_names,
    labels=list(range(len(class_names))),  # 이 줄 추가
    digits=4,
    zero_division=0
))

print("\n=== First 30 samples ===")
for i in range(min(30, len(y_int_true))):
    print(
        f"idx={i:03d} | "
        f"true={class_names[y_int_true[i]]:10s} | "
        f"float={class_names[y_float_subset_class[i]]:10s} | "
        f"int={class_names[y_pred_int_class[i]]:10s}"
    )


# ============================================================
# Confusion Matrix: int 모델용
# ============================================================

if SHOW_CONFUSION_MATRIX:
    # cm_int = confusion_matrix(y_int_true, y_pred_int_class)
    cm_int = confusion_matrix(y_int_true, y_pred_int_class, labels=list(range(len(class_names))))

    plt.figure(figsize=(10, 8))
    plt.imshow(cm_int, interpolation='nearest', cmap='Blues')
    plt.title('Integer Model Confusion Matrix')
    plt.colorbar()

    tick_marks = np.arange(len(class_names))
    plt.xticks(tick_marks, class_names, rotation=45, ha='right')
    plt.yticks(tick_marks, class_names)

    for i in range(len(class_names)):
        for j in range(len(class_names)):
            plt.text(j, i, str(cm_int[i, j]), ha='center', va='center', fontsize=8)

    plt.xlabel('Predicted')
    plt.ylabel('True')
    plt.tight_layout()
    plt.show()