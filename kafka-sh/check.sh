#!/bin/bash
ip=$(ip route get 1 | awk '{print $7;exit}')
KAFKA_HOME=/data/kafka
KAFKA_CONFIG=/data/kafka/config/client.properties
KAFKA_BROKER=$ip:9092

show_menu() {
  echo ""
  echo "=========================================="
  echo "           KAFKA 管理工具"
  echo "=========================================="
  echo "1.  列出所有 Topics"
  echo "2.  创建 Topic"
  echo "3.  删除 Topic"
  echo "4.  查看 Topic 详情"
  echo "5.  列出所有消费者组"
  echo "6.  查看消费者组详情"
  echo "7.  重置消费者组偏移量"
  echo "8.  生产测试消息"
  echo "9.  消费消息"
  echo "10. 性能测试"
  echo "0.  退出"
  echo "=========================================="
  echo -n "请选择 [0-10]: "
}

list_topics(){
  echo ""
  echo "========== 所有 Topics =========="
  $KAFKA_HOME/bin/kafka-topics.sh --list \
    --bootstrap-server $KAFKA_BROKER \
    --command-config $KAFKA_CONFIG
  echo "================================="
}

create_topic(){
  echo ""
  echo "========== 创建 Topic =========="
  read -p "Topic 名称: " topic
  read -p "分区数 [3]: " partitions
  partitions=${partitions:-3}
  read -p "副本因子 [1]: " replication
  replication=${replication:-1}

  $KAFKA_HOME/bin/kafka-topics.sh --create \
    --bootstrap-server $KAFKA_BROKER \
    --command-config $KAFKA_CONFIG \
    --topic $topic \
    --partitions $partitions \
    --replication-factor $replication

  if [ $? -eq 0 ]; then
    echo "✓ Topic '$topic' 创建成功"
  else
    echo "✗ Topic 创建失败"
  fi
}

delete_topic() {
  echo ""
  echo "========== 删除 Topic =========="
  read -p "要删除的 Topic 名称: " topic
  read -p "确认删除 '$topic'? (yes/no): " confirm
  if [ "$confirm" = "yes" ]; then
    $KAFKA_HOME/bin/kafka-topics.sh --delete \
      --bootstrap-server $KAFKA_BROKER \
      --command-config $KAFKA_CONFIG \
      --topic $topic

    if [ $? -eq 0 ]; then
      echo "✓ Topic '$topic' 删除成功"
    else
      echo "✗ Topic 删除失败"
    fi
  else
    echo "取消删除"
  fi
}

describe_topic() {
  echo ""
  echo "========== Topic 详情 =========="
  read -p "Topic 名称: " topic
  $KAFKA_HOME/bin/kafka-topics.sh --describe \
    --bootstrap-server $KAFKA_BROKER \
    --command-config $KAFKA_CONFIG \
    --topic $topic
}

list_groups() {
  echo ""
  echo "========== 所有消费者组 =========="
  $KAFKA_HOME/bin/kafka-consumer-groups.sh --list \
    --bootstrap-server $KAFKA_BROKER \
    --command-config $KAFKA_CONFIG
  echo "=================================="
}

describe_group() {
  echo ""
  echo "========== 消费者组详情 =========="
  read -p "消费者组名称: " group
  $KAFKA_HOME/bin/kafka-consumer-groups.sh --describe \
    --bootstrap-server $KAFKA_BROKER \
    --command-config $KAFKA_CONFIG \
    --group $group
}

reset_offsets() {
  echo ""
  echo "========== 重置消费者组偏移量 =========="
  read -p "消费者组名称: " group
  read -p "Topic 名称: " topic

  echo ""
  echo "重置选项:"
  echo "1. 重置到最早 (earliest)"
  echo "2. 重置到最新 (latest)"
  echo "3. 重置到指定偏移量"
  echo "4. 向前/向后移动"
  echo "5. 重置到指定时间"
  read -p "选择重置方式 [1-5]: " reset_choice

  case $reset_choice in
    1)
      RESET_OPTION="--to-earliest"
      ;;
    2)
      RESET_OPTION="--to-latest"
      ;;
    3)
      read -p "指定偏移量: " offset
      RESET_OPTION="--to-offset $offset"
      ;;
    4)
      read -p "移动量 (正数向前，负数向后): " shift
      RESET_OPTION="--shift-by $shift"
      ;;
    5)
      read -p "时间 (格式: 2024-12-11T10:00:00.000): " datetime
      RESET_OPTION="--to-datetime $datetime"
      ;;
    *)
      echo "无效选择"
      return
      ;;
  esac

  echo ""
  echo "预览重置结果:"
  $KAFKA_HOME/bin/kafka-consumer-groups.sh \
    --bootstrap-server $KAFKA_BROKER \
    --command-config $KAFKA_CONFIG \
    --group $group \
    --topic $topic \
    --reset-offsets \
    $RESET_OPTION \
    --dry-run

  echo ""
  read -p "确认执行重置? (yes/no): " confirm
  if [ "$confirm" = "yes" ]; then
    $KAFKA_HOME/bin/kafka-consumer-groups.sh \
      --bootstrap-server $KAFKA_BROKER \
      --command-config $KAFKA_CONFIG \
      --group $group \
      --topic $topic \
      --reset-offsets \
      $RESET_OPTION \
      --execute

    if [ $? -eq 0 ]; then
      echo "✓ 偏移量重置成功"
    else
      echo "✗ 偏移量重置失败"
    fi
  else
    echo "取消重置"
  fi
}

produce_messages() {
  echo ""
  echo "========== 生产消息 =========="
  read -p "Topic 名称: " topic
  echo "输入消息（每行一条，Ctrl+C 退出）:"
  echo "-----------------------------------"
  $KAFKA_HOME/bin/kafka-console-producer.sh \
    --bootstrap-server $KAFKA_BROKER \
    --producer.config $KAFKA_CONFIG \
    --topic $topic
}

consume_messages() {
  echo ""
  echo "========== 消费消息 =========="
  read -p "Topic 名称: " topic
  read -p "是否从头开始消费? (yes/no) [yes]: " from_beginning
  from_beginning=${from_beginning:-yes}

  echo "开始消费消息（Ctrl+C 退出）:"
  echo "-----------------------------------"

  if [ "$from_beginning" = "yes" ]; then
    $KAFKA_HOME/bin/kafka-console-consumer.sh \
      --bootstrap-server $KAFKA_BROKER \
      --consumer.config $KAFKA_CONFIG \
      --topic $topic \
      --from-beginning
  else
    $KAFKA_HOME/bin/kafka-console-consumer.sh \
      --bootstrap-server $KAFKA_BROKER \
      --consumer.config $KAFKA_CONFIG \
      --topic $topic
  fi
}

performance_test() {
  echo "1. 生产者性能测试"
  echo "2. 消费者性能测试"
  read -p "选择测试类型 [1-2]: " test_type

  case $test_type in
    1)
      echo ""
      echo "--- 生产者性能测试 ---"
      read -p "Topic 名称: " topic
      read -p "消息数量 [10000]: " num_records
      num_records=${num_records:-10000}
      read -p "消息大小(字节) [1024]: " record_size
      record_size=${record_size:-1024}
      read -p "吞吐量限制(条/秒) [-1=无限制]: " throughput
      throughput=${throughput:--1}

      echo ""
      echo "开始测试..."
      echo "消息数量: $num_records"
      echo "消息大小: $record_size 字节"
      echo "吞吐量限制: $throughput 条/秒"
      echo "-----------------------------------"

      $KAFKA_HOME/bin/kafka-producer-perf-test.sh \
        --topic $topic \
        --num-records $num_records \
        --record-size $record_size \
        --throughput $throughput \
        --producer.config $KAFKA_CONFIG
      ;;

    2)
      echo ""
      echo "--- 消费者性能测试 ---"
      read -p "Topic 名称: " topic
      read -p "消息数量 [10000]: " messages
      messages=${messages:-10000}

      echo ""
      echo "开始测试..."
      echo "消息数量: $messages"
      echo "-----------------------------------"

      $KAFKA_HOME/bin/kafka-consumer-perf-test.sh \
        --topic $topic \
        --messages $messages \
        --bootstrap-server $KAFKA_BROKER \
        --consumer.config $KAFKA_CONFIG \
        --show-detailed-statss
      ;;

    *)
      echo "无效选择"
      ;;
  esac
}

# 主循环
while true; do
  show_menu
  read choice

  case $choice in
    1) list_topics ;;
    2) create_topic ;;
    3) delete_topic ;;
    4) describe_topic ;;
    5) list_groups ;;
    6) describe_group ;;
    7) reset_offsets ;;
    8) produce_messages ;;
    9) consume_messages ;;
    10) performance_test ;;
    0)
      echo ""
      echo "退出程序"
      exit 0
      ;;
    *)
      echo ""
      echo "✗ 无效选择，请输入 0-10"
      ;;
  esac

  echo ""
  read -p "按回车继续..."
done
