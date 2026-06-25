import h5py
import numpy as np
from keras.src.layers.normalization import batch_normalization

filename = './models/wafer_cnn_0.952.h5'
with h5py.File(filename, 'r') as f:
    int_conv2d_weights = (f['model_weights']['conv2d']['sequential']['conv2d']['kernel'][:] * 128).astype(int)

    int_conv2d_weights = int_conv2d_weights & 0xFF
    print(list(int_conv2d_weights))
    print(int_conv2d_weights.shape)
    filters = int_conv2d_weights[:, :, 0, :]
    print(filters.shape)
    filters = np.transpose(filters, (2, 0, 1))
    print(filters)
    print(filters.shape)
    for i in range(len(filters)):
        np.savetxt('./weights/conv2d_weight_{}.txt'.format(i), filters[i],
                   fmt = '%02x', delimiter = ' ')
    np.savetxt('./weights/conv2d_weights.txt', filters.reshape(-1), fmt = '%02x', delimiter = ' ')


    int_conv2d_bias = (f['model_weights']['conv2d']['sequential']['conv2d']['bias'][:]
                          * 128).astype(int)
    print(int_conv2d_bias)
    int_conv2d_bias = int_conv2d_bias & 0xFF
    print(int_conv2d_bias)
    print(int_conv2d_bias.shape)
    np.savetxt('./weights/conv2d_bias.txt', int_conv2d_bias,
            fmt = '%02x', delimiter = ' ')


    int_conv2d_1_weights = (f['model_weights']['conv2d_1']['sequential']['conv2d_1']['kernel'][:] * 128).astype(int)
    int_conv2d_1_weights = int_conv2d_1_weights & 0xFF
    print(list(int_conv2d_1_weights))
    print(int_conv2d_1_weights.shape)
    filters = int_conv2d_1_weights
    filters = np.transpose(filters, (2, 0, 1, 3))
    filters_flat = filters.reshape(72, 16)
    print(filters_flat)
    print(filters_flat.shape)
    for i in range(len(filters_flat)):
        np.savetxt('./weights/conv2d_1_weight_{}.txt'.format(i), filters_flat[i],
                   fmt = '%02x', delimiter = ' ')
    np.savetxt('./weights/conv2d_1_weights.txt', filters_flat.reshape(-1), fmt='%02x', delimiter=' ')


    int_conv2d_1_bias = (f['model_weights']['conv2d_1']['sequential']['conv2d_1']['bias'][:]
                          * 128).astype(int)
    print(int_conv2d_1_bias)
    int_conv2d_1_bias = int_conv2d_1_bias & 0xFF
    print(int_conv2d_1_bias)
    print(int_conv2d_1_bias.shape)
    np.savetxt('./weights/conv2d_1_bias.txt', int_conv2d_1_bias,
            fmt = '%02x', delimiter = ' ')


    int_conv2d_2_weights = (f['model_weights']['conv2d_2']['sequential']['conv2d_2']['kernel'][:] * 128).astype(int)
    int_conv2d_2_weights = int_conv2d_2_weights & 0xFF
    print(list(int_conv2d_2_weights))
    print(int_conv2d_2_weights.shape)
    filters = int_conv2d_2_weights
    filters = np.transpose(filters, (2, 0, 1, 3))
    filters_flat = filters.reshape(144, 32)
    print(filters_flat)
    print(filters_flat.shape)
    for i in range(len(filters_flat)):
        np.savetxt('./weights/conv2d_2_weight_{}.txt'.format(i), filters_flat[i],
                   fmt = '%02x', delimiter = ' ')
    np.savetxt('./weights/conv2d_2_weights.txt', filters_flat.reshape(-1), fmt='%02x', delimiter=' ')


    int_conv2d_2_bias = (f['model_weights']['conv2d_2']['sequential']['conv2d_2']['bias'][:]
                          * 128).astype(int)
    print(int_conv2d_2_bias)
    int_conv2d_2_bias = int_conv2d_2_bias & 0xFF
    print(int_conv2d_2_bias)
    print(int_conv2d_2_bias.shape)
    np.savetxt('./weights/conv2d_2_bias.txt', int_conv2d_2_bias,
            fmt = '%02x', delimiter = ' ')


    int_dense_weights = (
        f['model_weights']['dense']['sequential']['dense']['kernel'][:]
        * 128).astype(int)
    int_dense_weights = int_dense_weights & 0xFF
    print(list(int_dense_weights))
    print(int_dense_weights.shape)
    np.savetxt('./weights/dense_weights.txt', int_dense_weights,
               fmt = '%02x', delimiter = ' ')
    np.savetxt('./weights/dense_weight.txt', int_dense_weights.reshape(-1), fmt='%02x', delimiter=' ')


    int_dense_bias = (
            f['model_weights']['dense']['sequential']['dense']['bias'][:]
            * 128).astype(int)
    int_dense_bias = int_dense_bias & 0xFF
    print(list(int_dense_bias))
    print(int_dense_bias.shape)
    np.savetxt('./weights/dense_bias.txt', int_dense_bias,
               fmt='%02x', delimiter=' ')


    int_dense_1_weights = (
        f['model_weights']['dense_1']['sequential']['dense_1']['kernel'][:]
        * 128).astype(int)
    int_dense_1_weights = int_dense_1_weights & 0xFF
    print(list(int_dense_1_weights))
    print(int_dense_1_weights.shape)
    np.savetxt('./weights/dense_1_weights.txt', int_dense_1_weights,
               fmt = '%02x', delimiter = ' ')
    np.savetxt('./weights/dense_1_weight.txt', int_dense_1_weights.reshape(-1), fmt='%02x', delimiter=' ')


    int_dense_1_bias = (
        f['model_weights']['dense_1']['sequential']['dense_1']['bias'][:]
        * 128).astype(int)
    int_dense_1_bias = int_dense_1_bias & 0xFF
    print(list(int_dense_1_bias))
    print(int_dense_1_bias.shape)
    np.savetxt('./weights/dense_1_bias.txt', int_dense_1_bias,
               fmt = '%02x', delimiter = ' ')


    bn_names = [
        'batch_normalization',
        'batch_normalization_1',
        'batch_normalization_2'
    ]

    for i, name in enumerate(bn_names):
        group = f['model_weights'][name]['sequential'][name]

        gamma = group['gamma'][:]
        beta = group['beta'][:]
        moving_mean = group['moving_mean'][:]
        moving_variance = group['moving_variance'][:]

        epsilon = 0.001  # Keras BatchNormalization 기본값

        scale = gamma / np.sqrt(moving_variance + epsilon)
        offset = beta - moving_mean * scale

        print(name)
        print(scale.shape, offset.shape)

        int_scale = np.round(scale * 256).astype(np.int32)
        int_offset = np.round(offset * 256).astype(np.int32)

        int_scale = int_scale & 0xFFFF
        int_offset = int_offset & 0xFFFF

        np.savetxt('./weights/bn{}_scale.txt'.format(i), int_scale, fmt = '%04x', delimiter = ' ')
        np.savetxt('./weights/bn{}_offset.txt'.format(i), int_offset, fmt = '%04x', delimiter = ' ')