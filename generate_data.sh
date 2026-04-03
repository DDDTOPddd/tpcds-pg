#!/bin/bash
set -u
set -o pipefail

# ============== 自动获取当前工作目录 ==============
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DSGEN_PATH="${DSGEN_PATH:-${BASE_DIR}}"
DSDGEN_PARALLEL="${DSDGEN_PARALLEL:-4}"
DSQGEN_SCALE="${DSQGEN_SCALE:-1}"
DSQGEN_DIALECT="${DSQGEN_DIALECT:-postgresql}"

declare -a dsdgen_pids=()
declare -a dsqgen_pids=()

# ==========================================================
# 函数: generate_dat_data
# 描述: 生成TPC-DS测试数据
# ==========================================================
generate_dat_data() {
    local TOOLS_DIR=${1:-"${DSGEN_PATH}/tools"}
    local SCALE=${2:-1}   # 默认生成 1GB
    local child

    cd "$TOOLS_DIR" || {
        echo "无法进入目录 $TOOLS_DIR"
        exit 1
    }

    [[ -x "./dsdgen" ]] || {
        echo "未找到可执行文件: $TOOLS_DIR/dsdgen, 请先执行 make OS=LINUX 编译"
        return 1
    }

    # 自动创建目标目录
    mkdir -p "${BASE_DIR}/tpcds_data"

    [[ "$DSDGEN_PARALLEL" =~ ^[1-9][0-9]*$ ]] || {
        echo "DSDGEN_PARALLEL 必须是大于 0 的整数,当前值: $DSDGEN_PARALLEL"
        return 1
    }

    echo "正在拉起 ${DSDGEN_PARALLEL} 个后台进程，生成规模为 ${SCALE}GB 的数据..."
    # 清空之前可能遗留的报错日志
    > "${BASE_DIR}/tpcds_data.log"

    for ((child = 1; child <= DSDGEN_PARALLEL; child++)); do
        nohup ./dsdgen -scale "$SCALE" -dir "${BASE_DIR}/tpcds_data" \
            -parallel "$DSDGEN_PARALLEL" -child "${child}" \
            -terminate n >>"${BASE_DIR}/tpcds_data.log" 2>&1 &
        dsdgen_pids+=("$!")
    done

    echo "TPC-DS 数据生成任务已启动, 并发数: $DSDGEN_PARALLEL.."
    return 0
}

# ==========================================================
# 函数: generate_query_data
# 描述: 生成TPC-DS查询SQL
# ==========================================================
generate_query_data() {
    local TOOLS_DIR="${DSGEN_PATH}/tools"

    cd "$TOOLS_DIR" || {
        echo "无法进入目录 $TOOLS_DIR"
        exit 1
    }

    [[ -x "./dsqgen" ]] || {
        echo "未找到可执行文件: $TOOLS_DIR/dsqgen, 请先编译"
        return 1
    }

    mkdir -p "${BASE_DIR}/tpcds_query"
    > "${BASE_DIR}/tpcds_query.log"

    # 通过 loop 单独为每个模板生成 SQL，实现一句SQL对应一个文件
    echo "TPC-DS 正在单独生成 99 条查询语句文件..."
    (
        for i in {1..99}; do
            ./dsqgen -output_dir "${BASE_DIR}/tpcds_query" \
                -template "query${i}.tpl" \
                -scale "$DSQGEN_SCALE" \
                -dialect "$DSQGEN_DIALECT" \
                -directory "${BASE_DIR}/query_templates" \
                >>"${BASE_DIR}/tpcds_query.log" 2>&1
                
            if [ -f "${BASE_DIR}/tpcds_query/query_0.sql" ]; then
                mv "${BASE_DIR}/tpcds_query/query_0.sql" "${BASE_DIR}/tpcds_query/query_${i}.sql"
            fi
        done
        echo "TPC-DS 查询语句 99 个文件已全部生成完毕！"
    ) &

    dsqgen_pids+=("$!")
    return 0
}

# ==========================================================
# 函数: wait_generate_jobs
# 描述: 等待后台生成任务结束并汇总退出状态
# ==========================================================
wait_generate_jobs() {
    local pid
    local total_jobs=0
    local failed_jobs=0

    for pid in "${dsdgen_pids[@]}" "${dsqgen_pids[@]}"; do
        [ -n "$pid" ] || continue
        total_jobs=$((total_jobs + 1))
        if ! wait "$pid"; then
            failed_jobs=$((failed_jobs + 1))
        fi
    done

    if [ "$failed_jobs" -gt 0 ]; then
        echo "生成任务结束, 失败任务数: $failed_jobs/$total_jobs.."
        return 1
    fi

    echo "生成任务全部完成.."
    return 0
}

generate_dat_data "${DSGEN_PATH}/tools" "${DSQGEN_SCALE}" || exit 1
generate_query_data || exit 1
wait_generate_jobs || exit 1

# 数据生成完成后，由于我们使用了 -terminate n 参数，已经不需要去出管线符
echo "全部预处理完成！"

