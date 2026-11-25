# ABAP ADT API MCP server

这个服务保留上游的 SAP ABAP 工具，并增加 `readResultPage` 用来读取过大的结果。对象的增删改查、锁定、激活、运输请求、查询、调试、重构、Git 和分析共用一个 SAP 会话，由本机受信任的 stdio 客户端持有。能读什么、能改什么，由 SAP 权限决定。

## 本 fork 增加的工具

这些工具在 `https://github.com/duangww/mcp-abap-abap-adt-api` 的 `local` 分支上，上游包里没有。本分支的 `createObject` 还会把 `SAP_LANGUAGE` 写入 `adtcore:language` 和 `adtcore:masterLanguage`。未设置时为 `EN`。

`getObjectSource` 仍返回较短的片段。结果超过 12000 个字符时不再返回正文。类、程序、包含、接口、CDS、BDEF、SRVD 和透明表的大段源码通过文件读写，源码正文不进入对话。

| 工具 | 作用 |
|---|---|
| `downloadSourceFile` | 把对象源码写到本机绝对路径。只返回路径、字节数和行数，不返回源码正文。之后用本地检索读这个文件。 |
| `uploadSourceFile` | 读取本机绝对路径上的文件并写入 SAP。同一次调用里完成锁定、写入、解锁和语法检查。`activate` 为 true 时，仅在 `syntax.errorCount` 为 0 后激活。`transport` 填运输请求号，不填任务号。 |
| `readProgramTexts` | 用文本元素自己的内容类型读取选择文本、文本符号和列表标题。不要用 `getObjectSource` 读这些地址，那个调用返回的是 HTML 预览。 |
| `writeProgramTexts` | 按名称合并选择文本、文本符号或列表标题。只改传入的名称。有改动时激活。`transport` 填请求号。 |
| `debuggerListenAttachVariables` | 在同一个有状态会话里听断点、附加调试器并读取变量。先调用 `debuggerSetBreakpoints`。本工具会阻塞，直到另一个会话命中断点。 |

```text
downloadSourceFile
  filePath   = 本机绝对路径
  objectUrl  = 对象 URL，不带 /source/main

uploadSourceFile
  filePath   = 本机绝对路径
  objectUrl  = 对象 URL，不带 /source/main
  transport  = 运输请求号
  activate   = true 时，语法检查没有错误才激活

readProgramTexts
  program = ZCOR013

writeProgramTexts
  program    = ZCOR013
  selections = [{ name: "S_BUKRS", text: "公司代码" }]
  symbols    = [{ name: "T01", text: "选择条件" }]
  transport  = 运输请求号
```

文件工具也可以不传 `objectUrl`，改为同时传 `objectName` 和 `objectKind`。`objectKind` 取 `class`、`program`、`include`、`interface`、`ddls`、`bdef`、`srvd`、`table` 之一。

## 安装和协议

使用 Node 22.22.2+ 或 24.15.0+。先执行 `npm ci` 和 `npm run build`，再让 MCP 客户端用 `node` 启动 `dist/index.js` 的绝对路径。已发布的 npm 包不含这里的改动，本仓库也不发布新版本。

```json
{
  "mcpServers": {
    "abap-adt": {
      "command": "node",
      "args": ["/absolute/path/mcp-abap-abap-adt-api/dist/index.js"],
      "env": {
        "SAP_URL": "https://sap.example.invalid:44300",
        "SAP_USER": "YOUR_USER",
        "SAP_PASSWORD": "YOUR_PASSWORD",
        "SAP_CLIENT": "100",
        "SAP_LANGUAGE": "EN"
      }
    }
  }
}
```

公开的 TypeScript MCP 2.0.0 支持 2026-07-28 的现代发现流程和 2025-11-25 的旧版初始化，并校验工具参数、支持取消和规范的错误。本包使用 stdio，不是 HTTP 监听器，也不提供 MCP OAuth。缺少凭据时仍可以做工具发现。`healthcheck` 只报告本机配置和会话恢复状态，不表示已经连上 SAP。

环境变量来自 MCP 客户端。只有显式设置 `SAP_ENV_FILE` 时才从该文件加载 dotenv。`SAP_URL` 只写源站，不带路径、查询串或内嵌账号密码。私有 CA 要在启动 Node 之前设置 `NODE_EXTRA_CA_CERTS`。不能关闭 TLS 校验。本机回环的 HTTP 仅用于测试夹具；受信任的私有 HTTP 部署必须设置 `SAP_ALLOW_HTTP=1`，凭据会暴露在那个网络上。

得到授权的代理可以用静态 `SAP_BEARER_TOKEN` 代替密码。轮换令牌需要重启进程。这里不实现 XSUAA 授权，也不证明租户已经接受该令牌。没有引入密码授权流程。

## 会话和限制

同一时间只跑一个操作，重叠调用会收到忙错误。调试监听也会占住这个会话，直到完成或取消。`SAP_REQUEST_TIMEOUT_MS` 默认 60000，允许 100 到 120000，登录和每一次底层 HTTP 请求都算在内。取消会关掉真实套接字。客户端不跟随重定向，不继承环境里的代理，不重试会改数据的操作，也不会在有状态调用失败后自动重新登录。被打断的写入可能已经改了 SAP：先检查写入和锁，再显式调用 `login`、`dropSession` 或 `logout` 恢复。关闭时会尝试在限定时间内登出；SAP 不可达时，状态会保留到 SAP 自己过期。

HTTP 只访问配置的源站，且路径在 `/sap/` 下。请求上限 2MiB，响应上限 4MiB，并校验 TLS。含 XML 实体声明的响应会被拒绝。输入 JSON 对字节数、嵌套、数组和字段契约都有上限。这是给受信任操作者用的工具，不是操作系统沙箱，也不是多用户服务。Git 工具可以让 SAP 用提供的凭据去连远程 Git 服务，能否成功取决于 SAP 和远程端的权限。

模式来自固定的 abap-adt-api 8.4.3 声明，包括对象、数组和重载。以前文档里把对象参数写成 JSON 字符串的用法仍然接受，会先解析再校验。未知的顶层参数会被拒绝。`scripts/generate-input-contracts.mjs` 和它的报告记录这层映射；升级依赖后要重跑并复查。里面的 TypeScript 6 编译器 API 只在开发时使用，应用程序由 TypeScript 7 构建。

`getObjectSource` 和成功的 `setObjectSource` 会留下源码快照。之后对同一 URL 调用 `syntaxCheckCode` 时可以省略 `code`（issue #2）。每个运行时的缓存上限是 8MiB、64 条、五分钟。会改数据或重置会话的操作会清掉旧快照。快照只是上次看到的文本，不能保证期间没有别人改过。显式传入的空文本会按一个空行检查，因为上游拒绝空字符串；结果里会带 `emptySourceNormalized`。源码选项可以是结构化对象或 JSON 对象，包括 active 和 inactive 版本。原有的按行分页仍然可用。读取类 include 时会先取类元数据；公开请求适配器能处理上游解析器拒绝的、只含单个链接的合法类 XML。Map 的条目会保留在 JSON 里。

结果超过 64KiB 时，返回不透明的 `resultId`、一页 JSON、`nextOffset` 和过期时间。用 `readResultPage` 把各页拼起来再做 JSON 解析，才能还原原来的工具结果。分页不会重复 SAP 请求，也不会写入。最多保留四个 4MiB 的结果，五分钟后过期；改数据或重置会话会清掉它们。过期后需要有意再执行原来的读取。更大的结果会明确失败。查询、搜索和 ATC 的默认条数是 100，有上限的地方最高 1000；接口可能多返回一行哨兵。其他大结构走通用分页。

## 校验和部署验收

```sh
npm run build
npm test
npm run verify:stdio
npm run verify:package
npm audit
docker build -t mcp-abap-api .
node scripts/verify-stdio.mjs --offline docker run --rm -i --network none mcp-abap-api
```

测试使用真实的本地 HTTP/XML 夹具，以及已安装的现代协议和旧协议交换。CI 在 Linux 和 Windows 的 Node 22/24 上以非 root 的 Docker 运行。不使用 SAP 生产凭据，也不做生产写入。得到授权的只读部署可以设置 `SAP_LIVE_TEST=1` 和可选的 `SAP_LIVE_SOURCE_URL`，再运行 `npm run verify:live`。它只检查登录、发现和可选的源码读取，不覆盖每一种 SAP 写入、调试、Git 或运输请求功能。那些要在开发系统上验证。权限、凭据、API 是否可用，以及支持到 2026 年底，都属于部署时的检查。

已有的 PR 19、20、21、22 涉及重叠错误、结果大小、类 include 和登录，仍等待仓库所有者审阅。PR 15 的状态恢复和重构 JSON 已经在起始分支上。PR 10 提议的 XSUAA 实现没有合并进来。

参考：[abap-adt-api](https://github.com/marcellourbani/abap-adt-api)、[MCP 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28)、[Node 私有 CA 配置](https://nodejs.org/api/cli.html#node_extra_ca_certsfile)。

## 原有工具流程

下面是原来的流程示例。上面的运行时、模式和安装说明优先于这些旧的、针对特定客户端的例子。大段源码改用本 fork 的 `downloadSourceFile` 和 `uploadSourceFile`。

## 给模型的说明

把下面这段说明提供给模型：

````
## mcp-abap-abap-adt-api Server

这个服务通过 ADT（ABAP Development Tools）API 访问 SAP 系统。可以查看 ABAP 对象、修改源码，以及管理运输请求。

**主要工具和用法：**

*   **`searchObject`：** 按查询字符串查找 ABAP 对象，例如类名。
    *   `query`：（string，必填）搜索词。
    *   返回对象 URI。示例：`/sap/bc/adt/oo/classes/zcl_invoice_xml_gen_model`

*   **`transportInfo`：** 读取指定对象的运输请求信息。
    *   `objSourceUrl`：（string，必填）对象 URI，来自 `searchObject`。
    *   返回运输请求详情，其中包括请求号（JSON 里的 `TRKORR`，或 `transportInfo.LOCKS.HEADER.TRKORR`）。

*   **`lock`：** 锁定 ABAP 对象以便编辑。
    *   `objectUrl`：（string，必填）对象 URI。
    *   返回 `lockHandle`，后续修改必须带上它。

*   **`unLock`：** 解锁先前锁定的 ABAP 对象。
    *   `objectUrl`：（string，必填）对象 URI。
    *   `lockHandle`：（string，必填）`lock` 返回的锁句柄。

*   **`setObjectSource`：** 修改较短的 ABAP 源码。大段源码用 `uploadSourceFile`。
    *   `objectSourceUrl`：（string，必填）对象 URI，并且带后缀 `/source/main`。示例：`/sap/bc/adt/oo/classes/zcl_invoice_xml_gen_model/source/main`
    *   `lockHandle`：（string，必填）`lock` 返回的锁句柄。
    *   `source`：（string，必填）完整的修改后源码。
    *   `transport`：（string，可选）运输请求号。

*   **`syntaxCheckCode`：** 对给定的 ABAP 源码做语法检查。
    *   `code`：（string，上传文件后可以省略）要检查的源码。
    *   `url`：（string，可选）对象 URL。
    *   `mainUrl`：（string，可选）主 URL。
    *   `mainProgram`：（string，可选）主程序。
    *   `version`：（string，可选）版本。
    *   返回语法检查结果，包括错误。

*   **`activate`：** 激活 ABAP 对象。激活和解除锁定的顺序见下面的说明。
    *   `object`：要激活的对象。

*   **`getObjectSource`：** 读取较短的 ABAP 源码。大段源码用 `downloadSourceFile`。
    *   `objectSourceUrl`：（string，必填）对象 URI，并且带后缀 `/source/main`。

**修改 ABAP 代码的流程：**

1.  **找到对象 URI：** 用 `searchObject`。
2.  **读原源码：** 大段用 `downloadSourceFile`；很短的片段才用 `getObjectSource`（带 `/source/main`）。
3.  **在本地修改源码文件。**
4.  **取得运输请求信息：** 用 `transportInfo`，或使用用户给出的请求号。
5.  **写入：** 大段用 `uploadSourceFile`。很短的片段才 `lock`、`setObjectSource`、`unLock`。
6.  **语法检查：** `uploadSourceFile` 已经检查。没有走文件上传时再用 `syntaxCheckCode`。
7.  **激活：** `uploadSourceFile` 的 `activate`，或 `activate`。
8.  **解锁：** 若仍持有锁，调用 `unLock`。激活前先解锁，否则会报使用者正在编辑。

**注意：**
*   **文件：** SAP 和本机文件系统是分开的。`getObjectSource` 只把源码放进工具结果，不会写文件。`downloadSourceFile` 才会把源码写到你指定的绝对路径。
*   **文件名：** 本地文件建议用 `[对象名].[对象类型].abap`。例如程序 `SAPMV45A.prog.abap`，类 `CL_IXML.clas.abap`。
*   **URL 后缀：** `setObjectSource` 和 `getObjectSource` 的源码地址要带 `/source/main`。`downloadSourceFile` 和 `uploadSourceFile` 的 `objectUrl` 不带这个后缀。
*   **运输请求：** 填请求号，不填任务号。可以从 `transportInfo` 或用户那里取得。
*   **锁句柄：** `setObjectSource` 和 `unLock` 必须使用 `lock` 返回的 `lockHandle`。锁可能过期，或被其他人释放；失败后要重新锁定。
*   **激活顺序：** 先解锁再激活。工具返回 JSON，要查看其中的错误信息。

## 高效访问数据库

SAP 系统数据量很大。写 ABAP 时只取需要的数据，减少性能影响和网络传输。不要在只需要少量数据时选出整张表，也不要使用过宽的 `WHERE`。

*   **使用 `WHERE`：** `SELECT` 里始终用 `WHERE` 过滤，只取需要的行。
*   **`UP TO 1 ROWS`：** 只需要一条记录时，若能提供 `SELECT SINGLE` 的全部关键字段，就用 `SELECT SINGLE`。否则用 `SELECT` 加上 `UP TO 1 ROWS`，让数据库找到第一条匹配记录后停止。示例：

    ```abap
    SELECT vgbel FROM vbrp WHERE vbeln = @me->lv_vbeln INTO @DATA(lv_vgbel) UP TO 1 ROWS.
      EXIT. " 找到后退出循环。
    ENDSELECT.
    ```

## 查看表和结构定义

遇到未知字段名或表使用不正确时，用下面的工具查看 DDIC 对象：

*   **`objectStructure`：** 按对象 URI 读取 ABAP 对象的结构和元数据，包括 DDIC 表和结构。先用 `searchObject` 把对象名解析成 URI。
*   **`ddicElement`：** 读取 DDIC 元素的详情，例如数据元素或域。
*   **`ddicRepositoryAccess`：** 按给定路径读取 DDIC 仓库信息。
*   **`tableContents`：** 读取表的内容行，不是表定义。临时 `SELECT` 用 `runQuery`。

````

## 排错

- **`npx` 找不到包，或客户端无法启动：** 确认 Node.js 已安装并在 PATH 中（`node -v`、`npm -v`）。Windows 上可把命令写成 `"command": "npx.cmd"`，或用源码构建，并把 `node dist/index.js` 写成绝对路径。
- **SAP 连接错误：** 核对 `SAP_URL`、`SAP_USER`、`SAP_PASSWORD`、`SAP_CLIENT`，确认系统可达、用户有 ADT 权限，并且 `SICF` 中的 `/sap/bc/adt` 已激活。
- **TLS 或自签名证书错误：** 在 Node 启动前把 `NODE_EXTRA_CA_CERTS` 设为受信任 CA 证书的绝对路径。证书校验保持开启。

## 参与贡献

欢迎贡献。步骤如下：

1. **Fork 本仓库**
2. **建立新分支**

   ```cmd
   git checkout -b feature/your-feature-name
   ```

3. **提交改动**

   ```cmd
   git commit -m "Add some feature"
   ```

4. **推送到自己的仓库**

   克隆出来的 `origin` 应是你自己的 fork，不要推到原作者仓库。

   ```cmd
   git push origin feature/your-feature-name
   ```

5. **打开 Pull Request**

## 许可证

本项目使用 [MIT License](LICENSE)。
