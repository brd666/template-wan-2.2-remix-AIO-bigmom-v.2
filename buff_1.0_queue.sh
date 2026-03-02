#!/bin/bash

# Указываем корневую папку ComfyUI и путь к Python виртуального окружения
COMFY_DIR="/workspace/ComfyUI"
CUSTOM_NODES_DIR="$COMFY_DIR/custom_nodes"
MODELS_DIR="$COMFY_DIR/models"
VENV_PYTHON="/venv/main/bin/python"

# Токен Civitai для приватных моделей
CIVITAI_TOKEN="93edfd8cf30d4caf7cdb82d6a92c475b"

# --- ОБНОВЛЕНО: Используем только надежный wget вместо aria2c ---
download_file() {
    local url=$1
    local dir=$2
    local filename=$3
    echo "Скачивание $filename в $dir..."
    mkdir -p "$dir"
    # -c позволяет докачать файл при обрыве, -O указывает точное имя и путь
    wget -c -O "$dir/$filename" "$url"
}

# Функция для Civitai (читает оригинальное имя файла из заголовков)
download_civitai() {
    local url=$1
    local dir=$2
    echo "Скачивание модели с Civitai в $dir..."
    mkdir -p "$dir"
    wget -c --content-disposition "$url" -P "$dir"
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

echo "=== 2. Установка Python-зависимостей строго в venv ComfyUI ==="
cd "$COMFY_DIR" || exit

$VENV_PYTHON -m pip install opencv-python-headless numba dynamicprompts

if [ -f "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack/install.py" ]; then
    $VENV_PYTHON "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack/install.py"
fi

$VENV_PYTHON -m pip install -r "$CUSTOM_NODES_DIR/was-node-suite-comfyui/requirements.txt"
$VENV_PYTHON -m pip install -r "$CUSTOM_NODES_DIR/ComfyUI-Easy-Use/requirements.txt"
$VENV_PYTHON -m pip install -r "$CUSTOM_NODES_DIR/comfyui-dynamicprompts/requirements.txt"

echo "=== 3. Загрузка базовых и инструментальных моделей ==="
# VAE
download_file "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors" "$MODELS_DIR/vae" "sdxl_vae.safetensors"

# Upscale (Remacri)
download_file "https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth" "$MODELS_DIR/upscale_models" "4x_foolhardy_Remacri.pth"

# SAM
download_file "https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth" "$MODELS_DIR/sams" "sam_vit_b_01ec64.pth"

# IP-Adapter & CLIP Vision
download_file "https://huggingface.co/h94/IP-Adapter-FaceID/resolve/main/ip-adapter-faceid-plusv2_sdxl.bin" "$MODELS_DIR/ipadapter" "ip-adapter-faceid-plusv2_sdxl.bin"
download_file "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors" "$MODELS_DIR/clip_vision" "CLIP-ViT-H-14-laion2B-s32b-b79k.safetensors"

echo "=== 4. Загрузка BBOX и SEGM моделей (Ultralytics) ==="
# Стандартные детекторы (YOLO)
download_file "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov9c.pt" "$MODELS_DIR/ultralytics/bbox" "face_yolov9c.pt"
download_file "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov8n.pt" "$MODELS_DIR/ultralytics/bbox" "head_yolov8n.pt"
download_file "https://huggingface.co/Bingsu/adetailer/resolve/main/hand_yolov9c.pt" "$MODELS_DIR/ultralytics/bbox" "hand_yolov9c.pt"

# --- ВАЖНО: КАСТОМНЫЕ ДЕТЕКТОРЫ ---
# Замени 'URL_ЗДЕСЬ' на реальные ссылки. Если ссылок нет, wget просто скачает пустоту.
download_file "URL_ЗДЕСЬ" "$MODELS_DIR/ultralytics/segm" "adetailer2dMouth_v10.pt"
download_file "URL_ЗДЕСЬ" "$MODELS_DIR/ultralytics/segm" "adetailerNose_.pt"
download_file "URL_ЗДЕСЬ" "$MODELS_DIR/ultralytics/bbox" "Eyeful_v2-Paired.pt"
download_file "URL_ЗДЕСЬ" "$MODELS_DIR/ultralytics/segm" "Nipple-yoro11x_seg.pt"
download_file "URL_ЗДЕСЬ" "$MODELS_DIR/ultralytics/segm" "2DCockAndBallYolo8x.pt"
download_file "URL_ЗДЕСЬ" "$MODELS_DIR/ultralytics/segm" "pussy_yolo11s_seg_best.pt"

echo "=== 5. Загрузка Checkpoints (Civitai) ==="
download_civitai "https://civitai.com/api/download/models/2703578?type=Model&format=SafeTensor&size=full&fp=fp16&token=${CIVITAI_TOKEN}" "$MODELS_DIR/checkpoints"
download_civitai "https://civitai.com/api/download/models/2167369?type=Model&format=SafeTensor&size=pruned&fp=fp16&token=${CIVITAI_TOKEN}" "$MODELS_DIR/checkpoints"

echo "=== 6. Загрузка LoRA (Civitai) ==="
download_civitai "https://civitai.com/api/download/models/2172230?type=Model&format=SafeTensor&token=${CIVITAI_TOKEN}" "$MODELS_DIR/loras"
download_civitai "https://civitai.com/api/download/models/586803?type=Model&format=SafeTensor&token=${CIVITAI_TOKEN}" "$MODELS_DIR/loras"
download_civitai "https://civitai.com/api/download/models/1387728?type=Model&format=SafeTensor&token=${CIVITAI_TOKEN}" "$MODELS_DIR/loras"
download_civitai "https://civitai.com/api/download/models/1145311?type=Model&format=SafeTensor&token=${CIVITAI_TOKEN}" "$MODELS_DIR/loras"

echo "=== Настройка завершена! ==="
