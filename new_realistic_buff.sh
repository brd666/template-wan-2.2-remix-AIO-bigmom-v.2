#!/bin/bash
# =============================================================================
# ComfyUI Setup Script for Vast.ai
# Workflow: realism-test2 (IllustriousRealism + Regional Prompting + IPAdapter)
# =============================================================================

COMFY_DIR="/workspace/ComfyUI"
CUSTOM_NODES_DIR="$COMFY_DIR/custom_nodes"
MODELS_DIR="$COMFY_DIR/models"
VENV_PYTHON="/venv/main/bin/python"
CIVITAI_TOKEN="93edfd8cf30d4caf7cdb82d6a92c475b"

download_file() {
    local url="$1"
    local dir="$2"
    local filename="$3"
    echo "[DL] $filename -> $dir"
    mkdir -p "$dir"
    wget -q --show-progress -c -O "$dir/$filename" "$url"
}

download_civitai() {
    local url="$1"
    local dir="$2"
    local filename="$3"
    echo "[Civitai] $filename -> $dir"
    mkdir -p "$dir"
    curl -L --retry 3 -H "Authorization: Bearer ${CIVITAI_TOKEN}" "$url" -o "$dir/$filename"
}

# =============================================================================
echo "=== 1. Custom Nodes ==="
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
)

for repo in "${repos[@]}"; do
    dir_name=$(basename "$repo" .git)
    if [ ! -d "$dir_name" ]; then
        git clone --depth=1 "$repo"
    else
        echo "[SKIP] $dir_name already exists"
    fi
done

# =============================================================================
echo "=== 2. Python зависимости ==="
# =============================================================================
cd "$COMFY_DIR" || exit 1

$VENV_PYTHON -m pip install -q --upgrade pip

$VENV_PYTHON -m pip install -q \
    opencv-python-headless \
    numba \
    dynamicprompts \
    piexif \
    ultralytics \
    dill \
    insightface \
    onnxruntime-gpu \
    facexlib \
    mediapipe \
    deepdiff \
    timm \
    einops \
    kornia \
    filelock \
    scipy \
    scikit-image \
    pycocotools \
    ftfy \
    python-dateutil \
    openai \
    requests \
    rembg

# Segment Anything (для Impact-Pack SAM)
$VENV_PYTHON -m pip install -q git+https://github.com/facebookresearch/segment-anything.git

# Impact Pack installer
if [ -f "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack/install.py" ]; then
    $VENV_PYTHON "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack/install.py"
fi

# requirements.txt для нод
for node_dir in was-node-suite-comfyui ComfyUI-Easy-Use comfyui-dynamicprompts comfyui_controlnet_aux ComfyUI-KJNodes ComfyUI_LayerStyle ComfyUI-Crystools; do
    req="$CUSTOM_NODES_DIR/$node_dir/requirements.txt"
    if [ -f "$req" ]; then
        echo "[REQ] $node_dir"
        $VENV_PYTHON -m pip install -q -r "$req" || true
    fi
done

# =============================================================================
echo "=== 3. Checkpoint ==="
# =============================================================================
mkdir -p "$MODELS_DIR/checkpoints/Illustrious/realistic"
download_civitai \
    "https://civitai.com/api/download/models/1599543" \
    "$MODELS_DIR/checkpoints/Illustrious/realistic" \
    "illustriousRealismBy_v10VAE.safetensors"

# =============================================================================
echo "=== 4. VAE ==="
# =============================================================================
download_file \
    "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors" \
    "$MODELS_DIR/vae" \
    "sdxl_vae.safetensors"

# =============================================================================
echo "=== 5. CLIP Vision ==="
# =============================================================================
download_file \
    "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors" \
    "$MODELS_DIR/clip_vision" \
    "CLIP-ViT-H-14-laion2B-s32b-b79k.safetensors"

download_file \
    "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/image_encoder/model.safetensors" \
    "$MODELS_DIR/clip_vision" \
    "CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors"

download_file \
    "https://huggingface.co/stabilityai/control-lora/resolve/main/revision/clip_vision_g.safetensors" \
    "$MODELS_DIR/clip_vision" \
    "clip_vision_g.safetensors"

# =============================================================================
echo "=== 6. IPAdapter ==="
# =============================================================================
download_file \
    "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin" \
    "$MODELS_DIR/ipadapter" \
    "ip-adapter-faceid-plusv2_sdxl.bin"

download_civitai \
    "https://civitai.com/api/download/models/1121145" \
    "$MODELS_DIR/ipadapter" \
    "noobIPAMARK1_mark1.safetensors"

# =============================================================================
echo "=== 7. ControlNet ==="
# =============================================================================
download_file \
    "https://huggingface.co/stabilityai/control-lora/resolve/main/control-LoRAs-rank256/control-lora-canny-rank256.safetensors" \
    "$MODELS_DIR/controlnet" \
    "control-lora-canny-rank256.safetensors"

download_civitai \
    "https://civitai.com/api/download/models/1243766" \
    "$MODELS_DIR/controlnet" \
    "noobaiXLControlnet_openposeModel.safetensors"

# =============================================================================
echo "=== 8. Upscale ==="
# =============================================================================
download_file \
    "https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth" \
    "$MODELS_DIR/upscale_models" \
    "4x_foolhardy_Remacri.pth"

# =============================================================================
echo "=== 9. SAM ==="
# =============================================================================
download_file \
    "https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth" \
    "$MODELS_DIR/sams" \
    "sam_vit_b_01ec64.pth"

# =============================================================================
echo "=== 10. Ultralytics BBOX / SEGM ==="
# =============================================================================
download_file "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov9c.pt"  "$MODELS_DIR/ultralytics/bbox" "face_yolov9c.pt"
download_file "https://huggingface.co/Bingsu/adetailer/resolve/main/hand_yolov8s.pt"  "$MODELS_DIR/ultralytics/bbox" "hand_yolov8s.pt"
download_file "https://huggingface.co/Bingsu/adetailer/resolve/main/hand_yolov9c.pt"  "$MODELS_DIR/ultralytics/bbox" "hand_yolov9c.pt"
download_civitai "https://civitai.com/api/download/models/1191574" "$MODELS_DIR/ultralytics/bbox" "Eyeful_v2-Paired.pt"
download_file "https://github.com/ultralytics/assets/releases/download/v8.3.0/yolo11m-seg.pt" "$MODELS_DIR/ultralytics/segm" "yolo11m-seg.pt"
download_civitai "https://civitai.com/api/download/models/1354472" "$MODELS_DIR/ultralytics/segm" "ntd11_anime_nsfw_segm_v5-variant1.pt"

# =============================================================================
echo "=== 11. LoRA ==="
# =============================================================================
mkdir -p "$MODELS_DIR/loras/Pony/style"
mkdir -p "$MODELS_DIR/loras/Pony/realistic"
mkdir -p "$MODELS_DIR/loras/Illustrious/concept"

download_civitai "https://civitai.com/api/download/models/2172230" "$MODELS_DIR/loras" "devmgf_Style.safetensors"
download_civitai "https://civitai.com/api/download/models/586803"  "$MODELS_DIR/loras" "incase_style_v3-1_ponyxl_ilff.safetensors"
download_civitai "https://civitai.com/api/download/models/1387728" "$MODELS_DIR/loras" "Jolly_Jacks_biggest_beasts_Illustrious.safetensors"
download_civitai "https://civitai.com/api/download/models/1145311" "$MODELS_DIR/loras" "round_breasts-IL-1.0.safetensors"
download_civitai "https://civitai.com/api/download/models/1189052" "$MODELS_DIR/loras" "incoth.safetensors"
download_civitai "https://civitai.com/api/download/models/1537611" "$MODELS_DIR/loras" "nb-c_v2_IL-000025.safetensors"
download_civitai "https://civitai.com/api/download/models/1447787" "$MODELS_DIR/loras" "Matte_Skin_Illustrious_v4.safetensors"
download_civitai "https://civitai.com/api/download/models/2213606" "$MODELS_DIR/loras" "smooth_soft_skin.safetensors"
download_civitai "https://civitai.com/api/download/models/1835318" "$MODELS_DIR/loras" "Breast_Size_Slider.safetensors"
download_civitai "https://civitai.com/api/download/models/2148484" "$MODELS_DIR/loras" "Femenine_body_hq_illu.safetensors"
download_civitai "https://civitai.com/api/download/models/1384096" "$MODELS_DIR/loras" "Narrow_Waist_ILXL.safetensors"
download_civitai "https://civitai.com/api/download/models/481798"  "$MODELS_DIR/loras" "Sinozick_Style_XL_Pony.safetensors"
download_civitai "https://civitai.com/api/download/models/1047254" "$MODELS_DIR/loras" "g0th1cPXL.safetensors"
download_civitai "https://civitai.com/api/download/models/1014562" "$MODELS_DIR/loras" "Expressive_H-000001.safetensors"
download_civitai "https://civitai.com/api/download/models/1835318" "$MODELS_DIR/loras" "Breast Size Slider - Illustrious - V2_alpha1.0_rank4_noxattn_last.safetensors"
download_civitai "https://civitai.com/api/download/models/1058506" "$MODELS_DIR/loras" "Spray Tan Slider_Pony.safetensors"
download_civitai "https://civitai.com/api/download/models/2082538" "$MODELS_DIR/loras" "AmateurStyle_v3_PONY_REALISM.safetensors"
download_civitai "https://civitai.com/api/download/models/907787"  "$MODELS_DIR/loras" "amateur_photo_v2.safetensors"
download_civitai "https://civitai.com/api/download/models/870027"  "$MODELS_DIR/loras" "igbaddie-PN.safetensors"

# LoRA в подпапках
download_civitai "https://civitai.com/api/download/models/829397"  "$MODELS_DIR/loras/Pony/style"          "amateur_style_v1_pony.safetensors"
download_civitai "https://civitai.com/api/download/models/1062449" "$MODELS_DIR/loras/Pony/realistic"      "Pony Realism Slider.safetensors"
download_civitai "https://civitai.com/api/download/models/1234567" "$MODELS_DIR/loras/Illustrious/concept" "Hyper_Muscles_V4.2.safetensors"
download_civitai "https://civitai.com/api/download/models/1113756" "$MODELS_DIR/loras/Illustrious/concept" "Eyes_for_Illustrious_Lora_Perfect_anime_eyes.safetensors"
download_civitai "https://civitai.com/api/download/models/1253891" "$MODELS_DIR/loras/Illustrious/concept" "detailed hand focus style illustriousXL v1.1.safetensors"

echo "=== Готово! ==="
