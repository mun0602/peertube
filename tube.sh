#!/bin/bash

set -e

# Màu cho output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Kiểm tra lệnh
command_exists() {
    command -v "$@" > /dev/null 2>&1
}

# Kiểm tra cổng 80/443 và đóng tiến trình nếu bị chiếm dụng
check_ports() {
    if sudo lsof -i :80 || sudo lsof -i :443; then
        echo -e "${RED}Cổng 80 hoặc 443 đã bị chiếm dụng. Đang đóng tiến trình...${NC}"
        sudo fuser -k 80/tcp 443/tcp
        echo -e "${GREEN}Đã giải phóng cổng 80 và 443.${NC}"
    else
        echo -e "${GREEN}Cổng 80 và 443 sẵn sàng sử dụng.${NC}"
    fi
}

# Cài đặt Node.js và NPM
install_nodejs_npm() {
    if command_exists node && command_exists npm; then
        NODE_VERSION=$(node -v | grep -o -E '[0-9]+' | head -1)
        if [ "$NODE_VERSION" -lt 16 ]; then
            echo -e "${RED}Node.js phiên bản quá cũ. Đang nâng cấp...${NC}"
            curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
            sudo apt install -y nodejs
        else
            echo -e "${GREEN}Node.js đã được cài đặt và đúng phiên bản.${NC}"
        fi
    else
        echo -e "${GREEN}Đang cài đặt Node.js và NPM...${NC}"
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt install -y nodejs
        echo -e "${GREEN}Node.js và NPM đã được cài đặt thành công.${NC}"
    fi
}

# Kiểm tra và nâng cấp Docker
install_docker() {
    if command_exists docker; then
        DOCKER_VERSION=$(docker --version | grep -o -E '[0-9]+' | head -1)
        if [ "$DOCKER_VERSION" -lt 20 ]; then
            echo -e "${RED}Docker phiên bản quá cũ. Đang nâng cấp Docker...${NC}"
            sudo apt update
            sudo apt remove -y docker docker-engine docker.io containerd runc
            sudo apt install -y docker.io
            sudo systemctl enable --now docker
        else
            echo -e "${GREEN}Docker đã được cài đặt và đúng phiên bản.${NC}"
        fi
    else
        echo "Cài đặt Docker..."
        sudo apt update
        sudo apt install -y docker.io
        sudo systemctl enable --now docker
        echo -e "${GREEN}Docker đã được cài đặt thành công.${NC}"
    fi
}

# Cài đặt Docker Compose V2
install_docker_compose() {
    if command_exists docker-compose; then
        COMPOSE_VERSION=$(docker-compose version --short | cut -d '.' -f1)
        if [ "$COMPOSE_VERSION" -lt 2 ]; then
            echo -e "${RED}Docker Compose quá cũ. Đang nâng cấp...${NC}"
            sudo apt remove -y docker-compose
            sudo curl -SL https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        else
            echo -e "${GREEN}Docker Compose đã đúng phiên bản.${NC}"
        fi
    else
        echo "Cài đặt Docker Compose..."
        sudo curl -SL https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        echo -e "${GREEN}Docker Compose đã được cài đặt thành công.${NC}"
    fi
}

# Cấu hình PeerTube
configure_peertube() {
    read -p "Nhập tên miền (domain, ví dụ: example.com): " DOMAIN
    read -p "Nhập email quản trị: " EMAIL
    read -p "Nhập mật khẩu PostgreSQL: " POSTGRES_PASSWORD
    read -p "Nhập mật khẩu admin cho PeerTube: " PEERTUBE_PASSWORD

    mkdir -p /opt/peertube
    cd /opt/peertube

    echo "Tải file docker-compose.yml và .env..."
    curl -sSL https://raw.githubusercontent.com/chocobozzz/PeerTube/master/support/docker/production/docker-compose.yml -o docker-compose.yml || { echo -e "${RED}Tải file docker-compose thất bại.${NC}"; exit 1; }
    curl -sSL https://raw.githubusercontent.com/chocobozzz/PeerTube/master/support/docker/production/.env -o .env || { echo -e "${RED}Tải file .env thất bại.${NC}"; exit 1; }

    echo "Cấu hình .env..."
    sed -i "s/<MY POSTGRES USERNAME>/peertube/g" .env
    sed -i "s/<MY POSTGRES PASSWORD>/$POSTGRES_PASSWORD/g" .env
    sed -i "s/<MY DOMAIN>/$DOMAIN/g" .env
    sed -i "s/<MY EMAIL ADDRESS>/$EMAIL/g" .env
    sed -i "s/<MY PEERTUBE SECRET>/$(openssl rand -hex 32)/g" .env
}

# Kiểm tra tên miền
check_domain() {
    if ! ping -c 1 $DOMAIN &> /dev/null; then
        echo -e "${RED}Tên miền $DOMAIN không trỏ về IP máy chủ này. Kiểm tra DNS.${NC}"
        exit 1
    else
        echo -e "${GREEN}Tên miền $DOMAIN trỏ đúng IP máy chủ.${NC}"
    fi
}

# Đóng và xóa các container đang chạy
cleanup_containers() {
    RUNNING_CONTAINERS=$(docker ps -q)
    if [ -n "$RUNNING_CONTAINERS" ]; then
        echo -e "${RED}Đang đóng và xóa các container đang chạy...${NC}"
        docker stop $RUNNING_CONTAINERS
        docker rm $RUNNING_CONTAINERS
        echo -e "${GREEN}Các container đã được đóng và xóa.${NC}"
    else
        echo -e "${GREEN}Không có container nào đang chạy.${NC}"
    fi
}

# Thiết lập Nginx và chứng chỉ SSL
setup_nginx_ssl() {
    echo "Kiểm tra các container đang chạy..."
    cleanup_containers
    echo "Cấu hình Nginx và SSL..."
    mkdir -p docker-volume/nginx docker-volume/certbot
    curl -sSL https://raw.githubusercontent.com/chocobozzz/PeerTube/master/support/nginx/peertube -o docker-volume/nginx/peertube || { echo -e "${RED}Tải cấu hình Nginx thất bại.${NC}"; exit 1; }

    docker run -it --rm --name certbot -p 80:80 -v "$(pwd)/docker-volume/certbot/conf:/etc/letsencrypt" certbot/certbot certonly --standalone -d $DOMAIN --email $EMAIL --agree-tos || { echo -e "${RED}Tạo chứng chỉ SSL thất bại.${NC}"; exit 1; }
}

# Khởi động PeerTube
deploy_peertube() {
    echo "Khởi động PeerTube..."
    docker-compose up -d || { echo -e "${RED}Khởi động PeerTube thất bại.${NC}"; exit 1; }
    sleep 10
    ADMIN_PASSWORD=$(docker-compose exec -u peertube peertube npm run reset-password -- -u root | grep "User password:" | awk '{print $3}')
    echo -e "${GREEN}Cài đặt hoàn thành!${NC}"
    echo -e "${GREEN}Tên miền: ${NC}https://$DOMAIN"
    echo -e "${GREEN}Admin: root${NC}"
    echo -e "${GREEN}Mật khẩu admin: $ADMIN_PASSWORD${NC}"
    send_email_notification
}

main() {
    check_ports
    install_nodejs_npm
    install_docker
    install_docker_compose
    configure_peertube
    check_domain
    setup_nginx_ssl
    deploy_peertube
}

main
