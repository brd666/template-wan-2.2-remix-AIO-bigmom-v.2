#!/bin/bash
set -o pipefail

# ==========================================
# UNIVERSAL WAN 2.2 INSTALLER (Vast.ai / Ubuntu 22/24)
# Template: anima princeofmusculer
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

if [ -d "/workspace/ComfyUI" ]; then
    COMFY_DIR="/workspace/ComfyUI"
elif [ -n "${COMFYUI_PATH:-}" ] && [ -d "${COMFYUI_PATH}" ]; then
    COMFY_DIR="${COMFYUI_PATH}"
elif [ -d "/opt/ComfyUI" ]; then
    COMFY_DIR="/opt/ComfyUI"
else
    echo "❌ ComfyUI не найден (проверены /workspace/ComfyUI, \$COMFYUI_PATH, /opt/ComfyUI)." >&2
    echo "   Задай COMFYUI_PATH в env инстанса Vast, либо проверь образ шаблона." >&2
    exit 1
fi
echo "📁 ComfyUI: $COMFY_DIR"
NODES_DIR="$COMFY_DIR/custom_nodes"
MODELS_DIR="$COMFY_DIR/models"

# 1b. ПИН ВЕРСИИ ЯДРА ComfyUI (иначе версия из образа может не совпасть с той,
#     на которой воркфлоу собран — BETA-фичи ядра меняются между релизами)
COMFY_VERSION='v0.27.0'
case "$COMFY_VERSION" in
    v*) COMFY_VERSION_ALT="${COMFY_VERSION#v}" ;;
    *)  COMFY_VERSION_ALT="v$COMFY_VERSION" ;;
esac
echo "📌 Ставлю ComfyUI версии $COMFY_VERSION (текущая: $(cd "$COMFY_DIR" && git describe --tags --always 2>/dev/null || echo неизвестна))"
COMFY_PINNED=""
(cd "$COMFY_DIR" && git fetch --tags --force origin) || echo "   ⚠️ git fetch не удался — пробую переключиться на то, что уже есть локально" >&2
if (cd "$COMFY_DIR" && git checkout --force "$COMFY_VERSION") 2>/dev/null; then
    COMFY_PINNED="$COMFY_VERSION"
elif (cd "$COMFY_DIR" && git checkout --force "$COMFY_VERSION_ALT") 2>/dev/null; then
    COMFY_PINNED="$COMFY_VERSION_ALT"
fi
if [ -n "$COMFY_PINNED" ]; then
    echo "   📦 Подтягиваю зависимости под эту версию (frontend/templates пиннятся в requirements.txt)..."
    (cd "$COMFY_DIR" && $PIP_EXEC install $EXTRA_PIP_FLAGS -r requirements.txt) || echo "   ⚠️ requirements.txt поставился не полностью — сверь версию frontend, если сабграфы поедут" >&2
    echo "✅ ComfyUI зафиксирован на $COMFY_PINNED"
else
    echo "❌ Не удалось переключить ComfyUI на $COMFY_VERSION (пробовал также $COMFY_VERSION_ALT)." >&2
    echo "   Проверь, что такой тег/коммит есть в репозитории ComfyUI (теги вида v0.27.0)." >&2
   echo "   Останавливаюсь: ноды закрепляются под ЭТУ версию ядра, и на другой они не заработают." >&2
    exit 1
fi

# 2. УСТАНОВКА СИСТЕМНЫХ УТИЛИТ (С защитой от сбоев сети)
echo "⚙️ Установка системных утилит..."
export DEBIAN_FRONTEND=noninteractive

# Пытаемся обновить репозитории 3 раза (на случай лагов security.ubuntu.com)
for i in {1..3}; do 
    apt-get update --fix-missing && break || (echo "Retry apt-get update..." && sleep 5)
done

apt-get install -y ffmpeg libgl1 libglx-mesa0 wget git

# 3. ПОДГОТОВКА БИБЛИОТЕК PYTHON
echo "💊 Обновление базовых библиотек..."
$PIP_EXEC install --upgrade pip $EXTRA_PIP_FLAGS
$PIP_EXEC install $EXTRA_PIP_FLAGS opencv-python-headless accelerate dynamicprompts imageio-ffmpeg onnxruntime

echo "🧩 ComfyUI-Manager: режим git — ставится обычной custom node ниже (нативный pip-пакет не нужен)."

# 4. УСТАНОВКА CUSTOM NODES
mkdir -p "$NODES_DIR"
cd "$NODES_DIR"

NODES_TOTAL=12
NODES_DONE=0
NODES_UNPINNED=0
NODES_PINNED_TOTAL=7
install_node() {
    REPO_URL=$1
    DIR_NAME=$2
    NODE_VER=$3
    NODES_DONE=$((NODES_DONE+1))
    echo "🔧 [$NODES_DONE/$NODES_TOTAL] Нода: $DIR_NAME"
    if [ ! -d "$DIR_NAME" ]; then
        echo "⬇️ Клонирование $DIR_NAME..."
        git clone --depth 1 --progress $REPO_URL
    else
        echo "🔄 $DIR_NAME найден, обновляю..."
        (cd "$DIR_NAME" && CUR_BRANCH=$(git rev-parse --abbrev-ref HEAD) && git fetch --depth 1 --progress origin "$CUR_BRANCH" && git reset --hard "origin/$CUR_BRANCH") || echo "   ⚠️ $DIR_NAME: обновление не удалось, использую версию с диска как есть" >&2
    fi
    
    if [ -n "$NODE_VER" ]; then
        echo "   📌 Ставлю версию из workflow: $NODE_VER"
        case "$NODE_VER" in
            v*) NODE_VER_ALT="${NODE_VER#v}" ;;
            *)  NODE_VER_ALT="v$NODE_VER" ;;
        esac
        if (cd "$DIR_NAME" && git fetch --depth 1 --force origin "$NODE_VER" && git checkout --force FETCH_HEAD) 2>/dev/null; then
            echo "   ✅ $DIR_NAME → $NODE_VER"
        elif (cd "$DIR_NAME" && git fetch --depth 1 --force origin "$NODE_VER_ALT" && git checkout --force FETCH_HEAD) 2>/dev/null; then
            echo "   ✅ $DIR_NAME → $NODE_VER_ALT"
        else
            echo "   ⚠️ $DIR_NAME: версия $NODE_VER в репозитории не найдена — остаюсь на последней" >&2
            NODES_UNPINNED=$((NODES_UNPINNED+1))
        fi
    fi
    
    if [ -f "$DIR_NAME/requirements.txt" ]; then
        echo "   📦 Ставлю зависимости для $DIR_NAME..."
        $PIP_EXEC install $EXTRA_PIP_FLAGS -r "$DIR_NAME/requirements.txt"
    fi
    echo "📊 Прогресс нод: $NODES_DONE/$NODES_TOTAL"
}

install_node 'https://github.com/Comfy-Org/ComfyUI-Manager' 'ComfyUI-Manager' ''
install_node 'https://github.com/willmiao/ComfyUI-Lora-Manager' 'ComfyUI-Lora-Manager' ''
install_node 'https://github.com/ltdrdata/ComfyUI-Impact-Pack' 'ComfyUI-Impact-Pack' ''
install_node 'https://github.com/yolain/ComfyUI-Easy-Use' 'ComfyUI-Easy-Use' ''
install_node 'https://github.com/kijai/ComfyUI-KJNodes' 'ComfyUI-KJNodes' '50a0837f9aea602b184bbf6dbabf66ed2c7a1d22'
install_node 'https://github.com/ltdrdata/ComfyUI-Impact-Subpack' 'ComfyUI-Impact-Subpack' '74db20c95eca152a6d686c914edc0ef4e4762cb8'
install_node 'https://github.com/rgthree/rgthree-comfy' 'rgthree-comfy' ''
install_node 'https://github.com/pamparamm/ComfyUI-ppm' 'ComfyUI-ppm' '1.0.42'
install_node 'https://github.com/WASasquatch/was-node-suite-comfyui' 'was-node-suite-comfyui' 'afeee09ba44e713ec52a413ac6b105fd06b2d356'
install_node 'https://github.com/ltdrdata/was-node-suite-comfyui' 'was-node-suite-comfyui' 'afeee09ba44e713ec52a413ac6b105fd06b2d356'
install_node 'https://github.com/adieyal/comfyui-dynamicprompts' 'comfyui-dynamicprompts' '3f2fff32358cf39e21b8b440ca87eac9a8e2bade'
install_node 'https://github.com/jupo-ai/comfy-join-prompt' 'comfy-join-prompt' '1.3.9'

if [ "$NODES_PINNED_TOTAL" -gt 0 ]; then
    echo "📌 Версии нод из workflow: закреплено $((NODES_PINNED_TOTAL-NODES_UNPINNED)) из $NODES_PINNED_TOTAL"
fi

# 5. СКАЧИВАНИЕ МОДЕЛЕЙ (wget, докачка до полного файла)
echo "⬇️ Скачивание моделей..."

MODELS_TOTAL=21
TOTAL_MODELS=0
OK_MODELS=0
FAILED_MODELS=()

resolve_final_url() {
    local u="$1" hops=0 header loc hdrs
    while [ "$hops" -lt 5 ]; do
        header=""
        if { [[ "$u" == *civitai.com* ]] || [[ "$u" == *civitai.red* ]]; } && [ -n "$CIVITAI_TOKEN" ]; then
            header="Authorization: Bearer $CIVITAI_TOKEN"
        elif [[ "$u" == *huggingface.co* ]] && [ -n "$HF_TOKEN" ]; then
            header="Authorization: Bearer $HF_TOKEN"
        fi
        if [ -z "$header" ]; then
            printf '%s' "$u"
            return 0
        fi
        hdrs=$(wget --header="$header" --method=HEAD --max-redirect=0 --server-response -q -O /dev/null "$u" 2>&1)
        loc=$(printf '%s\n' "$hdrs" | grep -i 'Location:' | tail -1 | sed -E 's/.*[Ll]ocation:[[:space:]]*//' | tr -d '\r')
        if [ -z "$loc" ]; then
            printf '%s' "$u"
            return 0
        fi
        u="$loc"
        hops=$((hops+1))
    done
    printf '%s' "$u"
}

download_model() {
    local URL="$1"
    local FILENAME=$(echo "$2" | tr '\\' '/')
    local TARGET_DIR="$3"
    TOTAL_MODELS=$((TOTAL_MODELS+1))
    echo "📦 [$TOTAL_MODELS/$MODELS_TOTAL] Модель: $FILENAME"
    
    mkdir -p "$TARGET_DIR"
    local DIR_PART=$(dirname "$FILENAME")
    if [ "$DIR_PART" != "." ]; then
        mkdir -p "$TARGET_DIR/$DIR_PART"
    fi
    
    if [ ! -s "$TARGET_DIR/$FILENAME" ]; then
        echo "   🚀 Загрузка $FILENAME..."
        
        MAX_ATTEMPTS=15
        RETRY_DELAY=5
        ATTEMPT=1
        WGET_OK=0
        WGET_EXIT=0
        while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
            if [ "$ATTEMPT" -gt 1 ]; then
                echo "   🔄 Докачка $FILENAME, попытка $ATTEMPT/$MAX_ATTEMPTS..."
            fi
            DL_URL=$(resolve_final_url "$URL")
            [ -n "$DL_URL" ] || DL_URL="$URL"
            if { [[ "$DL_URL" == *civitai.com* ]] || [[ "$DL_URL" == *civitai.red* ]]; } && [ -n "$CIVITAI_TOKEN" ]; then
                wget --header="Authorization: Bearer $CIVITAI_TOKEN" --tries=3 --timeout=30 -c --show-progress "$DL_URL" -O "$TARGET_DIR/$FILENAME"
            elif [[ "$DL_URL" == *huggingface.co* ]] && [ -n "$HF_TOKEN" ]; then
                wget --header="Authorization: Bearer $HF_TOKEN" --tries=3 --timeout=30 -c --show-progress "$DL_URL" -O "$TARGET_DIR/$FILENAME"
            else
                wget --tries=3 --timeout=30 -c --show-progress "$DL_URL" -O "$TARGET_DIR/$FILENAME"
            fi
            WGET_EXIT=$?
            if [ "$WGET_EXIT" -eq 0 ] && [ -s "$TARGET_DIR/$FILENAME" ]; then
                WGET_OK=1
                break
            fi
            echo "   ⚠️ wget завершился с кодом $WGET_EXIT (попытка $ATTEMPT/$MAX_ATTEMPTS) — жду ${RETRY_DELAY}с и докачиваю дальше..." >&2
            sleep "$RETRY_DELAY"
            ATTEMPT=$((ATTEMPT+1))
        done
        if [ "$WGET_OK" -ne 1 ]; then
            echo "   ❌ $FILENAME не удалось докачать за $MAX_ATTEMPTS попыток (последний код wget: $WGET_EXIT)" >&2
            AVAIL_KB=$(df -Pk "$TARGET_DIR" 2>/dev/null | tail -1 | awk '{print $4}')
            if [ -n "$AVAIL_KB" ] && [ "$AVAIL_KB" -lt 2097152 ] 2>/dev/null; then
                echo "   💾 Похоже, кончается место на диске (свободно: $((AVAIL_KB/1024)) МБ) — проверь размер диска инстанса Vast." >&2
            fi
        fi
    else
        echo "   ✅ $FILENAME уже существует и не пустой."
    fi
    
    if [ -s "$TARGET_DIR/$FILENAME" ]; then
        OK_MODELS=$((OK_MODELS+1))
    else
        echo "   ❌ НЕ СКАЧАЛОСЬ: $FILENAME" >&2
        FAILED_MODELS+=("$FILENAME")
    fi
    echo "📊 Прогресс моделей: $TOTAL_MODELS/$MODELS_TOTAL обработано (успешно: $OK_MODELS)"
}

download_model 'https://huggingface.co/adbrasi/wanlotest/resolve/main/Eyeful_v2-Individual.pt' 'Eyeful_v2-Individual.pt' "$MODELS_DIR/ultralytics/bbox"
download_model 'https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov9c.pt' 'face_yolov9c.pt' "$MODELS_DIR/ultralytics/bbox"
download_model 'https://huggingface.co/adbrasi/wanlotest/resolve/main/ntd11_anime_nsfw_segm_v5-variant1.pt' 'ntd11_anime_nsfw_segm_v5-variant1.pt' "$MODELS_DIR/ultralytics/segm"
download_model 'https://huggingface.co/Bingsu/adetailer/resolve/main/hand_yolov9c.pt' 'hand_yolov9c.pt' "$MODELS_DIR/ultralytics/bbox"
download_model 'https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/sams/sam_vit_b_01ec64.pth' 'sam_vit_b_01ec64.pth' "$MODELS_DIR/sams"
download_model 'https://huggingface.co/f5aiteam/VAE/resolve/main/qwen_image_vae.safetensors' 'qwen_image_vae.safetensors' "$MODELS_DIR/vae"
download_model 'https://huggingface.co/AunyMoons/loras-pack/resolve/2d7675f15ab93f8270f14ae2d65c7904f3192ee7/person_yolov8m-seg.pt' 'person_yolov8m-seg.pt' "$MODELS_DIR/ultralytics/segm"
download_model 'https://huggingface.co/Kutches/Anim4/resolve/441297abd33597506309ca63615d8a25c7041834/qwen_3_06b_base.safetensors' 'qwen_3_06b_base.safetensors' "$MODELS_DIR/text_encoders"
download_model 'https://huggingface.co/alienmafio/my-krea2-loras/resolve/main/qwen3VL4BAbliteratedComfyui_v10.safetensors' 'qwen3VL4BAbliteratedComfyui_v10.safetensors' "$MODELS_DIR/text_encoders"
download_model 'https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth' '4x_foolhardy_Remacri.pth' "$MODELS_DIR/upscale_models"
download_model 'https://civitai.red/api/download/models/3031464' 'incase23_lora.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/3022620' 'GothicNeonAnima.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/2979642' 'anima-turbo-lora-v0.2.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3043931' 'turbo2_dmd2_output_proj_kaiv1.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/2902360' 'hyper_breastsamina.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/2988398' 'sinozick-anima-style.safetensors' "$MODELS_DIR/loras"
# JollyJack-Style-Anima.safetensors отключена (галочка в шаблоне) — пропущена
download_model 'https://civitai.red/api/download/models/2988052' 'hyper_muscles_anima_v1.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3035023' 'anima_futanari_v3.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.com/api/download/models/3219387' 'kot2_Matte_skin_v5_Anima.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/3026718' 'background_detailer_v1anima.safetensors' "$MODELS_DIR/loras"
# hypermuscle32x32animabaseany300.safetensors отключена (галочка в шаблоне) — пропущена
download_model 'https://civitai.red/api/download/models/3201770' 'novaAnimeAM_v40.safetensors' "$MODELS_DIR/diffusion_models"

# ==========================================
echo ""
echo "📦 Модели: $OK_MODELS из $TOTAL_MODELS скачано"
if [ ${#FAILED_MODELS[@]} -gt 0 ]; then
    echo "⚠️ Не скачались:"
    for f in "${FAILED_MODELS[@]}"; do echo "   - $f"; done
fi
echo "✅ ВСЕ ОПЕРАЦИИ ЗАВЕРШЕНЫ!"
# ==========================================
