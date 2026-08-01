#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/data
USER_HOME=/home/user
ROOT_HOME=/root
PERSIST_USER_HOME=$DATA_DIR/home/user
PERSIST_ROOT_HOME=$DATA_DIR/root
CODEX_HOME_DIR=${CODEX_HOME:-$DATA_DIR/.codex}
RUNNER_USER=$(id -un)
RUNNER_GROUP=$(id -gn)
LEGACY_HOME_DIRS=(.config .railway .ssh)
ROOT_SHARED_DIRS=(.codex .config .railway .ssh)

replace_with_symlink() {
    local link_path=$1
    local target_path=$2

    sudo rm -rf "$link_path"
    sudo ln -s "$target_path" "$link_path"
}

seed_home() {
    local source_home=$1
    local target_home=$2

    if [ ! -d "$source_home" ] || [ -L "$source_home" ]; then
        return
    fi

    shopt -s dotglob nullglob
    for item in "$source_home"/*; do
        local name
        name=$(basename "$item")

        if [ ! -e "$target_home/$name" ] && [ ! -L "$target_home/$name" ]; then
            sudo cp -a "$item" "$target_home/$name"
        fi
    done
    shopt -u dotglob nullglob
}

seed_root_home() {
    if sudo test -d "$ROOT_HOME" && ! sudo test -L "$ROOT_HOME"; then
        sudo cp -a -n "$ROOT_HOME/." "$PERSIST_ROOT_HOME/"
    fi
}

migrate_legacy_home_dir() {
    local name=$1
    local legacy_path=$DATA_DIR/$name
    local target_path=$PERSIST_USER_HOME/$name

    if [ ! -e "$legacy_path" ] && [ ! -L "$legacy_path" ]; then
        return
    fi

    if [ ! -e "$target_path" ] && [ ! -L "$target_path" ]; then
        sudo mv "$legacy_path" "$target_path"
    elif [ -d "$legacy_path" ] && [ -d "$target_path" ]; then
        sudo cp -an "$legacy_path/." "$target_path/"
        sudo rm -rf "$legacy_path"
    fi
}

secure_codex_home() {
    local sensitive_file

    sudo chown -R "$RUNNER_USER:$RUNNER_GROUP" "$CODEX_HOME_DIR"
    sudo chmod 700 "$CODEX_HOME_DIR"

    for sensitive_file in "$CODEX_HOME_DIR/config.toml" "$CODEX_HOME_DIR/auth.json"; do
        if sudo test -f "$sensitive_file"; then
            sudo chown "$RUNNER_USER:$RUNNER_GROUP" "$sensitive_file"
            sudo chmod 600 "$sensitive_file"
        fi
    done
}

sudo mkdir -p "$DATA_DIR"
if ! grep -qs " $DATA_DIR " /proc/mounts; then
    echo "ERROR: /data is not a mounted volume. Attach a persistent volume at /data before starting Codex Anywhere." >&2
    exit 1
fi

sudo chown user:user "$DATA_DIR"
sudo mkdir -p "$PERSIST_USER_HOME" "$PERSIST_ROOT_HOME" "$CODEX_HOME_DIR"
sudo chown -R user:user "$PERSIST_USER_HOME" "$CODEX_HOME_DIR"
sudo chown -R root:root "$PERSIST_ROOT_HOME"
sudo mkdir -p "$USER_HOME"
sudo chown user:user "$USER_HOME"

for dir in "${LEGACY_HOME_DIRS[@]}"; do
    migrate_legacy_home_dir "$dir"
done

seed_home "$USER_HOME" "$PERSIST_USER_HOME"
seed_root_home

sudo mkdir -p "$PERSIST_USER_HOME/.config" "$PERSIST_USER_HOME/.local" "$PERSIST_USER_HOME/.cache" "$PERSIST_USER_HOME/.railway" "$PERSIST_USER_HOME/.ssh"
sudo chown -R user:user "$PERSIST_USER_HOME"
sudo chmod 700 "$PERSIST_USER_HOME/.ssh"

if [ -d "$PERSIST_USER_HOME/.codex" ] && [ ! -L "$PERSIST_USER_HOME/.codex" ]; then
    sudo cp -an "$PERSIST_USER_HOME/.codex/." "$CODEX_HOME_DIR/"
fi
replace_with_symlink "$PERSIST_USER_HOME/.codex" "$CODEX_HOME_DIR"
sudo chown -h user:user "$PERSIST_USER_HOME/.codex"

for dir in "${ROOT_SHARED_DIRS[@]}"; do
    if [ "$dir" = ".codex" ]; then
        replace_with_symlink "$PERSIST_ROOT_HOME/$dir" "$CODEX_HOME_DIR"
    else
        replace_with_symlink "$PERSIST_ROOT_HOME/$dir" "$PERSIST_USER_HOME/$dir"
    fi
done

replace_with_symlink "$USER_HOME" "$PERSIST_USER_HOME"
replace_with_symlink "$ROOT_HOME" "$PERSIST_ROOT_HOME"

if [ -d /opt/default-codex ]; then
    if [ ! -f "$CODEX_HOME_DIR/config.toml" ] && [ -f /opt/default-codex/config.toml ]; then
        cp /opt/default-codex/config.toml "$CODEX_HOME_DIR/config.toml"
    fi

    if [ ! -d "$CODEX_HOME_DIR/skills" ] && [ -d /opt/default-codex/skills ]; then
        cp -a /opt/default-codex/skills "$CODEX_HOME_DIR/skills"
    fi
fi

secure_codex_home

RUNNER_DIR=/data/home/user/actions-runner

if [ -x "$RUNNER_DIR/run.sh" ]; then
    cd "$RUNNER_DIR"
    exec ./run.sh
fi

cd "$DATA_DIR"
exec sleep infinity
