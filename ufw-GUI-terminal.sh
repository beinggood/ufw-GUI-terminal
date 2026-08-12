#!/bin/bash
# ============================================================
#  UFW 防火墙终端图形化配置工具
#  基于 dialog，支持鼠标点击操作
#  使用方法: sudo bash ufw-gui.sh
# ============================================================

# 注意：不要加 set -e，否则 dialog 点取消（返回非0）会导致脚本直接退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ... 其余代码保持不变 ...

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[错误] 请使用 root 权限运行此脚本：sudo bash $0${NC}"
    exit 1
fi

# 检查 dialog 是否安装
if ! command -v dialog &> /dev/null; then
    echo -e "${RED}[错误] 未安装 dialog，请先安装：apt install dialog / dnf install dialog${NC}"
    exit 1
fi

# 检查 ufw 是否安装
if ! command -v ufw &> /dev/null; then
    dialog --title "错误" --msgbox "未检测到 ufw，请先安装：\n\n  apt install ufw (Debian/Ubuntu)\n  dnf install ufw (Fedora/RHEL)" 10 50
    exit 1
fi

# 日志文件
LOG_FILE="/tmp/ufw-gui-commands.log"
> "$LOG_FILE"

# ============================================================
#  记录生成的命令
# ============================================================
log_cmd() {
    echo "$1" >> "$LOG_FILE"
}

# ============================================================
#  主菜单
# ============================================================
main_menu() {
    while true; do
        choice=$(dialog --clear --title " UFW 防火墙图形化配置工具" \
            --menu "\n请选择操作（支持鼠标点击）：" 24 65 14 \
            "1" " 查看防火墙状态" \
            "2" " 启用 / 禁用防火墙" \
            "3" "️  设置默认策略" \
            "4" " 添加放行规则（端口）" \
            "5" " 添加服务预设规则" \
            "6" " 添加拒绝规则" \
            "7" " 查看已有规则列表" \
            "8" "️  删除规则" \
            "9" " 备份规则" \
            "10" " 恢复规则" \
            "11" " 查看命令日志" \
            "12" " 重置防火墙" \
            "0" " 退出" \
            3>&1 1>&2 2>&3)

        exit_status=$?
        if [ $exit_status -ne 0 ]; then
            break
        fi

        case $choice in
            1)  show_status ;;
            2)  toggle_firewall ;;
            3)  set_default_policy ;;
            4)  add_allow_rule ;;
            5)  add_service_rule ;;
            6)  add_deny_rule ;;
            7)  show_rules ;;
            8)  delete_rule ;;
            9)  backup_rules ;;
            10) restore_rules ;;
            11) show_log ;;
            12) reset_firewall ;;
            0)  exit 0 ;;
        esac
    done
}

# ============================================================
#  查看状态
# ============================================================
show_status() {
    status_output=$(ufw status verbose 2>&1 | sed -r "s/\x1B\[[0-9;]*[a-zA-Z]//g")
    dialog --title "防火墙状态" --scrolltext --msgbox "$status_output" 20 70
}

# ============================================================
#  启用/禁用
# ============================================================
toggle_firewall() {
    while true; do
        choice=$(dialog --title "启用/禁用防火墙" \
            --menu "请选择操作：" 12 50 4 \
            "1" "启用防火墙 (ufw enable)" \
            "2" "禁用防火墙 (ufw disable)" \
            "0" "返回" \
            3>&1 1>&2 2>&3) || return

        case $choice in
            1)
                ufw --force enable
                log_cmd "ufw --force enable"
                dialog --title "完成" --msgbox "防火墙已启用！" 8 40
                ;;
            2)
                ufw disable
                log_cmd "ufw disable"
                dialog --title "完成" --msgbox "防火墙已禁用！" 8 40
                ;;
            0|"")
                return
                ;;
        esac
    done
}

# ============================================================
#  设置默认策略
# ============================================================
set_default_policy() {
    while true; do
        choice=$(dialog --title "设置默认策略" \
            --menu "入站流量默认策略：" 12 50 4 \
            "1" "默认拒绝所有入站 (deny) - 推荐" \
            "2" "默认拒绝并记录 (reject)" \
            "3" "默认允许所有入站 (allow)" \
            "0" "返回" \
            3>&1 1>&2 2>&3) || return

        case $choice in
            1)
                ufw default deny incoming
                log_cmd "ufw default deny incoming"
                dialog --title "完成" --msgbox "默认入站策略已设为：deny" 8 45
                ;;
            2)
                ufw default reject incoming
                log_cmd "ufw default reject incoming"
                dialog --title "完成" --msgbox "默认入站策略已设为：reject" 8 45
                ;;
            3)
                ufw default allow incoming
                log_cmd "ufw default allow incoming"
                dialog --title "完成" --msgbox "默认入站策略已设为：allow" 8 45
                ;;
            0|"")
                return
                ;;
        esac
    done
}

# ============================================================
#  添加放行规则
# ============================================================
add_allow_rule() {
    while true; do
        # 选择协议
        proto=$(dialog --title "添加放行规则" \
            --menu "选择协议类型：" 12 50 4 \
            "tcp" "TCP" \
            "udp" "UDP" \
            "both" "TCP + UDP（同时放行）" \
            3>&1 1>&2 2>&3) || return

        # 输入端口
        port=$(dialog --title "添加放行规则" \
            --inputbox "请输入端口号（如 80 或 8080:8090）：" 10 50 \
            3>&1 1>&2 2>&3) || return

        if [ -z "$port" ]; then
            dialog --title "错误" --msgbox "端口不能为空！" 8 40
            continue
        fi

        # 可选：指定来源 IP
        source_ip=$(dialog --title "添加放行规则" \
            --inputbox "指定来源 IP（留空表示允许所有来源）：\n例如：192.168.1.0/24" 10 55 \
            3>&1 1>&2 2>&3) || return

        # 构建命令 —— 处理 both 的情况
        if [ "$proto" = "both" ]; then
            if [ -n "$source_ip" ]; then
                cmd_tcp="ufw allow from $source_ip to any port $port proto tcp"
                cmd_udp="ufw allow from $source_ip to any port $port proto udp"
            else
                cmd_tcp="ufw allow $port/tcp"
                cmd_udp="ufw allow $port/udp"
            fi
            cmd_display="$cmd_tcp\n$cmd_udp"

            confirm=$(dialog --title "确认规则" \
                --yesno "即将执行以下命令：\n\n  $cmd_display\n\n是否继续？" 14 65 \
                3>&1 1>&2 2>&3)

            if [ $? -eq 0 ]; then
                eval $cmd_tcp
                eval $cmd_udp
                log_cmd "$cmd_tcp"
                log_cmd "$cmd_udp"
                dialog --title "成功" --msgbox "规则已添加（TCP + UDP）：\n\n  $cmd_display" 12 65
            fi
        else
            if [ -n "$source_ip" ]; then
                cmd="ufw allow from $source_ip to any port $port proto $proto"
            else
                cmd="ufw allow $port/$proto"
            fi

            confirm=$(dialog --title "确认规则" \
                --yesno "即将执行以下命令：\n\n  $cmd\n\n是否继续？" 12 60 \
                3>&1 1>&2 2>&3)

            if [ $? -eq 0 ]; then
                eval $cmd
                log_cmd "$cmd"
                dialog --title "成功" --msgbox "规则已添加：\n\n  $cmd" 10 60
            fi
        fi
        return  # 添加完一条规则后返回主菜单
    done
}

# ============================================================
#  服务预设规则
# ============================================================
add_service_rule() {
    service=$(dialog --title "服务预设规则" \
        --menu "选择要放行的服务：" 20 55 12 \
        "SSH(22)" "SSH 远程登录 - TCP 22" \
        "HTTP(80)" "HTTP Web 服务 - TCP 80" \
        "HTTPS(443)" "HTTPS 安全 Web - TCP 443" \
        "FTP(21)" "FTP 文件传输 - TCP 21" \
        "DNS(53)" "DNS 域名解析 - UDP 53" \
        "MySQL(3306)" "MySQL 数据库 - TCP 3306" \
        "PostgreSQL(5432)" "PostgreSQL - TCP 5432" \
        "Redis(6379)" "Redis 缓存 - TCP 6379" \
        "MongoDB(27017)" "MongoDB - TCP 27017" \
        "Docker(2376)" "Docker 远程 API - TCP 2376" \
        "VNC(5900)" "VNC 远程桌面 - TCP 5900" \
        "RDP(3389)" "远程桌面 RDP - TCP 3389" \
        3>&1 1>&2 2>&3) || return

    # 提取端口和协议
    case $service in
        "SSH(22)")         port="22";     proto="tcp" ;;
        "HTTP(80)")       port="80";     proto="tcp" ;;
        "HTTPS(443)")     port="443";    proto="tcp" ;;
        "FTP(21)")        port="21";     proto="tcp" ;;
        "DNS(53)")        port="53";     proto="udp" ;;
        "MySQL(3306)")    port="3306";   proto="tcp" ;;
        "PostgreSQL(5432)") port="5432"; proto="tcp" ;;
        "Redis(6379)")    port="6379";   proto="tcp" ;;
        "MongoDB(27017)") port="27017";  proto="tcp" ;;
        "Docker(2376)")   port="2376";   proto="tcp" ;;
        "VNC(5900)")      port="5900";   proto="tcp" ;;
        "RDP(3389)")      port="3389";   proto="tcp" ;;
    esac

    cmd="ufw allow $port/$proto"

    confirm=$(dialog --title "确认" \
        --yesno "即将放行服务：$service\n\n  命令：$cmd\n\n是否继续？" 12 55 \
        3>&1 1>&2 2>&3)

    if [ $? -eq 0 ]; then
        eval $cmd
        log_cmd "$cmd"
        dialog --title "成功" --msgbox "已放行：$service\n\n  $cmd" 10 55
    fi
}

# ============================================================
#  添加拒绝规则
# ============================================================
add_deny_rule() {
    while true; do
        port=$(dialog --title "添加拒绝规则" \
            --inputbox "请输入要拒绝的端口号：" 10 50 \
            3>&1 1>&2 2>&3) || return

        if [ -z "$port" ]; then
            dialog --title "错误" --msgbox "端口不能为空！" 8 40
            continue
        fi

        proto=$(dialog --title "添加拒绝规则" \
            --menu "选择协议：" 12 50 3 \
            "tcp" "TCP" \
            "udp" "UDP" \
            "both" "TCP + UDP（同时拒绝）" \
            3>&1 1>&2 2>&3) || return

        if [ "$proto" = "both" ]; then
            cmd_tcp="ufw deny $port/tcp"
            cmd_udp="ufw deny $port/udp"
            cmd_display="$cmd_tcp\n$cmd_udp"

            confirm=$(dialog --title "确认" \
                --yesno "即将执行：\n\n  $cmd_display\n\n是否继续？" 12 55 \
                3>&1 1>&2 2>&3)

            if [ $? -eq 0 ]; then
                eval $cmd_tcp
                eval $cmd_udp
                log_cmd "$cmd_tcp"
                log_cmd "$cmd_udp"
                dialog --title "成功" --msgbox "拒绝规则已添加（TCP + UDP）：\n\n  $cmd_display" 12 55
            fi
        else
            cmd="ufw deny $port/$proto"

            confirm=$(dialog --title "确认" \
                --yesno "即将执行：\n\n  $cmd\n\n是否继续？" 10 55 \
                3>&1 1>&2 2>&3)

            if [ $? -eq 0 ]; then
                eval $cmd
                log_cmd "$cmd"
                dialog --title "成功" --msgbox "拒绝规则已添加：\n\n  $cmd" 10 55
            fi
        fi
        return  # 添加完一条规则后返回主菜单
    done
}

# ============================================================
#  查看规则
# ============================================================
show_rules() {
    rules=$(ufw status numbered 2>&1 | sed -r "s/\x1B\[[0-9;]*[a-zA-Z]//g")
    dialog --title "当前规则列表" --scrolltext --msgbox "$rules" 22 75
}

# ============================================================
#  删除规则
# ============================================================
delete_rule() {
    while true; do
        # 1. 动态获取当前规则列表，并去掉颜色转义码防止 dialog 排版错位
        rules_raw=$(ufw status numbered 2>&1 | sed -r "s/\x1B\[[0-9;]*[a-zA-Z]//g")

        # 2. 解析规则，构建 dialog --menu 的选项列表
        menu_items=()
        while IFS= read -r line; do
            # 匹配 [数字] 开头的规则行
            if [[ "$line" =~ ^\[[[:space:]]*([0-9]+)\][[:space:]]*(.*) ]]; then
                num="${BASH_REMATCH[1]}"
                detail="${BASH_REMATCH[2]}"
                # 清理多余空格，使显示更整齐
                detail=$(echo "$detail" | sed 's/  */ /g')
                menu_items+=("$num" "$detail")
            fi
        done <<< "$rules_raw"

        # 如果没有规则，提示并返回
        if [ ${#menu_items[@]} -eq 0 ]; then
            dialog --title "提示" --msgbox "当前没有任何规则，无需删除。" 8 50
            return
        fi

        # 3. 弹出规则选择菜单（支持鼠标点击）
        selected=$(dialog --title "删除规则 - 请选择要删除的规则" \
            --menu "\n点击选中要删除的规则，然后点击「确定」：\n（点击「取消」返回主菜单）" \
            22 78 15 \
            "${menu_items[@]}" \
            3>&1 1>&2 2>&3) || return

        # 4. 从 menu_items 中找到选中规则的详细信息
        selected_detail=""
        for ((i=0; i<${#menu_items[@]}; i+=2)); do
            if [ "${menu_items[$i]}" = "$selected" ]; then
                selected_detail="${menu_items[$((i+1))]}"
                break
            fi
        done

        # 5. 弹出确认删除对话框
        confirm=$(dialog --title "⚠️ 确认删除" \
            --yesno "确定要删除以下规则吗？\n\n  规则编号：[$selected]\n  规则详情：$selected_detail\n\n  执行命令：ufw delete $selected\n\n点击「是」删除，点击「否」返回规则列表。" \
            14 65 \
            3>&1 1>&2 2>&3)

        if [ $? -eq 0 ]; then
            # 用户点击「是」，执行删除
            ufw --force delete "$selected"
            log_cmd "ufw delete $selected"
            dialog --title "成功" --msgbox "规则 #$selected 已成功删除！" 8 45
            # 删除后继续循环，刷新列表，方便连续删除
        else
            # 用户点击「否」，不删除，回到规则列表重新选择
            continue
        fi
    done
}

# ============================================================
#  查看命令日志
# ============================================================
show_log() {
    if [ -s "$LOG_FILE" ]; then
        log_content=$(cat "$LOG_FILE")
        dialog --title "本次会话执行的命令" --scrolltext --msgbox "$log_content" 20 70
    else
        dialog --title "命令日志" --msgbox "本次会话尚未执行任何命令。" 8 50
    fi
}

# ============================================================
#  重置防火墙
# ============================================================
reset_firewall() {
    confirm=$(dialog --title "⚠️ 警告" \
        --yesno "此操作将重置所有 UFW 规则！\n\n包括所有已添加的放行/拒绝规则。\n确定要继续吗？" 12 55 \
        3>&1 1>&2 2>&3)

    if [ $? -eq 0 ]; then
        ufw --force reset
        log_cmd "ufw --force reset"
        dialog --title "完成" --msgbox "防火墙已重置为初始状态。" 8 45
    fi
}

# ============================================================
#  备份规则
# ============================================================
backup_rules() {
    backup_file=$(dialog --title "备份规则" \
        --inputbox "请输入备份文件保存路径：\n\n（留空则默认保存到 /root/ufw-rules-backup-$(date +%Y%m%d%H%M%S).txt）" \
        12 65 \
        3>&1 1>&2 2>&3)

    # 点取消或关闭，直接返回主菜单
    if [ $? -ne 0 ]; then
        return
    fi

    # 如果用户没输入路径，使用默认路径
    if [ -z "$backup_file" ]; then
        backup_file="/root/ufw-rules-backup-$(date +%Y%m%d%H%M%S).txt"
    fi

    # 执行备份
    if ufw status numbered > "$backup_file" 2>&1; then
        log_cmd "ufw status numbered > $backup_file"
        dialog --title "成功" --msgbox "规则已备份到：\n\n  $backup_file" 10 65
    else
        dialog --title "错误" --msgbox "备份失败，请检查路径是否有写入权限。" 8 50
    fi
}

# ============================================================
#  恢复规则
# ============================================================
restore_rules() {
    # 选择备份文件
    restore_file=$(dialog --title "恢复规则" \
        --inputbox "请输入备份文件路径：\n\n（备份文件应为 ufw status 的输出格式）" \
        10 65 \
        3>&1 1>&2 2>&3)

    # 点取消或关闭，直接返回主菜单
    if [ $? -ne 0 ]; then
        return
    fi

    # 校验文件是否存在
    if [ -z "$restore_file" ] || [ ! -f "$restore_file" ]; then
        dialog --title "错误" --msgbox "文件不存在或路径为空！\n\n  $restore_file" 10 60
        return
    fi

    # 显示文件内容让用户确认
    file_content=$(cat "$restore_file")
    confirm=$(dialog --title "️ 确认恢复" \
        --yesno "即将从以下文件恢复规则：\n\n  $restore_file\n\n文件内容预览：\n\n$file_content\n\n注意：恢复前建议先重置防火墙，避免规则冲突。\n\n是否继续？" \
        20 70 \
        3>&1 1>&2 2>&3)

    if [ $? -eq 0 ]; then
        # 解析备份文件中的规则并逐条添加
        restored=0
        failed=0

        while IFS= read -r line; do
            # 匹配 ALLOW IN 规则
            if echo "$line" | grep -q "ALLOW IN"; then
                # 提取端口和来源
                port=$(echo "$line" | grep -oP '\d+/(tcp|udp|both)' | head -1)
                source=$(echo "$line" | awk '{print $NF}')

                if [ -n "$port" ]; then
                    if [ "$source" = "Anywhere" ] || [ -z "$source" ]; then
                        ufw allow "$port" 2>/dev/null && ((restored++)) || ((failed++))
                    else
                        ufw allow from "$source" to any port "$(echo $port | cut -d'/' -f1)" proto "$(echo $port | cut -d'/' -f2)" 2>/dev/null && ((restored++)) || ((failed++))
                    fi
                fi
            # 匹配 DENY IN 规则
            elif echo "$line" | grep -q "DENY IN"; then
                port=$(echo "$line" | grep -oP '\d+/(tcp|udp|both)' | head -1)
                source=$(echo "$line" | awk '{print $NF}')

                if [ -n "$port" ]; then
                    if [ "$source" = "Anywhere" ] || [ -z "$source" ]; then
                        ufw deny "$port" 2>/dev/null && ((restored++)) || ((failed++))
                    else
                        ufw deny from "$source" to any port "$(echo $port | cut -d'/' -f1)" proto "$(echo $port | cut -d'/' -f2)" 2>/dev/null && ((restored++)) || ((failed++))
                    fi
                fi
            fi
        done < "$restore_file"

        log_cmd "从 $restore_file 恢复规则（成功：$restored，失败：$failed）"
        dialog --title "恢复完成" --msgbox "规则恢复完成！\n\n  成功：$restored 条\n  失败：$failed 条\n\n建议执行「查看防火墙状态」确认规则是否正确。" 12 55
    fi
}

# ============================================================
#  启动
# ============================================================
dialog --title "欢迎" --msgbox "欢迎使用 UFW 防火墙图形化配置工具！\n\n此工具将引导您完成防火墙的配置。\n\n支持鼠标点击操作。\n\n️ 请使用 root 权限运行。" 14 55

main_menu

dialog --title "再见" --msgbox "感谢使用 UFW 防火墙图形化配置工具！\n\n命令日志已保存到：\n  $LOG_FILE" 10 55
