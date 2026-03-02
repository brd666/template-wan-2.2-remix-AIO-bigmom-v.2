#!/bin/bash

# Указываем корневую папку ComfyUI
COMFY_DIR="/workspace/ComfyUI"
CUSTOM_NODES_DIR="$COMFY_DIR/custom_nodes"
MODELS_DIR="$COMFY_DIR/models"

# Токен Civitai для приватных/NSFW моделей
CIVITAI_TOKEN="93edfd8cf30d4caf7cdb82d6a92c475b"

# Функция для обычных прямых ссылок (HuggingFace, Github)
download_file() {
    local url=$1
    local dir=$2
    local filename=$3
    echo "Скачивание $filename в $dir..."
    mkdir -p "$dir"
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M "$url" -d "$dir" -o "$filename"
}

# Функция для Civitai (читает оригинальное имя файла из заголовков)
download_civitai() {
    local url=$1
    local dir=$2
    echo "Скачивание модели с Civitai в $dir..."
    mkdir -p "$dir"
    wget --content-disposition "$url" -P "$dir"
}

echo "=== 1. Установка кастомных нод (Custom Nodes) ==="
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

echo "=== 2. Установка Python-зависимостей для нод ==="
cd "$COMFY_DIR" || exit
if [ -f "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack/install.py" ]; then
    python "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack/install.py"
fi
pip install -r "$CUSTOM_NODES_DIR/was-node-suite-comfyui/requirements.txt"
pip install -r "$CUSTOM_NODES_DIR/ComfyUI-Easy-Use/requirements.txt"

echo "=== 3. Загрузка базовых и инструментальных моделей ==="
# VAE
download_file "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors" "$MODELS_DIR/vae" "sdxl_vae.safetensors"

# Upscale
download_file "https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth" "$MODELS_DIR/upscale_models" "4x_foolhardy_Remacri.pth"

# SAM
download_file "https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth" "$MODELS_DIR/sams" "sam_vit_b_01ec64.pth"

# IP-Adapter & CLIP Vision
download_file "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin" "$MODELS_DIR/ipadapter" "ip-adapter-faceid-plusv2_sdxl.bin"
download_file "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors" "$MODELS_DIR/clip_vision" "CLIP-ViT-H-14-laion2B-s32b-b79k.safetensors"

echo "=== 4. Загрузка BBOX и SEGM моделей (Ultralytics) ==="
download_file "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8n.pt" "$MODELS_DIR/ultralytics/bbox" "head_yolov8n.pt"
download_file "https://huggingface.co/Bingsu/adetailer/resolve/main/hand_yolov8n.pt" "$MODELS_DIR/ultralytics/bbox" "hand_yolov9c.pt"

# !! ВНИМАНИЕ: Сюда нужно будет добавить прямые ссылки на твои кастомные YOLO (nipples, pussy, etc.) !!

echo "=== 5. Загрузка Checkpoints (Civitai) ==="
download_civitai "https://civitai.com/api/download/models/2703578?type=Model&format=SafeTensor&size=full&fp=fp16&token=${CIVITAI_TOKEN}" "$MODELS_DIR/checkpoints"
download_civitai "https://civitai.com/api/download/models/2167369?type=Model&format=SafeTensor&size=pruned&fp=fp16&token=${CIVITAI_TOKEN}" "$MODELS_DIR/checkpoints"

echo "=== 6. Загрузка LoRA (Civitai) ==="
download_civitai "https://civitai.com/api/download/models/2172230?type=Model&format=SafeTensor&token=${CIVITAI_TOKEN}" "$MODELS_DIR/loras"
download_civitai "https://civitai.com/api/download/models/586803?type=Model&format=SafeTensor&token=${CIVITAI_TOKEN}" "$MODELS_DIR/loras"
download_civitai "https://civitai.com/api/download/models/1387728?type=Model&format=SafeTensor&token=${CIVITAI_TOKEN}" "$MODELS_DIR/loras"
download_civitai "https://civitai.com/api/download/models/1145311?type=Model&format=SafeTensor&token=${CIVITAI_TOKEN}" "$MODELS_DIR/loras"

echo "=== Настройка завершена! ==="
