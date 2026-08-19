#!/bin/bash
set -o pipefail

# ==========================================
# UNIVERSAL WAN 2.2 INSTALLER (Vast.ai / Ubuntu 22/24)
# Template: video test enhance
# ==========================================

# 0. PREFLIGHT: проверка GPU до трат времени/денег
mkdir -p /opt/da
cat > /opt/da/gpu_health.sh <<'GPUHEALTH'
#!/bin/bash
# Проверка живости GPU. exit 0 = можно работать, exit 1 = нет (см. причину в stderr).
if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "nvidia-smi не найден — это не GPU-инстанс или драйвер не встал" >&2; exit 1
fi
nvidia-smi -L >/dev/null 2>&1 || { echo "nvidia-smi не смог опросить карту" >&2; exit 1; }
VRAM_LINE=$(nvidia-smi --query-gpu=memory.total,memory.free --format=csv,noheader,nounits 2>/dev/null)
echo "VRAM: ${VRAM_LINE:-неизвестно} МБ (всего, свободно)"
RECOVERY_ACTION=$(nvidia-smi --query-gpu=gpu_recovery_action --format=csv,noheader 2>/dev/null | tr -d '[:space:]')
if [ -n "$RECOVERY_ACTION" ] && [ "$RECOVERY_ACTION" != "None" ] && [ "$RECOVERY_ACTION" != "N/A" ]; then
    echo "GPU просит recovery action: $RECOVERY_ACTION — состояние хоста, изнутри пода не чинится" >&2; exit 1
fi
ECC_ERR=$(nvidia-smi --query-gpu=ecc.errors.uncorrected.volatile.total --format=csv,noheader,nounits 2>/dev/null | tr -d '[:space:]')
if [ -n "$ECC_ERR" ] && [ "$ECC_ERR" != "0" ] && [ "$ECC_ERR" != "N/A" ]; then
    echo "⚠️ Некорректируемые ECC-ошибки: $ECC_ERR — карта может быть нестабильна" >&2
fi
PY_PROBE=python3; command -v "$PY_PROBE" >/dev/null 2>&1 || PY_PROBE=python
if command -v "$PY_PROBE" >/dev/null 2>&1; then
    "$PY_PROBE" - <<'PYEOF'
import ctypes, sys
try:
    rc = ctypes.CDLL("libcuda.so").cuInit(0)
except OSError:
    sys.exit(0)
if rc != 0:
    print(f"cuInit вернул {rc} (не 0) — CUDA-контекст не создаётся", file=sys.stderr)
    sys.exit(1)
PYEOF
    [ $? -ne 0 ] && { echo "CUDA не инициализируется при живом nvidia-smi — GPU в нерабочем состоянии" >&2; exit 1; }
fi
exit 0
GPUHEALTH
chmod +x /opt/da/gpu_health.sh

echo "🔍 Preflight: проверяю GPU..."
if ! /opt/da/gpu_health.sh; then
    echo "❌ GPU в нерабочем состоянии, скриптом это не чинится — уничтожь инстанс и возьми другой хост." >&2
    exit 1
fi
echo "✅ Preflight пройден."

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
COMFY_VERSION='v0.26.0'
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

NODES_TOTAL=16
NODES_DONE=0
NODES_UNPINNED=0
NODES_PINNED_TOTAL=8
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
install_node 'https://github.com/Kijai/ComfyUI-WanVideoWrapper' 'ComfyUI-WanVideoWrapper' ''
install_node 'https://github.com/kijai/ComfyUI-KJNodes' 'ComfyUI-KJNodes' ''
install_node 'https://github.com/pythongosssss/ComfyUI-Custom-Scripts' 'ComfyUI-Custom-Scripts' '1.2.5'
install_node 'https://github.com/yolain/ComfyUI-Easy-Use' 'ComfyUI-Easy-Use' ''
install_node 'https://github.com/adieyal/comfyui-dynamicprompts' 'comfyui-dynamicprompts' '3f2fff32358cf39e21b8b440ca87eac9a8e2bade'
install_node 'https://github.com/WASasquatch/was-node-suite-comfyui' 'was-node-suite-comfyui' '1.0.2'
install_node 'https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite' 'ComfyUI-VideoHelperSuite' '4c7858ddd5126f7293dc3c9f6e0fc4c263cde079'
install_node 'https://github.com/ltdrdata/ComfyUI-Inspire-Pack' 'ComfyUI-Inspire-Pack' '1.23.0'
install_node 'https://github.com/Fannovel16/ComfyUI-Frame-Interpolation' 'ComfyUI-Frame-Interpolation' '1.0.6'
install_node 'https://github.com/ltdrdata/ComfyUI-Impact-Pack' 'ComfyUI-Impact-Pack' '8.28.3'
install_node 'https://github.com/aining2022/ComfyUI_Swwan' 'ComfyUI_Swwan' '1.0.2606200020'
install_node 'https://github.com/ltdrdata/ComfyUI-Manager' 'ComfyUI-Manager' ''
install_node 'https://github.com/DemonGatanjieu/Anomalous_Model_Browser' 'Anomalous_Model_Browser' ''
install_node 'https://github.com/jupo-ai/comfy-join-prompt' 'comfy-join-prompt' ''

if [ "$NODES_PINNED_TOTAL" -gt 0 ]; then
    echo "📌 Версии нод из workflow: закреплено $((NODES_PINNED_TOTAL-NODES_UNPINNED)) из $NODES_PINNED_TOTAL"
fi

# 5. СКАЧИВАНИЕ МОДЕЛЕЙ (wget, докачка до полного файла)
echo "⬇️ Скачивание моделей..."

MODELS_TOTAL=5
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

download_model 'https://civitai.red/api/download/models/3070870' 'qwen3vl_4b_fp8_scaled.safetensors' "$MODELS_DIR/text_encoders"
download_model 'https://huggingface.co/dci05049/wan-video/resolve/main/nsfw_wan_umt5-xxl_fp8_scaled.safetensors' 'nsfw_wan_umt5-xxl_fp8_scaled.safetensors' "$MODELS_DIR/text_encoders"
download_model 'https://huggingface.co/dci05049/wan-video/resolve/main/Wan2.2_Remix_NSFW_i2v_14b_high_lighting_v2.0.safetensors' 'Wan2.2_Remix_NSFW_i2v_14b_high_lighting_v2.0.safetensors' "$MODELS_DIR/diffusion_models"
download_model 'https://huggingface.co/dci05049/wan-video/resolve/main/Wan2.2_Remix_NSFW_i2v_14b_low_lighting_v2.0.safetensors' 'Wan2.2_Remix_NSFW_i2v_14b_low_lighting_v2.0.safetensors' "$MODELS_DIR/diffusion_models"
download_model 'https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors' 'wan_2.1_vae.safetensors' "$MODELS_DIR/vae"

# ==========================================
# 6. RECOVERY KIT: resume после сбоя + circuit breaker
echo "🛡️ Ставлю recovery kit..."
mkdir -p /opt/da
cat > /opt/da/comfy_watchdog.py <<'WATCHDOGPY'
#!/usr/bin/env python3
"""Watchdog для ComfyUI на Vast: детектор сбоя по логу и по застою очереди с resume прерванного job
(reactive), circuit breaker при мёртвой карте или исчерпанном бюджете рестартов. Сознательно НЕТ
планового/профилактического рестарта по памяти — см. комментарий у RUNTIME_RECOVERY_DEFAULT_ENABLED в
templates_commands.rs: исходная утечка RAM (killала ComfyUI каждые ~14 job) оказалась единичным
инцидентом на одном тяжёлом воркфлоу, а не системным дефектом, и уже самовосстанавливается существующей
инфраструктурой (supervisor autorestart + нативный recovery-хук Persistent Queue) без участия этого кода.
Источник остальных порогов — разбор суточного лога инстанса 47994363 (2026-08-19): мёртвый поток
prompt_worker держал под 5ч45м при живом HTTP, 274 job провалились за минуту при OOM-каскаде, 127
рестартов supervisor сделал за 12 минут после смерти карты. На здоровом прогоне (любой длины, любой
воркфлоу) watchdog не вмешивается — молчит, пока не увидит факт одной из этих проблем."""
import json, os, re, sqlite3, subprocess, sys, time, urllib.request

COMFY_LOG = "/workspace/ComfyUI/user/comfyui.log"
QUEUE_DB = "/workspace/ComfyUI/user/persistent_queue.sqlite3"
STATE_FILE = "/opt/da/watchdog_state.json"
METRICS_LOG = "/workspace/comfy-metrics.log"
HALTED_FILE = "/opt/da/HALTED.txt"
GPU_HEALTH = "/opt/da/gpu_health.sh"

POLL_SECONDS = 30
STALL_MINUTES = 20
RESTART_BUDGET = 3
RESTART_WINDOW_MINUTES = 60
JOB_ATTEMPTS_CAP = 3
FAULT_PATTERNS = [re.compile(p) for p in [r"Exception in thread .*prompt_worker", r"CUDA error: unspecified launch failure", r"torch.OutOfMemoryError", r"c10::AcceleratorError", r"IndexError: tuple index out of range"]]


def now():
    return time.time()


def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {"restarts": [], "log_pos": 0, "stall_since": None}


def save_state(st):
    with open(STATE_FILE, "w") as f:
        json.dump(st, f)


def comfy_port():
    m = re.search(r"--port[= ](\d+)", os.environ.get("COMFYUI_ARGS", ""))
    return m.group(1) if m else "8188"


def comfy_pid(port):
    # Через прослушиваемый порт, а не через grep по argv: launcher на Vast делает `cd
    # /workspace/ComfyUI && python main.py ...`, и в cmdline процесса может не быть подстроки
    # "ComfyUI/main.py" вообще (относительный путь main.py, полный путь есть только в traceback,
    # не в argv) — такой grep рисковал молча никогда не находить процесс и держать watchdog
    # бездействующим целиком. Порт ComfyUI слушает всегда, это надёжнее.
    try:
        out = subprocess.run(["ss", "-ltnp"], capture_output=True, text=True, timeout=5).stdout
        for line in out.splitlines():
            if f":{port} " in line or line.rstrip().endswith(f":{port}"):
                m = re.search(r"pid=(\d+)", line)
                if m:
                    return m.group(1)
    except Exception:
        pass
    # ss недоступен/не root — резервный путь по имени процесса
    out = subprocess.run(["pgrep", "-f", "main.py"], capture_output=True, text=True)
    pids = [p for p in out.stdout.split() if p]
    return pids[0] if pids else None


def rss_percent(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            rss_kb = int(re.search(r"VmRSS:\s+(\d+)", f.read()).group(1))
        limit_kb = None
        for path in ("/sys/fs/cgroup/memory.max", "/sys/fs/cgroup/memory/memory.limit_in_bytes"):
            try:
                v = open(path).read().strip()
                if v.isdigit():
                    limit_kb = int(v) // 1024
                    break
            except Exception:
                continue
        if not limit_kb:
            with open("/proc/meminfo") as f:
                limit_kb = int(re.search(r"MemTotal:\s+(\d+)", f.read()).group(1))
        return rss_kb / limit_kb * 100, rss_kb
    except Exception:
        return None, None


def jobs_since_restart():
    try:
        with open(COMFY_LOG, errors="ignore") as f:
            return f.read().count("Prompt executed in")
    except Exception:
        return 0


def queue_running(port):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/queue", timeout=5) as r:
            data = json.load(r)
        return bool(data.get("queue_running"))
    except Exception:
        return None  # HTTP мог быть просто занят — не паникуем на одном промахе


def new_faults(state):
    try:
        size = os.path.getsize(COMFY_LOG)
    except Exception:
        return [], state.get("log_pos", 0)
    pos = state.get("log_pos", 0)
    if pos > size:
        pos = 0  # лог пересоздан (новый inode при рестарте supervisor'а) — читаем с начала
    with open(COMFY_LOG, errors="ignore") as f:
        f.seek(pos)
        chunk = f.read()
    return [p.pattern for p in FAULT_PATTERNS if p.search(chunk)], size


def recover_queue():
    """running/interrupted -> pending (started_at сброшен); failed -> pending пока attempts < cap.
    Таблица queue_items и статусы pending/running/completed/failed/interrupted — из server/database.py
    плагина ComfyUI-Persistent-Queue (co5dt/ComfyUI-Persistent-Queue), проверено дословно 2026-08-19,
    не угадано. Вызывается перед первым стартом и перед каждым рестартом. Persistent Queue сам умеет
    восстанавливать running -> pending при старте ComfyUI (видно в исходном логе: "PersistentQueue
    recovery: 0 running -> pending") — этот вызов на такой случай безвреден (WHERE ничего не находит),
    а даёт то, чего плагин сам не делает: ограниченный повтор failed/interrupted, чтобы один
    отравленный job не проходил через них бесконечно."""
    if not os.path.exists(QUEUE_DB):
        return
    try:
        conn = sqlite3.connect(QUEUE_DB, timeout=10)
        cols = [r[1] for r in conn.execute("PRAGMA table_info(queue_items)").fetchall()]
        if not cols:
            return  # таблицы queue_items нет — не та БД/версия плагина, не трогаем чужую схему вслепую
        if "attempts" not in cols:
            conn.execute("ALTER TABLE queue_items ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0")
        conn.execute(
            "UPDATE queue_items SET status='pending', started_at=NULL, attempts=attempts+1 "
            "WHERE status IN ('running', 'interrupted')"
        )
        conn.execute(
            "UPDATE queue_items SET status='pending', started_at=NULL, attempts=attempts+1 "
            "WHERE status='failed' AND attempts < ?",
            (JOB_ATTEMPTS_CAP,),
        )
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"[watchdog] queue_recover: {e}", file=sys.stderr)


def halt(reason):
    with open(HALTED_FILE, "w") as f:
        f.write(f"{time.ctime()}\n{reason}\n")
    subprocess.run(["supervisorctl", "stop", "comfyui"], capture_output=True)
    print(f"[watchdog] CIRCUIT BREAKER: {reason}", file=sys.stderr)


def gpu_healthy():
    return subprocess.run([GPU_HEALTH], capture_output=True).returncode == 0


def restart_comfy(state, reason):
    window_start = now() - RESTART_WINDOW_MINUTES * 60
    state["restarts"] = [t for t in state["restarts"] if t > window_start] + [now()]
    if len(state["restarts"]) > RESTART_BUDGET:
        halt(f"превышен бюджет рестартов ({RESTART_BUDGET} за {RESTART_WINDOW_MINUTES} мин) — последняя причина: {reason}")
        return False
    if not gpu_healthy():
        halt(f"GPU нездорова после сбоя — последняя причина: {reason}")
        return False
    print(f"[watchdog] рестарт ComfyUI: {reason}")
    recover_queue()
    subprocess.run(["supervisorctl", "restart", "comfyui"], capture_output=True)
    state["log_pos"] = 0
    state["stall_since"] = None
    return True


def log_metrics(pid, port):
    pct, rss_kb = (None, None) if pid is None else rss_percent(pid)
    vram = subprocess.run(
        ["nvidia-smi", "--query-gpu=memory.used,memory.total", "--format=csv,noheader,nounits"],
        capture_output=True, text=True,
    ).stdout.strip()
    line = f"{time.ctime()} rss={rss_kb}KB({pct}%) vram={vram} queue_running={queue_running(port)} jobs={jobs_since_restart()}\n"
    with open(METRICS_LOG, "a") as f:
        f.write(line)


def main():
    if os.path.exists(HALTED_FILE):
        print("[watchdog] HALTED.txt присутствует — жду ручной проверки, не пытаюсь рестартовать.")
        while True:
            time.sleep(POLL_SECONDS)
    state = load_state()
    recover_queue()  # хук перед первым стартом — тот же смысл, что ручной хук владельца в расследовании
    while True:
        time.sleep(POLL_SECONDS)
        if os.path.exists(HALTED_FILE):
            continue
        port = comfy_port()
        pid = comfy_pid(port)
        log_metrics(pid, port)
        if pid is None:
            continue  # ComfyUI между попытками supervisor'а поднять процесс — в этом такте не мешаем
        faults, new_pos = new_faults(state)
        state["log_pos"] = new_pos
        qr = queue_running(port)
        stalled = False
        if qr:
            if state.get("stall_since") is None:
                state["stall_since"] = now()
            elif now() - state["stall_since"] > STALL_MINUTES * 60:
                stalled = True
        else:
            state["stall_since"] = None
        if faults or stalled:
            reason = ", ".join(faults) if faults else f"очередь не движется {STALL_MINUTES} мин (похоже на мёртвый prompt_worker при живом процессе)"
            subprocess.run(["kill", "-9", pid], capture_output=True)
            restart_comfy(state, reason)
        # Намеренно НЕТ планового рестарта по памяти здесь — см. docstring модуля и комментарий у
        # RUNTIME_RECOVERY_DEFAULT_ENABLED в templates_commands.rs. rss_percent()/jobs_since_restart()
        # по-прежнему считаются в log_metrics() выше — чисто для видимости в comfy-metrics.log, ни на что
        # не влияют. На здоровом прогоне этот такт не делает ничего, кроме одной строки метрик.
        save_state(state)


if __name__ == "__main__":
    main()

WATCHDOGPY
chmod +x /opt/da/comfy_watchdog.py
rm -f /opt/da/HALTED.txt

cat > /etc/supervisor/conf.d/da-comfy-watchdog.conf <<'WATCHDOGCONF'
[program:da-comfy-watchdog]
command=python3 /opt/da/comfy_watchdog.py
autostart=true
autorestart=true
startsecs=3
stdout_logfile=/var/log/portal/da-comfy-watchdog.log
stderr_logfile=/var/log/portal/da-comfy-watchdog.log
WATCHDOGCONF

COMFYUI_CONF=/etc/supervisor/conf.d/comfyui.conf
if [ -f "$COMFYUI_CONF" ]; then
    CUR_STARTSECS=$(grep '^startsecs=' "$COMFYUI_CONF" | head -1 | cut -d= -f2)
    if [ -n "$CUR_STARTSECS" ] && [ "$CUR_STARTSECS" -lt 10 ] 2>/dev/null; then
        sed -i "s/^startsecs=.*/startsecs=10/" "$COMFYUI_CONF"
        echo "🔧 comfyui.conf: startsecs $CUR_STARTSECS → 10"
    fi
    grep -q '^startretries=' "$COMFYUI_CONF" || echo "startretries=1000" >> "$COMFYUI_CONF"
else
    echo "⚠️ $COMFYUI_CONF не найден — startsecs/startretries не проверены (образ мог измениться)" >&2
fi

if command -v supervisorctl >/dev/null 2>&1; then
    supervisorctl reread >/dev/null 2>&1 || true
    supervisorctl update >/dev/null 2>&1 || true
    echo "✅ Recovery kit поставлен и запущен (da-comfy-watchdog)."
else
    echo "⚠️ supervisorctl не найден — файлы recovery kit на месте, но не подхвачены. Проверь вручную." >&2
fi

# ==========================================
echo ""
echo "📦 Модели: $OK_MODELS из $TOTAL_MODELS скачано"
if [ ${#FAILED_MODELS[@]} -gt 0 ]; then
    echo "⚠️ Не скачались:"
    for f in "${FAILED_MODELS[@]}"; do echo "   - $f"; done
fi
echo "✅ ВСЕ ОПЕРАЦИИ ЗАВЕРШЕНЫ!"
# ==========================================
