#!/bin/bash
exec > /var/log/user-data.log 2>&1

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

aws s3 cp s3://${s3_bucket}/config/.env.prod.properties /home/ubuntu/.env.prod.properties
mkdir -p /home/ubuntu/secrets

# CloudWatch Agent 네임스페이스를 jeonlog/EC2로 설정
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CW_CONFIG'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/lib/docker/containers/**/*-json.log",
            "log_group_name": "/ec2/jeonlog/docker",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "/ec2/jeonlog/syslog",
            "log_stream_name": "{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "jeonlog/EC2",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "swap": {
        "measurement": ["swap_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"],
        "metrics_collection_interval": 60
      }
    }
  }
}
CW_CONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
aws s3 cp s3://${s3_bucket}/secrets/firebase-service-account.json /home/ubuntu/secrets/firebase-service-account.json
chmod 600 /home/ubuntu/secrets/firebase-service-account.json

cat > /usr/local/bin/deploy.sh << 'DEPLOY'
#!/bin/bash
exec >> /var/log/deploy.log 2>&1
echo "[$(date)] Starting deploy..."
REGION="ap-northeast-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com
IMAGE_URL=$(aws ssm get-parameter --name /jeonlog/prod/ecr-image-url --region $REGION --query Parameter.Value --output text)
aws s3 cp s3://${s3_bucket}/config/.env.prod.properties /home/ubuntu/.env.prod.properties 2>/dev/null || true
aws s3 cp s3://${s3_bucket}/secrets/firebase-service-account.json /home/ubuntu/secrets/firebase-service-account.json 2>/dev/null || true
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REGISTRY
docker pull $IMAGE_URL
docker stop app 2>/dev/null || true
docker rm app 2>/dev/null || true
docker run -d --name app --restart unless-stopped \
  -e SPRING_PROFILES_ACTIVE=prod \
  --env-file /home/ubuntu/.env.prod.properties \
  -p ${app_port}:${app_port} \
  -v /home/ubuntu/secrets/firebase-service-account.json:/home/ubuntu/secrets/firebase-service-account.json \
  $IMAGE_URL
echo "[$(date)] Deploy complete: $IMAGE_URL"
DEPLOY
chmod +x /usr/local/bin/deploy.sh

IMAGE_URL=$(aws ssm get-parameter --name /jeonlog/prod/ecr-image-url --region $REGION --query Parameter.Value --output text 2>/dev/null)

if [ -n "$IMAGE_URL" ] && [ "$IMAGE_URL" != "PLACEHOLDER" ]; then
  /usr/local/bin/deploy.sh
fi
