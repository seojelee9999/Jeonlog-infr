#!/bin/bash
exec > /var/log/grafana-setup.log 2>&1

mkdir -p /home/ubuntu/monitoring

# Prometheus 설정 — ASG 인스턴스 자동 탐색 (EC2 Service Discovery)
cat > /home/ubuntu/monitoring/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'jeonlog-nodes'
    ec2_sd_configs:
      - region: ${aws_region}
        port: 9100
        filters:
          - name: "tag:aws:autoscaling:groupName"
            values: ["${asg_name}"]
    relabel_configs:
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance
      - source_labels: [__meta_ec2_tag_Name]
        target_label: name

  - job_name: 'jeonlog-app'
    metrics_path: '/actuator/prometheus'
    ec2_sd_configs:
      - region: ${aws_region}
        port: 5000
        filters:
          - name: "tag:aws:autoscaling:groupName"
            values: ["${asg_name}"]
    relabel_configs:
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance
EOF

# Docker Compose — Prometheus + Grafana
cat > /home/ubuntu/monitoring/docker-compose.yml << EOF
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=15d'
      - '--web.enable-remote-write-receiver'
      - '--enable-feature=native-histograms'
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${grafana_admin_password}
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-piechart-panel,redis-datasource

  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    command: >
      redis-server
      --requirepass ${redis_password}
      --maxmemory 256mb
      --maxmemory-policy allkeys-lru
      --appendonly yes
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    mem_limit: 300m

volumes:
  prometheus-data:
  grafana-data:
  redis-data:
EOF

chown -R ubuntu:ubuntu /home/ubuntu/monitoring
cd /home/ubuntu/monitoring
docker compose up -d

echo "[$(date)] Grafana setup complete — http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3000"
