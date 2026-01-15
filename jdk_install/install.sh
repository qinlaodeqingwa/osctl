#!/bin/bash

#########################################################
# 批量安装JDK脚本 v1.1
# 功能：支持多节点批量安装、自定义JDK版本、显示下载进度
# 使用方法：./install_jdk.sh
#########################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# 检查本地是否已安装expect（用于自动化SSH交互）
check_expect() {
    if ! command -v expect &> /dev/null; then
        log_warn "expect未安装，正在安装..."
        yum install -y expect 2>/dev/null || apt-get install -y expect 2>/dev/null
    fi
}

# 输入节点信息
input_nodes() {
    echo "=========================================="
    echo "请输入目标节点信息（用逗号分隔）"
    echo "格式：ip1,ip2,ip3 或 user@ip1,user@ip2"
    echo "例如：192.168.1.10,192.168.1.11,192.168.1.12"
    echo "或：root@192.168.1.10,root@192.168.1.11"
    echo "=========================================="
    read -p "请输入节点列表: " node_input

    if [ -z "$node_input" ]; then
        log_error "节点列表不能为空！"
        exit 1
    fi

    # 将逗号分隔的字符串转换为数组
    IFS=',' read -ra NODES <<< "$node_input"
}

# 输入SSH密码
input_password() {
    read -s -p "请输入SSH密码: " ssh_password
    echo
    if [ -z "$ssh_password" ]; then
        log_error "密码不能为空！"
        exit 1
    fi
}

# 选择JDK版本
select_jdk_version() {
    echo "=========================================="
    echo "请选择JDK版本："
    echo "1) JDK 8 (8u332)"
    echo "2) JDK 11 (11.0.15)"
    echo "3) JDK 17 (17.0.1)"
    echo "4) JDK 17 (17.0.2)"
    echo "5) JDK 21 (21.0.1)"
    echo "6) 自定义版本"
    echo "=========================================="
    read -p "请选择 [1-6]: " version_choice

    case $version_choice in
        1)
            JDK_VERSION="8u332"
            JDK_URL="https://mirrors.huaweicloud.com/openjdk/8u332-b09/openjdk-8u332-b09_linux-x64_bin.tar.gz"
            JDK_DIR="jdk8u332-b09"
            ;;
        2)
            JDK_VERSION="11.0.15"
            JDK_URL="https://mirrors.huaweicloud.com/openjdk/11.0.15/openjdk-11.0.15_linux-x64_bin.tar.gz"
            JDK_DIR="jdk-11.0.15"
            ;;
        3)
            JDK_VERSION="17.0.1"
            JDK_URL="https://mirrors.huaweicloud.com/openjdk/17.0.1/openjdk-17.0.1_linux-x64_bin.tar.gz"
            JDK_DIR="jdk-17.0.1"
            ;;
        4)
            JDK_VERSION="17.0.2"
            JDK_URL="https://mirrors.huaweicloud.com/openjdk/17.0.2/openjdk-17.0.2_linux-x64_bin.tar.gz"
            JDK_DIR="jdk-17.0.2"
            ;;
        5)
            JDK_VERSION="21.0.1"
            JDK_URL="https://mirrors.huaweicloud.com/openjdk/21.0.1/openjdk-21.0.1_linux-x64_bin.tar.gz"
            JDK_DIR="jdk-21.0.1"
            ;;
        6)
            read -p "请输入JDK版本号（如17.0.1）: " JDK_VERSION
            read -p "请输入下载URL: " JDK_URL
            read -p "请输入解压后的目录名（如jdk-17.0.1）: " JDK_DIR
            ;;
        *)
            log_error "无效的选择！"
            exit 1
            ;;
    esac

    JDK_FILENAME=$(basename $JDK_URL)
    INSTALL_DIR="/usr/local/$JDK_DIR"

    log_info "已选择JDK版本: $JDK_VERSION"
    log_info "下载地址: $JDK_URL"
    log_info "安装目录: $INSTALL_DIR"
}

# 在远程节点安装JDK
install_jdk_on_node() {
    local node=$1
    local user="root"
    local host=$node

    # 解析user@host格式
    if [[ $node == *"@"* ]]; then
        user=$(echo $node | cut -d'@' -f1)
        host=$(echo $node | cut -d'@' -f2)
    fi

    log_info "开始在节点 $host 上安装JDK..."

    # 创建远程安装脚本
    cat > /tmp/install_jdk_remote.sh <<'EOF'
#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}开始安装JDK...${NC}"
echo -e "${BLUE}=========================================${NC}"

# 检查是否已安装JDK
if [ -d "INSTALL_DIR_PLACEHOLDER" ]; then
    echo -e "${YELLOW}警告：JDK已存在于 INSTALL_DIR_PLACEHOLDER${NC}"
    echo -e "${YELLOW}正在删除旧版本...${NC}"
    rm -rf INSTALL_DIR_PLACEHOLDER
fi

# 下载JDK
echo -e "${GREEN}[1/4] 正在下载JDK...${NC}"
cd /tmp

# 删除可能存在的旧文件
rm -f JDK_FILENAME_PLACEHOLDER

if command -v wget &> /dev/null; then
    # 使用wget下载，显示进度条
    wget --progress=bar:force JDK_URL_PLACEHOLDER 2>&1 | while IFS= read -r line; do
        echo "$line"
    done
    download_result=${PIPESTATUS[0]}
elif command -v curl &> /dev/null; then
    # 使用curl下载，显示进度
    curl -# -O JDK_URL_PLACEHOLDER
    download_result=$?
else
    echo -e "${RED}错误：wget和curl都未安装！${NC}"
    exit 1
fi

if [ $download_result -ne 0 ] || [ ! -f "JDK_FILENAME_PLACEHOLDER" ]; then
    echo -e "${RED}错误：JDK下载失败！${NC}"
    exit 1
fi

echo -e "${GREEN}下载完成！${NC}"

# 解压JDK
echo -e "${GREEN}[2/4] 正在解压JDK...${NC}"
tar -zxf JDK_FILENAME_PLACEHOLDER
if [ $? -ne 0 ]; then
    echo -e "${RED}错误：解压失败！${NC}"
    exit 1
fi
echo -e "${GREEN}解压完成！${NC}"

# 移动到安装目录
echo -e "${GREEN}[3/4] 正在安装JDK到 INSTALL_DIR_PLACEHOLDER...${NC}"
mkdir -p /usr/local
mv JDK_DIR_PLACEHOLDER /usr/local/
if [ $? -ne 0 ]; then
    echo -e "${RED}错误：移动文件失败！${NC}"
    exit 1
fi
echo -e "${GREEN}安装完成！${NC}"

# 配置环境变量
echo -e "${GREEN}[4/4] 正在配置环境变量...${NC}"

# 备份profile
cp /etc/profile /etc/profile.bak.$(date +%Y%m%d%H%M%S)

# 先删除旧的JDK配置
sed -i '/^#JDK环境变量/,+3d' /etc/profile
sed -i '/^export JAVA_HOME.*\/jdk/d' /etc/profile
sed -i '/^export.*JAVA_HOME/d' /etc/profile

# 添加新的JDK配置
cat >> /etc/profile <<'EOL'

#JDK环境变量
export JAVA_HOME=INSTALL_DIR_PLACEHOLDER
export PATH=$PATH:$JAVA_HOME/bin
export CLASSPATH=.:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar
EOL

echo -e "${GREEN}环境变量配置完成！${NC}"

# 清理安装包
echo -e "${GREEN}正在清理临时文件...${NC}"
rm -f /tmp/JDK_FILENAME_PLACEHOLDER

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}JDK安装完成！${NC}"
echo -e "${BLUE}=========================================${NC}"

# 验证安装
echo -e "${GREEN}验证JDK安装：${NC}"
source /etc/profile
INSTALL_DIR_PLACEHOLDER/bin/java -version

EOF

    # 替换占位符
    sed -i "s|INSTALL_DIR_PLACEHOLDER|$INSTALL_DIR|g" /tmp/install_jdk_remote.sh
    sed -i "s|JDK_URL_PLACEHOLDER|$JDK_URL|g" /tmp/install_jdk_remote.sh
    sed -i "s|JDK_FILENAME_PLACEHOLDER|$JDK_FILENAME|g" /tmp/install_jdk_remote.sh
    sed -i "s|JDK_DIR_PLACEHOLDER|$JDK_DIR|g" /tmp/install_jdk_remote.sh

    # 使用expect自动化SSH交互，并实时显示输出
    expect <<EOD
set timeout 600
log_user 1

# 复制脚本到远程主机
spawn scp /tmp/install_jdk_remote.sh ${user}@${host}:/tmp/
expect {
    "yes/no" { send "yes\r"; exp_continue }
    "password:" { send "$ssh_password\r" }
}
expect eof

# 执行远程脚本，实时显示输出
spawn ssh -t ${user}@${host} "bash /tmp/install_jdk_remote.sh; rm -f /tmp/install_jdk_remote.sh"
expect {
    "yes/no" { send "yes\r"; exp_continue }
    "password:" { send "$ssh_password\r" }
}

# 等待脚本执行完成
expect {
    eof { }
    timeout { puts "执行超时"; exit 1 }
}

# 获取退出状态
catch wait result
set exit_code [lindex \$result 3]
exit \$exit_code
EOD

    local result=$?

    if [ $result -eq 0 ]; then
        log_info "节点 $host 安装成功！"
        return 0
    else
        log_error "节点 $host 安装失败！"
        return 1
    fi
}

# 主函数
main() {
    clear
    echo -e "${BLUE}"
    echo "=========================================="
    echo "       JDK批量安装脚本 v1.1"
    echo "=========================================="
    echo -e "${NC}"

    # 检查依赖
    check_expect

    # 输入节点信息
    input_nodes

    # 输入SSH密码
    input_password

    # 选择JDK版本
    select_jdk_version

    # 确认信息
    echo "=========================================="
    echo "即将在以下节点安装JDK $JDK_VERSION："
    for node in "${NODES[@]}"; do
        echo "  - $node"
    done
    echo "=========================================="
    read -p "确认开始安装？(y/n): " confirm

    if [ "$confirm" != "y" ]; then
        log_warn "取消安装"
        exit 0
    fi

    # 批量安装
    success_count=0
    fail_count=0
    success_nodes=()
    fail_nodes=()

    for node in "${NODES[@]}"; do
        echo ""
        echo -e "${BLUE}=========================================="
        echo -e "正在处理节点: $node"
        echo -e "==========================================${NC}"
        install_jdk_on_node "$node"
        if [ $? -eq 0 ]; then
            ((success_count++))
            success_nodes+=("$node")
        else
            ((fail_count++))
            fail_nodes+=("$node")
        fi
        echo ""
    done

    # 显示安装结果
    echo ""
    echo -e "${BLUE}=========================================="
    echo -e "${GREEN}安装完成！${NC}"
    echo -e "${BLUE}=========================================="
    echo -e "${GREEN}成功: $success_count 个节点${NC}"
    if [ $success_count -gt 0 ]; then
        for node in "${success_nodes[@]}"; do
            echo -e "  ${GREEN}✓${NC} $node"
        done
    fi
    echo ""
    echo -e "${RED}失败: $fail_count 个节点${NC}"
    if [ $fail_count -gt 0 ]; then
        for node in "${fail_nodes[@]}"; do
            echo -e "  ${RED}✗${NC} $node"
        done
    fi
    echo -e "${BLUE}==========================================${NC}"

    # 清理临时文件
    rm -f /tmp/install_jdk_remote.sh
}

# 执行主函数
main
