#!/bin/bash

: <<'COMMENT'
 Kafka部署
 使用方法: ./deploy_cluster.sh
 功能:
   - 交互式配置节点信息
   - 可选择是否启用SASL认证
   - 自动生成节点配置
COMMENT

cd "$(dirname "${BASH_SOURCE[0]}")"
set -o errexit -o nounset -o pipefail

# ==================== 配置参数 ====================
SCRIPT_DIR="$(pwd)"
NODES_CONFIG_FILE="${SCRIPT_DIR}/nodes_config.txt"
HOSTS_FILE="${SCRIPT_DIR}/hosts.txt"

# SSH配置
SSH_USER="root"
SSH_PORT="22"
SSH_KEY=""  # 留空使用默认密钥

# Kafka配置
KAFKA_VERSION="4.0.1"
SCALA_VERSION="2.13"
INSTALL_DIR="/data"
JAVA_HOME="/usr/lib/jvm/jdk-17.0.15+6"

# 是否启用SASL认证（将通过交互式输入设置）
ENABLE_SASL=false
SASL_ADMIN_USER="admin"
SASL_ADMIN_PASSWORD=""

# 节点信息（将通过交互式输入设置）
declare -a NODE_IPS=()
declare -A NODE_MAP=()

# ==================== 颜色输出 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

log_prompt() {
    echo -e "${CYAN}[INPUT]${NC} $1"
}

# ==================== 交互式配置 ====================
interactive_config() {
    clear
    echo "=========================================="
    echo "  Kafka 集群部署配置向导"
    echo "=========================================="
    echo ""

    # 1. 配置节点信息
    log_step "步骤 1: 配置集群节点"
    echo ""

    while true; do
        read -p "请输入集群节点数量 (建议3个或以上): " node_count
        # -ge 大于等于
        if [[ "$node_count" =~ ^[0-9]+$ ]] && [ "$node_count" -ge 1 ]; then
            break
        else
            log_error "请输入有效的数字（至少1个节点）"
        fi
    done

    echo ""
    log_info "请依次输入 $node_count 个节点的IP地址:"
    echo ""

    for ((i=1; i<=node_count; i++)); do
        while true; do
            read -p "节点 $i 的IP地址: " ip_address

            # 验证IP格式
            if [[ $ip_address =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                # 检查是否重复（修复：先检查数组是否为空）
                local is_duplicate=false
                # NODE_IPS数组数量大于0
                if [ ${#NODE_IPS[@]} -gt 0 ]; then
                    for existing_ip in "${NODE_IPS[@]}"; do
                        if [ "$existing_ip" = "$ip_address" ]; then
                            is_duplicate=true
                            break
                        fi
                    done
                fi

                if [ "$is_duplicate" = true ]; then
                    log_error "IP地址重复，请重新输入"
                    continue
                fi

                NODE_IPS+=("$ip_address")
                NODE_MAP[$ip_address]=$i
                log_info "✓ 节点 $i: $ip_address"
                break
            else
                log_error "IP地址格式不正确，请重新输入"
            fi
        done
    done

    # 2. 配置SASL认证
    echo ""
    log_step "步骤 2: 配置SASL认证"
    echo ""

    while true; do
        read -p "是否启用SASL认证? (y/n): " enable_sasl_input

        case "$enable_sasl_input" in
            y|Y|yes|YES)
                ENABLE_SASL=true
                log_info "✓ SASL认证已启用"

                # 配置SASL用户名
                echo ""
                read -p "SASL管理员用户名 [默认: admin]: " sasl_user_input
                SASL_ADMIN_USER=${sasl_user_input:-admin}

                # 配置SASL密码
                while true; do
                    read -sp "SASL管理员密码: " sasl_pass1
                    echo ""
                    read -sp "确认密码: " sasl_pass2
                    echo ""

                    if [ "$sasl_pass1" = "$sasl_pass2" ]; then
                        if [ -n "$sasl_pass1" ]; then
                            SASL_ADMIN_PASSWORD="$sasl_pass1"
                            log_info "✓ 密码设置成功"
                            break
                        else
                            log_error "密码不能为空"
                        fi
                    else
                        log_error "两次密码不一致，请重新输入"
                    fi
                done
                break
                ;;
            n|N|no|NO)
                ENABLE_SASL=false
                log_info "✓ SASL认证未启用"
                break
                ;;
            *)
                log_error "请输入 y 或 n"
                ;;
        esac
    done

    # 3. 配置Kafka版本
    echo ""
    log_step "步骤 3: 配置Kafka版本"
    echo ""
    read -p "Kafka版本 [默认: $KAFKA_VERSION]: " kafka_version_input
    KAFKA_VERSION=${kafka_version_input:-$KAFKA_VERSION}
    log_info "✓ Kafka版本: $KAFKA_VERSION"

    # 4. 配置安装目录
    echo ""
    log_step "步骤 4: 配置安装目录"
    echo ""
    read -p "安装目录 [默认: $INSTALL_DIR]: " install_dir_input
    INSTALL_DIR=${install_dir_input:-$INSTALL_DIR}
    log_info "✓ 安装目录: $INSTALL_DIR"

    # 5. 配置Java路径
    echo ""
    log_step "步骤 5: 配置Java路径"
    echo ""
    read -p "JAVA_HOME路径 [默认: $JAVA_HOME]: " java_home_input
    JAVA_HOME=${java_home_input:-$JAVA_HOME}
    log_info "✓ JAVA_HOME: $JAVA_HOME"

    # 显示配置摘要
    show_config_summary
}

# ==================== 显示配置摘要 ====================
show_config_summary() {
    echo ""
    echo "=========================================="
    echo "  配置摘要"
    echo "=========================================="
    echo ""
    echo "集群配置:"
    echo "  节点数量: ${#NODE_IPS[@]}"
    echo "  Kafka版本: $KAFKA_VERSION"
    echo "  安装目录: $INSTALL_DIR"
    echo "  JAVA_HOME: $JAVA_HOME"
    echo ""
    echo "节点列表:"
    for ip in "${NODE_IPS[@]}"; do
        node_id=${NODE_MAP[$ip]}
        echo "  节点 $node_id: $ip"
    done
    echo ""
    echo "SASL认证:"
    if [ "$ENABLE_SASL" = true ]; then
        echo -e "  状态: ${GREEN}已启用${NC}"
        echo "  用户名: $SASL_ADMIN_USER"
        echo "  密码: ${SASL_ADMIN_PASSWORD//?/*}"
    else
        echo -e "  状态: ${YELLOW}未启用${NC}"
    fi
    echo ""
    echo "=========================================="
    echo ""
}

# ==================== 保存配置到文件 ====================
save_config_to_files() {
    log_step "保存配置到文件..."

    # 保存节点配置
    cat > "$NODES_CONFIG_FILE" << EOF
# Kafka集群节点配置
# 格式: 节点ID,IP地址
# 自动生成时间: $(date '+%Y-%m-%d %H:%M:%S')

EOF

    for ip in "${NODE_IPS[@]}"; do
        node_id=${NODE_MAP[$ip]}
        echo "${node_id},${ip}" >> "$NODES_CONFIG_FILE"
    done

    # 保存主机列表
    cat > "$HOSTS_FILE" << EOF
# Kafka集群主机列表
# 自动生成时间: $(date '+%Y-%m-%d %H:%M:%S')

EOF

    for ip in "${NODE_IPS[@]}"; do
        echo "$ip" >> "$HOSTS_FILE"
    done

    log_info "✓ 配置已保存到:"
    log_info "  - $NODES_CONFIG_FILE"
    log_info "  - $HOSTS_FILE"
}

# ==================== SSH命令封装 ====================
ssh_exec() {
    local host=$1
    local cmd=$2

    if [ -n "$SSH_KEY" ]; then
        ssh -i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no "${SSH_USER}@${host}" \
            "source /etc/profile 2>/dev/null; source ~/.bashrc 2>/dev/null; $cmd"
    else
        ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no "${SSH_USER}@${host}" \
            "source /etc/profile 2>/dev/null; source ~/.bashrc 2>/dev/null; $cmd"
    fi
}

scp_file() {
    local src=$1
    local host=$2
    local dest=$3

    if [ -n "$SSH_KEY" ]; then
        scp -i "$SSH_KEY" -P "$SSH_PORT" -o StrictHostKeyChecking=no "$src" "${SSH_USER}@${host}:${dest}"
    else
        scp -P "$SSH_PORT" -o StrictHostKeyChecking=no "$src" "${SSH_USER}@${host}:${dest}"
    fi
}

# ==================== 检测节点连通性 ====================
check_nodes_connectivity() {
    log_step "检测节点连通性..."
    echo ""
    # 声明空数组
    local failed_nodes=()

    for ip in "${NODE_IPS[@]}"; do
        node_id=${NODE_MAP[$ip]}
        echo -n "检测节点 $node_id ($ip) ... "

        if ssh_exec "$ip" "echo 'OK'" &>/dev/null; then
            echo -e "${GREEN}✓ 连接成功${NC}"
        else
            echo -e "${RED}✗ 连接失败${NC}"
            failed_nodes+=("$ip")
        fi
    done

    if [ ${#failed_nodes[@]} -gt 0 ]; then
        echo ""
        log_error "以下节点连接失败:"
        for ip in "${failed_nodes[@]}"; do
            echo "  - $ip"
        done
        echo ""
        read -p "是否继续部署? (y/n): " continue_deploy
        if [ "$continue_deploy" != "y" ] && [ "$continue_deploy" != "Y" ]; then
            log_info "部署已取消"
            exit 1
        fi
    else
        echo ""
        log_info "✓ 所有节点连接正常"
    fi
}

# ==================== 检测Java环境 ====================
check_java_environment() {
    log_step "检测Java环境..."
    echo ""

    local failed_nodes=()

    for ip in "${NODE_IPS[@]}"; do
        node_id=${NODE_MAP[$ip]}
        echo -n "检测节点 $node_id ($ip) Java环境 ... "

        if ssh_exec "$ip" "${JAVA_HOME}/bin/java -version" &>/dev/null; then
            echo -e "${GREEN}✓ Java正常${NC}"
        else
            echo -e "${YELLOW}⚠ Java未找到${NC}"
            failed_nodes+=("$ip")
        fi
    done

    if [ ${#failed_nodes[@]} -gt 0 ]; then
        echo ""
        log_warn "以下节点Java环境异常:"
        for ip in "${failed_nodes[@]}"; do
            echo "  - $ip"
        done
        echo ""
        log_info "尝试创建Java软链接..."

        for ip in "${failed_nodes[@]}"; do
            ssh_exec "$ip" "ln -sf ${JAVA_HOME}/bin/java /usr/bin/java" || true
        done
    else
        echo ""
        log_info "✓ 所有节点Java环境正常"
    fi
}

# ==================== 生成集群UUID ====================
generate_cluster_uuid() {
    log_step "生成集群UUID..."

    CLUSTER_UUID=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | head -c 22)

    if [ -z "$CLUSTER_UUID" ]; then
        log_error "生成UUID失败"
        exit 1
    fi

    echo "$CLUSTER_UUID" > /tmp/kafka_cluster_uuid.txt
    log_info "集群UUID: $CLUSTER_UUID"
}

# ==================== 生成controller.quorum.voters配置 ====================
generate_quorum_voters() {
    local quorum_voters=""

    for ip in "${NODE_IPS[@]}"; do
        node_id=${NODE_MAP[$ip]}

        if [ -z "$quorum_voters" ]; then
            quorum_voters="${node_id}@${ip}:9093"
        else
            quorum_voters="${quorum_voters},${node_id}@${ip}:9093"
        fi
    done

    echo "$quorum_voters"
}

# ==================== 生成配置文件 ====================
generate_config_for_node() {
    local node_id=$1
    local node_ip=$2
    local config_file="/tmp/kafka_server_${node_ip}.properties"

    log_info "生成节点 $node_id ($node_ip) 配置文件..."

    local quorum_voters=$(generate_quorum_voters)

    cat > "$config_file" << EOF
# Kafka Cluster Configuration
# Node ID: ${node_id}
# Node IP: ${node_ip}
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

############################# Server Basics #############################

process.roles=broker,controller
node.id=${node_id}
controller.quorum.voters=${quorum_voters}

############################# Socket Server Settings #############################

EOF

    if [ "$ENABLE_SASL" = true ]; then
        cat >> "$config_file" << EOF
listeners=SASL_PLAINTEXT://${node_ip}:9092,CONTROLLER://${node_ip}:9093
controller.listener.names=CONTROLLER
advertised.listeners=SASL_PLAINTEXT://${node_ip}:9092
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,SSL:SSL,SASL_PLAINTEXT:SASL_PLAINTEXT,SASL_SSL:SASL_SSL
security.inter.broker.protocol=SASL_PLAINTEXT
sasl.enabled.mechanisms=PLAIN
sasl.mechanism.inter.broker.protocol=PLAIN
EOF
    else
        cat >> "$config_file" << EOF
listeners=PLAINTEXT://${node_ip}:9092,CONTROLLER://${node_ip}:9093
controller.listener.names=CONTROLLER
advertised.listeners=PLAINTEXT://${node_ip}:9092
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,SSL:SSL,SASL_PLAINTEXT:SASL_PLAINTEXT,SASL_SSL:SASL_SSL
EOF
    fi

    cat >> "$config_file" << EOF

num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600

############################# Log Basics #############################

log.dirs=${INSTALL_DIR}/kafka/kraft-combined-logs
num.partitions=3
num.recovery.threads.per.data.dir=1

############################# Internal Topic Settings #############################

offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2

############################# Log Retention Policy #############################

log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000

############################# Performance Settings #############################

num.replica.fetchers=4
replica.high.watermark.checkpoint.interval.ms=5000
compression.type=producer
auto.create.topics.enable=true
delete.topic.enable=true

EOF

    log_info "✓ 配置文件生成完成: $config_file"
}

# ==================== 生成SASL配置 ====================
generate_sasl_config() {
    local node_ip=$1
    local config_file="/tmp/kafka_server_jaas_${node_ip}.conf"

    if [ "$ENABLE_SASL" = true ]; then
        cat > "$config_file" << EOF
KafkaServer {
  org.apache.kafka.common.security.plain.PlainLoginModule required
  username="${SASL_ADMIN_USER}"
  password="${SASL_ADMIN_PASSWORD}"
  user_${SASL_ADMIN_USER}="${SASL_ADMIN_PASSWORD}";
};
EOF
    fi
}

# ==================== 生成systemd服务文件 ====================
generate_systemd_service() {
    local node_id=$1
    local node_ip=$2
    local service_file="/tmp/kafka_${node_ip}.service"

    cat > "$service_file" << EOF
[Unit]
Description=Kafka Server (KRaft) - Node ${node_id}
Documentation=https://kafka.apache.org/documentation/
After=network.target

[Service]
Type=simple
User=root
Group=root

# Java 环境配置
Environment="JAVA_HOME=${JAVA_HOME}"
Environment="JRE_HOME=${JAVA_HOME}/jre"
Environment="PATH=${JAVA_HOME}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="CLASSPATH=.:${JAVA_HOME}/lib/dt.jar:${JAVA_HOME}/lib/tools.jar"
EOF

    if [ "$ENABLE_SASL" = true ]; then
        echo "Environment=\"KAFKA_OPTS=-Djava.security.auth.login.config=${INSTALL_DIR}/kafka/config/kafka_server_jaas.conf\"" >> "$service_file"
    fi

    cat >> "$service_file" << EOF

# Kafka 配置
WorkingDirectory=${INSTALL_DIR}/kafka
ExecStart=${INSTALL_DIR}/kafka/bin/kafka-server-start.sh ${INSTALL_DIR}/kafka/config/server.properties
ExecStop=${INSTALL_DIR}/kafka/bin/kafka-server-stop.sh

# 重启策略
Restart=on-failure
RestartSec=10
TimeoutStopSec=30

# 资源限制
LimitNOFILE=100000
LimitNPROC=100000

# 日志配置
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kafka-node-${node_id}

[Install]
WantedBy=multi-user.target
EOF
}

# ==================== 单节点安装脚本 ====================
create_install_script() {
    local node_id=$1
    local node_ip=$2
    local script_file="/tmp/install_node_${node_ip}.sh"

    cat > "$script_file" << 'EOFSCRIPT'
#!/bin/bash
set -e

NODE_ID="$1"
CLUSTER_UUID="$2"
KAFKA_VERSION="$3"
SCALA_VERSION="$4"
INSTALL_DIR="$5"
JAVA_HOME="$6"

KAFKA_PACKAGE="kafka_${SCALA_VERSION}-${KAFKA_VERSION}"
DOWNLOAD_URL="https://mirrors.aliyun.com/apache/kafka/${KAFKA_VERSION}/${KAFKA_PACKAGE}.tgz"

echo "[INFO] 开始安装 Kafka 节点 ${NODE_ID}..."

# 配置Java环境
echo "[INFO] 配置Java环境..."
ln -sf ${JAVA_HOME}/bin/java /usr/bin/java 2>/dev/null || true
ln -sf ${JAVA_HOME}/bin/javac /usr/bin/javac 2>/dev/null || true

# 验证Java
if ! ${JAVA_HOME}/bin/java -version &>/dev/null; then
    echo "[ERROR] Java环境异常"
    exit 1
fi

# 下载Kafka
cd /tmp/kafka_install
if [ ! -f "${KAFKA_PACKAGE}.tgz" ]; then
    echo "[INFO] 下载 Kafka ${KAFKA_VERSION}..."
    wget -c "$DOWNLOAD_URL" || {
        echo "[ERROR] 下载失败"
        exit 1
    }
fi

# 解压安装
echo "[INFO] 解压 Kafka..."
mkdir -p "${INSTALL_DIR}"
tar zxf "${KAFKA_PACKAGE}.tgz" -C "${INSTALL_DIR}/"

# 创建软链接
rm -f "${INSTALL_DIR}/kafka"
ln -s "${INSTALL_DIR}/${KAFKA_PACKAGE}" "${INSTALL_DIR}/kafka"

# 创建日志目录
mkdir -p "${INSTALL_DIR}/kafka/kraft-combined-logs"

# 复制配置文件
echo "[INFO] 配置 Kafka..."
cp /tmp/kafka_install/server.properties "${INSTALL_DIR}/kafka/config/server.properties"

if [ -f /tmp/kafka_install/kafka_server_jaas.conf ]; then
    cp /tmp/kafka_install/kafka_server_jaas.conf "${INSTALL_DIR}/kafka/config/"
fi

# 格式化存储目录
echo "[INFO] 格式化存储目录..."
cd "${INSTALL_DIR}/kafka"

# 确保Java环境
export JAVA_HOME=${JAVA_HOME}
export PATH=${JAVA_HOME}/bin:$PATH

./bin/kafka-storage.sh format -t "${CLUSTER_UUID}" -c config/server.properties

# 安装systemd服务
echo "[INFO] 配置 systemd 服务..."
cp /tmp/kafka_install/kafka.service /etc/systemd/system/kafka.service
systemctl daemon-reload

echo "[INFO] 节点 ${NODE_ID} 安装完成 ✓"
EOFSCRIPT

    chmod +x "$script_file"
}

# ==================== 部署到所有节点 ====================
deploy_all_nodes() {
    log_step "开始部署所有节点..."
    echo ""

    # 生成所有配置文件
    for ip in "${NODE_IPS[@]}"; do
        node_id=${NODE_MAP[$ip]}

        generate_config_for_node "$node_id" "$ip"
        generate_sasl_config "$ip"
        generate_systemd_service "$node_id" "$ip"
        create_install_script "$node_id" "$ip"
    done

    # 部署到每个节点
    local node_index=1
    for ip in "${NODE_IPS[@]}"; do
        node_id=${NODE_MAP[$ip]}

        echo ""
        log_step "部署节点 $node_index/${#NODE_IPS[@]} (节点ID: $node_id, IP: $ip)..."
        echo "-----------------------------------"

        # 创建远程目录
        log_info "创建远程目录..."
        ssh_exec "$ip" "mkdir -p /tmp/kafka_install"

        # 上传文件
        log_info "上传配置文件..."
        scp_file "/tmp/kafka_server_${ip}.properties" "$ip" "/tmp/kafka_install/server.properties"
        scp_file "/tmp/kafka_${ip}.service" "$ip" "/tmp/kafka_install/kafka.service"
        scp_file "/tmp/install_node_${ip}.sh" "$ip" "/tmp/kafka_install/install.sh"
        scp_file "/tmp/kafka_cluster_uuid.txt" "$ip" "/tmp/kafka_install/cluster_uuid.txt"

        if [ "$ENABLE_SASL" = true ]; then
            scp_file "/tmp/kafka_server_jaas_${ip}.conf" "$ip" "/tmp/kafka_install/kafka_server_jaas.conf"
        fi

        # 执行安装
        log_info "执行安装脚本..."
        ssh_exec "$ip" "bash /tmp/kafka_install/install.sh $node_id $(cat /tmp/kafka_cluster_uuid.txt) $KAFKA_VERSION $SCALA_VERSION $INSTALL_DIR $JAVA_HOME"

        log_info "✓ 节点 $node_id 部署完成"

        ((node_index++))
    done

    echo ""
    log_info "✓ 所有节点部署完成"
}

# ==================== 启动所有节点 ====================
start_all_nodes() {
    log_step "启动所有节点..."
    echo ""

    for ip in "${NODE_IPS[@]}"; do
        node_id=${NODE_MAP[$ip]}

        log_info "启动节点 $node_id ($ip)..."
        ssh_exec "$ip" "systemctl enable kafka && systemctl start kafka"
        sleep 3
    done

    echo ""
    log_info "✓ 所有节点启动完成"
}

# ==================== 检查集群状态 ====================
check_cluster_status() {
    log_step "检查集群状态..."
    echo ""

    echo "=========================================="
    echo "  集群节点状态"
    echo "=========================================="

    for ip in "${NODE_IPS[@]}"; do
        node_id=${NODE_MAP[$ip]}

        echo ""
        echo "节点 $node_id ($ip):"
        echo "-----------------------------------"

        # 检查服务状态
        if ssh_exec "$ip" "systemctl is-active kafka" &>/dev/null; then
            echo -e "  服务状态: ${GREEN}运行中${NC} ✓"
        else
            echo -e "  服务状态: ${RED}已停止${NC} ✗"
            continue
        fi

        # 检查端口
        if ssh_exec "$ip" "ss -tuln 2>/dev/null | grep -E ':(9092|9093)' &>/dev/null || netstat -tuln 2>/dev/null | grep -E ':(9092|9093)' &>/dev/null"; then
            echo -e "  端口状态: ${GREEN}正常监听${NC} ✓"
        else
            echo -e "  端口状态: ${RED}未监听${NC} ✗"
        fi

        # 检查进程
        if ssh_exec "$ip" "ps aux | grep kafka | grep -v grep" &>/dev/null; then
            echo -e "  进程状态: ${GREEN}运行中${NC} ✓"
        else
            echo -e "  进程状态: ${RED}未运行${NC} ✗"
        fi
    done

    echo ""
    echo "=========================================="
}

# ==================== 生成客户端配置 ====================
generate_client_config() {
    log_step "生成客户端配置..."

    local bootstrap_servers=""
    for ip in "${NODE_IPS[@]}"; do
        if [ -z "$bootstrap_servers" ]; then
            bootstrap_servers="${ip}:9092"
        else
            bootstrap_servers="${bootstrap_servers},${ip}:9092"
        fi
    done

    cat > "kafka_client.properties" << EOF
# Kafka集群客户端配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

bootstrap.servers=${bootstrap_servers}

EOF

    if [ "$ENABLE_SASL" = true ]; then
        cat >> "kafka_client.properties" << EOF
# SASL认证配置
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \\
  username="${SASL_ADMIN_USER}" \\
  password="${SASL_ADMIN_PASSWORD}";
EOF
    fi

    log_info "✓ 客户端配置文件已生成: kafka_client.properties"
}

# ==================== 生成管理脚本 ====================
generate_management_scripts() {
    log_step "生成管理脚本..."

    # 启动脚本
    cat > "start_cluster.sh" << 'EOF'
#!/bin/bash
HOSTS_FILE="./hosts.txt"
while read host; do
    [[ -z "$host" || "$host" =~ ^# ]] && continue
    echo "启动节点: $host"
    ssh root@${host} "systemctl start kafka"
done < "$HOSTS_FILE"
echo "集群启动完成"
EOF

    # 停止脚本
    cat > "stop_cluster.sh" << 'EOF'
#!/bin/bash
HOSTS_FILE="./hosts.txt"
while read host; do
    [[ -z "$host" || "$host" =~ ^# ]] && continue
    echo "停止节点: $host"
    ssh root@${host} "systemctl stop kafka"
done < "$HOSTS_FILE"
echo "集群停止完成"
EOF

    # 状态检查脚本
    cat > "check_cluster.sh" << 'EOF'
#!/bin/bash
HOSTS_FILE="./hosts.txt"
echo "=========================================="
echo "  Kafka 集群状态"
echo "=========================================="
while read host; do
    [[ -z "$host" || "$host" =~ ^# ]] && continue
    echo ""
    echo "节点: $host"
    echo "-----------------------------------"
    ssh root@${host} "systemctl status kafka --no-pager | head -10"
done < "$HOSTS_FILE"
EOF

    chmod +x start_cluster.sh stop_cluster.sh check_cluster.sh

    log_info "✓ 管理脚本已生成:"
    log_info "  - start_cluster.sh (启动集群)"
    log_info "  - stop_cluster.sh (停止集群)"
    log_info "  - check_cluster.sh (检查状态)"
}

# ==================== 显示部署信息 ====================
show_deployment_info() {
    echo ""
    echo "=========================================="
    log_info "Kafka集群部署完成！"
    echo "=========================================="
    echo ""
    echo "集群信息:"
    echo "  节点数量: ${#NODE_IPS[@]}"
    echo "  Kafka版本: ${KAFKA_VERSION}"
    echo "  集群UUID: $(cat /tmp/kafka_cluster_uuid.txt)"
    echo "  安装目录: ${INSTALL_DIR}"
    echo "  SASL认证: $([ "$ENABLE_SASL" = true ] && echo "已启用" || echo "未启用")"
    echo ""
    echo "节点列表:"
    for ip in "${NODE_IPS[@]}"; do
        node_id=${NODE_MAP[$ip]}
        echo "  节点 $node_id: $ip:9092"
    done
    echo ""

    if [ "$ENABLE_SASL" = true ]; then
        echo "SASL认证信息:"
        echo "  用户名: $SASL_ADMIN_USER"
        echo "  密码: $SASL_ADMIN_PASSWORD"
        echo ""
    fi

    echo "配置文件:"
    echo "  节点配置: $NODES_CONFIG_FILE"
    echo "  主机列表: $HOSTS_FILE"
    echo "  客户端配置: kafka_client.properties"
    echo ""
    echo "管理脚本:"
    echo "  启动集群: ./start_cluster.sh"
    echo "  停止集群: ./stop_cluster.sh"
    echo "  检查状态: ./check_cluster.sh"
    echo ""
    echo "常用命令:"
    echo "  查看服务状态: systemctl status kafka"
    echo "  查看日志: journalctl -u kafka -f"
    echo "  查看端口: ss -tuln | grep -E '9092|9093'"
    echo ""
    echo "=========================================="
}

# ==================== 清理临时文件 ====================
cleanup() {
    if [ "${#NODE_IPS[@]}" -gt 0 ]; then
        log_info "清理临时文件..."
        rm -f /tmp/kafka_server_*.properties
        rm -f /tmp/kafka_server_jaas_*.conf
        rm -f /tmp/kafka_*.service
        rm -f /tmp/install_node_*.sh
    fi
}

# ==================== 主函数 ====================
main() {
    clear
    echo "=========================================="
    echo "  Kafka 部署工具"
    echo "=========================================="
    echo ""

    # 交互式配置
    interactive_config

    # 确认部署
    echo ""
    read -p "确认开始部署? (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "部署已取消"
        exit 0
    fi

    # 保存配置
    save_config_to_files

    # 检查节点连通性
    check_nodes_connectivity

    # 检查Java环境
    check_java_environment

    # 生成集群UUID
    generate_cluster_uuid

    # 部署集群
    deploy_all_nodes

    # 启动集群
    start_all_nodes

    # 等待服务启动
    log_info "等待服务启动..."
    sleep 10

    # 检查集群状态
    check_cluster_status

    # 生成客户端配置
    generate_client_config

    # 生成管理脚本
    generate_management_scripts

    # 显示部署信息
    show_deployment_info

    # 清理临时文件
    cleanup

    echo ""
    log_info "部署流程全部完成！🎉"
}

# 捕获退出信号，清理临时文件
trap cleanup EXIT

# 执行主函数
main
