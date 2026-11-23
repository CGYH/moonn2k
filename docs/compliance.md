# moonn2k 标准版本、符合性终点与代表性报文说明

> 用途：MoonBit 开源大赛十一月黑客松报名补充材料。
> 项目仓库：https://github.com/CGYH/moonn2k
> 补充日期：2026-11-23
> 本文只澄清协议目标、验收边界和已有实现证据，不扩大项目范围，也不作 NMEA 官方认证声明。

## 1. 目标标准版本与公开实现基线

### 1.1 目标标准版本

moonn2k 以 **NMEA 2000 Version 3.000（with amendments，含修订）** 作为目标标准代际。NMEA 官网当前将该版本列为发布版本，并说明标准主要包括：

- **Main Document**：网络与协议要求；
- **Appendix A&B**：网络消息（PGN）定义，是标准消息集的核心；
- **Appendix C / Certification Tool**：产品认证相关工具与要求。

官方来源：NMEA，*NMEA 2000 Standards*，
https://www.nmea.org/nmea-2000 （查阅日期：2026-11-23）。

这里的“目标标准版本”表示项目所面向的协议代际，**不表示本项目已经持有官方标准全文、逐条完成官方符合性测试或取得 NMEA 认证**。

### 1.2 当前可公开核验的实现基线

本次开源实现没有将网络资料混称为“官方标准文本”。十个 PGN 的字段名、位偏移、位宽、符号性、分辨率和单位，统一固定在以下公开、可复核的上游版本：

```text
canboat/canboat@6ce848c6048ae81414c90dd3cee57699f98c6738
文件：docs/canboat.json
canboat SchemaVersion：2.8.0
```

项目仅以该数据为字段布局参考，在 MoonBit 中重新实现，没有复制 canboat 代码。完整来源和许可记录见仓库 `THIRD_PARTY.md`，逐字段布局见 `docs/pgn-support.md`。

**NMEA 2000 Version 3.000 是目标标准版本；canboat SchemaVersion 2.8.0 是公开字段数据库自身的版本。二者属于不同体系，不能互相替代，也不能把“2.8.0”写成 NMEA 标准版本。**

由于官方标准全文采用许可方式提供，本项目当前声明是“基于公开信息的独立实现”。后续若取得官方 Version 3.000 文档，应建立逐条款差异表并升级参考向量；在完成该工作前，不声称逐条符合官方全文。

## 2. 完整符合性终点及其与限定范围的关系

本项目区分两个不同终点，避免把“声明子集已实现完整”误写成“整个 NMEA 2000 标准已完整符合”。

### 2.1 本次申报的终点：P0 Profile 内完整符合性

本次项目的完整工程终点是：**对下面明确声明的 P0 Profile，所有协议行为均有实现、有固定输入输出、有自动化测试，并能从干净源码环境复现。**“完整”仅针对这个封闭、可枚举的子集，不针对 NMEA 2000 的全部 PGN 或官方产品认证。

| 子集能力 | 本次终点定义 | 主要证据 |
|---|---|---|
| 29 位扩展 CAN ID | 构造与解析 priority、reserved、data page、PF、PS、source；正确区分 PDU1/PDU2 并推导 PGN | `src/identifier`、`fixtures/identifier.json`、ID 测试 |
| 经典 CAN 数据帧 | 0..8 字节硬边界；规范十六进制输入输出；非法长度和非法字符显式报错 | `src/frame`、HEX 测试 |
| 位级编解码 | LSB-first，支持 1..64 位、跨字节、非对齐、有符号值和越界错误 | `src/bits`、BIT 测试 |
| 单帧消息 | 对声明 PGN 完成字段级解码和编码；未知 PGN 原样透传而非误判失败 | `src/registry`、`src/pgn` |
| Fast Packet | 9..223 字节；首帧 6 字节负载、后续帧 7 字节；sequence 0..7；最多 32 帧；完成重组后只交付一次 | `src/fast_packet`、`fixtures/fast_packet.json`、FPS/FPR 测试 |
| 重组健壮性 | 覆盖乱序、首帧迟到的有界暂存、相同重复帧幂等、冲突重复帧拒绝、会话重启、超时、会话与暂存上限 | FPR-001..026 |
| 十个声明 PGN | 59904、60928、126992、126993、126996、127250、128267、129025、129026、130306 的元数据驱动编解码 | `src/pgn/metadata.mbt`、`fixtures/pgn-vectors.json` |
| 字段语义 | 保留 raw 值；按分辨率/偏移计算物理值；处理有符号字段、枚举和文本；已声明 NA 模式只按完整值匹配 | PGN 与 registry/codec 测试 |
| 可复现性 | 核心无硬件、文件、网络和墙上时钟依赖；时间作为参数注入；wasm-gc、JS、native 三目标测试通过 | `docs/testing.md`、CI、`docs/acceptance.md` |

每个声明 PGN 的验收至少包含：正常值、边界值、已声明 NA 值、截断拒绝、编码/解码往返、固定参考向量。Product Information 还执行“类型化编码 → Fast Packet 分段 → 乱序输入 → 重组 → 类型化解码”的端到端测试。

因此，**P0 限定范围不是“尚未完成的任意十个示例”，而是本次符合性终点的组成边界：范围之外的 PGN 不进入本次符合性声明，范围之内的行为不得缺项。**

### 2.2 非本次终点：NMEA 官方完整标准符合性与产品认证

若把“完整符合性”定义为对整个 NMEA 2000 Version 3.000 的官方符合性或产品认证，则严谨终点应包括：取得官方标准及修订、建立 Main Document 与 Appendix A&B 的逐条款映射、覆盖所需 PGN 与网络服务、使用 Appendix C 认证工具，并由 NMEA 完成验证。硬件、电气、连接器和实时总线行为也属于产品认证语境，而不是当前离线编解码库的测试所能替代的内容。

**该官方认证终点不属于本次 P0 申报范围，本项目不作此类声明。**二者关系如下：

```text
NMEA 2000 Version 3.000 完整标准 / 官方产品认证
                    │
                    ▼ 明确裁剪，不外推声明
本次 P0：离线协议编解码与 Fast Packet 的封闭子集
                    │
                    ▼ 子集内逐条实现、固定向量、自动化测试
本次交付终点：P0 Profile 内完整、可复现、可审计
```

后续扩展可按两条路径进行，但均不是本次验收的隐含前置条件：

1. **协议覆盖扩展**：取得官方文档后做条款映射，增加重复字段组、更多 PGN 和独立解码器差分测试；
2. **设备与认证扩展**：接入真实 CAN 硬件，实现所需网络管理与其他传输方式，再评估官方认证。

### 2.3 明确排除项

本次不声称支持：NMEA 官方认证、真实硬件或物理层、完整 J1939 TP.BAM/TP.CM、全部 PGN、重复字段组、专有 PGN 猜测，以及真实总线时序。Fast Packet 默认 1000 ms 超时和短末帧 `0xFF` 填充是项目策略；接收端只按声明长度取有效负载，不依赖填充值。NA 模式的来源与限制另见 `THIRD_PARTY.md`。

## 3. 具有公开协议依据的代表性报文输入输出

以下案例均来自仓库固定向量，并已用当前 CLI 或端到端测试执行。字段布局依据为第 1.2 节固定的 canboat 版本；示例不是未经核对的随意字节串。

### 案例 A：PGN 129025，Position, Rapid Update（单帧、PDU2、有符号物理量）

**输入 CAN 帧：**

```text
CAN ID = 0x19F80196
Data   = 40 a1 31 20 fa 0c fb f9
```

**标识符推导：**

- priority = 6，data page = 1，PF = 248，PS = 1，source = 150；
- PF ≥ 240，因此是 PDU2，PS 属于 PGN，不是目的地址；
- PGN = `(1 << 16) | (248 << 8) | 1` = **129025**。

**负载推导：**

| 字段 | 位偏移/位宽 | 原始值与换算 | 解码结果 |
|---|---|---|---|
| Latitude | 0/32，有符号，小端 | raw = `0x2031A140` = 540123456；分辨率 `1e-7 deg` | **54.0123456°** |
| Longitude | 32/32，有符号，小端 | raw = -100987654；分辨率 `1e-7 deg` | **-10.0987654°** |

**CLI 实际输出（数值显示保留六位小数）：**

```json
{
  "pgn": 129025,
  "name": "Position, Rapid Update",
  "transport": "single-frame",
  "payload_hex": "40a13120fa0cfbf9",
  "fields": {
    "Latitude": {"raw": 540123456, "value": 54.012346},
    "Longitude": {"raw": -100987654, "value": -10.098765}
  }
}
```

**复现与证据：**

```bash
moon run cmd/n2k --target native -- decode-frame \
  --id 0x19F80196 --data 40a13120fa0cfbf9 --json
```

固定向量：`fixtures/pgn-vectors.json` → `129025_normal`；字段布局：`docs/pgn-support.md` → PGN 129025。

### 案例 B：PGN 127250，Vessel Heading（单帧、缩放、有符号值、枚举）

**输入 CAN 帧：**

```text
CAN ID = 0x19F11296
Data   = 42 11 11 64 00 ce ff 01
```

该标识符对应 PGN **127250**、源地址 150。按固定字段布局解码：

| 字段 | 原始字节/原始值 | 换算或查表 | 输出 |
|---|---|---|---|
| SID | `42` → 66 | 无缩放 | 66 |
| Heading | `11 11` → 4369 | `4369 × 0.0001 rad` | **0.4369 rad** |
| Deviation | `64 00` → 100 | `100 × 0.0001 rad` | **0.0100 rad** |
| Variation | `ce ff` → 有符号 -50 | `-50 × 0.0001 rad` | **-0.0050 rad** |
| Reference | 低 2 位 = 1 | lookup：1 = Magnetic | **Magnetic** |

**CLI 实际输出的核心字段：**

```json
{
  "pgn": 127250,
  "name": "Vessel Heading",
  "fields": {
    "SID": {"raw": 66},
    "Heading": {"raw": 4369, "value": 0.436900},
    "Deviation": {"raw": 100, "value": 0.010000},
    "Variation": {"raw": -50, "value": -0.005000},
    "Reference": {"raw": 1, "name": "Magnetic"}
  }
}
```

**复现与证据：**

```bash
moon run cmd/n2k --target native -- decode-frame \
  --id 0x19F11296 --data 4211116400ceff01 --json
```

固定向量：`fixtures/pgn-vectors.json` → `127250_normal`；字段偏移、分辨率和 Reference 表：`docs/pgn-support.md` → PGN 127250。

### 案例 C：PGN 126996，Product Information（134 字节、20 帧 Fast Packet）

**输入语义与完整负载：**

本例输入一条 Product Information 消息：NMEA 2000 Version 原始值 2100、Product Code 888、Model ID `moonn2k-demo`、Software Version Code `v0.1.0`、Model Version `sim-unit-1`、Model Serial Code `SN00042`、Certification Level 0、Load Equivalency 1。完整 134 字节负载固定于 `fixtures/pgn-vectors.json` → `126996_normal`。

发送参数：

```text
CAN ID      = 0x19F01424   (PGN 126996, source 36)
sequence id = 4
payload len = 134
```

**分段后的代表性 CAN 帧（完整输出共 20 帧）：**

| 帧序号 | CAN ID | Data（hex） | 含义 |
|---:|---|---|---|
| 0 | `0x19F01424` | `8086340878036d6f` | `0x80` = sequence 4、frame 0；`0x86` = 声明长度 134；随后 6 字节负载 |
| 1 | `0x19F01424` | `816f6e6e326b2d64` | `0x81` = 同 sequence、frame 1；随后 7 字节负载 |
| 2 | `0x19F01424` | `82656d6f00000000` | frame 2；随后 7 字节负载 |
| … | … | … | 中间帧按同一规则连续承载负载 |
| 18 | `0x19F01424` | `9200000000000000` | frame 18 |
| 19 | `0x19F01424` | `930001ffffffffff` | 最后一帧；有效余量 2 字节为 `00 01`，`FF` 仅为填充 |

首帧给出声明总长度，后续帧沿用 sequence 并递增 frame counter。接收端只按 134 字节声明长度截取有效数据，末尾 `0xFF` 不进入解码结果。项目还测试了“所有后续帧先于首帧到达”的乱序情况：后续帧有界暂存，首帧到达后按帧序号归位并只完成一次。

**重组后的类型化输出：**

```json
{
  "pgn": 126996,
  "name": "Product Information",
  "transport": "fast-packet",
  "fields": {
    "NMEA 2000 Version": {"raw": 2100, "value": 2.100000},
    "Product Code": {"raw": 888},
    "Model ID": {"text": "moonn2k-demo"},
    "Software Version Code": {"text": "v0.1.0"},
    "Model Version": {"text": "sim-unit-1"},
    "Model Serial Code": {"text": "SN00042"},
    "Certification Level": {"raw": 0},
    "Load Equivalency": {"raw": 1}
  }
}
```

**依据与证据：**

- Fast Packet 线格式与边界：`fixtures/fast_packet.json`，FPS/FPR 测试；
- Product Information 字段布局：bit 0/16 版本、bit 16/16 产品代码、随后四个各 32 字节文本字段、bit 1056/8 认证级别、bit 1064/8 负载等效值，见 `docs/pgn-support.md`；
- 端到端测试：`src/pgn/pgn_test.mbt` → `PGN-126996 fast packet end-to-end`；
- 本例 20 帧发送输出由 CLI `fast-send` 实际生成，重组后字段输出由 CLI `decode` 实际生成。

## 4. 符合性证据索引

| 审核关注点 | 仓库中的可核验材料 |
|---|---|
| 目标标准版本 | 本文第 1 节；NMEA 官方来源链接 |
| 公开字段定义版本 | `THIRD_PARTY.md`；`docs/pgn-support.md` |
| 完整 P0 范围与排除项 | 本文第 2 节；`docs/protocol-scope.md` |
| 每个 PGN 的偏移、位宽、分辨率 | `src/pgn/metadata.mbt`；`docs/pgn-support.md` |
| 固定报文输入与预期输出 | `fixtures/identifier.json`、`fixtures/fast_packet.json`、`fixtures/pgn-vectors.json` |
| 单帧与 Fast Packet 自动化测试 | `src/identifier`、`src/fast_packet`、`src/pgn` 下测试文件 |
| 三目标与干净环境复现 | `docs/testing.md`、`docs/acceptance.md`、CI 工作流 |
| 不作认证或超范围声明 | 本文第 2.2、2.3 节；`README.md`；`docs/protocol-scope.md` |

复现命令：

```bash
moon fmt --check
moon check --target all --deny-warn
moon test --target all
moon run cmd/n2k --target native -- selftest
```

## 5. 可直接粘贴到报名表的精简说明

**目标标准版本与实现基线：**moonn2k 面向 NMEA 2000 Version 3.000（with amendments，NMEA 官网当前发布版本）。本次开源实现是可离线验证的协议子集，不声称已完成官方标准全文逐条符合性测试或 NMEA 产品认证。十个 PGN 的公开可核验字段基线固定为 canboat/canboat@6ce848c6048ae81414c90dd3cee57699f98c6738 的 docs/canboat.json（canboat SchemaVersion 2.8.0）；该版本号是字段数据库版本，不与 NMEA 标准版本混用。

**完整符合性终点及范围关系：**本次终点是所声明 P0 Profile 内的完整符合性，即 29 位 CAN ID 与 PDU1/PDU2、单帧、9..223 字节 Fast Packet、十个指定 PGN 的编解码均有实现、固定向量和自动化测试，并覆盖乱序、重复、冲突、重启、超时与资源上限。范围外 PGN 原样透传，不纳入符合性声明。官方完整标准符合性/产品认证需要官方文档、条款映射、Appendix C 工具及 NMEA 验证，不属于本次离线协议库范围；本项目不作此类声明。

**代表性报文：**例如 CAN ID `0x19F80196`、数据 `40a13120fa0cfbf9`，按 PDU2 得 PGN 129025，解出 Latitude raw 540123456 → 54.0123456°、Longitude raw -100987654 → -10.0987654°；CAN ID `0x19F11296`、数据 `4211116400ceff01`，解出 PGN 127250 的 Heading 0.4369 rad、Deviation 0.0100 rad、Variation -0.0050 rad、Reference Magnetic。另有 PGN 126996 的 134 字节 Product Information 经 sequence 4 分成 20 帧，首帧声明长度，末帧仅填充不影响有效负载，乱序重组后恢复 Model ID `moonn2k-demo`、Serial `SN00042` 等全部字段。完整输入输出、计算过程和仓库证据链接见 `docs/compliance.md` 与 `fixtures/`。
