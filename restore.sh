#!/usr/bin/env bash
# =============================================================================
# gnome-restore.sh — Полное восстановление визуальных настроек GNOME
# Использование: bash gnome-restore.sh <архив.tar.gz>
# =============================================================================

set -u

# ---------- Цвета ---------------------------------------------------------- #
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERR ]${RESET}  $*" >&2; }
section() { echo -e "\n${BOLD}══════ $* ══════${RESET}"; }

# ---------- Аргументы ------------------------------------------------------- #
ARCHIVE="${1:-}"
if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
    error "Укажите путь к архиву бэкапа:"
    echo  "  bash gnome-restore.sh gnome-visual-backup-*.tar.gz"
    exit 1
fi

# ---------- Проверка DE ----------------------------------------------------- #
section "Проверка окружения"
if [[ "${XDG_CURRENT_DESKTOP:-}" != *GNOME* ]]; then
    error "Этот скрипт предназначен для GNOME (XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-не задан})"
    exit 1
fi
ok "GNOME обнаружен: $XDG_CURRENT_DESKTOP"

# ---------- Предупреждение -------------------------------------------------- #
echo -e "\n${YELLOW}${BOLD}⚠  ВНИМАНИЕ${RESET}${YELLOW}: Восстановление перезапишет текущие темы, иконки,"
echo "   расширения и настройки dconf. Продолжить? [y/N]${RESET} "
read -r confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { info "Отменено пользователем."; exit 0; }

# ---------- Распаковка ------------------------------------------------------ #
section "Распаковка архива"
WORK_DIR=$(mktemp -d /tmp/gnome-restore-XXXXXX)
info "Распаковка $ARCHIVE → $WORK_DIR ..."
tar -xzf "$ARCHIVE" -C "$WORK_DIR" --strip-components=1
ok "Распаковано"

# Читаем метаданные
if [[ -f "$WORK_DIR/metadata.txt" ]]; then
    echo ""
    echo -e "${BOLD}Информация о бэкапе:${RESET}"
    cat "$WORK_DIR/metadata.txt" | sed 's/^/  /'
    echo ""
fi

# ---------- Вспом. функция копирования ------------------------------------- #
restore_dir() {
    local src_rel="$1"   # путь внутри архива
    local dst="$2"       # абсолютный путь назначения
    local src="$WORK_DIR/$src_rel"
    if [[ -e "$src" ]]; then
        mkdir -p "$dst"
        # Копируем содержимое, не саму папку
        cp -rf "$src"/. "$dst/" 2>/dev/null && ok "Восстановлено: $dst" || warn "Ошибка восстановления: $dst"
    else
        warn "Не найдено в архиве: $src_rel (пропускаем)"
    fi
}

# ---------- 1. Темы --------------------------------------------------------- #
section "1. Темы"
restore_dir "themes/user"    "$HOME/.themes"
restore_dir "themes/local"   "$HOME/.local/share/themes"

if [[ -f "$WORK_DIR/themes/system-themes-list.txt" ]]; then
    echo -e "\n  ${YELLOW}Системные темы из /usr/share/themes/ (не восстанавливаются автоматически):${RESET}"
    cat "$WORK_DIR/themes/system-themes-list.txt" | sed 's/^/    • /'
fi

# ---------- 2. Иконки и курсоры -------------------------------------------- #
section "2. Иконки и курсоры"
restore_dir "icons/user"     "$HOME/.icons"
restore_dir "icons/local"    "$HOME/.local/share/icons"

if [[ -f "$WORK_DIR/icons/system-icons-list.txt" ]]; then
    echo -e "\n  ${YELLOW}Системные иконки из /usr/share/icons/ (не восстанавливаются автоматически):${RESET}"
    cat "$WORK_DIR/icons/system-icons-list.txt" | sed 's/^/    • /'
fi

# ---------- 3. Шрифты ------------------------------------------------------- #
section "3. Шрифты"
restore_dir "fonts/local"    "$HOME/.local/share/fonts"
restore_dir "fonts/user"     "$HOME/.fonts"

# Обновляем кэш шрифтов
if command -v fc-cache &>/dev/null; then
    fc-cache -fv &>/dev/null && ok "Кэш шрифтов обновлён (fc-cache)"
fi

# ---------- 4. GTK конфигурации -------------------------------------------- #
section "4. GTK конфигурации"
restore_dir "config/gtk-3.0"  "$HOME/.config/gtk-3.0"
restore_dir "config/gtk-4.0"  "$HOME/.config/gtk-4.0"
[[ -f "$WORK_DIR/config/gtkrc-2.0" ]] && cp "$WORK_DIR/config/gtkrc-2.0" "$HOME/.gtkrc-2.0" && ok "gtkrc-2.0"

# ---------- 5. Расширения --------------------------------------------------- #
section "5. GNOME Shell расширения"

EXT_DEST="$HOME/.local/share/gnome-shell/extensions"
mkdir -p "$EXT_DEST"

if [[ -d "$WORK_DIR/extensions/user-extensions" ]]; then
    cp -rf "$WORK_DIR/extensions/user-extensions"/. "$EXT_DEST/"
    ok "Пользовательские расширения восстановлены → $EXT_DEST"
fi

if [[ -f "$WORK_DIR/extensions/system-extensions-list.txt" ]]; then
    echo -e "\n  ${YELLOW}Системные расширения (требуют установки вручную или через пакетный менеджер):${RESET}"
    cat "$WORK_DIR/extensions/system-extensions-list.txt" | sed 's/^/    • /'
fi

# ---------- 6. Обои --------------------------------------------------------- #
section "6. Обои"
WALLPAPER_DIR="$HOME/.local/share/backgrounds/restored"
mkdir -p "$WALLPAPER_DIR"

if [[ -d "$WORK_DIR/wallpapers" ]]; then
    # Копируем файлы обоев
    find "$WORK_DIR/wallpapers" -maxdepth 1 -type f ! -name "*.txt" | while read -r wp; do
        cp "$wp" "$WALLPAPER_DIR/"
        WP_NAME=$(basename "$wp")
        WP_PATH="$WALLPAPER_DIR/$WP_NAME"
        ok "Обои восстановлены: $WP_PATH"
    done

    # Применяем обои через gsettings (берём первый файл если несколько)
    FIRST_WP=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f | head -1)
    if [[ -n "$FIRST_WP" ]]; then
        gsettings set org.gnome.desktop.background picture-uri "file://$FIRST_WP" 2>/dev/null && ok "Обои применены (light)"
        gsettings set org.gnome.desktop.background picture-uri-dark "file://$FIRST_WP" 2>/dev/null && ok "Обои применены (dark)" || true
    fi
fi

# ---------- 7. Настройки dconf --------------------------------------------- #
section "7. Восстановление настроек dconf"

load_dconf() {
    local file="$1"
    local path="$2"
    if [[ -f "$WORK_DIR/dconf/$file" && -s "$WORK_DIR/dconf/$file" ]]; then
        dconf load "$path" < "$WORK_DIR/dconf/$file" && ok "dconf загружен: $path" || warn "Ошибка загрузки dconf: $path"
    fi
}

load_dconf "gnome-desktop.dconf"          "/org/gnome/desktop/"
load_dconf "gnome-shell.dconf"            "/org/gnome/shell/"
load_dconf "gnome-mutter.dconf"           "/org/gnome/mutter/"
load_dconf "gnome-settings-daemon.dconf"  "/org/gnome/settings-daemon/"

# ---------- 8. Настройки расширений ---------------------------------------- #
section "8. Настройки расширений"

DCONF_EXT_ALL="$WORK_DIR/extensions/dconf/_all-extensions.dconf"
if [[ -f "$DCONF_EXT_ALL" && -s "$DCONF_EXT_ALL" ]]; then
    dconf load /org/gnome/shell/extensions/ < "$DCONF_EXT_ALL" \
        && ok "Настройки всех расширений загружены" \
        || warn "Ошибка загрузки настроек расширений"
fi

# Также загружаем индивидуальные дампы (если были сохранены)
if [[ -d "$WORK_DIR/extensions/dconf" ]]; then
    for dconf_file in "$WORK_DIR/extensions/dconf"/*.dconf; do
        [[ -f "$dconf_file" ]] || continue
        base=$(basename "$dconf_file" .dconf)
        [[ "$base" == "_all-extensions" ]] && continue
        path_file="${dconf_file}.path"
        if [[ -f "$path_file" ]]; then
            dconf_path=$(cat "$path_file")
            dconf load "$dconf_path" < "$dconf_file" 2>/dev/null || true
        fi
    done
fi

# ---------- 9. Дополнительные настройки ------------------------------------ #
section "9. Дополнительные настройки"

load_extra_dconf() {
    local file="$1"
    local path="$2"
    if [[ -f "$WORK_DIR/extra/$file" && -s "$WORK_DIR/extra/$file" ]]; then
        dconf load "$path" < "$WORK_DIR/extra/$file" && ok "dconf загружен: $path" || warn "Ошибка: $path"
    fi
}

load_extra_dconf "wm-keybindings.dconf"  "/org/gnome/desktop/wm/keybindings/"
load_extra_dconf "media-keys.dconf"      "/org/gnome/settings-daemon/plugins/media-keys/"
load_extra_dconf "session.dconf"         "/org/gnome/desktop/session/"

# ---------- 10. Явное применение визуальных настроек ----------------------- #
section "10. Применение тем, иконок, курсора, цветовой схемы"

THEME_FILE="$WORK_DIR/themes/active-theme.txt"

# Вспомогательная функция: читает значение из active-theme.txt и убирает кавычки
get_theme_val() {
    local key="$1"
    grep "^${key}:" "$THEME_FILE" 2>/dev/null | sed "s/^${key}: *//" | tr -d "'" | xargs
}

apply_gsetting() {
    local schema="$1" key="$2" value="$3" label="$4"
    if [[ -n "$value" && "$value" != "N/A" ]]; then
        gsettings set "$schema" "$key" "$value" 2>/dev/null \
            && ok "$label → $value" \
            || warn "Не удалось применить $label ($value)"
    fi
}

if [[ -f "$THEME_FILE" ]]; then
    GTK_THEME=$(get_theme_val "gtk-theme")
    ICON_THEME=$(get_theme_val "icon-theme")
    CURSOR_THEME=$(get_theme_val "cursor-theme")
    CURSOR_SIZE=$(get_theme_val "cursor-size")
    COLOR_SCHEME=$(get_theme_val "color-scheme")
    FONT_NAME=$(get_theme_val "font-name")
    DOC_FONT=$(get_theme_val "document-font")
    MONO_FONT=$(get_theme_val "monospace-font")
    SHELL_THEME=$(get_theme_val "shell-theme")

    apply_gsetting org.gnome.desktop.interface gtk-theme          "$GTK_THEME"    "GTK тема"
    apply_gsetting org.gnome.desktop.interface icon-theme         "$ICON_THEME"   "Иконки"
    apply_gsetting org.gnome.desktop.interface cursor-theme       "$CURSOR_THEME" "Курсор"
    apply_gsetting org.gnome.desktop.interface cursor-size        "$CURSOR_SIZE"  "Размер курсора"
    apply_gsetting org.gnome.desktop.interface color-scheme       "$COLOR_SCHEME" "Цветовая схема"
    apply_gsetting org.gnome.desktop.interface font-name          "$FONT_NAME"    "Шрифт интерфейса"
    apply_gsetting org.gnome.desktop.interface document-font-name "$DOC_FONT"     "Шрифт документов"
    apply_gsetting org.gnome.desktop.interface monospace-font-name "$MONO_FONT"   "Моно-шрифт"

    # Shell тема (через расширение user-theme)
    if [[ -n "$SHELL_THEME" && "$SHELL_THEME" != "N/A" ]]; then
        gsettings set org.gnome.shell.extensions.user-theme name "$SHELL_THEME" 2>/dev/null \
            && ok "Shell тема → $SHELL_THEME" \
            || warn "Shell тема не применена (возможно, расширение user-theme не активно)"
    fi
else
    warn "Файл active-theme.txt не найден — пропускаем явное применение тем"
fi

# ---------- 11. Включение расширений --------------------------------------- #
section "11. Включение расширений"

if [[ -f "$WORK_DIR/extensions/enabled-extensions.txt" ]]; then
    # Восстанавливаем список включённых расширений напрямую через gsettings
    ENABLED=$(cat "$WORK_DIR/extensions/enabled-extensions.txt")
    if [[ -n "$ENABLED" && "$ENABLED" != "@as []" ]]; then
        gsettings set org.gnome.shell enabled-extensions "$ENABLED" 2>/dev/null \
            && ok "Список включённых расширений восстановлен" \
            || warn "Не удалось восстановить список расширений"

        # Попытка включить каждое расширение через CLI
        if command -v gnome-extensions &>/dev/null; then
            # Парсим UUID из gsettings формата ['ext1', 'ext2', ...]
            echo "$ENABLED" | tr -d "[]'" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | while read -r uuid; do
                [[ -z "$uuid" ]] && continue
                gnome-extensions enable "$uuid" 2>/dev/null && info "Включено: $uuid" || warn "Не удалось включить: $uuid"
            done
        fi
    fi
fi

# ---------- 12. Обновление кэшей ------------------------------------------- #
section "12. Обновление кэшей"

if command -v gtk-update-icon-cache &>/dev/null; then
    find "$HOME/.local/share/icons" "$HOME/.icons" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | while read -r icon_dir; do
        gtk-update-icon-cache -f -t "$icon_dir" &>/dev/null && info "Кэш иконок: $icon_dir" || true
    done
    ok "Кэши иконок обновлены"
fi

# ---------- Очистка --------------------------------------------------------- #
rm -rf "$WORK_DIR"
info "Временные файлы удалены"

# ---------- Итог ------------------------------------------------------------ #
section "Восстановление завершено!"
echo -e " ${GREEN}${BOLD}Все визуальные настройки GNOME восстановлены.${RESET}"
echo ""
echo -e " ${YELLOW}Рекомендуется:${RESET}"
echo    "  • Выйти из сессии и войти снова для полного применения всех изменений"
echo    "  • На Wayland: перезагрузить тему без перезапуска:"
echo    "      gnome-extensions disable user-theme@gnome-shell-extensions.gcampax.github.com"
echo    "      sleep 1"
echo    "      gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com"
echo    "  • На X11: Alt+F2 → r для перезапуска GNOME Shell"
echo    "  • Системные темы/иконки из /usr/share/... установите вручную, если нужны"
