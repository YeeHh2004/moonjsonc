# JSON 标准、交付范围与复现案例

## 标准版本和本期终点

普通 JSON 以 [IETF RFC 8259（2017 年 12 月，STD 90）](https://www.rfc-editor.org/rfc/rfc8259)
为规范依据，语法同时对照 [ECMA-404 第二版（2017 年 12 月）](https://ecma-international.org/publications-and-standards/standards/ecma-404/)。
项目目标是在下述公开资源限制内，完整实现标准定义的 JSON 文本语法：接受合法文本、拒绝不合法文本，
提供带源位置的表示，供数据导入、开发工具和自动化程序独立调用。JSONC 的注释和尾逗号属于单列扩展。

本期交付为：严格解析 API、标准条款回归测试、JSONC 容错检查、结构化查询与原文补丁、
格式化与事务，以及可安装的 Mooncakes 包、CLI、示例和双后端 CI。JSON Schema、JSON5、
任意精度算术和网络协议栈不在本期范围内。严格 JSON 输出的验证范围是对合法且键唯一的 JSON
进行保留根值的格式化或结构化修改，再以严格入口检查结果；删除根值属于文档移除，
会留下空内容，不承诺输出 JSON 文本。JSONC 编辑结果仍可包含扩展语法。

完成条件是以上交付可以复现，标准条款及边界均有测试，严格路径与扩展路径不会互相放宽。
标准符合性是实现目标和逐项验证要求，测试通过不等同于第三方认证或对无限输入空间的证明。

## 两个入口

```moonbit
// 0.1.1 起：严格语法，成功返回带原文和位置的 Document，失败返回诊断。
@jsonc.parse_json(text) // Result[Document, Array[Diagnostic]]

// 配置/编辑器：默认允许注释、尾逗号；错误时仍返回容错树。
@jsonc.parse(text) // Document
```

`parse_json` 固定禁止注释、尾逗号和空文档，只允许配置资源限额。输入必须恰好包含一个值；
`42`、`"text"`、`true`、`false`、`null` 都能独立作为根节点。
`parse` 关闭扩展后的诊断还包含配置编辑的重复键检查，因此不应把它的全部诊断直接称为标准语法错误。

严格解析接受重复键并在树中保留所有属性；`node_value` 投影为最后一个值。
解码后相同的键（如 `"a"` 和 `"\u0061"`）也按重复键处理。`find_node` 对歧义路径返回 `None`，
格式化和结构化编辑继续拒绝重复键，避免静默修改某一个同名属性。这是编辑安全策略，
没有把 RFC 8259 §4 的唯一性建议改写成语法禁令。

## 标准条款与实现契约

| 依据 | 严格 JSON 的范围与行为 | 验证位置 |
| --- | --- | --- |
| RFC §§2–5；ECMA-404 §§4–7 | 四种标准空白；对象、数组、字符串、数字、布尔、null；任意根值；容器分隔符及完整输入 | `standards_test.mbt`、`tests/standards.test.mjs` |
| RFC §6；ECMA-404 §8 | 十进制整数、负号、小数、正负指数；拒绝前导零、前导加号、缺失数字、NaN、Infinity | 同上；扫描器及既有数字回归 |
| RFC §§7–8.3；ECMA-404 §9 | 引号、反斜杠、全部短转义和 `\uXXXX`；解码 Unicode 及代理对；拒绝未转义控制字符和非法转义 | 同上；扫描器回归 |
| RFC §4 | 语法树保留重复属性；值投影最后一个生效；编辑歧义独立拒绝 | 严格入口/协议回归及编辑测试 |
| RFC §§6、9 | 数字原文保留 `-0`、`9007199254740993`、`1e400`、`1e-400`；值投影的估算数值仍是 Double | 数字原文与补丁回归 |
| RFC §8.1 | MoonBit API 输入已解码的 String；CLI 对文件及 stdin 严格解码 UTF-8，非法字节拒绝；开头 BOM 拒绝，不生成 BOM | `tests/cli.test.mjs` |
| RFC §8.2 | 核心 String 解析保留孤立代理转义对应的 UTF-16 单元；这是语法允许但互操作性有限的情形 | 严格入口及既有代理单元回归 |
| RFC §§9–10 | 严格输入失败返回诊断；合法且键唯一的 JSON 在保留根值的格式化/编辑后再次严格解析成功 | 标准及格式化回归、示例 |

位置信息均为原文的 **UTF-16 code units**；CLI 文件编码 UTF-8 与这个定位单位不同。
树和 token 保留源码跨度，数字节点可以从原文精确取回。数值运算不承诺任意精度；
不得把 Double 估算值当成保真序列化依据。JSONC 的 `strip_comments` 只是词法去注释，
不会清除尾逗号，不构成通用 JSONC→标准 JSON 转换器。

资源限制：默认嵌套深度 128（可设 1–512），最多 100,000 个值；默认最多 100 条诊断
（可设 1–1000）。协议源文本最多 1 Mi UTF-16 单元，CLI 文件/stdin 最多 8 MiB，仍受协议限制。
超限会返回错误，不以静默截断后的成功代替。核心 String API 无文件或网络 I/O；宿主负责 UTF-8
编解码。外层 JSON 协议由 MoonBit core 解码，直接包含孤立代理单元的外层请求有额外限制，见
[协议说明](PROTOCOL.md)。

## 具体输入与输出

CLI 的树字段还包含子节点、原文和 UTF-16 范围，下表只列关键输出。

| 输入/操作 | 模式 | 关键输出 |
| --- | --- | --- |
| `42` | `check-json` | `valid:true`，根 `kind:"number"`、`raw:"42"`、`value:"42"` |
| `null` | `parse-json` | `valid:true`，根 `kind:"null"`、`value:null` |
| `[1,]` | `check-json` | `valid:false`，`TrailingComma`，`offset:2`、`length:1` |
| `{/*keep*/"enabled":false,}` | `check-json` / `check` | 严格模式拒绝注释及尾逗号；JSONC 模式通过 |
| `01`、`NaN`、`true false` | `check-json` | `valid:false`，有位置诊断，无成功语法树 |
| `{"a":1,"a":2}` | `parse-json` | `valid:true`，树有两个属性，值投影 `a=2`；编辑它返回 `InvalidDocument` |
| `9007199254740993` | `parse-json` | 数字节点的 `raw` / `value` 字符串均逐字保留输入 |

配置编辑的完整例子：

- 输入：`{/*keep*/"enabled":false,"id":9007199254740993}`
- 操作：路径 `["enabled"]`，新值文本 `true`。
- 输出：`{/*keep*/"enabled":true,"id":9007199254740993}`
- 补丁：`[{"offset":19,"length":5,"content":"true"}]`。

这里输出仍是 JSONC；注释和大数字原文保留，修改范围可核对。

## 复现

工具链和安装方法见 [DEVELOPMENT](DEVELOPMENT.md)。在仓库根目录：

```sh
moon run examples/standards --target js
moon run examples/standards --target wasm-gc
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
node scripts/build.mjs
node --test tests/standards.test.mjs tests/cli.test.mjs
```

对 UTF-8 文件执行 `node cli/moonjsonc.mjs check-json input.json` 或
`node cli/moonjsonc.mjs parse-json input.json`。退出码 0 表示通过，1 表示语法诊断，
2 表示文件/编码/参数错误。协议调用也支持同名 `op`；扩展选项不能使严格入口接受注释或尾逗号。
