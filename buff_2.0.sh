#!/bin/bash

COMFY_DIR="/workspace/ComfyUI"
CUSTOM_NODES_DIR="$COMFY_DIR/custom_nodes"
MODELS_DIR="$COMFY_DIR/models"
VENV_PYTHON="/venv/main/bin/python"
CIVITAI_TOKEN="93edfd8cf30d4caf7cdb82d6a92c475b"

download_file() {
    local url=$1
    local dir=$2
    local filename=$3
    echo "Скачивание $filename в $dir..."
    mkdir -p "$dir"
    wget -c -O "$dir/$filename" "$url"
}

download_civitai() {
    local url=$1
    local dir=$2
    local filename=$3
    echo "Скачивание $filename с Civitai в $dir..."
    mkdir -p "$dir"
    curl -L -H "Authorization: Bearer ${CIVITAI_TOKEN}" "$url" -o "$dir/$filename"
}

echo "=== 1. Установка кастомных нод ==="
mkdir -p "$CUSTOM_NODES_DIR"
cd "$CUSTOM_NODES_DIR" || exit

git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git
git clone https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git
git clone https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git
git clone https://github.com/rgthree/rgthree-comfy.git
git clone https://github.com/yolain/ComfyUI-Easy-Use.git
git clone https://github.com/WASasquatch/was-node-suite-comfyui.git
git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git
git clone https://github.com/adieyal/comfyui-dynamicprompts.git

echo "=== 2. Установка Python-зависимостей ==="
cd "$COMFY_DIR" || exit

$VENV_PYTHON -m pip install opencv-python-headless numba dynamicprompts piexif ultralytics dill
$VENV_PYTHON -m pip install git+https://github.com/facebookresearch/segment-anything.git

if [ -f "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack/install.py" ]; then
    $VENV_PYTHON "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack/install.py"
fi

$VENV_PYTHON -m pip install -r "$CUSTOM_NODES_DIR/was-node-suite-comfyui/requirements.txt"
$VENV_PYTHON -m pip install -r "$CUSTOM_NODES_DIR/ComfyUI-Easy-Use/requirements.txt"
$VENV_PYTHON -m pip install -r "$CUSTOM_NODES_DIR/comfyui-dynamicprompts/requirements.txt"

echo "=== 3. Загрузка базовых моделей ==="
download_file "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors" "$MODELS_DIR/vae" "sdxl_vae.safetensors"
download_file "https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth" "$MODELS_DIR/upscale_models" "4x_foolhardy_Remacri.pth"
download_file "https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth" "$MODELS_DIR/sams" "sam_vit_b_01ec64.pth"
download_file "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin" "$MODELS_DIR/ipadapter" "ip-adapter-faceid-plusv2_sdxl.bin"
download_file "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors" "$MODELS_DIR/clip_vision" "CLIP-ViT-H-14-laion2B-s32b-b79k.safetensors"

echo "=== 4. Загрузка Ultralytics моделей ==="
download_file "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov9c.pt" "$MODELS_DIR/ultralytics/bbox" "face_yolov9c.pt"
download_file "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8n.pt" "$MODELS_DIR/ultralytics/bbox" "head_yolov8n.pt"
download_file "https://huggingface.co/Bingsu/adetailer/resolve/main/hand_yolov9c.pt" "$MODELS_DIR/ultralytics/bbox" "hand_yolov9c.pt"

echo "=== 5. Загрузка Checkpoints ==="
download_civitai "https://civitai.com/api/download/models/1643845" "$MODELS_DIR/checkpoints" "illustriousRealismByKlaabu.safetensors"

echo "=== 6. Загрузка LoRA ==="
download_civitai "https://civitai.com/api/download/models/1189052" "$MODELS_DIR/loras" "incase_style_v3-1_ponyxl_ilff.safetensors"
download_civitai "https://civitai.com/api/download/models/382152" "$MODELS_DIR/loras" "Expressive_H-000001.safetensors"
download_civitai "https://civitai.com/api/download/models/1835318" "$MODELS_DIR/loras" "Breast_Size_Slider.safetensors"
download_civitai "https://civitai.com/api/download/models/2300536" "$MODELS_DIR/loras" "Hyper_Muscles_V4.2.safetensors"
download_civitai "https://civitai.com/api/download/models/1272693" "$MODELS_DIR/loras" "Spray_Tan_Slider_Pony.safetensors"
download_civitai "https://civitai.com/api/download/models/1253021" "$MODELS_DIR/loras" "Pony_Realism_Slider.safetensors"
download_civitai "https://civitai.com/api/download/models/1359711" "$MODELS_DIR/loras" "AmateurStyle_v3_PONY_REALISM.safetensors"
download_civitai "https://civitai.com/api/download/models/1755959" "$MODELS_DIR/loras" "amateur_photo_v2.safetensors"
download_civitai "https://civitai.com/api/download/models/556208" "$MODELS_DIR/loras" "igbaddie-PN.safetensors"

echo "=== Настройка завершена! ==="
