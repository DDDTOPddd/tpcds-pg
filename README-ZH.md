# tpcds-kit

官方的 TPC-DS 工具可以在 [tpc.org](http://www.tpc.org/tpc_documents_current_versions/current_specifications.asp) 找到。

此版本基于 v2.10.0，并进行了以下修改：

* 允许在 macOS 环境下编译 (commit [2ec45c5](https://github.com/gregrahn/tpcds-kit/commit/2ec45c5ed97cc860819ee630770231eac738097c))
* 修复了明显的查询模板错误，例如：
  * query22a: [#31](https://github.com/gregrahn/tpcds-kit/issues/31)
  * query77a: [#43](https://github.com/gregrahn/tpcds-kit/issues/43)
* 将 `s_web_returns` 的列 `wret_web_site_id` 重命名为 `wret_web_page_id` 以符合规范。详情见 [#22](https://github.com/gregrahn/tpcds-kit/issues/22) 和 [#42](https://github.com/gregrahn/tpcds-kit/issues/42)。

要查看所有修改，请使用 diff 对比 master 分支和具体版本分支的文件。例如：`master` 对比 `v2.10.0`。

## 安装设置

### Linux

请确保已安装所需的开发工具：

Ubuntu 系统:
```
sudo apt-get install gcc make flex bison byacc git
```

CentOS/RHEL 系统:
```
sudo yum install gcc make flex bison byacc git
```

然后运行以下命令克隆仓库并构建工具：

```
git clone https://github.com/gregrahn/tpcds-kit.git
cd tpcds-kit/tools
make OS=LINUX
```

### macOS

请确保已安装所需的开发工具：

```
xcode-select --install
```

然后运行以下命令克隆仓库并构建工具：

```
git clone https://github.com/gregrahn/tpcds-kit.git
cd tpcds-kit/tools
make OS=MACOS
```

## 使用 TPC-DS 工具

### 数据生成

数据生成是通过 `dsdgen` 完成的。可以使用 `dsdgen -help` 查看所有可用选项。如果您不是在 `tools/` 目录下运行 `dsdgen`，那么您需要使用 `-DISTRIBUTIONS /.../tpcds-kit/tools/tpcds.idx` 选项来指定分布文件的路径。输出目录（通过 `-DIR` 选项指定）必须在运行 `dsdgen` 之前创建并存在。

### 查询生成

查询生成是通过 `dsqgen` 完成的。可以使用 `dsqgen -help` 查看所有可用选项。

以下命令可用于生成 10TB 数据量级别（`-SCALE 10000`）下的全部 99 个查询，按数字顺序排列（`-QUALIFY Y`），使用 Netezza 方言模板（`-DIALECT netezza`），并将输出存入 `/tmp/query_0.sql`（`-OUTPUT_DIR /tmp`）。

```
dsqgen \
-DIRECTORY ../query_templates \
-INPUT ../query_templates/templates.lst \
-VERBOSE Y \
-QUALIFY Y \
-SCALE 10000 \
-DIALECT netezza \
-OUTPUT_DIR /tmp
```