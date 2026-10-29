> Curated public copy of a local final report. Local-only paths and links were de-identified; subordinate logs/data may not be in this repository. Measurements were not rerun for publication.

# C13: PDX Vector Search in DuckLake — 可行性审查

**日期：2026-10-27。Executive Verdict：NO-GO，针对“现在投入数月完成有独立机制、跨真实负载竞争力、潜在 workshop 价值的优秀 MSc 论文”这一标准。** CWI 官方 C13 的“本地集成＋性能比较”仍可能是合理的集成型毕设，但它不是本次要求的论文充分条件。目前确认的主要缺口是已有 PDX/DuckIR 与 DuckLake 版本化 Parquet 存储之间的适配；尚无证据表明一个小范围、未被已有工作覆盖的机制能带来稳定端到端净收益。停止于审计和隔离实验，**未实现核心扩展，未修改 C17，未提交 PR**。

下文“确认”=固定版本的源码/官方文献/本次原始观测；“推断”=可行架构但未编译验证；“未知”不可解释为零成本。公开证据不能排除 CWI 内部尚未公开的实现。

## 1. 已有工作、版本和创新性重叠

固定 HEAD：`cwida/PDX@3059d67e133112a515f5fc778b45ba48254e8cc0`、`Noorts/PDXearch@f1a2abf80d16e39ea2cd521d15ea52ede72c86c3`（现名 DuckIR）、`duckdb/ducklake@4c8981b8519013a58cdfc173b03eeb2b47d45497`、`duckdb/duckdb-vss@3685131eacaf0d467d430be5c4e5e7d1d483437a`、`lance-format/lance@0c80e6292fa4496b995b65faaade9a2eb85219ec`。DuckIR [CMake](https://github.com/Noorts/PDXearch/blob/f1a2abf80d16e39ea2cd521d15ea52ede72c86c3/CMakeLists.txt#L36-L42) 固定的是较旧 PDX `448163660149a6f5296b79cc7d010141beed504a`，不可混报版本。

| 想法 | 已有证据 | 对 C13 的含义 |
|---|---|---|
| PDX 算法、IVF/两层 IVF、维度剪枝 | [SIGMOD 2025 论文](https://ir.cwi.nl/pub/35044/35044.pdf)；[PDX `ivf_tree.hpp`](https://github.com/cwida/PDX/blob/3059d67e133112a515f5fc778b45ba48254e8cc0/include/pdx/indexes/ivf_tree.hpp#L267-L357)；[PR #14](https://github.com/cwida/PDX/pull/14)、[#16](https://github.com/cwida/PDX/pull/16) 已有 resumable/filtered search、外部谓词、bulk gather；[#25](https://github.com/cwida/PDX/pull/25) 已有 I/O-aware cluster 排序。 | 算法、过滤和持久化不能重复包装为原创；[分页加载](https://github.com/cwida/PDX/blob/3059d67e133112a515f5fc778b45ba48254e8cc0/include/pdx/indexes/ivf_vanilla.hpp#L46-L61) 也不是所有 index 类型等价支持。 |
| DuckDB–PDX 集成 | Simon van Noort [2025 作者摘要](https://dbdbd2025.uantwerpen.be/wp-content/uploads/2025/12/dbdbd25_16.pdf) 已提出 row-group-aligned IVF、并行、过滤策略，明确 DuckLake future work；[CWI seminar](https://dsdsd.da.cwi.nl/upcoming_talks/) 确认学生项目。DuckIR [README](https://github.com/Noorts/PDXearch/blob/f1a2abf80d16e39ea2cd521d15ea52ede72c86c3/README.md#L133-L219) 与合并 [#26](https://github.com/Noorts/PDXearch/pull/26)、[#27](https://github.com/Noorts/PDXearch/pull/27)、[#29](https://github.com/Noorts/PDXearch/pull/29)、[#31](https://github.com/Noorts/PDXearch/pull/31)、[#35](https://github.com/Noorts/PDXearch/pull/35) 已有 native 表维护、过滤、late materialization、checkpoint/WAL、out-of-core。 | 新任务是真正的 DuckLake 存储适配，但单纯移植已有机制只算集成；未找到公开完整学生论文不证明不存在。 |
| A：Top-K 记录取回 | DuckIR [native Fetch](https://github.com/Noorts/PDXearch/blob/f1a2abf80d16e39ea2cd521d15ea52ede72c86c3/src/index/search/vss_index_scan_physical.cpp#L195-L218)，VSS [native Fetch](https://github.com/duckdb/duckdb-vss/blob/3685131eacaf0d467d430be5c4e5e7d1d483437a/src/hnsw/hnsw_index_scan.cpp#L182-L207)，Lance [`take_rows`](https://github.com/lance-format/lance/blob/0c80e6292fa4496b995b65faaade9a2eb85219ec/rust/lance/src/dataset.rs#L1829-L1879) 已有。DuckDB **开放** [Parquet page-index PR #27326](https://github.com/duckdb/duckdb/pull/27326) 正改善页剪枝/跳转。 | 仅“batch top-K IDs”或“late materialization”不是新贡献。可能剩下快照正确、低读放大 Parquet 取回，但须打败强基线和在研 PR。 |
| B：snapshot-consistent indexing | Lance [immutable index segments / manifest / partial coverage / compaction](https://github.com/lance-format/lance/blob/0c80e6292fa4496b995b65faaade9a2eb85219ec/docs/src/format/index/index.md#L48-L120) 与 [fragment reuse](https://github.com/lance-format/lance/blob/0c80e6292fa4496b995b65faaade9a2eb85219ec/docs/src/format/index/system/frag_reuse.md#L1-L33) 已覆盖通用架构。 | DuckLake 专属实现缺口是真实的；通用 manifest/delta/remap 思路非原创，维护范围很宽。 |
| C：filtered vector search | DuckIR 已有 predicate/resume；VSS 当前 [BuildFilterBitmap](https://github.com/duckdb/duckdb-vss/blob/3685131eacaf0d467d430be5c4e5e7d1d483437a/src/hnsw/hnsw_index_scan.cpp#L45-L110)（O(n) 过滤列扫描，不等于免费）；[LanceDB](https://docs.lancedb.com/search/filtering)、[ACORN](https://arxiv.org/abs/2403.04871)、[pgvector iterative scan](https://github.com/pgvector/pgvector#iterative-index-scans) 已覆盖常规方案。 | 文件元数据+PDX 也许可优化远端 I/O，但没有真实 filtered 工作负载证据；单调 nprobe 阈值不是足够论文贡献。 |

[CWI C13](https://www.cwi.nl/en/research/database-architectures/general-information-on-msc-projects-at-the-da-group/msc-projects-at-cwi-amsterdam/) 的出版物是 extended goal，官方列项目不证明创新性。页面把 LanceDB 泛称 closed-source/proprietary 不能作当前研究定位：[Lance](https://github.com/lance-format/lance) 与 [LanceDB](https://github.com/lancedb/lancedb) 有公开源码。VSS 当前已有 [`SerializeToWAL`](https://github.com/duckdb/duckdb-vss/blob/3685131eacaf0d467d430be5c4e5e7d1d483437a/src/hnsw/hnsw_index.cpp#L608-L636)，但本次未做 crash-recovery 验证。

## 2. 真实源码架构和端到端接口（含隐藏成本）

**直接复用 DuckIR 不可行，已确认。** DuckLake 实测 `FLOAT[128]` 建表失败，`FLOAT[]` 能建表且 query-time 可 cast 为 `FLOAT[128]`；标准/HNSW `CREATE INDEX` 均报 `DuckLake does not support indexes`，见 [DuckLake types](https://github.com/duckdb/ducklake/blob/4c8981b8519013a58cdfc173b03eeb2b47d45497/src/common/ducklake_types.cpp#L18-L51) 和 [catalog](https://github.com/duckdb/ducklake/blob/4c8981b8519013a58cdfc173b03eeb2b47d45497/src/storage/ducklake_catalog.cpp#L1166-L1172)。DuckIR optimizer 要求 `seq_scan` + `IsDuckTable()` [源码](https://github.com/Noorts/PDXearch/blob/f1a2abf80d16e39ea2cd521d15ea52ede72c86c3/src/index/search/duckir_scan_optimizer.cpp#L737-L751)，CREATE INDEX 需要 `FLOAT[N] ARRAY` [源码](https://github.com/Noorts/PDXearch/blob/f1a2abf80d16e39ea2cd521d15ea52ede72c86c3/src/index/create/vss_index_create_plan.cpp#L75-L89)，Top-K 用 `DuckTransaction` + native `GetStorage().Fetch`；[持久化](https://github.com/Noorts/PDXearch/blob/f1a2abf80d16e39ea2cd521d15ea52ede72c86c3/src/index/vss_index.cpp#L878-L930) 绑定 native block allocator。PDX 搜索内核、stream serialization、cluster source、predicate API 可借用；catalog/optimizer/fetch/事务/存储生命周期不可直接复用。

**最小冻结快照架构（推断，未实现）：**

```text
DuckLake Parquet FLOAT[] at snapshot S
 -> DuckLake reader 扫描并验证维度、NULL/NaN、metric；批量构建 PDX shard
 -> PDX uint32 局部 ID + (S, DuckLake BIGINT rowid, file ID, file_row_number) locator sidecar
 -> 完整 sidecar 写入、校验后发布 S manifest（不冒充 DuckLake 原子 commit）
 -> 显式 SQL table function 在同一 S 搜 PDX Top-K
 -> 映射 ID，按文件/行组分组，经 DuckLake reader 取回并验证 K 个行
 -> 对 delete/版本做可见性检查和必要的迭代补足，再输出 SQL 结果
```

PDX candidate ID 是 [`uint32_t`](https://github.com/cwida/PDX/blob/3059d67e133112a515f5fc778b45ba48254e8cc0/include/pdx/common.hpp#L215-L217)，现有 [dense row-ID mapping](https://github.com/cwida/PDX/blob/3059d67e133112a515f5fc778b45ba48254e8cc0/include/pdx/indexes/ivf_utils.hpp#L163-L229) 对稀疏 64-bit DuckLake rowid 不合适。DuckLake `rowid` 是稳定逻辑 ID，但其 [virtual-column filter 不生成文件裁剪](https://github.com/duckdb/ducklake/blob/4c8981b8519013a58cdfc173b03eeb2b47d45497/src/storage/ducklake_multi_file_list.cpp#L119-L133)；`file_index` 只是扫描内编号，[`GetRowIdColumns`](https://github.com/duckdb/ducklake/blob/4c8981b8519013a58cdfc173b03eeb2b47d45497/src/storage/ducklake_table_entry.cpp#L427-L450) 也不能变出持久 locator。对于某些文件 reader 从内部 `ROW_ID_FIELD_ID` 读显式 ID，而非 `row_id_start + file_row_number`，[源码](https://github.com/duckdb/ducklake/blob/4c8981b8519013a58cdfc173b03eeb2b47d45497/src/storage/ducklake_multi_file_reader.cpp#L635-L667)。因此 compaction/排序后不能普遍用简单减法定位；[row lineage 文档](https://ducklake.select/docs/stable/duckdb/advanced_features/row_lineage) 只保证逻辑 ID，不保证物理位置。

| 步骤 | 可用接口（源码）与最小修改 | 必须保持的约束 / 失败风险 |
|---|---|---|
| 确定可见文件 | [`DuckLakeMetadataManager::GetFilesForTable(table,snapshot,filter,include_local_changes)`](https://github.com/duckdb/ducklake/blob/4c8981b8519013a58cdfc173b03eeb2b47d45497/src/storage/ducklake_metadata_manager.cpp#L2364) | build/query 同 S；begin/end snapshot 可见性、local changes、schema mapping。 |
| 选择文件取回 | [`DuckLakeMultiFileList(read_info,files_to_scan)`](https://github.com/duckdb/ducklake/blob/4c8981b8519013a58cdfc173b03eeb2b47d45497/src/storage/ducklake_multi_file_list.cpp#L36-L44)，compaction 已用 | 是**指定文件扫描，不是点 fetch**；需 residual rowid/位置筛选，仍可能读整页/行组。直接 `read_parquet` 会绕开 [delete/inline deletion/transaction/snapshot reader](https://github.com/duckdb/ducklake/blob/4c8981b8519013a58cdfc173b03eeb2b47d45497/src/storage/ducklake_multi_file_reader.cpp#L310-L422)，可能返回错版本或已删行。 |
| INSERT / UPDATE / DELETE | 冻结 S 原型应拒绝其他快照或退回精确扫描；完整系统要 delta、补足 K、失效规则 | UPDATE 为 delete+insert、[保留逻辑 rowid](https://github.com/duckdb/ducklake/blob/4c8981b8519013a58cdfc173b03eeb2b47d45497/src/storage/ducklake_update.cpp#L182-L239)，但 vector 值可变；单靠 rowid/可见性过滤不能纠正旧距离。 |
| Compaction / GC | 每个新 S 重建 locator 或正确解释 lineage；保留旧 manifest 到旧读者结束 | 文件和物理 offset 会变，必须证明 sidecar 原子发布、崩溃回收、历史快照不串版。 |
| SQL 接口 | 起步显式 table function；完整 `ORDER BY distance LIMIT K` rewrite 后置 | CTE、过滤、join、投影语义与 optimizer 变成额外工程；不可把接口出现视为真正端到端 SQL 集成。 |

**范围估算而非工期承诺**：冻结 S 的验证适配仍需 DuckLake reader/file-list 桥、PDX 转换/构建、locator/manifest、table function、测试等约 4–7 模块；若要完整 INSERT/DELETE/UPDATE、compaction、snapshot、事务失败原子性，则触及 catalog、metadata、transaction、writer、compactor、GC、optimizer/reader 的更广接口。这正是“表面一个 hook、实际底层重构”的风险。

## 3. 实验：实测、可推断空间、证据缺口

环境：macOS arm64 / Darwin 25.5.0；Python DuckDB `2.0.0`、DuckLake extension `417a9117f5`、VSS extension `3685131eac`，4 threads。公开 [ANN-Benchmarks](https://github.com/erikbern/ann-benchmarks#data-sets) 两个真实向量来源：SIFT1M 128D/L2 (`sift-128-euclidean.hdf5`, SHA256 `dd6f0a6ed6b7ebb8934680f861a33ed01ff33991eaee4fd60914d854a0ca5984`)，GloVe 1,183,514 100D/cosine (`glove-100-angular.hdf5`, SHA256 `544af1d5e84e112cd4749571dcfd8ca109818a572f850af75a3a09e093a953c4`)。每表 40 批 INSERT → 40 Parquet 文件；active data-file bytes 分别约 133.5/484.7 MB。各取 8 个测试 query × 3 次交错计时，24 样本的 p95 为最近秩；足够作淘汰初筛，不够作统计显著性结论。SQL 返回 `id,payload`；`payload='record-N'` **是人工占位，不是真实记录负载**，数据亦无真实过滤标签。exact 的 Top-10 与数据集真值在这 8 个 query 全部吻合。

| 数据 / 观察 | DuckLake exact scan, p50/p95 | DuckLake 真值 ID 后的取回, p50/p95 | native DuckDB VSS 完整 SQL |
|---|---:|---:|---:|
| SIFT1M | 156.10/270.39 ms，Recall@10=1 | 6.58/9.12 ms，**仅 oracle-ID hydration** | ef=128：1.58/1.89 ms，8-query 平均 recall=1.00；build 67.2 s |
| GloVe 1.18M | 257.09/342.80 ms，Recall@10=1 | 9.45/11.69 ms，**仅 oracle-ID hydration** | ef=256：2.42/2.85 ms，平均 recall=0.90；build 121.3 s |

`EXPLAIN ANALYZE`：oracle `WHERE rowid IN (...)` 列示全部 40 文件；exact vector scan 也列示 40 文件，后续 late-materialization 阶段有 7/8 文件。样本表的 `rowid == id` 全量对照为 0 个 mismatch，**只对该插入顺序成立**。oracle 数字**不含 PDX search、index load、ID 转换、delete/snapshot 检查**。VSS 用 native 内存表和 `FLOAT[N] ARRAY`，计划中证实 `HNSW Index: vec_idx`；它与 DuckLake 的存储、资源边界不同，不能据此断言尚未实现的 PDX 集成输赢。VSS 构建期间 process peak RSS 约 2.01/1.94 GB，包含 Python、Arrow/HDF5、表和索引，不是可与 DuckLake 相减的“索引内存”。

**针对 A 的更强控制/负结果：**同一 oracle Top-10 ID，用 `WHERE id IN (...)` 比 `WHERE rowid IN (...)`。`id` 是按文件递增的真正存储列，文件统计能裁剪到 SIFT 约 7、GloVe 约 8 文件；各 24 次交错观测：

| 取回投影 p50 | `rowid`（列示 40 文件） | `id`（列示 7/8 文件） |
|---|---:|---:|
| SIFT `id,payload` | 3.96 ms | 4.17 ms |
| GloVe `id,payload` | 5.30 ms | 5.55 ms |
| SIFT `id,payload,embedding` | 27.22 ms | 26.90 ms |
| GloVe `id,payload,embedding` | 36.99 ms | 37.12 ms |

所以**只减少计划列示的文件数，在本地热缓存和小占位 payload 下没有测得净收益**。本控制与上表 oracle hydration 在不同运行/缓存状态下测得，绝不可把 3.96 与 6.58 ms 当成同一 A/B 处理效果。不能把 `Total Files Read` 当成 bytes/request 数，也不能外推到 S3、冷缓存或大真实 payload。独立诊断另以 20×5k 行验证 rowid 点查列示 20 文件、按有序 id 点查 1 文件，压实后 rowid 保留；这支持源码解释，非性能收益。

**没有测得、不能编造的指标**：PDX on DuckLake 完整延迟/Recall@K、PDX index build/load/update/bytes/RSS/I/O、LanceDB 同语义实测、冷/远端缓存、过滤条件及 filtered exact truth、真实大 payload、不同分散度、并发、DELETE/UPDATE/历史 snapshot。没有 PDX 运行，因前置新颖性和 A 负门槛未满足；因此不存在可负责地填入的“PDX 加速比”或净收益上界。exact 与 oracle 取回的差值也**不是** A 的可节省上界，因为它包含 ANN 替代全表距离计算的收益；A 最多改善取回部分，具体比例须 PDX 端到端分解。

## 4. Opportunity ranking：只选一个待证伪假设

| 排名 | 缺口/可推广性 | 最小实现、可能上界 | 重叠/最大失败条件 | 决定 |
|---|---|---|---|---|
| **1 A：snapshot-correct、bounded-I/O 的跨 Parquet Top-K 取回** | K≪N 且命中分散时可能适用于一般 lakehouse ANN；不是 PDX 特化。 | 先给 **oracle 正确 IDs**，测 payload hydration 的真实 bytes/ranges/RTT、p50/p95、端到端占比；若确有余量，使用 snapshot file list + locator + DuckLake reader。上界仅为可去除的取回开销。 | Native VSS/DuckIR 与 Lance 已有随机/late fetch；DuckDB PR #27326 正做 page-index；本次 40→7/8 文件剪枝无热本地收益。 | 最值得**先证伪**，当前不是 GO。 |
| 2 B：snapshot-consistent PDX indexing | DuckLake 确有版本化文件与索引生命周期缺口。 | S0/S1 sidecar manifest、delta、compaction remap、失败发布；看重建/维护/存储/查询综合成本。 | Lance 已有通用先例；完整事务/GC 侵入深。冻结 S sidecar 是集成而非新研究。 | 现在 No-Go。 |
| 3 C：filtered search + DuckLake metadata | 多文件/谓词选择率有真实系统问题潜力。 | PDX external predicate/resume + DuckLake file stats；须在真实过滤真值下验证 I/O、召回、underfill。 | van Noort/DuckIR、ACORN、Lance、VSS、pgvector 占据空间；现在没有真实 filter 证据。 | 现在 No-Go。 |

**唯一可保留的论文核心问题（尚未证实）：**“在不复制 payload、不破坏 DuckLake snapshot 语义的条件下，能否使分散 Top-K 命中的实际 Parquet bytes/ranges/解码成本显著接近可实现下界，并转化为跨负载端到端净收益？”这不同于“接上 PDX 就有论文”。如必须引入新格式、复制 payload、修改底层事务存储或只在一个冷远端极端例子受益，按本项目标准也应停止。

## 5. 严格 Go/No-Go、工程风险与优秀论文交付

按用户五条**必须同时成立**的标准：① 独立未覆盖机制 **未确认**；② 两来源显示 exact scan 很慢，但未确认强基线下的可优化 Top-K 取回瓶颈；③ 冻结快照有可推断小范围路径，动态正确系统没有；④ 多数据集方案可设计，但缺真实 payload/filter/远端和 PDX 运行；⑤ 当前最可能的可交付物只是已有算法的存储适配。**故现在投入几个月以追求 workshop 级独立研究：No-Go。** 这不等同于“系统技术上不可能”；有 CWI 导师既有内部代码/课题授权时可另评估一个**集成型硕士项目**，但不能把其成功概率与本目标混同。

要重新开放，先完成**门槛实验，不先写核心补丁**。以下是预设推荐阈值，不是已达结果：

1. 至少 2 个独立来源、各 ≥1M 向量/≥32 Parquet 文件、**真实可取回 payload**；至少一个有真实过滤字段/filtered exact ground truth；覆盖维度/分散度、热/冷缓存、至少一个远端对象存储。YFCC-10M 有真实 tag filters 与 filtered truth，可作过滤候选；[Big-ANN 官方说明](https://github.com/harsha-simhadri/big-ann-benchmarks/blob/main/neurips23/README.md)。向量文件不等于真实文档 payload，不能把随机字符串冒充。
2. Oracle IDs 下先比较现有 DuckLake、真实有序 ID/metadata 强基线、PR #27326 能力与 Lance `take_rows`。目标：两来源 p50/p95 取回都 ≥2× 改善、实际 bytes/requests 明显下降，且取回占估计完整查询 ≥30%。如果仅文件数下降，像本次一样时间不降，直接停止 A。
3. 在白板/最小诊断中证明 locator + reader 对 NULL、删除、向量 UPDATE、compaction、S0/S1 snapshot、失败发布正确；冻结 S 原型必须显式拒绝/退回其他版本。实施路径若需要 DuckLake ARRAY/index 规范变更、native `GetStorage()` 大改或全面事务/GC 重构，按“最小可落地”门槛停止。
4. 上述通过才做一个**端到端** PDX+DuckLake 垂直片段；同数据/投影/过滤、matched Recall@10 ≥0.90 和 ≥0.95 档比较 DuckLake exact、VSS、LanceDB。分列 search / ID-map / fetch / SQL，报告 p50/p95、index build/load/update、index bytes、peak RSS、cold/warm I/O、并发/错误恢复；足够独立查询和重复顺序，给区间而非挑选正例。
5. 与 DuckIR/van Noort、Lance、ACORN、VSS 和 PR #27326 做机制差异/消融。如果只比普通 fixed-snapshot sidecar + 现有 selective scan 快一点，或者只是换参数/benchmark，维持 No-Go。

**若五门槛意外通过，优秀 CWI MSc 的完整交付**应包含：形式化的问题与成本模型；可复现、版本固定的 C++ 实现和多版本正确性测试；至少两类真实向量/过滤/记录负载；同语义同召回的外部比较；构建/查询/维护/资源账；消融、失败边界与负结果；代码及脚本公开。Workshop 价值必须来自经过外部对照的**新机制**，不是官方题目、PDX 核心速度或单一 benchmark 的高倍数。

## 6. 复现命令、原始数据和边界

实验代码：同目录 `vector_probe.py`、`native_vss_probe.py`、`id_vs_rowid_probe.py`；原始每次 timing/recall、EXPLAIN 见 `artifacts/ducklake_{sift,glove}/` 与 `artifacts/vss_{sift,glove}/`（约 708 KB）。`id_vs_rowid_probe.py` 是按原始 SQL/参数补存的**等价复现脚本**，原始交互运行的 JSON 已保存，不声称逐字符相同。安装扩展至用户缓存；要完全隔离需设置 DuckDB extension directory。新版本安装可能不能重现本次 extension hash。

```bash
python3 -m venv /tmp/c13-vector-py
/tmp/c13-vector-py/bin/python -m pip install 'duckdb==2.0.0' h5py numpy pyarrow
mkdir -p /tmp/c13-vector-data
curl -L https://ann-benchmarks.com/sift-128-euclidean.hdf5 -o /tmp/c13-vector-data/sift-128-euclidean.hdf5
curl -L https://ann-benchmarks.com/glove-100-angular.hdf5 -o /tmp/c13-vector-data/glove-100-angular.hdf5
shasum -a 256 /tmp/c13-vector-data/*.hdf5  # 对照第 3 节 SHA256
cd <local-projects>/C13_feasibility_20261027
/tmp/c13-vector-py/bin/python - <<'PY'
import duckdb
c=duckdb.connect(); c.execute('INSTALL ducklake; INSTALL vss')
PY
/tmp/c13-vector-py/bin/python vector_probe.py --dataset sift --out-dir /tmp/c13-vector-probe-new
/tmp/c13-vector-py/bin/python vector_probe.py --dataset glove --out-dir /tmp/c13-vector-probe-new
/tmp/c13-vector-py/bin/python id_vs_rowid_probe.py --dataset sift --out-dir /tmp/c13-vector-probe-new
/tmp/c13-vector-py/bin/python id_vs_rowid_probe.py --dataset glove --out-dir /tmp/c13-vector-probe-new
/tmp/c13-vector-py/bin/python native_vss_probe.py --dataset sift --out-dir /tmp/c13-native-vss-new
/tmp/c13-vector-py/bin/python native_vss_probe.py --dataset glove --out-dir /tmp/c13-native-vss-new
```

不能在同一输出目录重复运行 `vector_probe.py`：它执行 `CREATE TABLE`；用全新 `--out-dir`。VSS 构建需约数 GB RAM/分钟级时间。DuckLake 大文件与原始 HDF5 留在 `/tmp`，可能被系统清理，但可重建。两个真实来源**不是**两个真实 payload/filter 工作负载；这是本次对 A/C 结论不升级为最终性能结论的核心限制。没有做真 OS 冷缓存、远端 I/O 或 PDX 索引测量。

附加直接类型/索引诊断（在新 DuckLake catalog 上执行）：`CREATE TABLE lake.t(v FLOAT[128])` 失败；`CREATE TABLE lake.t(v FLOAT[])` 成功；`CREATE INDEX idx ON lake.t(v)` 与 `CREATE INDEX idx ON lake.t USING HNSW(v)` 都由 DuckLake catalog 拒绝。20 文件 rowid 诊断是独立小检查，不用于加速比。全部实验输出位于 C17 **同级的隔离目录** `<local-projects>/C13_feasibility_20261027/`，原 C17 工作区的原有 dirty 状态未被改动。
