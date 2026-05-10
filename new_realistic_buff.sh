#!/bin/bash
# =============================================================================
# ComfyUI Setup Script for Vast.ai — с проверкой файлов
# =============================================================================

COMFY_DIR="/workspace/ComfyUI"
CUSTOM_NODES_DIR="$COMFY_DIR/custom_nodes"
MODELS_DIR="$COMFY_DIR/models"
VENV_PYTHON="/venv/main/bin/python"
CIVITAI_TOKEN="93edfd8cf30d4caf7cdb82d6a92c475b"

# Минимальный размер валидного файла (1MB)
MIN_SIZE=1048576

# =============================================================================
# Функции
# =============================================================================

# Проверить файл: существует и больше MIN_SIZE
check_file() {
    local path="$1"
    if [ -f "$path" ] && [ "$(stat -c%s "$path" 2>/dev/null || echo 0)" -gt "$MIN_SIZE" ]; then
        return 0  # OK
    fi
    return 1  # Битый или отсутствует
}

# Скачать с HuggingFace / прямая ссылка
download_file() {
    local url="$1"
    local dir="$2"
    local filename="$3"
    local dest="$dir/$filename"
    mkdir -p "$dir"
    if check_file "$dest"; then
        echo "[SKIP] $filename (уже есть)"
        return 0
    fi
    [ -f "$dest" ] && rm -f "$dest"
    echo "[DL] $filename ..."
    wget -q --show-progress -c --timeout=60 --tries=3 -O "$dest" "$url"
    if check_file "$dest"; then
        echo "[OK] $filename"
    else
        echo "[FAIL] $filename — файл битый или не скачался!"
        rm -f "$dest"
    fi
}

# Скачать с Civitai (токен в URL — работает с wget)
download_civitai() {
    local model_id="$1"
    local dir="$2"
    local filename="$3"
    local dest="$dir/$filename"
    mkdir -p "$dir"
    if check_file "$dest"; then
        echo "[SKIP] $filename (уже есть)"
        return 0
    fi
    [ -f "$dest" ] && rm -f "$dest"
    echo "[Civitai] $filename (id: $model_id) ..."
    wget -q --show-progress -c --timeout=120 --tries=3 \
        --content-disposition \
        -O "$dest" \
        "https://civitai.com/api/download/models/${model_id}?token=${CIVITAI_TOKEN}"
    if check_file "$dest"; then
        echo "[OK] $filename"
    else
        echo "[FAIL] $filename — проверь model_id $model_id на civitai.com!"
        rm -f "$dest"
    fi
}

# =============================================================================
echo "=== 1. Обновление ComfyUI ==="
# =============================================================================
cd "$COMFY_DIR" || exit 1
git pull
$VENV_PYTHON -m pip install -q -r requirements.txt

# =============================================================================
echo "=== 2. Custom Nodes ==="
# =============================================================================
mkdir -p "$CUSTOM_NODES_DIR"
cd "$CUSTOM_NODES_DIR" || exit 1

repos=(
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
    "https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git"
    "https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git"
    "https://github.com/rgthree/rgthree-comfy.git"
    "https://github.com/yolain/ComfyUI-Easy-Use.git"
    "https://github.com/WASasquatch/was-node-suite-comfyui.git"
    "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git"
    "https://github.com/adieyal/comfyui-dynamicprompts.git"
    "https://github.com/Fannovel16/comfyui_controlnet_aux.git"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git"
    "https://github.com/kijai/ComfyUI-KJNodes.git"
    "https://github.com/BadCafeCode/masquerade-nodes-comfyui.git"
    "https://github.com/crystian/ComfyUI-Crystools.git"
    "https://github.com/melMass/comfy_mtb.git"
    "https://github.com/ltdrdata/ComfyUI-Manager.git"
    "https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git"
    "https://github.com/chflame163/ComfyUI_LayerStyle.git"
    "https://github.com/willisplummer/ComfyUI-Lora-Manager.git"
    "https://github.com/KohakuBlueleaf/z-tipo-extension.git"
    "https://github.com/pamparamm/ComfyUI-ppm.git"
    "https://github.com/alexopus/ComfyUI-Image-Saver.git"
    "https://github.com/victorchall/ComfyUI-FBCNN.git"
    "https://github.com/SanxRoz/ComfyUI-Gemini.git"
)

for repo in "${repos[@]}"; do
    dir_name=$(basename "$repo" .git)
    if [ ! -d "$dir_name" ]; then
        git clone --depth=1 "$repo" && echo "[OK] $dir_name"
    else
        echo "[SKIP] $dir_name"
    fi
done

# =============================================================================
echo "=== 3. Python зависимости ==="
# =============================================================================
cd "$COMFY_DIR" || exit 1

$VENV_PYTHON -m pip install -q --upgrade pip
$VENV_PYTHON -m pip install -q \
    opencv-python-headless numba dynamicprompts piexif ultralytics dill \
    insightface onnxruntime-gpu facexlib mediapipe deepdiff timm einops \
    kornia filelock scipy scikit-image pycocotools ftfy python-dateutil \
    openai requests rembg tipo-kgen

$VENV_PYTHON -m pip install -q \
    git+https://github.com/facebookresearch/segment-anything.git

if [ -f "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack/install.py" ]; then
    $VENV_PYTHON "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack/install.py"
fi

for node_dir in \
    was-node-suite-comfyui ComfyUI-Easy-Use comfyui-dynamicprompts \
    comfyui_controlnet_aux ComfyUI-KJNodes ComfyUI_LayerStyle \
    ComfyUI-Crystools z-tipo-extension ComfyUI-ppm ComfyUI-Image-Saver \
    ComfyUI-FBCNN ComfyUI-Gemini; do
    req="$CUSTOM_NODES_DIR/$node_dir/requirements.txt"
    [ -f "$req" ] && $VENV_PYTHON -m pip install -q -r "$req" || true
done

# =============================================================================
echo "=== 4. Checkpoint ==="
# =============================================================================
mkdir -p "$MODELS_DIR/checkpoints/Illustrious/realistic"
# illustriousRealismBy v10 VAE — https://civitai.com/models/1412827
download_civitai "1599543" \
    "$MODELS_DIR/checkpoints/Illustrious/realistic" \
    "illustriousRealismBy_v10VAE.safetensors"

# =============================================================================
echo "=== 5. VAE ==="
# =============================================================================
download_file \
    "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors" \
    "$MODELS_DIR/vae" "sdxl_vae.safetensors"

# =============================================================================
echo "=== 6. CLIP Vision ==="
# =============================================================================
download_file \
    "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors" \
    "$MODELS_DIR/clip_vision" "CLIP-ViT-H-14-laion2B-s32b-b79k.safetensors"

download_file \
    "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/image_encoder/model.safetensors" \
    "$MODELS_DIR/clip_vision" "CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors"

download_file \
    "https://huggingface.co/stabilityai/control-lora/resolve/main/revision/clip_vision_g.safetensors" \
    "$MODELS_DIR/clip_vision" "clip_vision_g.safetensors"

# =============================================================================
echo "=== 7. IPAdapter ==="
# =============================================================================
download_file \
    "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin" \
    "$MODELS_DIR/ipadapter" "ip-adapter-faceid-plusv2_sdxl.bin"

# noobIPAMARK1 — https://civitai.com/models/1000401
download_civitai "1121145" "$MODELS_DIR/ipadapter" "noobIPAMARK1_mark1.safetensors"

# =============================================================================
echo "=== 8. ControlNet ==="
# =============================================================================
download_file \
    "https://huggingface.co/stabilityai/control-lora/resolve/main/control-LoRAs-rank256/control-lora-canny-rank256.safetensors" \
    "$MODELS_DIR/controlnet" "control-lora-canny-rank256.safetensors"

# noobaiXL controlnet openpose — https://civitai.com/models/1178383
download_civitai "1243766" "$MODELS_DIR/controlnet" "noobaiXLControlnet_openposeModel.safetensors"

# =============================================================================
echo "=== 9. Upscale ==="
# =============================================================================
download_file \
    "https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth" \
    "$MODELS_DIR/upscale_models" "4x_foolhardy_Remacri.pth"

# =============================================================================
echo "=== 10. SAM ==="
# =============================================================================
download_file \
    "https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth" \
    "$MODELS_DIR/sams" "sam_vit_b_01ec64.pth"

# =============================================================================
echo "=== 11. Ultralytics BBOX / SEGM ==="
# =============================================================================
download_file \
    "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov9c.pt" \
    "$MODELS_DIR/ultralytics/bbox" "face_yolov9c.pt"

download_file \
    "https://huggingface.co/Bingsu/adetailer/resolve/main/hand_yolov8s.pt" \
    "$MODELS_DIR/ultralytics/bbox" "hand_yolov8s.pt"

download_file \
    "https://huggingface.co/Bingsu/adetailer/resolve/main/hand_yolov9c.pt" \
    "$MODELS_DIR/ultralytics/bbox" "hand_yolov9c.pt"

# Eyeful v2 — https://civitai.com/models/1141490
download_civitai "1191574" "$MODELS_DIR/ultralytics/bbox" "Eyeful_v2-Paired.pt"

download_file \
    "https://github.com/ultralytics/assets/releases/download/v8.3.0/yolo11m-seg.pt" \
    "$MODELS_DIR/ultralytics/segm" "yolo11m-seg.pt"

# ntd11 anime nsfw segm — https://civitai.com/models/1296788
download_civitai "1354472" "$MODELS_DIR/ultralytics/segm" "ntd11_anime_nsfw_segm_v5-variant1.pt"

# =============================================================================
echo "=== 12. LoRA ==="
# =============================================================================
mkdir -p "$MODELS_DIR/loras/Pony/style"
mkdir -p "$MODELS_DIR/loras/Pony/realistic"
mkdir -p "$MODELS_DIR/loras/Illustrious/concept"

# devmgf Style — https://civitai.com/models/916444
download_civitai "2172230" "$MODELS_DIR/loras" "devmgf_Style.safetensors"

# incase style ponyxl — https://civitai.com/models/197285
download_civitai "586803" "$MODELS_DIR/loras" "incase_style_v3-1_ponyxl_ilff.safetensors"

# Jolly Jacks biggest beasts Illustrious — https://civitai.com/models/742576
download_civitai "1387728" "$MODELS_DIR/loras" "Jolly_Jacks_biggest_beasts_Illustrious.safetensors"

# round breasts IL — https://civitai.com/models/600985
download_civitai "1145311" "$MODELS_DIR/loras" "round_breasts-IL-1.0.safetensors"

# incoth — https://civitai.com/models/621513
download_civitai "1189052" "$MODELS_DIR/loras" "incoth.safetensors"

# nb-c v2 IL — https://civitai.com/models/791396
download_civitai "1537611" "$MODELS_DIR/loras" "nb-c_v2_IL-000025.safetensors"

# Matte Skin Illustrious v4 — https://civitai.com/models/757127
download_civitai "1447787" "$MODELS_DIR/loras" "Matte_Skin_Illustrious_v4.safetensors"

# smooth soft skin — https://civitai.com/models/937540
download_civitai "2213606" "$MODELS_DIR/loras" "smooth_soft_skin.safetensors"

# Breast Size Slider Illustrious V2 — https://civitai.com/models/866325
download_civitai "1835318" "$MODELS_DIR/loras" "Breast_Size_Slider_IL_V2.safetensors"

# Femenine body hq illu — https://civitai.com/models/917444
download_civitai "2148484" "$MODELS_DIR/loras" "Femenine_body_hq_illu.safetensors"

# Narrow Waist ILXL — https://civitai.com/models/741396
download_civitai "1384096" "$MODELS_DIR/loras" "Narrow_Waist_ILXL.safetensors"

# Sinozick Style XL Pony — https://civitai.com/models/224084
download_civitai "481798" "$MODELS_DIR/loras" "Sinozick_Style_XL_Pony.safetensors"

# g0th1cPXL — https://civitai.com/models/546285
download_civitai "1047254" "$MODELS_DIR/loras" "g0th1cPXL.safetensors"

# Expressive H — https://civitai.com/models/548421
download_civitai "1014562" "$MODELS_DIR/loras" "Expressive_H-000001.safetensors"

# Spray Tan Slider Pony — https://civitai.com/models/553432
download_civitai "1058506" "$MODELS_DIR/loras" "Spray_Tan_Slider_Pony.safetensors"

# AmateurStyle v3 PONY REALISM — https://civitai.com/models/889888
download_civitai "2082538" "$MODELS_DIR/loras" "AmateurStyle_v3_PONY_REALISM.safetensors"

# amateur photo v2 — https://civitai.com/models/469174
download_civitai "907787" "$MODELS_DIR/loras" "amateur_photo_v2.safetensors"

# igbaddie PN — https://civitai.com/models/446256
download_civitai "870027" "$MODELS_DIR/loras" "igbaddie-PN.safetensors"

# --- LoRA в подпапках (структура из воркфлоу) ---

# amateur style v1 pony -> Pony/style/
download_civitai "829397" "$MODELS_DIR/loras/Pony/style" "amateur_style_v1_pony.safetensors"

# Pony Realism Slider -> Pony/realistic/
download_civitai "1062449" "$MODELS_DIR/loras/Pony/realistic" "Pony_Realism_Slider.safetensors"

# Eyes for Illustrious -> Illustrious/concept/
download_civitai "1113756" "$MODELS_DIR/loras/Illustrious/concept" "Eyes_for_Illustrious_Lora_Perfect_anime_eyes.safetensors"

# detailed hand focus illustriousXL -> Illustrious/concept/
download_civitai "1253891" "$MODELS_DIR/loras/Illustrious/concept" "detailed_hand_focus_illustriousXL_v1.1.safetensors"

# Hyper Muscles V4.2 -> Illustrious/concept/
# !! Найди актуальный model version ID на https://civitai.com и замени 0000000
download_civitai "0000000" "$MODELS_DIR/loras/Illustrious/concept" "Hyper_Muscles_V4.2.safetensors"

# =============================================================================
echo ""
echo "=== ИТОГОВАЯ ПРОВЕРКА ВСЕХ ФАЙЛОВ ==="
# =============================================================================
MISSING=0

check_report() {
    local path="$1"
    local name="$2"
    if check_file "$path"; then
        echo "  [OK] $name"
    else
        echo "  [!!] ОТСУТСТВУЕТ: $name"
        MISSING=$((MISSING + 1))
    fi
}

echo "--- Checkpoints ---"
check_report "$MODELS_DIR/checkpoints/Illustrious/realistic/illustriousRealismBy_v10VAE.safetensors" "illustriousRealismBy_v10VAE"

echo "--- VAE ---"
check_report "$MODELS_DIR/vae/sdxl_vae.safetensors" "sdxl_vae"

echo "--- CLIP Vision ---"
check_report "$MODELS_DIR/clip_vision/CLIP-ViT-H-14-laion2B-s32b-b79k.safetensors" "CLIP-ViT-H-14"
check_report "$MODELS_DIR/clip_vision/CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors" "CLIP-ViT-bigG-14"
check_report "$MODELS_DIR/clip_vision/clip_vision_g.safetensors" "clip_vision_g"

echo "--- IPAdapter ---"
check_report "$MODELS_DIR/ipadapter/ip-adapter-faceid-plusv2_sdxl.bin" "ip-adapter-faceid-plusv2_sdxl"
check_report "$MODELS_DIR/ipadapter/noobIPAMARK1_mark1.safetensors" "noobIPAMARK1_mark1"

echo "--- ControlNet ---"
check_report "$MODELS_DIR/controlnet/control-lora-canny-rank256.safetensors" "control-lora-canny-rank256"
check_report "$MODELS_DIR/controlnet/noobaiXLControlnet_openposeModel.safetensors" "noobaiXL_openpose"

echo "--- Upscale ---"
check_report "$MODELS_DIR/upscale_models/4x_foolhardy_Remacri.pth" "4x_foolhardy_Remacri"

echo "--- SAM ---"
check_report "$MODELS_DIR/sams/sam_vit_b_01ec64.pth" "sam_vit_b"

echo "--- Ultralytics ---"
check_report "$MODELS_DIR/ultralytics/bbox/face_yolov9c.pt" "face_yolov9c"
check_report "$MODELS_DIR/ultralytics/bbox/hand_yolov8s.pt" "hand_yolov8s"
check_report "$MODELS_DIR/ultralytics/bbox/hand_yolov9c.pt" "hand_yolov9c"
check_report "$MODELS_DIR/ultralytics/bbox/Eyeful_v2-Paired.pt" "Eyeful_v2-Paired"
check_report "$MODELS_DIR/ultralytics/segm/yolo11m-seg.pt" "yolo11m-seg"
check_report "$MODELS_DIR/ultralytics/segm/ntd11_anime_nsfw_segm_v5-variant1.pt" "ntd11_segm"

echo "--- LoRA ---"
check_report "$MODELS_DIR/loras/devmgf_Style.safetensors" "devmgf_Style"
check_report "$MODELS_DIR/loras/incase_style_v3-1_ponyxl_ilff.safetensors" "incase_style"
check_report "$MODELS_DIR/loras/Jolly_Jacks_biggest_beasts_Illustrious.safetensors" "Jolly_Jacks"
check_report "$MODELS_DIR/loras/round_breasts-IL-1.0.safetensors" "round_breasts"
check_report "$MODELS_DIR/loras/incoth.safetensors" "incoth"
check_report "$MODELS_DIR/loras/nb-c_v2_IL-000025.safetensors" "nb-c_v2"
check_report "$MODELS_DIR/loras/Matte_Skin_Illustrious_v4.safetensors" "Matte_Skin"
check_report "$MODELS_DIR/loras/smooth_soft_skin.safetensors" "smooth_soft_skin"
check_report "$MODELS_DIR/loras/Breast_Size_Slider_IL_V2.safetensors" "Breast_Size_Slider"
check_report "$MODELS_DIR/loras/Femenine_body_hq_illu.safetensors" "Femenine_body"
check_report "$MODELS_DIR/loras/Narrow_Waist_ILXL.safetensors" "Narrow_Waist"
check_report "$MODELS_DIR/loras/Sinozick_Style_XL_Pony.safetensors" "Sinozick_Style"
check_report "$MODELS_DIR/loras/g0th1cPXL.safetensors" "g0th1cPXL"
check_report "$MODELS_DIR/loras/Expressive_H-000001.safetensors" "Expressive_H"
check_report "$MODELS_DIR/loras/Spray_Tan_Slider_Pony.safetensors" "Spray_Tan_Slider"
check_report "$MODELS_DIR/loras/AmateurStyle_v3_PONY_REALISM.safetensors" "AmateurStyle_v3"
check_report "$MODELS_DIR/loras/amateur_photo_v2.safetensors" "amateur_photo_v2"
check_report "$MODELS_DIR/loras/igbaddie-PN.safetensors" "igbaddie-PN"
check_report "$MODELS_DIR/loras/Pony/style/amateur_style_v1_pony.safetensors" "amateur_style_pony"
check_report "$MODELS_DIR/loras/Pony/realistic/Pony_Realism_Slider.safetensors" "Pony_Realism_Slider"
check_report "$MODELS_DIR/loras/Illustrious/concept/Eyes_for_Illustrious_Lora_Perfect_anime_eyes.safetensors" "Eyes_IL"
check_report "$MODELS_DIR/loras/Illustrious/concept/detailed_hand_focus_illustriousXL_v1.1.safetensors" "hand_focus_IL"

echo ""
if [ "$MISSING" -eq 0 ]; then
    echo "=== ВСЕ ФАЙЛЫ НА МЕСТЕ — Запускай ComfyUI! ==="
else
    echo "=== ВНИМАНИЕ: $MISSING файл(ов) не скачались — смотри [!!] выше ==="
fi
