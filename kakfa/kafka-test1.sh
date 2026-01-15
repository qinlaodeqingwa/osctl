package kafka

import (
	"fmt"
	"log"
	"time"

	"github.com/IBM/sarama"
)

// 创建kafka同步生产者，返回两个值 sarama.SyncProducer对象  error
func newProducer(brokers []string, username, password string, saslMechanism string, tlsEnable bool) (sarama.SyncProducer, error) {
	cfg := sarama.NewConfig()
	cfg.Version = sarama.V4_0_0_0
	//发送消息后，要求kafka返回true，否则SendMessage不知道成功与否
	cfg.Producer.Return.Successes = true
	//所有副本全部写入
	cfg.Producer.RequiredAcks = sarama.WaitForAll
	cfg.Producer.Idempotent = true
	//防止重复发送
	cfg.Producer.Retry.Max = 10
	cfg.Producer.Retry.Backoff = 200 * time.Microsecond
	//启用消息压缩 snappy算法
	cfg.Producer.Compression = sarama.CompressionSnappy
	//每次只允许一个网络请求
	cfg.Net.MaxOpenRequests = 1
	// 用于sasl认证
	if username != "" {
		cfg.Net.SASL.Enable = true
		cfg.Net.SASL.User = username
		cfg.Net.SASL.Password = password
		switch saslMechanism {
		case "SCRAM-SHA-256":
			cfg.Net.SASL.SCRAMClientGeneratorFunc = func() sarama.SCRAMClient {
				return &XDGSCRAMClient{HashGeneratorFcn: SHA512}
			}
		case "PLAIN":
			cfg.Net.SASL.Mechanism = sarama.SASLTypePlaintext
		default:
			return nil, fmt.Errorf("unknown saslMechanism: %s", saslMechanism)
		}
	}
	if tlsEnable {
		cfg.Net.TLS.Enable = true
	}
	return sarama.NewSyncProducer(brokers, cfg)
}

func newAdmin(brokers []string, username, password string) (sarama.ClusterAdmin, error) {
	cfg := sarama.NewConfig()
	if username != "" {
		cfg.Net.SASL.Enable = true
		cfg.Net.SASL.User = username
		cfg.Net.SASL.Password = password
		cfg.Net.SASL.Mechanism = sarama.SASLTypePlaintext
	}

	return sarama.NewClusterAdmin(brokers, cfg)
}

func newConsumer(brokers []string, username, password string) (sarama.Consumer, error) {
	cfg := sarama.NewConfig()
	cfg.Version = sarama.V4_0_0_0

	if username != "" {
		cfg.Net.SASL.Enable =
			true
		cfg.Net.SASL.User = username
		cfg.Net.SASL.Password = password
		cfg.Net.SASL.Mechanism = sarama.SASLTypePlaintext
	}

	return sarama.NewConsumer(brokers, cfg)
}

func inspectTopic(brokers []string, topic string, username, password string) {
	admin, err := newAdmin(brokers, username, password)
	if err != nil {
		log.Printf(
			"❌ 创建 Admin 客户端失败: %v\n", err)
		return
	}
	defer admin.Close()
	metadata, err := admin.DescribeTopics([]string{topic})
	if err != nil {
		log.Printf("❌ 获取 Topic 信息失败: %v\n", err)
		return
	}
	for _, meta := range metadata {
		log.Printf(
			"📋 Topic: %s\n", meta.Name)
		log.Printf(
			"   分区数量: %d\n", len(meta.Partitions))

		for _, partition := range meta.Partitions {
			log.Printf(
				"   - Partition %d: Leader=%d, Replicas=%v, ISR=%v\n",
				partition.ID, partition.Leader, partition.Replicas, partition.Isr)
		}
	}
	consumer, err := newConsumer(brokers, username, password)
	if err != nil {
		log.Printf("❌ 创建 Consumer 失败: %v\n", err)
		return
	}
	defer consumer.Close()
	partitions, err := consumer.Partitions(topic)
	if err != nil {
		log.Printf(
			"❌ 获取分区列表失败: %v\n", err)
		return
	}
	log.Printf("\n 分区 offest信息：")
	totalMessages := int64(0)
	for _, partition := range partitions {
		oldestOffset, err := consumer.ConsumePartition(topic, partition, sarama.OffsetOldest)
		if err != nil {
			log.Printf(
				"❌ 获取分区 %d 信息失败: %v\n", partition, err)
			continue
		}
		oldestOffset.Close()
		newestOffset, err := consumer.ConsumePartition(topic, partition, sarama.OffsetNewest)
		if err != nil {
			log.Printf(
				"❌ 获取分区 %d 信息失败: %v\n", partition, err)
			continue
		}
		oldest := oldestOffset.HighWaterMarkOffset()
		newest := newestOffset.HighWaterMarkOffset()
		messageCount := newest - oldest
		totalMessages += messageCount
		log.Printf(
			"   Partition %d: Oldest=%d, Newest=%d, Messages=%d\n",
			partition, oldest, newest, messageCount)
		newestOffset.Close()
	}
	log.Printf("\n✅ Topic '%s' 总消息数: %d\n", topic, totalMessages)
}

func readRecentMessages(brokers []string, topic string, username, password string, count int) {
	log.Printf("\n========== 读取最近 %d 条消息 ==========\n", count)

	consumer, err := newConsumer(brokers, username, password)
	if err != nil {
		log.Printf("❌ 创建 Consumer 失败: %v\n", err)
		return
	}
	defer consumer.Close()

	partitions, err := consumer.Partitions(topic)
	if err != nil {
		log.Printf("❌ 获取分区列表失败: %v\n", err)
		return
	}

	for _, partition := range partitions {
		// 从最新位置往前读取
		pc, err := consumer.ConsumePartition(topic, partition, sarama.OffsetNewest-int64(count))
		if err != nil {
			log.Printf("❌ 消费分区 %d 失败: %v\n", partition, err)
			continue
		}

		log.Printf("\n📨 Partition %d 的消息:\n", partition)

		timeout := time.After(2 * time.Second)
		msgCount := 0

	Loop:
		for {
			select {
			case msg := <-pc.Messages():
				msgCount++
				log.Printf("  [%d] Offset=%d, Key=%s, Value=%s, Time=%s\n",
					msgCount,
					msg.Offset,
					string(msg.Key),
					string(msg.Value),
					msg.Timestamp.Format("2006-01-02 15:04:05"))

				if msgCount >= count {
					break Loop
				}
			case <-timeout:
				break Loop
			}
		}

		pc.Close()
	}
}
func main() {
	log.Println("========== Kafka Producer 启动 ==========")

	brokers := []string{"192.168.241.22:9092"}
	username := "admin"
	password := "admin"
	topic := "test"

	// 1. 发送消息
	log.Println("\n📤 开始发送消息...")
	producer, err := newProducer(brokers, username, password, "PLAIN", false)
	if err != nil {
		log.Fatalf("❌ 创建生产者失败: %v", err)
	}
	defer producer.Close()

	sentCount := 0
	for i := 1; i <= 5; i++ {
		msg := &sarama.ProducerMessage{
			Topic: topic,
			Key:   sarama.StringEncoder(fmt.Sprintf("user:%d", i)),
			Value: sarama.StringEncoder(fmt.Sprintf(`{"id":%d,"message":"hello world","timestamp":"%s"}`,
				i, time.Now().Format(time.RFC3339))),
		}

		partition, offset, err := producer.SendMessage(msg)
		if err != nil {
			log.Printf("  ❌ 消息 #%d 发送失败: %v\n", i, err)
		} else {
			sentCount++
			log.Printf("  ✅ 消息 #%d 发送成功! partition=%d, offset=%d\n", i, partition, offset)
		}

		time.Sleep(100 * time.Millisecond)
	}

	log.Printf("\n✅ 成功发送 %d 条消息\n", sentCount)

	// 2. 查看 Topic 信息
	inspectTopic(brokers, topic, username, password)

	// 3. 读取最近的消息
	readRecentMessages(brokers, topic, username, password, 10)

	log.Println("\n========== 程序执行完毕 ==========")
}
