package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/IBM/sarama"
)

type KafkaClient struct {
	brokers  []string
	username string
	password string
	config   *sarama.Config
}

type ConsumerGroupHandler struct {
	name string
}

// Setup 在消费者组会话开始时调用
func (h ConsumerGroupHandler) Setup(sarama.ConsumerGroupSession) error {
	log.Printf("🟢 [%s] 消费者组会话开始\n", h.name)
	return nil
}

// Cleanup 在消费者组会话结束时调用
func (h ConsumerGroupHandler) Cleanup(sarama.ConsumerGroupSession) error {
	log.Printf("🔴 [%s] 消费者组会话结束\n", h.name)
	return nil
}

// ConsumeClaim 处理消息
func (h ConsumerGroupHandler) ConsumeClaim(session sarama.ConsumerGroupSession, claim sarama.ConsumerGroupClaim) error {
	for {
		select {
		case message := <-claim.Messages():
			if message == nil {
				return nil
			}

			log.Printf("📨 [%s] 收到消息:\n", h.name)
			log.Printf("   ├─ Topic: %s\n", message.Topic)
			log.Printf("   ├─ Partition: %d\n", message.Partition)
			log.Printf("   ├─ Offset: %d\n", message.Offset)
			log.Printf("   ├─ Key: %s\n", string(message.Key))
			log.Printf("   ├─ Value: %s\n", string(message.Value))
			log.Printf("   ├─ Timestamp: %s\n", message.Timestamp.Format("2025-11-02 15:04:05"))
			log.Printf("   └─ Headers: %v\n", message.Headers)

			// 标记消息已处理
			session.MarkMessage(message, "")

		case <-session.Context().Done():
			return nil
		}
	}
}

func (kc *KafkaClient) ListAllTopics() error {
	client, err := sarama.NewClient(kc.brokers, kc.config)
	if err != nil {
		return fmt.Errorf("创建客户端失败: %w", err)
	}
	defer client.Close()

	topics, err := client.Topics()
	if err != nil {
		return fmt.Errorf("获取 topics 失败: %w", err)
	}

	log.Printf("\n========== Kafka 集群所有 Topic ==========\n")
	for _, topic := range topics {
		partitions, _ := client.Partitions(topic)
		totalMessages := int64(0)
		for _, p := range partitions {
			oldest, _ := client.GetOffset(topic, p, sarama.OffsetOldest)
			newest, _ := client.GetOffset(topic, p, sarama.OffsetNewest)
			totalMessages += newest - oldest
		}
		log.Printf("Topic: %s | Partitions: %d | 消息总数: %d\n", topic, len(partitions), totalMessages)
	}
	log.Println("==========================================")
	return nil
}

// 构造函数 创建对象
func NewKafkaClient(broker []string, username, password string) *KafkaClient {
	cfg := sarama.NewConfig()
	cfg.Version = sarama.V4_0_0_0
	if username != "" {
		cfg.Net.SASL.Enable = true
		cfg.Net.SASL.User = username
		cfg.Net.SASL.Password = password
		cfg.Net.SASL.Mechanism = sarama.SASLTypePlaintext
	}
	return &KafkaClient{broker, username, password, cfg}
}

// 创建生产者
func (kc *KafkaClient) NewProducer() (sarama.SyncProducer, error) {
	cfg := kc.config
	cfg.Producer.Return.Successes = true
	cfg.Producer.RequiredAcks = sarama.WaitForAll
	cfg.Producer.Idempotent = true
	cfg.Producer.Retry.Max = 10
	cfg.Producer.Compression = sarama.CompressionSnappy
	cfg.Net.MaxOpenRequests = 1
	return sarama.NewSyncProducer(kc.brokers, cfg)
}

func (kc *KafkaClient) SendMessage(producer sarama.SyncProducer, topic, key, value string) error {
	msg := &sarama.ProducerMessage{
		Topic: topic,
		Key:   sarama.StringEncoder(key),
		Value: sarama.StringEncoder(value),
	}
	partition, offset, err := producer.SendMessage(msg)
	if err != nil {
		return err
	}
	log.Printf("Message sent to partition %d at offset %d\n", partition, offset)
	return nil
}

func (kc *KafkaClient) GetTopicInfo(topic string) error {
	client, err := sarama.NewClient(kc.brokers, kc.config)
	if err != nil {
		return fmt.Errorf("创建客户端失败:%w", err)
	}
	defer client.Close()
	partitions, err := client.Partitions(topic)
	if err != nil {
		return fmt.Errorf("获取分区失败: %w", err)
	}

	log.Printf("\n========== Topic '%s' 信息 ==========\n", topic)
	totalMessages := int64(0)

	for _, partition := range partitions {
		oldest, _ := client.GetOffset(topic, partition, sarama.OffsetOldest)
		newest, _ := client.GetOffset(topic, partition, sarama.OffsetNewest)
		count := newest - oldest
		totalMessages += count

		log.Printf("Partition %d: %d 条消息 (offset: %d -> %d)\n", partition, count, oldest, newest-1)
	}

	log.Printf("总计: %d 条消息\n", totalMessages)
	log.Println("======================================")
	return nil
}

func (kc *KafkaClient) NewConsumerGroup(groupID string) (sarama.ConsumerGroup, error) {
	cfg := kc.config
	cfg.Consumer.Group.Rebalance.Strategy = sarama.NewBalanceStrategyRoundRobin()
	cfg.Consumer.Offsets.Initial = sarama.OffsetOldest
	cfg.Consumer.Return.Errors = true

	return sarama.NewConsumerGroup(kc.brokers, groupID, cfg)
}

func (kc *KafkaClient) StartConsumerGroup(groupID string, topics []string, ctx context.Context) error {
	consumerGroup, err := kc.NewConsumerGroup(groupID)
	if err != nil {
		return fmt.Errorf("创建消费者组失败: %w", err)
	}
	defer consumerGroup.Close()

	handler := ConsumerGroupHandler{name: groupID}

	log.Printf("[%s] 消费者组启动，订阅 topics: %v\n", groupID, topics)

	// 处理错误
	go func() {
		for err := range consumerGroup.Errors() {
			log.Printf("[%s] 消费者组错误: %v\n", groupID, err)
		}
	}()

	// 持续消费
	for {
		select {
		case <-ctx.Done():
			log.Printf("[%s] 消费者组停止\n", groupID)
			return nil
		default:
			if err := consumerGroup.Consume(ctx, topics, handler); err != nil {
				log.Printf("[%s] 消费失败: %v\n", groupID, err)
				return err
			}
		}
	}
}

func (kc *KafkaClient) StartConsumerGroupAsync(groupID string, topics []string, ctx context.Context, wg *sync.WaitGroup) {
	wg.Add(1)
	go func() {
		defer wg.Done()
		if err := kc.StartConsumerGroup(groupID, topics, ctx); err != nil {
			log.Printf("[%s] 消费者组异常退出: %v\n", groupID, err)
		}
	}()
}

func (kc *KafkaClient) ListConsumerGroups() error {
	admin, err := sarama.NewClusterAdmin(kc.brokers, kc.config)
	if err != nil {
		return fmt.Errorf("创建管理客户端失败: %w", err)
	}
	defer admin.Close()

	groups, err := admin.ListConsumerGroups()
	if err != nil {
		return fmt.Errorf("获取消费者组失败: %w", err)
	}

	log.Printf("\n========== 所有消费者组 ==========\n")
	if len(groups) == 0 {
		log.Println("当前没有任何消费者组")
	} else {
		for groupID, groupType := range groups {
			log.Printf("  - %s (类型: %s)\n", groupID, groupType)
		}
	}
	log.Println("==================================")
	return nil
}

func (kc *KafkaClient) DescribeConsumerGroup(groupID string) error {
	admin, err := sarama.NewClusterAdmin(kc.brokers, kc.config)
	if err != nil {
		return fmt.Errorf("创建管理客户端失败: %w", err)
	}
	defer admin.Close()

	groups, err := admin.DescribeConsumerGroups([]string{groupID})
	if err != nil {
		return fmt.Errorf("获取消费者组详情失败: %w", err)
	}

	log.Printf("\n========== 消费者组 '%s' 详情 ==========\n", groupID)
	for _, group := range groups {
		log.Printf("状态: %s\n", group.State)
		log.Printf("协议类型: %s\n", group.ProtocolType)
		log.Printf("协议: %s\n", group.Protocol)
		log.Printf("成员数: %d\n", len(group.Members))

		for memberID, member := range group.Members {
			log.Printf("\n  成员 ID: %s\n", memberID)
			log.Printf("    客户端 ID: %s\n", member.ClientId)
			log.Printf("    客户端 Host: %s\n", member.ClientHost)
		}
	}
	log.Println("==========================================")
	return nil
}

func main() {
	client := NewKafkaClient(
		[]string{"47.100.253.132:9092"},
		"admin",
		"QE5E3GrFDSCFRcsB",
	)

	producer, err := client.NewProducer()
	if err != nil {
		log.Fatalf("创建生产者失败: %v", err)
	}
	defer producer.Close()

	log.Println("\n发送消息...")
	for i := 1; i <= 10; i++ {
		key := fmt.Sprintf("user:%d", i)
		value := fmt.Sprintf(`{"id":%d,"msg":"hello from producer","timestamp":"%s"}`,
			i, time.Now().Format("2006-01-02 15:04:05"))

		if err := client.SendMessage(producer, "test-heiheihei", key, value); err != nil {
			log.Printf("#%d 失败: %v\n", i, err)
		}
		time.Sleep(100 * time.Millisecond)
	}

	if err := client.ListAllTopics(); err != nil {
		log.Printf("%v\n", err)
	}

	time.Sleep(500 * time.Millisecond)
	if err := client.GetTopicInfo("test-heiheihei"); err != nil {
		log.Printf("%v\n", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var wg sync.WaitGroup

	client.StartConsumerGroupAsync(
		"test-consumer-group-1",
		[]string{"test-heiheihei"},
		ctx,
		&wg,
	)

	client.StartConsumerGroupAsync(
		"test-consumer-group-2",
		[]string{"test-heiheihei"},
		ctx,
		&wg,
	)

	time.Sleep(5 * time.Second)

	if err := client.ListConsumerGroups(); err != nil {
		log.Printf("%v\n", err)
	}

	if err := client.DescribeConsumerGroup("test-consumer-group-1"); err != nil {
		log.Printf("%v\n", err)
	}

	log.Println("\n⏳ 消费者运行中，按 Ctrl+C 退出...")

	// 监听系统信号
	sigterm := make(chan os.Signal, 1)
	signal.Notify(sigterm, syscall.SIGINT, syscall.SIGTERM)
	<-sigterm

	log.Println("\n收到退出信号，正在关闭...")
	cancel()
	wg.Wait()
	log.Println("所有消费者已关闭")
}
