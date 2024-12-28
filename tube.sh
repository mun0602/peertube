#!/bin/bash

# Định nghĩa thư mục làm việc
WORKDIR="/root/peertube"
NGINX_VOLUME="$WORKDIR/docker-volume/nginx"
CERTBOT_VOLUME="$WORKDIR/docker-volume/certbot"

# Cài đặt Docker và Docker Compose
echo ">>> Cài đặt Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl start docker
    systemctl enable docker
    rm get-docker.sh
else
    echo "Docker đã được cài đặt."
fi

echo ">>> Cài đặt Docker Compose..."
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep "tag_name" | cut -d '"' -f 4)
    curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
else
    echo "Docker Compose đã được cài đặt."
fi

# Tạo thư mục làm việc
echo ">>> Tạo thư mục làm việc..."
mkdir -p $WORKDIR
cd $WORKDIR

# Tải xuống docker-compose.yml và .env
echo ">>> Tải xuống docker-compose.yml..."
curl -s https://raw.githubusercontent.com/chocobozzz/PeerTube/master/support/docker/production/docker-compose.yml > docker-compose.yml

# Thêm tự động khởi động lại vào docker-compose.yml
sed -i '/services:/a\
  restart: unless-stopped' docker-compose.yml

echo ">>> Tải xuống .env..."
curl -s https://raw.githubusercontent.com/chocobozzz/PeerTube/master/support/docker/production/.env > .env

# Tùy chỉnh các giá trị trong tệp .env
echo ">>> Tùy chỉnh .env..."
read -p "Nhập tên miền (không bao gồm https://): " DOMAIN
read -p "Nhập địa chỉ email: " EMAIL
POSTGRES_USER="peertube"
POSTGRES_PASSWORD=$(openssl rand -hex 16)
PEERTUBE_SECRET=$(openssl rand -hex 32)

sed -i "s|<MY POSTGRES USERNAME>|$POSTGRES_USER|g" .env
sed -i "s|<MY POSTGRES PASSWORD>|$POSTGRES_PASSWORD|g" .env
sed -i "s|<MY DOMAIN>|$DOMAIN|g" .env
sed -i "s|<MY EMAIL ADDRESS>|$EMAIL|g" .env
sed -i "s|<MY PEERTUBE SECRET>|$PEERTUBE_SECRET|g" .env

# Thiết lập Nginx
echo ">>> Thiết lập Nginx..."
mkdir -p $NGINX_VOLUME
curl -s https://raw.githubusercontent.com/chocobozzz/PeerTube/master/support/nginx/peertube > $NGINX_VOLUME/peertube

# Tạo chứng chỉ SSL/TLS ban đầu
echo ">>> Tạo chứng chỉ SSL/TLS..."
mkdir -p $CERTBOT_VOLUME
docker run -it --rm --name certbot -p 80:80 -v "$CERTBOT_VOLUME/conf:/etc/letsencrypt" certbot/certbot certonly --standalone --email $EMAIL --agree-tos -d $DOMAIN

# Khởi động container PeerTube
echo ">>> Khởi động PeerTube..."
docker compose up -d

# Thêm cron job để kiểm tra container mỗi phút
echo ">>> Cấu hình cron job kiểm tra container..."
CRON_JOB="* * * * * docker ps | grep -q peertube || docker compose restart"
(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

echo ">>> Cài đặt hoàn tất."
echo ">>> Truy cập PeerTube tại: https://$DOMAIN"
echo ">>> Mật khẩu PostgreSQL: $POSTGRES_PASSWORD"
echo ">>> Mật khẩu admin mặc định có thể tìm thấy bằng lệnh:"
echo "docker compose logs peertube | grep -A1 root"
