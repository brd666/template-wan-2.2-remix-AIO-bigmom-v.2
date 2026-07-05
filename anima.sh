#!/bin/bash

# ==========================================
# UNIVERSAL WAN 2.2 INSTALLER (Vast.ai / Ubuntu 22/24)
# Template: anima 0.4
# ==========================================

# 1. НАСТРОЙКА ПЕРЕМЕННЫХ И ПУТЕЙ
if [ -f "/venv/main/bin/python" ]; then
    PY_EXEC="/venv/main/bin/python"
    PIP_EXEC="/venv/main/bin/pip"
    echo "✅ Найден venv python: $PY_EXEC"
else
    PY_EXEC="python3"
    PIP_EXEC="pip3"
    # Для Python 3.11+ (Ubuntu 24.04) нужен флаг прорыва системных пакетов
    if python3 -c "import sys; print(sys.version_info >= (3, 11))" | grep -q "True"; then
        EXTRA_PIP_FLAGS="--break-system-packages"
    fi
    echo "⚠️ Используем системный python3 $EXTRA_PIP_FLAGS"
fi

COMFY_DIR="/workspace/ComfyUI"
NODES_DIR="$COMFY_DIR/custom_nodes"
MODELS_DIR="$COMFY_DIR/models"

# 2. УСТАНОВКА СИСТЕМНЫХ УТИЛИТ (С защитой от сбоев сети)
echo "⚙️ Установка системных утилит..."
export DEBIAN_FRONTEND=noninteractive

# Пытаемся обновить репозитории 3 раза (на случай лагов security.ubuntu.com)
for i in {1..3}; do 
    apt-get update --fix-missing && break || (echo "Retry apt-get update..." && sleep 5)
done

apt-get install -y aria2 ffmpeg libgl1 libglx-mesa0 wget git

# 3. ПОДГОТОВКА БИБЛИОТЕК PYTHON
echo "💊 Обновление базовых библиотек..."
$PIP_EXEC install --upgrade pip $EXTRA_PIP_FLAGS
$PIP_EXEC install $EXTRA_PIP_FLAGS opencv-python-headless accelerate dynamicprompts imageio-ffmpeg onnxruntime

# 4. УСТАНОВКА CUSTOM NODES
mkdir -p "$NODES_DIR"
cd "$NODES_DIR"

install_node() {
    REPO_URL=$1
    DIR_NAME=$2
    if [ ! -d "$DIR_NAME" ]; then
        echo "⬇️ Клонирование $DIR_NAME..."
        git clone --depth 1 $REPO_URL
    else
        echo "🔄 $DIR_NAME найден, обновляю..."
        cd "$DIR_NAME" && git pull && cd ..
    fi
    
    if [ -f "$DIR_NAME/requirements.txt" ]; then
        echo "   📦 Ставлю зависимости для $DIR_NAME..."
        $PIP_EXEC install $EXTRA_PIP_FLAGS -r "$DIR_NAME/requirements.txt"
    fi
}


# 5. СКАЧИВАНИЕ МОДЕЛЕЙ (С поддержкой wget в случае провала aria2)
echo "⬇️ Скачивание моделей (Wan 2.2)..."

download_model() {
    local URL="$1"
    local FILENAME=$(echo "$2" | tr '\\' '/')
    local TARGET_DIR="$3"
    
    mkdir -p "$TARGET_DIR"
    local DIR_PART=$(dirname "$FILENAME")
    if [ "$DIR_PART" != "." ]; then
        mkdir -p "$TARGET_DIR/$DIR_PART"
    fi
    
    if [ ! -s "$TARGET_DIR/$FILENAME" ]; then
        echo "   🚀 Загрузка $FILENAME..."
        
        # Попытка №1: aria2 (многопоточность)
        if command -v aria2c &> /dev/null; then
            if [[ "$URL" =~ "civitai.com" && -n "$CIVITAI_TOKEN" ]]; then
                aria2c --console-log-level=warn --summary-interval=0 -c -x 16 -s 16 -k 1M --header="Authorization: Bearer $CIVITAI_TOKEN" "$URL" -d "$TARGET_DIR" -o "$FILENAME"
            elif [[ "$URL" =~ "huggingface.co" && -n "$HF_TOKEN" ]]; then
                aria2c --console-log-level=warn --summary-interval=0 -c -x 16 -s 16 -k 1M --header="Authorization: Bearer $HF_TOKEN" "$URL" -d "$TARGET_DIR" -o "$FILENAME"
            else
                aria2c --console-log-level=warn --summary-interval=0 -c -x 16 -s 16 -k 1M "$URL" -d "$TARGET_DIR" -o "$FILENAME"
            fi
        fi
        
        # Попытка №2: wget (если aria2 не скачал или его нет)
        if [ ! -s "$TARGET_DIR/$FILENAME" ]; then
            echo "   ⚠️ aria2 не справился, использую wget..."
            if [[ "$URL" =~ "civitai.com" && -n "$CIVITAI_TOKEN" ]]; then
                wget --header="Authorization: Bearer $CIVITAI_TOKEN" -q --show-progress -c "$URL" -P "$TARGET_DIR" -O "$TARGET_DIR/$FILENAME"
            elif [[ "$URL" =~ "huggingface.co" && -n "$HF_TOKEN" ]]; then
                wget --header="Authorization: Bearer $HF_TOKEN" -q --show-progress -c "$URL" -P "$TARGET_DIR" -O "$TARGET_DIR/$FILENAME"
            else
                wget -q --show-progress -c "$URL" -P "$TARGET_DIR" -O "$TARGET_DIR/$FILENAME"
            fi
        fi
    else
        echo "   ✅ $FILENAME уже существует и не пустой."
    fi
}

# Set CIVITAI_TOKEN from environment if present
TOKEN="${CIVITAI_TOKEN}"

download_model 'https://huggingface.co/adbrasi/wanlotest/resolve/main/Eyeful_v2-Individual.pt' 'Eyeful_v2-Individual.pt' "$MODELS_DIR/ultralytics/bbox"
download_model 'https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov9c.pt' 'face_yolov9c.pt' "$MODELS_DIR/ultralytics/bbox"
download_model 'https://huggingface.co/Nudimmud/adetailers/resolve/main/ntd11_anime_nsfw_segm_v5-variant1.pt' 'ntd11_anime_nsfw_segm_v5-variant1.pt' "$MODELS_DIR/ultralytics/segm"
download_model 'https://huggingface.co/Bingsu/adetailer/resolve/main/hand_yolov9c.pt' 'hand_yolov9c.pt' "$MODELS_DIR/ultralytics/bbox"
download_model 'https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth' '4x_foolhardy_Remacri.pth' "$MODELS_DIR/upscale_models"
download_model 'https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/sams/sam_vit_b_01ec64.pth' 'sam_vit_b_01ec64.pth' "$MODELS_DIR/sams"
download_model 'https://huggingface.co/f5aiteam/VAE/resolve/main/qwen_image_vae.safetensors' 'qwen_image_vae.safetensors' "$MODELS_DIR/vae"
download_model 'https://huggingface.co/Bingsu/adetailer/resolve/main/person_yolov8m-seg.pt' 'person_yolov8m-seg.pt' "$MODELS_DIR/ultralytics/segm"
download_model 'https://huggingface.co/Kutches/Anim4/resolve/441297abd33597506309ca63615d8a25c7041834/qwen_3_06b_base.safetensors' 'qwen_3_06b_base.safetensors' "$MODELS_DIR/text_encoders"
download_model 'https://civitai.red/api/download/models/3086321?token='$TOKEN 'novaAnimeAM_v25.safetensors' "$MODELS_DIR/diffusion_models"
download_model 'https://civitai.red/api/download/models/2988052?token='$TOKEN 'hyper_muscles_anima_v1.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/2979642?token='$TOKEN 'anima-turbo-lora-v0.2.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/3022620?token='$TOKEN 'GothicNeonAnima.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/3026718?token='$TOKEN 'background_detailer_v1anima.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/2902360?token='$TOKEN 'hyper_breastsamina.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/3031464?token='$TOKEN 'incase23_lora.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/2985705?token='$TOKEN 'Flar_ANIMA_BASE.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2817661?token='$TOKEN 'dark_art_style_Anima-step00002750.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3007041?token='$TOKEN 'purple_tarot.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3035023?token='$TOKEN 'anima_futanari_v3.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2972344?token='$TOKEN 'csr-AnimaB_V10-V2-CAME.safetensors' "$MODELS_DIR/loras"

# ==========================================
echo "✅ ВСЕ ОПЕРАЦИИ ЗАВЕРШЕНЫ!"
# ==========================================
