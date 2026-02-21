#!/usr/bin/env bash
set -euo pipefail

DEFAULT_SESSION_BASE="default"

require_tmux() {
  if ! command -v tmux >/dev/null 2>&1; then
    echo "未检测到 tmux，请先安装：apt-get install -y tmux"
    exit 1
  fi
}

session_exists() {
  local name="$1"
  tmux has-session -t "$name" 2>/dev/null
}

attach_or_switch() {
  local name="$1"
  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$name"
  else
    tmux attach-session -t "$name"
  fi
}

next_default_session_name() {
  if ! session_exists "$DEFAULT_SESSION_BASE"; then
    echo "$DEFAULT_SESSION_BASE"
    return 0
  fi

  local n=1
  while session_exists "${DEFAULT_SESSION_BASE}(${n})"; do
    ((n++))
  done
  echo "${DEFAULT_SESSION_BASE}(${n})"
}

create_session_from_menu() {
  local name
  read -r -p "输入新会话名（回车自动命名）: " name

  if [[ -z "$name" ]]; then
    name="$(next_default_session_name)"
    echo "使用默认名称: $name"
  fi

  if session_exists "$name"; then
    echo "会话 '$name' 已存在。请使用选项 2 进入，或换个名称重试。"
    return 1
  fi

  tmux new-session -d -s "$name" -c "$HOME"
  echo "已创建会话 '$name'，正在进入..."
  attach_or_switch "$name"
}

list_recent_sessions() {
  local fmt
  fmt="#{?session_last_attached,#{session_last_attached},0}"$'\t'"#S"
  tmux list-sessions -F "$fmt" 2>/dev/null \
    | sort -rn \
    | head -n 5 \
    | cut -f2- || true
}

list_all_sessions() {
  tmux list-sessions -F "#S" 2>/dev/null || true
}

enter_recent_session_from_menu() {
  mapfile -t sessions < <(list_recent_sessions)
  if [[ "${#sessions[@]}" -eq 0 ]]; then
    echo "当前没有可进入的会话。"
    return 0
  fi

  echo "最近 5 个会话："
  local i
  for i in "${!sessions[@]}"; do
    printf "  %d) %s\n" "$((i + 1))" "${sessions[$i]}"
  done
  echo "  0) 返回"
  read -r -p "请选择编号: " idx

  if [[ "$idx" == "0" ]]; then
    return 0
  fi
  if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#sessions[@]} )); then
    echo "输入无效。"
    return 1
  fi

  attach_or_switch "${sessions[$((idx - 1))]}"
}

parse_selection_spec() {
  local spec="$1"
  local max="$2"
  spec="${spec//[[:space:]]/}"

  [[ -n "$spec" ]] || return 1

  local -A seen=()
  local -a selected=()
  local -a parts=()
  local part start end i
  IFS=',' read -r -a parts <<< "$spec"

  for part in "${parts[@]}"; do
    [[ -n "$part" ]] || return 1

    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"
      end="${BASH_REMATCH[2]}"
      (( start >= 1 && end >= 1 && start <= end && end <= max )) || return 1
      for ((i = start; i <= end; i++)); do
        if [[ -z "${seen[$i]+x}" ]]; then
          seen[$i]=1
          selected+=("$i")
        fi
      done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      i="$part"
      (( i >= 1 && i <= max )) || return 1
      if [[ -z "${seen[$i]+x}" ]]; then
        seen[$i]=1
        selected+=("$i")
      fi
    else
      return 1
    fi
  done

  printf "%s\n" "${selected[@]}"
}

cleanup_sessions_from_menu() {
  local -a sessions=()
  mapfile -t sessions < <(list_all_sessions)
  if [[ "${#sessions[@]}" -eq 0 ]]; then
    echo "当前没有可清理的会话。"
    return 0
  fi

  echo "所有会话："
  local i
  for i in "${!sessions[@]}"; do
    printf "  %d) %s\n" "$((i + 1))" "${sessions[$i]}"
  done
  echo "支持格式: n, n-m, n,m,o, n-m,a-b, all"
  echo "输入 0 返回"

  local spec
  read -r -p "请输入要清理的编号: " spec
  spec="${spec//[[:space:]]/}"
  if [[ "$spec" == "0" ]]; then
    return 0
  fi

  local -a picked=()
  if [[ "${spec,,}" == "all" ]]; then
    for i in "${!sessions[@]}"; do
      picked+=("$((i + 1))")
    done
  else
    local parsed
    if ! parsed="$(parse_selection_spec "$spec" "${#sessions[@]}")"; then
      echo "输入格式无效。"
      return 1
    fi
    mapfile -t picked <<< "$parsed"
  fi

  if [[ "${#picked[@]}" -eq 0 ]]; then
    echo "未选择任何会话。"
    return 1
  fi

  echo "将删除以下会话："
  for i in "${picked[@]}"; do
    printf "  - %s\n" "${sessions[$((i - 1))]}"
  done

  local confirm
  read -r -p "确认删除? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "已取消。"
    return 0
  fi

  local ok=0
  local fail=0
  local name
  for i in "${picked[@]}"; do
    name="${sessions[$((i - 1))]}"
    if tmux kill-session -t "$name" 2>/dev/null; then
      echo "已删除: $name"
      ((ok++))
    else
      echo "删除失败: $name"
      ((fail++))
    fi
  done
  echo "清理完成，成功 $ok，失败 $fail。"
}

show_sessions() {
  if ! tmux ls 2>/dev/null; then
    echo "当前没有会话。"
  fi
}

main_menu() {
  while true; do
    cat <<'EOF'

==== tmux 简易助手 ====
1) 创建会话（输入名称，回车自动命名）
2) 进入已知会话（最近 5 个）
3) 查看所有会话
4) 清理会话（按编号批量删除）
0) 退出
EOF
    read -r -p "选择功能: " choice

    case "$choice" in
      1)
        create_session_from_menu
        ;;
      2)
        enter_recent_session_from_menu
        ;;
      3)
        show_sessions
        ;;
      4)
        cleanup_sessions_from_menu
        ;;
      0)
        exit 0
        ;;
      *)
        echo "无效选择，请重试。"
        ;;
    esac
  done
}

require_tmux
main_menu
