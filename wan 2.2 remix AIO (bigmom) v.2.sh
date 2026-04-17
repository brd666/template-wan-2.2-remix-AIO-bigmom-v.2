#!/bin/bash

# ==========================================
# UNIVERSAL WAN 2.2 INSTALLER (Vast.ai / Ubuntu 22/24)
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

# libgl1 — универсальный пакет вместо устаревшего libgl1-mesa-glx
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

install_node "https://github.com/Kijai/ComfyUI-WanVideoWrapper.git" "ComfyUI-WanVideoWrapper"
install_node "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" "ComfyUI-VideoHelperSuite"
install_node "https://github.com/kijai/ComfyUI-KJNodes.git" "ComfyUI-KJNodes"
install_node "https://github.com/ltdrdata/ComfyUI-Inspire-Pack.git" "ComfyUI-Inspire-Pack"
install_node "https://github.com/yolain/ComfyUI-Easy-Use.git" "ComfyUI-Easy-Use"
install_node "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git" "ComfyUI-Frame-Interpolation"
install_node "https://github.com/adieyal/comfyui-dynamicprompts.git" "comfyui-dynamicprompts"
install_node "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git" "ComfyUI-Custom-Scripts"

# 5. СКАЧИВАНИЕ МОДЕЛЕЙ (С поддержкой wget в случае провала aria2)
echo "⬇️ Скачивание моделей (Wan 2.2)..."

download_model() {
    URL=$1
    FILENAME=$2
    TARGET_DIR=$3
    
    mkdir -p "$TARGET_DIR"
    
    if [ ! -s "$TARGET_DIR/$FILENAME" ]; then
        echo "   🚀 Загрузка $FILENAME..."
        
        # Попытка №1: aria2 (многопоточность)
        if command -v aria2c &> /dev/null; then
            aria2c --console-log-level=warn --summary-interval=0 -c -x 16 -s 16 -k 1M "$URL" -d "$TARGET_DIR" -o "$FILENAME"
        fi
        
        # Попытка №2: wget (если aria2 не скачал или его нет)
        if [ ! -s "$TARGET_DIR/$FILENAME" ]; then
            echo "   ⚠️ aria2 не справился, использую wget..."
            wget -q --show-progress -c "$URL" -P "$TARGET_DIR" -O "$TARGET_DIR/$FILENAME"
        fi
    else
        echo "   ✅ $FILENAME уже существует и не пустой."
    fi
}

# --- Checkpoints & Text Encoders ---
download_model "https://huggingface.co/dci05049/wan-video/resolve/main/Wan2.2_Remix_NSFW_i2v_14b_high_lighting_v2.0.safetensors" "Wan2.2_Remix_NSFW_i2v_14b_high_lighting_v2.0.safetensors" "$MODELS_DIR/diffusion_models"
download_model "https://huggingface.co/dci05049/wan-video/resolve/main/Wan2.2_Remix_NSFW_i2v_14b_low_lighting_v2.0.safetensors" "Wan2.2_Remix_NSFW_i2v_14b_low_lighting_v2.0.safetensors" "$MODELS_DIR/diffusion_models"
download_model "https://huggingface.co/dci05049/wan-video/resolve/main/nsfw_wan_umt5-xxl_fp8_scaled.safetensors" "nsfw_wan_umt5-xxl_fp8_scaled.safetensors" "$MODELS_DIR/text_encoders"
download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" "wan_2.1_vae.safetensors" "$MODELS_DIR/vae"

# --- LoRAs (Civitai) ---
TOKEN="081a64d161426a342030222e826cbbca"
download_model "https://civitai.com/api/download/models/2553271?token=$TOKEN" "NSFW-22-H-e8.safetensors" "$MODELS_DIR/loras"
download_model "https://civitai.com/api/download/models/2553151?token=$TOKEN" "NSFW-22-L-e8.safetensors" "$MODELS_DIR/loras"

echo "=========================================="
echo "✅ ВСЕ ОПЕРАЦИИ ЗАВЕРШЕНЫ!"
echo "=========================================="
