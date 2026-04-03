#!/bin/bash
set -u
set -o pipefail

# ============== 自动获取当前工作目录 ==============
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${BASE_DIR}/tools"
DAT_DIR="${BASE_DIR}/tpcds_data"

# ============== 数据库连接配置 ==============
# 根据刚才的 Python 测试文件提取的配置
DB_NAME="${TPCDS_DB_NAME:-tpcds_1g}"
DB_USER="${TPCDS_DB_USER:-dddtop}"
DB_PASS="${TPCDS_DB_PASS:-8414}"
DB_HOST="${TPCDS_DB_HOST:-localhost}"
MAX_JOBS="${MAX_JOBS:-4}"

export PGPASSWORD="$DB_PASS"

echo "========================================"
echo "目标数据库: $DB_NAME"
echo "数据库用户: $DB_USER"
echo "并发导入数: $MAX_JOBS"
echo "数据存放夹: $DAT_DIR"
echo "========================================"

# ==========================================================
# Step 1: 在库中建表
# ==========================================================
echo "[1/2] 正在新建 TPCDS 表结构..."
psql -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -v ON_ERROR_STOP=1 -f "${TOOLS_DIR}/tpcds.sql" > /dev/null
if [ $? -eq 0 ]; then
    echo "=> 表结构创建成功！"
else
    echo "=> 表结构创建失败，请检查连接或SQL。"
    exit 1
fi

# ==========================================================
# Step 2: 导入数据
# ==========================================================
echo "[2/2] 开始导入数据..."

load_data_to_table() {
    local dat_file="$1"
    local table_name
    local escaped_dat_file

    # 使用 awk 剥离文件名后面的并发行标识（如 _1_4.dat 变成原来的表名）
    # 由于生成工具加了 _child_parallel 后缀，需要把后面的两个数字截断提取表名
    table_name=$(basename "$dat_file" .dat | awk -F'_' '{s=$1; for (i=2; i<NF-1; i++) s=s"_"$i; print s}')

    [[ -n "$table_name" ]] || {
        echo "无法从文件名解析表名: $dat_file"
        return 1
    }

    escaped_dat_file=${dat_file//\'/\'\'}

    if psql -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -c "\COPY $table_name FROM '$escaped_dat_file' WITH NULL '' DELIMITER '|' CSV" >> /dev/null 2>&1; then
        echo " - 成功: $table_name <- $(basename "$dat_file")"
        return 0
    else
        echo " - 失败: $table_name <- $(basename "$dat_file")"
        return 1
    fi
}

shopt -s nullglob
dat_files=("$DAT_DIR"/*.dat)

if [ "${#dat_files[@]}" -eq 0 ]; then
    echo "目录 $DAT_DIR 下未找到 .dat 文件.."
    exit 1
fi

count=0
failed_jobs=0

for dat_file in "${dat_files[@]}"; do
    load_data_to_table "$dat_file" &
    count=$((count + 1))

    # 控制后台并发数
    if [ "$count" -ge "$MAX_JOBS" ]; then
        if ! wait -n; then
            failed_jobs=$((failed_jobs + 1))
        fi
        count=$((count - 1))
    fi
done

wait # 等待最后剩余的作业完成

if [ "$failed_jobs" -gt 0 ]; then
    echo "导入完毕！但有失败的文件，请检查报错日志。"
    exit 1
else
    echo "全部数据成功导入 PostgreSQL 库 $DB_NAME 中！"
fi

