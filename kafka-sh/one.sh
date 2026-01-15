#!/bin/bash
: <<'COMMENT'
 Kafka 4.0.1 自动化安装脚本
 使用方法: ./install_kafka.sh [选项]
 选项:
   --enable-sasl    启用SASL认证
   --cluster-mode   集群模式（默认为单机模式）
   --node-id=N      节点ID（集群模式必需，默认为1）
   --machine-ip=IP  机器IP地址（必需）
COMMENT
set -e

# ==================== 配置参数 ====================
KAFKA_VERSION="4.0.1"
SCALA_VERSION="2.13"
KAFKA_PACKAGE="kafka_${SCALA_VERSION}-${KAFKA_VERSION}"
DOWNLOAD_URL="https://mirrors.aliyun.com/apache/kafka/${KAFKA_VERSION}/${KAFKA_PACKAGE}.tgz"
INSTALL_DIR="/data"
KAFKA_HOME="${INSTALL_DIR}/kafka"
JAVA_HOME="/usr/local/jdk-17.0.1"

# 默认参数
ENABLE_SASL=false
CLUSTER_MODE=false
NODE_ID=1
MACHINE_IP=""

# ==================== 解析命令行参数 ====================
for arg in "$@"; do
    case $arg in
        --enable-sasl)
            ENABLE_SASL=true
            shift
            ;;
        --cluster-mode)
            CLUSTER_MODE=true
            shift
            ;;
        --node-id=*)
            NODE_ID="${arg#*=}"
            shift
            ;;
        --machine-ip=*)
            MACHINE_IP="${arg#*=}"
            shift
            ;;
        --help)
            echo "使用方法: $0 [选项]"
            echo "选项:"
            echo "  --enable-sasl       启用SASL认证"
            echo "  --cluster-mode      集群模式（默认为单机模式）"
            echo "  --node-id=N         节点ID（默认为1）"
            echo "  --machine-ip=IP     机器IP地址（必需）"
            exit 0
            ;;
        *)
            echo "未知参数: $arg"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
done

# ==================== 参数验证 ====================
if [ -z "$MACHINE_IP" ]; then
    echo "错误: 必须指定机器IP地址 (--machine-ip=IP)"
    exit 1
fi

# ==================== 颜色输出 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ==================== 检查环境 ====================
check_environment() {
    log_info "检查安装环境..."

    # 检查是否为root用户
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用root用户运行此脚本"
        exit 1
    fi

    # 检查Java环境
    if [ ! -d "$JAVA_HOME" ]; then
        log_error "Java未安装或路径不正确: $JAVA_HOME"
        log_info "请先安装JDK 17或更高版本"
        exit 1
    fi

    # 检查必要命令
    for cmd in wget tar; do
        if ! command -v $cmd &> /dev/null; then
            log_error "命令 $cmd 未找到，请先安装"
            exit 1
        fi
    done

    log_info "环境检查通过"
}

# ==================== 下载Kafka ====================
download_kafka() {
    log_info "开始下载Kafka ${KAFKA_VERSION}..."

    if [ -f "${KAFKA_PACKAGE}.tgz" ]; then
        log_warn "安装包已存在，跳过下载"
    else
        wget -c "$DOWNLOAD_URL" || {
            log_error "下载失败"
            exit 1
        }
    fi

    log_info "下载完成"
}

# ==================== 解压安装 ====================
install_kafka() {
    log_info "开始安装Kafka..."

    # 创建安装目录
    mkdir -p "$INSTALL_DIR"

    # 解压
    tar zxf "${KAFKA_PACKAGE}.tgz" -C "$INSTALL_DIR"

    # 创建软链接
    if [ -L "$KAFKA_HOME" ]; then
        rm -f "$KAFKA_HOME"
    fi
    ln -s "${INSTALL_DIR}/${KAFKA_PACKAGE}" "$KAFKA_HOME"

    # 创建日志目录
    mkdir -p /data/kafka/kraft-combined-logs

    log_info "Kafka安装完成"
}

# ==================== 生成集群UUID ====================
generate_cluster_id() {
    log_info "生成集群UUID..."

    cd "$KAFKA_HOME"
    CLUSTER_UUID=$(./bin/kafka-storage.sh random-uuid)

    log_info "集群UUID: $CLUSTER_UUID"
    echo "$CLUSTER_UUID" > /tmp/kafka_cluster_uuid.txt
}

# ==================== 生成配置文件 ====================
generate_config() {
    log_info "生成配置文件..."

    # 备份原配置文件
    cp "${KAFKA_HOME}/config/server.properties" "${KAFKA_HOME}/config/server.properties.bak"

    # 生成server.properties
    cat > "${KAFKA_HOME}/config/server.properties" << EOF
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

############################# Server Basics #############################

# 节点的角色。这是一个同时充当 Controller 和 Broker 的节点。
process.roles=broker,controller

# 节点的唯一 ID。确保集群内每个节点 ID 唯一。
node.id=${NODE_ID}

# Controller 节点的列表。所有 Controller 节点（包括自己）都要列在这里。
controller.quorum.voters=${NODE_ID}@${MACHINE_IP}:9093
controller.listener.names=CONTROLLER

############################# Socket Server Settings #############################

EOF

    # 根据是否启用SASL生成不同的listeners配置
    if [ "$ENABLE_SASL" = true ]; then
        cat >> "${KAFKA_HOME}/config/server.properties" << EOF
listeners=SASL_PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
advertised.listeners=SASL_PLAINTEXT://${MACHINE_IP}:9092,CONTROLLER://${MACHINE_IP}:9093
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,SSL:SSL,SASL_PLAINTEXT:SASL_PLAINTEXT,SASL_SSL:SASL_SSL

# SASL配置
security.inter.broker.protocol=SASL_PLAINTEXT
sasl.enabled.mechanisms=PLAIN
sasl.mechanism.inter.broker.protocol=PLAIN
EOF
    else
        cat >> "${KAFKA_HOME}/config/server.properties" << EOF
listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://${MACHINE_IP}:9093
advertised.listeners=PLAINTEXT://${MACHINE_IP}:9092,CONTROLLER://${MACHINE_IP}:9093
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,SSL:SSL,SASL_PLAINTEXT:SASL_PLAINTEXT,SASL_SSL:SASL_SSL
EOF
    fi

    cat >> "${KAFKA_HOME}/config/server.properties" << EOF

num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600

############################# Log Basics #############################

# 日志数据存储的目录
log.dirs=/data/kafka/kraft-combined-logs

num.partitions=1
num.recovery.threads.per.data.dir=1

############################# Internal Topic Settings #############################
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1

############################# Log Retention Policy #############################

log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000

EOF

    log_info "server.properties 配置文件生成完成"
}

# ==================== 生成SASL配置 ====================
generate_sasl_config() {
    if [ "$ENABLE_SASL" = true ]; then
        log_info "生成SASL认证配置..."

        cat > "${KAFKA_HOME}/config/kafka_server_jaas.conf" << 'EOF'
KafkaServer {
  org.apache.kafka.common.security.plain.PlainLoginModule required
  username="admin"
  password="admin"
  user_admin="admin";
};
EOF

        log_info "SASL配置文件生成完成"
        log_warn "默认用户名/密码为: admin/admin，请及时修改！"
    fi
}

# ==================== 格式化存储目录 ====================
format_storage() {
    log_info "格式化存储目录..."

    cd "$KAFKA_HOME"
    CLUSTER_UUID=$(cat /tmp/kafka_cluster_uuid.txt)

    if [ "$CLUSTER_MODE" = true ]; then
        ./bin/kafka-storage.sh format -t "$CLUSTER_UUID" -c config/server.properties
    else
        ./bin/kafka-storage.sh format --standalone -t "$CLUSTER_UUID" -c config/server.properties
    fi

    log_info "存储目录格式化完成"
}

# ==================== 创建systemd服务 ====================
create_systemd_service() {
    log_info "创建systemd服务..."

    # 生成服务文件
    cat > /etc/systemd/system/kafka.service << EOF
[Unit]
Description=Kafka Server (KRaft)
After=network.target

[Service]
Type=simple
Environment="JAVA_HOME=${JAVA_HOME}"
EOF

    if [ "$ENABLE_SASL" = true ]; then
        echo "Environment=\"KAFKA_OPTS=-Djava.security.auth.login.config=${KAFKA_HOME}/config/kafka_server_jaas.conf\"" >> /etc/systemd/system/kafka.service
    fi

    cat >> /etc/systemd/system/kafka.service << EOF
ExecStart=${KAFKA_HOME}/bin/kafka-server-start.sh ${KAFKA_HOME}/config/server.properties
ExecStop=${KAFKA_HOME}/bin/kafka-server-stop.sh
Restart=on-failure
User=root
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF

    # 重载systemd
    systemctl daemon-reload

    log_info "systemd服务创建完成"
}

# ==================== 启动Kafka ====================
start_kafka() {
    log_info "启动Kafka服务..."

    systemctl enable kafka
    systemctl start kafka

    sleep 5

    if systemctl is-active --quiet kafka; then
        log_info "Kafka服务启动成功"
    else
        log_error "Kafka服务启动失败，请检查日志"
        systemctl status kafka
        exit 1
    fi
}

# ==================== 显示安装信息 ====================
show_info() {
    echo ""
    echo "=========================================="
    log_info "Kafka安装完成！"
    echo "=========================================="
    echo "安装目录: $KAFKA_HOME"
    echo "配置文件: ${KAFKA_HOME}/config/server.properties"
    echo "日志目录: /data/kafka/kraft-combined-logs"
    echo "节点ID: $NODE_ID"
    echo "机器IP: $MACHINE_IP"
    echo "集群UUID: $(cat /tmp/kafka_cluster_uuid.txt)"
    echo ""
    echo "服务管理命令:"
    echo "  启动: systemctl start kafka"
    echo "  停止: systemctl stop kafka"
    echo "  重启: systemctl restart kafka"
    echo "  状态: systemctl status kafka"
    echo "  日志: journalctl -u kafka -f"
    echo ""

    if [ "$ENABLE_SASL" = true ]; then
        echo "SASL认证已启用"
        echo "  用户名: admin"
        echo "  密码: admin"
        echo "  配置文件: ${KAFKA_HOME}/config/kafka_server_jaas.conf"
        echo "  ⚠️  请及时修改默认密码！"
        echo ""
    fi

    echo "测试连接:"
    if [ "$ENABLE_SASL" = true ]; then
        echo "  ${KAFKA_HOME}/bin/kafka-broker-api-versions.sh --bootstrap-server ${MACHINE_IP}:9092 --command-config client.properties"
    else
        echo "  ${KAFKA_HOME}/bin/kafka-broker-api-versions.sh --bootstrap-server ${MACHINE_IP}:9092"
    fi
    echo "=========================================="
}

# ==================== 生成客户端配置示例 ====================
generate_client_config() {
    if [ "$ENABLE_SASL" = true ]; then
        log_info "生成客户端配置示例..."

        cat > "${KAFKA_HOME}/config/client.properties" << 'EOF'
security.protocol=SASL_PLAINTEXT
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required \
  username="admin" \
  password="admin";
EOF

        log_info "客户端配置示例: ${KAFKA_HOME}/config/client.properties"
    fi
}

# ==================== 主函数 ====================
main() {
    log_info "开始安装Kafka ${KAFKA_VERSION}..."
    log_info "安装模式: $([ "$CLUSTER_MODE" = true ] && echo "集群模式" || echo "单机模式")"
    log_info "SASL认证: $([ "$ENABLE_SASL" = true ] && echo "启用" || echo "禁用")"

    check_environment
    download_kafka
    install_kafka
    generate_cluster_id
    generate_config
    generate_sasl_config
    format_storage
    create_systemd_service
    generate_client_config
    start_kafka
    show_info

    log_info "安装流程全部完成！"
}

# 执行主函数
main
