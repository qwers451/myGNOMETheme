#!/usr/bin/env bash
# =============================================================================
# gnome-backup.sh — Полное сохранение визуальных настроек GNOME
# Использование: bash gnome-backup.sh [папка-для-архива]
# =============================================================================

# Убрано set -e, чтобы скрипт не падал из-за отдельных команд dconf
set -u

# ---------- Цвета для вывода ----------------------------------------------- #
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERR ]${RESET}  $*" >&2; }
section() { echo -e "\n${BOLD}══════ $* ══════${RESET}"; }

# ---------- Проверка DE ----------------------------------------------------- #
section "Проверка окружения"
if [[ "${XDG_CURRENT_DESKTOP:-}" != *GNOME* ]]; then
    error "Этот скрипт предназначен для GNOME (XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-не задан})"
    exit 1
fi
ok "GNOME обнаружен: $XDG_CURRENT_DESKTOP"

# ---------- Подготовка директорий ------------------------------------------ #
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="gnome-visual-backup-${TIMESTAMP}"
OUTPUT_DIR="${1:-$HOME}"
WORK_DIR="/tmp/${BACKUP_NAME}"
ARCHIVE="${OUTPUT_DIR}/${BACKUP_NAME}.tar.gz"

mkdir -p "$WORK_DIR"
info "Рабочая директория: $WORK_DIR"

# ---------- Вспомогательная функция копирования ---------------------------- #
copy_if_exists() {
    local src="$1"
    local dst="$2"
    if [[ -e "$src" ]]; then
        mkdir -p "$(dirname "$WORK_DIR/$dst")"
        cp -rL "$src" "$WORK_DIR/$dst" 2>/dev/null && ok "Скопировано: $src" || warn "Ошибка копирования: $src"
    else
        warn "Не найдено (пропускаем): $src"
    fi
}

# ---------- 1. Настройки через dconf --------------------------------------- #
section "1. Экспорт настроек dconf (GNOME)"
mkdir -p "$WORK_DIR/dconf"

info "Дамп org.gnome.desktop ..."
dconf dump /org/gnome/desktop/ > "$WORK_DIR/dconf/gnome-desktop.dconf"
ok "gnome-desktop.dconf"

info "Дамп org.gnome.shell ..."
dconf dump /org/gnome/shell/ > "$WORK_DIR/dconf/gnome-shell.dconf"
ok "gnome-shell.dconf"

info "Дамп org.gnome.mutter ..."
dconf dump /org/gnome/mutter/ > "$WORK_DIR/dconf/gnome-mutter.dconf"
ok "gnome-mutter.dconf"

info "Дамп org.gnome.settings-daemon ..."
dconf dump /org/gnome/settings-daemon/ > "$WORK_DIR/dconf/gnome-settings-daemon.dconf"
ok "gnome-settings-daemon.dconf"

info "Полный дамп /org/gnome/ ..."
dconf dump /org/gnome/ > "$WORK_DIR/dconf/gnome-full.dconf"
ok "gnome-full.dconf"

# ---------- 2. Обои --------------------------------------------------------- #
section "2. Обои рабочего стола"
mkdir -p "$WORK_DIR/wallpapers"

WALLPAPER_URI=$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null | tr -d "'" | sed "s|'||g")
WALLPAPER_URI_DARK=$(gsettings get org.gnome.desktop.background picture-uri-dark 2>/dev/null | tr -d "'" | sed "s|'||g")

save_wallpaper() {
    local uri="$1"
    local label="$2"
    if [[ -n "$uri" && "$uri" != "none" && "$uri" != "''" ]]; then
        local path
        path=$(echo "$uri" | sed 's|file://||')
        if [[ -f "$path" ]]; then
            cp "$path" "$WORK_DIR/wallpapers/" && ok "Обои ($label): $path"
        else
            warn "Файл обоев не найден ($label): $path"
        fi
    fi
}

save_wallpaper "$WALLPAPER_URI" "light"
save_wallpaper "$WALLPAPER_URI_DARK" "dark"

# Сохраняем все gsettings для фона
gsettings list-recursively org.gnome.desktop.background 2>/dev/null \
    > "$WORK_DIR/wallpapers/background-settings.txt"
ok "Настройки фона сохранены"

# ---------- 3. Темы --------------------------------------------------------- #
section "3. Темы (GTK / Shell)"
copy_if_exists "$HOME/.themes"                   "themes/user"
copy_if_exists "$HOME/.local/share/themes"       "themes/local"

# Список системных тем (сами папки не копируем — они большие)
ls /usr/share/themes/ 2>/dev/null > "$WORK_DIR/themes/system-themes-list.txt" || true
ok "Список системных тем сохранён"

# Текущая активная тема
{
    echo "gtk-theme:      $(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)"
    echo "shell-theme:    $(gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null || echo 'N/A')"
    echo "icon-theme:     $(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null)"
    echo "cursor-theme:   $(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null)"
    echo "cursor-size:    $(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null)"
    echo "font-name:      $(gsettings get org.gnome.desktop.interface font-name 2>/dev/null)"
    echo "document-font:  $(gsettings get org.gnome.desktop.interface document-font-name 2>/dev/null)"
    echo "monospace-font: $(gsettings get org.gnome.desktop.interface monospace-font-name 2>/dev/null)"
    echo "color-scheme:   $(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)"
} > "$WORK_DIR/themes/active-theme.txt"
ok "Активные темы/шрифты сохранены в active-theme.txt"

# ---------- 4. Иконки и курсоры -------------------------------------------- #
section "4. Иконки и курсоры"
copy_if_exists "$HOME/.icons"                    "icons/user"
copy_if_exists "$HOME/.local/share/icons"        "icons/local"

ls /usr/share/icons/ 2>/dev/null > "$WORK_DIR/icons/system-icons-list.txt" || true
ok "Список системных иконок сохранён"

# ---------- 5. Шрифты ------------------------------------------------------- #
section "5. Шрифты"
copy_if_exists "$HOME/.local/share/fonts"        "fonts/local"
copy_if_exists "$HOME/.fonts"                    "fonts/user"
ls /usr/share/fonts/ 2>/dev/null > "$WORK_DIR/fonts/system-fonts-list.txt" || true
ok "Пользовательские шрифты скопированы"

# ---------- 6. GTK конфигурации -------------------------------------------- #
section "6. GTK 3 / GTK 4 конфигурации"
copy_if_exists "$HOME/.config/gtk-3.0"           "config/gtk-3.0"
copy_if_exists "$HOME/.config/gtk-4.0"           "config/gtk-4.0"
copy_if_exists "$HOME/.gtkrc-2.0"                "config/gtkrc-2.0"

# ---------- 7. GNOME Shell расширения -------------------------------------- #
section "7. GNOME Shell расширения"
mkdir -p "$WORK_DIR/extensions/dconf"

EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
if [[ -d "$EXT_DIR" ]]; then
    cp -r "$EXT_DIR" "$WORK_DIR/extensions/user-extensions"
    ok "Пользовательские расширения скопированы"
fi

# Список системных расширений
ls /usr/share/gnome-shell/extensions/ 2>/dev/null \
    > "$WORK_DIR/extensions/system-extensions-list.txt" || true
ok "Список системных расширений сохранён"

# Список включённых расширений
gsettings get org.gnome.shell enabled-extensions 2>/dev/null \
    > "$WORK_DIR/extensions/enabled-extensions.txt"
ok "Список включённых расширений сохранён"

# Список отключённых расширений (явно отключённые)
gsettings get org.gnome.shell disabled-extensions 2>/dev/null \
    > "$WORK_DIR/extensions/disabled-extensions.txt" || true

# dconf дамп настроек каждого расширения
info "Экспорт настроек расширений через dconf..."
EXT_COUNT=0

# Сканируем пользовательские расширения
if [[ -d "$EXT_DIR" ]]; then
    for ext_path in "$EXT_DIR"/*/; do
        [[ -d "$ext_path" ]] || continue
        uuid=$(basename "$ext_path")
        # dconf путь для расширения
        dconf_path="/org/gnome/shell/extensions/$(echo "$uuid" | sed 's|@.*||' | tr '.' '-' | tr '_' '-')/"

        # Пробуем стандартный путь
        dump=$(dconf dump "$dconf_path" 2>/dev/null)
        if [[ -n "$dump" ]]; then
            safe_name=$(echo "$uuid" | tr '/' '_')
            echo "$dump" > "$WORK_DIR/extensions/dconf/${safe_name}.dconf"
            echo "$dconf_path" >> "$WORK_DIR/extensions/dconf/${safe_name}.dconf.path"
            ((EXT_COUNT++))
        fi
    done
fi

# Дамп всего пространства расширений целиком (запасной вариант)
dconf dump /org/gnome/shell/extensions/ 2>/dev/null \
    > "$WORK_DIR/extensions/dconf/_all-extensions.dconf"
ok "Настройки расширений экспортированы ($EXT_COUNT шт. с отдельными дампами)"

# ---------- 8. Дополнительные настройки ------------------------------------ #
section "8. Доп. настройки рабочего стола"
mkdir -p "$WORK_DIR/extra"

# Раскладки клавиатуры
gsettings get org.gnome.desktop.input-sources sources 2>/dev/null \
    > "$WORK_DIR/extra/keyboard-layouts.txt" || true

# Горячие клавиши
dconf dump /org/gnome/desktop/wm/keybindings/ 2>/dev/null \
    > "$WORK_DIR/extra/wm-keybindings.dconf"
dconf dump /org/gnome/settings-daemon/plugins/media-keys/ 2>/dev/null \
    > "$WORK_DIR/extra/media-keys.dconf"

# Ночной режим
gsettings list-recursively org.gnome.settings-daemon.plugins.color 2>/dev/null \
    > "$WORK_DIR/extra/night-light.txt" || true

# Питание и блокировка
dconf dump /org/gnome/desktop/session/ 2>/dev/null \
    > "$WORK_DIR/extra/session.dconf"

ok "Дополнительные настройки сохранены"

# ---------- 9. Метаданные --------------------------------------------------- #
section "9. Метаданные бэкапа"
{
    echo "backup_date:     $(date --iso-8601=seconds)"
    echo "hostname:        $(hostname)"
    echo "user:            $USER"
    echo "gnome_version:   $(gnome-shell --version 2>/dev/null || echo 'unknown')"
    echo "distro:          $(lsb_release -sd 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
    echo "kernel:          $(uname -r)"
} > "$WORK_DIR/metadata.txt"
ok "Метаданные записаны"

# ---------- 10. Упаковка ---------------------------------------------------- #
section "10. Создание архива"
info "Упаковка в $ARCHIVE ..."
tar -czf "$ARCHIVE" -C /tmp "$BACKUP_NAME"
ARCHIVE_SIZE=$(du -sh "$ARCHIVE" | cut -f1)
ok "Архив создан: $ARCHIVE ($ARCHIVE_SIZE)"

# Очистка
rm -rf "$WORK_DIR"
info "Временные файлы удалены"

# ---------- Итог ------------------------------------------------------------ #
section "Готово!"
echo -e " ${GREEN}${BOLD}Бэкап сохранён:${RESET} $ARCHIVE"
echo -e " ${CYAN}Размер:${RESET}        $ARCHIVE_SIZE"
echo ""
echo -e " Для восстановления:"
echo -e "   ${BOLD}bash ~/gnome-restore.sh \"$ARCHIVE\"${RESET}"
