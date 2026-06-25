import Path


scratch_none_dir = Path("./results/wafer_test/scratch_pred_none")
scratch_loc_dir = Path("./results/wafer_test/scratch_pred_loc")
scratch_correct_dir = Path("./results/wafer_test/scratch_correct")

scratch_none_dir.mkdir(parents=True, exist_ok=True)
scratch_loc_dir.mkdir(parents=True, exist_ok=True)
scratch_correct_dir.mkdir(parents=True, exist_ok=True)

scratch_idx = class_names.index("Scratch")
none_idx = class_names.index("none")
loc_idx = class_names.index("Loc")

scratch_true_indices = np.where(y_test == scratch_idx)[0]

for save_num, data_idx in enumerate(scratch_true_indices):
    true_label = class_names[int(y_test[data_idx])]
    pred_label = class_names[int(y_pred[data_idx])]

    img = X_test_info[data_idx].squeeze()

    if y_pred[data_idx] == none_idx:
        save_dir = scratch_none_dir
    elif y_pred[data_idx] == loc_idx:
        save_dir = scratch_loc_dir
    elif y_pred[data_idx] == scratch_idx:
        save_dir = scratch_correct_dir
    else:
        continue

    plt.figure(figsize=(3, 3))
    plt.imshow(img, cmap="gray", vmin=0, vmax=2)
    plt.title(f"T: {true_label}\nP: {pred_label}")
    plt.axis("off")

    save_path = save_dir / f"scratch_{save_num:03d}_P_{pred_label}.png"
    plt.savefig(save_path, dpi=150, bbox_inches="tight")
    plt.close()

print("Scratch → none 저장:", scratch_none_dir)
print("Scratch → Loc 저장:", scratch_loc_dir)
print("Scratch 정답 저장:", scratch_correct_dir)