#!/bin/bash

# ==========================================
# FINAL FIX: WAN 2.2 INSTALLER FOR VAST.AI
# ==========================================

# 1. НАСТРОЙКА ОКРУЖЕНИЯ
# Определяем, где лежит настоящий Python для ComfyUI
if [ -f "/venv/main/bin/python" ]; then
    PY_EXEC="/venv/main/bin/python"
    PIP_EXEC="/venv/main/bin/pip"
    echo "✅ Найден venv python: $PY_EXEC"
else
    PY_EXEC="python3"
    PIP_EXEC="pip"
    echo "⚠️ Используем системный python3"
fi

COMFY_DIR="/workspace/ComfyUI"
NODES_DIR="$COMFY_DIR/custom_nodes"
MODELS_DIR="$COMFY_DIR/models"

# 2. УСТАНОВКА СИСТЕМНЫХ УТИЛИТ (ARIA2 + FFMPEG)
echo "⚙️ Установка системных утилит..."
apt-get update
apt-get install -y aria2 ffmpeg libgl1-mesa-glx

# Проверка, встал ли aria2
if ! command -v aria2c &> /dev/null; then
    echo "❌ ОШИБКА: aria2c не установился. Пробую запасной вариант..."
    apt-get install -y aria2
fi

# 3. ЛЕЧЕНИЕ БИБЛИОТЕК (CV2, ACCELERATE)
echo "💊 Лечение библиотек Python..."
$PIP_EXEC install --upgrade pip
$PIP_EXEC install opencv-python opencv-python-headless accelerate dynamicprompts imageio-ffmpeg

# 4. УСТАНОВКА CUSTOM NODES
cd $NODES_DIR

install_node() {
    REPO_URL=$1
    DIR_NAME=$2
    if [ ! -d "$DIR_NAME" ]; then
        echo "⬇️ Клонирование $DIR_NAME..."
        git clone $REPO_URL
    else
        echo "🔄 $DIR_NAME уже установлен, пропускаем."
    fi
    
    # Если есть requirements, ставим их в правильный питон
    if [ -f "$DIR_NAME/requirements.txt" ]; then
        echo "   📦 Зависимости для $DIR_NAME..."
        cd $DIR_NAME
        $PIP_EXEC install -r requirements.txt
        cd ..
    fi
}

install_node "https://github.com/Kijai/ComfyUI-WanVideoWrapper.git" "ComfyUI-WanVideoWrapper"
install_node "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" "ComfyUI-VideoHelperSuite"
install_node "https://github.com/kijai/ComfyUI-KJNodes.git" "ComfyUI-KJNodes"
install_node "https://github.com/ltdrdata/ComfyUI-Inspire-Pack.git" "ComfyUI-Inspire-Pack"
install_node "https://github.com/yolain/ComfyUI-Easy-Use.git" "ComfyUI-Easy-Use"
install_node "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git" "ComfyUI-Frame-Interpolation"
install_node "https://github.com/adieyal/comfyui-dynamicprompts.git" "comfyui-dynamicprompts"

# Custom Scripts (без requirements)
if [ ! -d "ComfyUI-Custom-Scripts" ]; then
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git
fi

# 5. СКАЧИВАНИЕ МОДЕЛЕЙ
echo "⬇️ Скачивание моделей (Wan 2.2)..."

# Функция скачивания через aria2
download_model() {
    URL=$1
    FILENAME=$2
    TARGET_DIR=$3
    
    mkdir -p "$TARGET_DIR"
    cd "$TARGET_DIR"
    
    if [ ! -f "$FILENAME" ]; then
        echo "   🚀 Качаем $FILENAME..."
        aria2c --console-log-level=error -c -x 16 -s 16 -k 1M "$URL" -o "$FILENAME"
    else
        echo "   ✅ $FILENAME уже скачан."
    fi
}

# --- Checkpoints ---
download_model "https://huggingface.co/dci05049/wan-video/resolve/main/Wan2.2_Remix_NSFW_i2v_14b_high_lighting_v2.0.safetensors" \
               "Wan2.2_Remix_NSFW_i2v_14b_high_lighting_v2.0.safetensors" \
               "$MODELS_DIR/diffusion_models"

download_model "https://huggingface.co/dci05049/wan-video/resolve/main/Wan2.2_Remix_NSFW_i2v_14b_low_lighting_v2.0.safetensors" \
               "Wan2.2_Remix_NSFW_i2v_14b_low_lighting_v2.0.safetensors" \
               "$MODELS_DIR/diffusion_models"

# --- Text Encoder (T5) ---
download_model "https://huggingface.co/dci05049/wan-video/resolve/main/nsfw_wan_umt5-xxl_fp8_scaled.safetensors" \
               "nsfw_wan_umt5-xxl_fp8_scaled.safetensors" \
               "$MODELS_DIR/text_encoders"

# --- VAE ---
download_model "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" \
               "wan_2.1_vae.safetensors" \
               "$MODELS_DIR/vae"

# --- LoRAs (Civitai API) ---
echo "⬇️ Скачивание кастомных LoRA с Civitai..."
download_model "https://civitai.com/api/download/models/2553271?type=Model&format=SafeTensor&token=081a64d161426a342030222e826cbbca" \
               "NSFW-22-H-e8.safetensors" \
               "$MODELS_DIR/loras"

download_model "https://civitai.com/api/download/models/2553151?type=Model&format=SafeTensor&token=081a64d161426a342030222e826cbbca" \
               "NSFW-22-L-e8.safetensors" \
               "$MODELS_DIR/loras"

echo "=========================================="
echo "✅ ВСЁ ГОТОВО! ПЕРЕЗАПУСТИ COMFYUI"
echo "=========================================="
