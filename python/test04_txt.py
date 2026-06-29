import pandas as pd
import os

CSV_PATH = './mem/input_images_by_class/input_image_list.csv'
OUT_PATH = './mem/test_list.txt'

# Vivado에서 접근할 절대 경로 기준
PROJECT_ROOT = '/home/ming/workspace_ondevice_2/Project_NPU'

df = pd.read_csv(CSV_PATH)

with open(OUT_PATH, 'w', encoding='utf-8') as f:
    for case_id, row in df.iterrows():
        true_idx = int(row['class_idx'])

        # 일단 expected_idx는 true_idx로 둠
        # 나중에 Python int 모델 예측값으로 바꾸는 것을 추천
        expected_idx = true_idx

        class_name = str(row['class_name'])

        mem_path = row['mem_path'].replace('\\', '/')

        # 상대경로를 Vivado용 절대경로로 변환
        # 예: ./mem/input_images_by_class/... -> C:/project_2/mem/input_images_by_class/...
        if mem_path.startswith('./'):
            mem_path = mem_path[2:]

        abs_path = PROJECT_ROOT + '/' + mem_path

        f.write(f'{case_id} {true_idx} {expected_idx} {class_name} {abs_path}\n')

print('saved:', OUT_PATH)