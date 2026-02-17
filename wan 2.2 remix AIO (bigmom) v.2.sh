#!/bin/bash

# ==========================================
# KIRILL'S WAN 2.2 REMIX SETUP (FIXED ENVIRONMENT)
# ==========================================

# 1. ОПРЕДЕЛЕНИЕ ПРАВИЛЬНОГО PYTHON
# Vast.ai часто использует venv. Проверяем его наличие.
if [ -f "/venv/main/bin/python" ]; then
    PYTHON_EXEC="/venv/main/bin/python"
    echo "✅ Обнаружено виртуальное окружение: $PYTHON_EXEC"
else
    PYTHON_EXEC="python3"
    echo "⚠️ Виртуальное окружение не найдено, используем системный python3"
fi

# Пути
COMFY_DIR="/workspace/ComfyUI"
NODES_DIR="$COMFY_DIR/custom_nodes"
MODELS_DIR="$COMFY_DIR/models"

echo "🚀 Начинаем установку (используем $PYTHON_EXEC)..."

# 2. УСТАНОВКА СИСТЕМНЫХ ЗАВИСИМОСТЕЙ
apt-get update && apt-get install -y ffmpeg aria2 libgl1-mesa-glx

# 3. ПРИНУДИТЕЛЬНАЯ УСТАНОВКА ПРОБЛЕМНЫХ БИБЛИОТЕК
# Устанавливаем их прямо в venv, чтобы избежать ошибок ModuleNotFoundError
echo "📦 Установка критических библиотек (cv2, accelerate, dynamicprompts)..."
$PYTHON_EXEC -m pip install --upgrade pip
$PYTHON_EXEC -m pip install opencv-python opencv-python-headless accelerate dynamicprompts imageio-ffmpeg

# 4. УСТАНОВКА CUSTOM NODES
cd $NODES_DIR

# Функция для клонирования и установки зависимостей
install_node() {
    REPO_URL=$1
    DIR_NAME=$2
    if [ ! -d "$DIR_NAME" ]; then
        echo "⬇️ Клонирование $DIR_NAME..."
        git clone $REPO_URL
    else
        echo "🔄 $DIR_NAME уже существует, пропускаем клонирование..."
    fi
    
    if [ -f "$DIR_NAME/requirements.txt" ]; then
        echo "   📦 Установка зависимостей для $DIR_NAME..."
        cd $DIR_NAME
        $PYTHON_EXEC -m pip install -r requirements.txt
        cd ..
    fi
}

# --- Установка нод ---
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

# 5. ЗАГРУЗКА МОДЕЛЕЙ (С проверкой, чтобы не качать заново)
echo "⬇️ Проверка и докачка моделей..."

# --- Diffusion Models ---
cd $MODELS_DIR/diffusion_models
# High Lighting
if [ ! -f "Wan2.2_Remix_NSFW_i2v_14b_high_lighting_v2.0.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M "https://huggingface.co/dci05049/wan-video/resolve/main/Wan2.2_Remix_NSFW_i2v_14b_high_lighting_v2.0.safetensors"
fi
# Low Lighting
if [ ! -f "Wan2.2_Remix_NSFW_i2v_14b_low_lighting_v2.0.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M "https://huggingface.co/dci05049/wan-video/resolve/main/Wan2.2_Remix_NSFW_i2v_14b_low_lighting_v2.0.safetensors"
fi

# --- Text Encoders ---
mkdir -p $MODELS_DIR/text_encoders
cd $MODELS_DIR/text_encoders
if [ ! -f "nsfw_wan_umt5-xxl_fp8_scaled.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M "https://huggingface.co/dci05049/wan-video/resolve/main/nsfw_wan_umt5-xxl_fp8_scaled.safetensors"
fi

# --- VAE ---
mkdir -p $MODELS_DIR/vae
cd $MODELS_DIR/vae
if [ ! -f "wan_2.1_vae.safetensors" ]; then
    aria2c --console-log-level=error -c -x 16 -s 16 -k 1M "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors"
fi

# --- LoRAs (PLACEHOLDER) ---
# Не забудь вставить ссылки, если нашел их!
cd $MODELS_DIR/loras
# aria2c ...

echo "✅ Установка завершена! Перезапусти ComfyUI (RESTART)."
