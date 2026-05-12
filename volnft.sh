#!/bin/bash

# =================================================================
# 脚本名称: volnft (修正版)
# =================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

STATE_DIR="/etc/volnft"
RULES_FILE="$STATE_DIR/rules.db"
SHORTCUT_PATH="/usr/local/bin/volnft"
NFT_TABLE="volnft_table"

# 1. 快捷键安装与保护
install_shortcut() {
    if [[ "$EUID" -ne 0 ]]; then return; fi
    local current_script=$(realpath "$0")
    # 检查是否已存在快捷键且指向不同文件
    if [ -f "$SHORTCUT_PATH" ]; then
        if [ "$(realpath "$SHORTCUT_PATH")" != "$current_script" ]; then
            echo -e "${YELLOW}[跳过] $SHORTCUT_PATH 已被其他程序占用。${PLAIN}"
            return
        fi
    fi
    ln -sf "$current_script" "$SHORTCUT_PATH"
    chmod +x "$SHORTCUT_PATH"
}

# 2. 核心：流量单位转换
format_traffic() {
    local b=${1:-0}
    if [ "$b" -lt 1024 ]; then echo "${b}B"
    elif [ "$b" -lt 1048576 ]; then echo "$(printf "%.2f" $(echo "scale=2; $b/1024" | bc))KB"
    elif [ "$b" -lt 1073741824 ]; then echo "$(printf "%.2f" $(echo "scale=2; $b/1048576" | bc))MB"
    else echo "$(printf "%.2f" $(echo "scale=2; $b/1073741824" | bc))GB"
    fi
}

# 3. 核心：应用规则 (修复语法并优化重载)
apply_rules() {
    echo -e "${YELLOW}正在热加载 nftables 规则...${PLAIN}"
    mkdir -p "$STATE_DIR"
    touch "$RULES_FILE"

    local tmp_file=$(mktemp)
    cat <<EOF > "$tmp_file"
table inet $NFT_TABLE {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
    }
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        masquerade
    }
}
EOF

    # 渲染规则与计数器
    while read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        # 假设格式: ID|协议|监听端口|目标地址|目标端口
        IFS='|' read -r rid proto lport thost tport <<< "$line"
        
        # 增量添加计数器和转发规则
        echo "add counter inet $NFT_TABLE cnt_id_$rid { packets 0 bytes 0 }" >> "$tmp_file"
        echo "add rule inet $NFT_TABLE prerouting $proto dport $lport counter name cnt_id_$rid dnat to $thost:$tport" >> "$tmp_file"
    done < "$RULES_FILE"

    if nft -f "$tmp_file"; then
        echo -e "${GREEN}规则重载完成！${PLAIN}"
    else
        echo -e "${RED}规则语法错误，请检查 $RULES_FILE${PLAIN}"
    fi
    rm -f "$tmp_file"
}

# 4. 统计展示
show_stats() {
    clear
    echo -e "${GREEN}ID\t监听端口\t目标地址\t累计流量${PLAIN}"
    echo "------------------------------------------------------------"
    local counters_json=$(nft -j list counters inet $NFT_TABLE 2>/dev/null)
    
    while read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        IFS='|' read -r rid proto lport thost tport <<< "$line"
        
        # 提取字节数 (此处为兼容性处理，若无 jq 则使用 awk)
        local bytes=$(echo "$counters_json" | grep -A 8 "cnt_id_$rid" | grep "bytes" | awk '{print $2}' | tr -d '",')
        bytes=${bytes:-0}
        
        printf "%-8s %-12s %-20s %-15s\n" "$rid" "$lport" "$thost:$tport" "$(format_traffic $bytes)"
    done < "$RULES_FILE"
    echo ""
    read -n 1 -s -r -p "按任意键返回菜单..."
}

# 5. 主菜单 (修复语法错误)
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}=== volnft 管理工具 ===${PLAIN}"
        echo -e "1. 添加规则"
        echo -e "2. 查看统计"
        echo -e "3. 应用/重载规则"
        echo -e "4. 卸载脚本"
        echo -e "0. 退出"
        echo "-----------------------"
        read -p "选择操作 [0-4]: " opt
        case "$opt" in
            1)
                echo "功能开发中：请手动编辑 $RULES_FILE"
                sleep 2
                ;;
            2)
                show_stats
                ;; # 修正点：确保这里有分号闭合
            3)
                apply_rules
                sleep 2
                ;;
            4)
                nft delete table inet $NFT_TABLE 2>/dev/null
                rm -f "$SHORTCUT_PATH"
                echo "脚本已卸载"
                exit 0
                ;;
            0)
                exit 0
                ;;
            *)
                echo -e "${RED}选择错误！${PLAIN}"
                sleep 1
                ;;
        esac
    done
}

# 启动环境检查
if ! command -v nft >/dev/null 2>&1; then
    echo -e "${RED}错误: 未检测到 nftables，请先安装。${PLAIN}"
    exit 1
fi

install_shortcut
main_menu
