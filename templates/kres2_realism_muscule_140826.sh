#!/bin/bash
set -o pipefail

# ==========================================
# UNIVERSAL WAN 2.2 INSTALLER (Vast.ai / Ubuntu 22/24)
# Template: kres2 realism muscule
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
COMFY_VERSION='0.27.0'
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

NODES_TOTAL=17
NODES_DONE=0
NODES_UNPINNED=0
NODES_PINNED_TOTAL=12
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
install_node 'https://github.com/kijai/ComfyUI-KJNodes' 'ComfyUI-KJNodes' ''
install_node 'https://github.com/rgthree/rgthree-comfy' 'rgthree-comfy' '1.0.2606200020'
install_node 'https://github.com/PGCRT/CRT-Nodes' 'CRT-Nodes' '2.5.3'
install_node 'https://github.com/pythongosssss/ComfyUI-Custom-Scripts' 'ComfyUI-Custom-Scripts' '1.2.5'
install_node 'https://github.com/chrisgoringe/cg-use-everywhere' 'cg-use-everywhere' '7.8.0'
install_node 'https://github.com/yolain/ComfyUI-Easy-Use' 'ComfyUI-Easy-Use' ''
install_node 'https://github.com/WASasquatch/was-node-suite-comfyui' 'was-node-suite-comfyui' ''
install_node 'https://github.com/ltdrdata/was-node-suite-comfyui' 'was-node-suite-comfyui' '3.0.1'
install_node 'https://github.com/chflame163/ComfyUI_LayerStyle' 'ComfyUI_LayerStyle' '2.0.37'
install_node 'https://github.com/Azornes/Comfyui-Resolution-Master' 'Comfyui-Resolution-Master' '1.6.2'
install_node 'https://github.com/capitan01R/ComfyUI-Krea2T-Enhancer' 'ComfyUI-Krea2T-Enhancer' '75a14cb93487d0fea7985f199717da46ab5cb53d'
install_node 'https://github.com/adieyal/comfyui-dynamicprompts' 'comfyui-dynamicprompts' '3f2fff32358cf39e21b8b440ca87eac9a8e2bade'
install_node 'https://github.com/ltdrdata/ComfyUI-Impact-Pack' 'ComfyUI-Impact-Pack' '8.28.3'
install_node 'https://github.com/aining2022/ComfyUI_Swwan' 'ComfyUI_Swwan' '1.0.2606200020'
install_node 'https://github.com/jupo-ai/comfy-join-prompt' 'comfy-join-prompt' '1.3.9'

if [ "$NODES_PINNED_TOTAL" -gt 0 ]; then
    echo "📌 Версии нод из workflow: закреплено $((NODES_PINNED_TOTAL-NODES_UNPINNED)) из $NODES_PINNED_TOTAL"
fi

# 5. СКАЧИВАНИЕ МОДЕЛЕЙ (wget, докачка до полного файла)
echo "⬇️ Скачивание моделей..."

MODELS_TOTAL=12
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

download_model 'https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors' 'wan_2.1_vae.safetensors' "$MODELS_DIR/vae"
download_model 'https://civitai.red/api/download/models/3068874' 'Detailer-KREA2.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/3090634' 'Krea2-realism-V2.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/3107044' 'NB-Sora-Muscle_Krea2_weighted_noema_rank48_merged.safetensors' "$MODELS_DIR/loras"
# krea2_bigger_muscular.safetensors отключена (галочка в шаблоне) — пропущена
download_model 'https://civitai.red/api/download/models/3097834' 'skindetails_krea2_loraholic.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/3071726' 'BreastSlider-KREA2.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/3198230' 'snofs_krea_v1_3.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/3109006' 'realism_engine_krea2_v3.1.safetensors' "$MODELS_DIR/loras"
download_model 'https://civitai.red/api/download/models/3066073' 'real_3d_krea2_loraholic.safetensors' "$MODELS_DIR/loras"
download_model 'https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth' '4x_foolhardy_Remacri.pth' "$MODELS_DIR/upscale_models"
download_model 'https://civitai.red/api/download/models/3091481' 'krea2/krea2TurboOfficialComfy_krea2TurboInt8.safetensors' "$MODELS_DIR/diffusion_models"
download_model 'https://huggingface.co/alienmafio/my-krea2-loras/resolve/main/qwen3VL4BAbliteratedComfyui_v10.safetensors' 'qwen3VL4BAbliteratedComfyui_v10.safetensors' "$MODELS_DIR/text_encoders"

# ==========================================
echo ""
echo "📦 Модели: $OK_MODELS из $TOTAL_MODELS скачано"
if [ ${#FAILED_MODELS[@]} -gt 0 ]; then
    echo "⚠️ Не скачались:"
    for f in "${FAILED_MODELS[@]}"; do echo "   - $f"; done
fi
echo "✅ ВСЕ ОПЕРАЦИИ ЗАВЕРШЕНЫ!"
# ==========================================
