# MoonJSONC 项目申报书（11 月复审稿）

> AI 辅助参考稿；请本人核对、补全身份信息并用自己的文字形成提交稿。

**项目名称：** MoonJSONC——MoonBit 标准 JSON 解析与 JSONC 原文编辑基础库

**参赛者：** YeeHh2004（本人核对）

**联系方式：** 本人填写

**项目方向：** 通用数据处理／开发工具基础库

**GitHub：** [YeeHh2004/moonjsonc](https://github.com/YeeHh2004/moonjsonc)

**项目简介与通用性**　为接口数据导入、配置管理、编辑器和自动化工具提供可独立使用的标准 JSON 严格解析，以及 JSONC 原文编辑能力。输入文本，输出带位置的语法树、诊断或可审阅的文本补丁；修改局部字段时保留无关排版、注释和数字原文。核心算法采用 MoonBit，支持 JavaScript、Wasm GC，不绑定行业或界面框架。

**标准与最终交付范围**　普通 JSON 以 [RFC 8259（2017 年 12 月）](https://www.rfc-editor.org/rfc/rfc8259)及 [ECMA-404 第二版（2017 年 12 月）](https://ecma-international.org/publications-and-standards/standards/ecma-404/)为依据，以在公开资源限制内**完整实现 JSON 文本语法**为目标：覆盖六类值、任意根值、容器嵌套、标准空白、数字文法、字符串转义与 Unicode；严格入口拒绝注释、尾逗号及额外根值。重复键语法允许并保留，歧义编辑另行拒绝；数字原文保留不等于任意精度运算。CLI 严格读取 UTF-8；默认深度 128、可设至 512，最多 100,000 个值。JSONC 注释与尾逗号单列为扩展。交付终点为严格解析、定位、格式化、原文编辑及事务闭环，附条款映射、正反例、双后端 CI、使用样例和 Mooncakes 包；合法且键唯一的 JSON 在保留根值的格式化／修改后须再次通过严格解析。JSON5、Schema 校验及任意精度算术不列入本期。

**至少三个完整使用场景**

1. **接口数据导入：** 程序调用 `parse_json`，对输入 `42` 返回数字根节点、原文 `42`；对 `[1,]` 返回尾逗号诊断（UTF-16 偏移 2、长度 1），据此接受数据或提示修正。
2. **项目配置升级：** 将 `{/*keep*/"enabled":false,"id":9007199254740993}` 的 `enabled` 改为 `true`，输出 `{/*keep*/"enabled":true,"id":9007199254740993}`，补丁为 `{offset:19,length:5,content:"true"}`，供维护者审阅保存。
3. **部署参数更新：** 读取 `{"version":3,"replicas":2}`，先断言版本为 `3`，再将两项更新为 `4`、`5`，输出 `{"version":4,"replicas":5}`；若断言版本为 `2`，整批返回冲突，不返回部分修改结果。

**核心功能与验证**　严格 JSON 入口、JSONC 容错扫描与语法树；路径查询、UTF-16 源位置、事件遍历；全文／范围格式化；字段增删改、数组插入、补丁应用；快照与值断言事务。仓库提供 CLI、浏览器工作台、标准案例及独立安装示例，CI 覆盖检查、构建、测试。公开提交记录不少于 10 次实质提交，具体标准边界与复现命令见 [STANDARDS](https://github.com/YeeHh2004/moonjsonc/blob/main/docs/STANDARDS.md)。

**原创与开源说明**　原创、AI 辅助实现，MIT 许可。参考 [Microsoft node-jsonc-parser](https://github.com/microsoft/node-jsonc-parser)（MIT）的功能范围并作测试对照，未复制其运行时代码。项目在值解析之外交付源位置、保留原文的补丁与事务能力；参考来源、许可及生态差异随仓库公开。
