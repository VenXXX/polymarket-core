#!/bin/bash

# ==================== Polymarket 本地环境一键启动脚本 ====================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检测 Docker Compose 命令
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    log_error "Docker Compose 未安装"
    exit 1
fi

log_info "使用 Docker Compose 命令：$COMPOSE_CMD"

echo ""
echo "========================================"
echo "  Polymarket 本地环境一键启动"
echo "========================================"
echo ""

# 检查 Docker
log_info "检查依赖..."
if ! command -v docker &> /dev/null; then
    log_error "Docker 未安装"
    exit 1
fi
log_success "Docker 已安装"

# 检查 Foundry（可选）
if ! command -v forge &> /dev/null; then
    log_warn "Foundry (forge) 未安装，将跳过合约部署步骤"
    log_info "安装 Foundry: curl -L https://foundry.paradigm.xyz | bash"
    SKIP_FOUNDRY=true
else
    log_success "Foundry 已安装"
    SKIP_FOUNDRY=false
fi

# 停止旧容器
log_info "停止旧容器..."
$COMPOSE_CMD down 2>/dev/null || true
log_success "旧容器已停止"

# 启动基础设施
log_info "启动基础设施（Redis + MySQL + Anvil）..."
$COMPOSE_CMD up -d

log_info "等待服务启动..."
sleep 15

# 检查 Redis
if $COMPOSE_CMD exec -T redis redis-cli ping &> /dev/null; then
    log_success "Redis 已启动"
else
    log_error "Redis 启动失败"
    $COMPOSE_CMD logs redis
    exit 1
fi

# 检查 MySQL
if $COMPOSE_CMD exec -T mysql mysqladmin ping -h localhost -u root -proot &> /dev/null; then
    log_success "MySQL 已启动"
else
    log_error "MySQL 启动失败"
    $COMPOSE_CMD logs mysql
    exit 1
fi

# 检查 Anvil
sleep 5
if curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | grep -q "jsonrpc"; then
    log_success "Anvil 已启动 (http://localhost:8545)"
else
    log_warn "Anvil 可能还在启动中"
fi

log_success "基础设施启动完成"

echo ""
echo "========================================"
echo "  基础设施已启动！"
echo "========================================"
echo ""
echo "✅ Redis:   localhost:6379"
echo "✅ MySQL:   localhost:3306"
echo "✅ Anvil:   http://localhost:8545"
echo ""

if [ "$SKIP_FOUNDRY" = true ]; then
    echo "========================================"
    echo "  ⚠️  Foundry 未安装，跳过合约部署"
    echo "========================================"
    echo ""
    echo "安装 Foundry 后运行:"
    echo "  curl -L https://foundry.paradigm.xyz | bash"
    echo "  foundryup"
    echo "  forge script script/Deploy.s.sol --broadcast --rpc-url http://localhost:8545"
    echo ""
else
    echo "========================================"
    echo "  下一步：部署智能合约"
    echo "========================================"
    echo ""
    log_info "运行合约部署..."
    forge script script/Deploy.s.sol --broadcast --rpc-url http://localhost:8545 --slow
fi
