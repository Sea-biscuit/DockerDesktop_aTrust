# DockerDesktop_aTrust

本项目通过 Docker 容器化运行深信服 `aTrust` Linux 客户端（当前适配版本：`2.5.16.30`），将虚拟网卡与客户端完全隔离在容器内，对外仅暴露标准的 **SOCKS5 (`21080`)** 与 **HTTP (`28888`)** 代理端口，实现安全、无痕访问内部网络。

```text
注：如有余力可自行设置映射端口，本项目默认设置高位以免系统自动占用
```

---

## 一、 核心安全特性与原理

### 1. 为什么在 Windows 宿主机直接安装 aTrust 有安全隐患？
- **强行注入私有根证书**：`aTrust` 会在宿主机系统证书库与浏览器（Firefox NSS 库等）中自动导入深信服自签名根证书。
- **本地 SSL 中间人解密（MITM）**：`aTrust` 在本地 `127.0.0.1:54632` 启动 `aTrustSSLProxy`，劫持并解密本地 HTTPS 流量。
- **后台常驻与内核驱动污染**：安装大量开机自启高权限服务、虚拟网卡驱动与环境检测模块（扫描本地进程、硬件信息等）。

### 2. 本方案如何实现全链路安全隔离？

```text
[宿主机浏览器 / SSH]
       │
       ├── 1. 登录认证 (HTTPS) ──> https://vpn.example.edu.cn (公网直连 CAS 认证)
       │                                  │
       │                          (网页前端 JS 回调)
       │                                  ▼
       ├── 2. 凭据下发 (54631) ──> https://localhost.sangfor.com.cn:54631
       │                          (使用深信服官方公网权威证书，宿主机免装任何私有证书)
       │                                  │
       │                         [Docker 容器: atrust-vpn]
       │                                  ├── aTrustAgent 接收 Token 并建立隧道
       │                                  └── 拉起容器内虚拟网卡 utun7 (2.0.0.1)
       │
       └── 3. 内网访问 (21080) ──> SOCKS5 127.0.0.1:21080 (danted)
                                          │
                                  (直接走 Linux 内核路由转发，完全绕过 54632 MITM 代理)
                                          ▼
                                     [utun7 隧道网卡] ──> 内网目标服务器 (端到端原生 TLS)
```

1. **宿主机根证书零污染**：`libaTrustCaService.so` 的导证操作被完全限制在容器内部，Windows 宿主机 `LocalMachine\Root` 与 `CurrentUser\Root` 不安装任何第三方根证书。
2. **物理级绕过 `54632` 中间人代理**：宿主机流量通过容器内的开源代理服务端 `danted`（`21080`）和 `tinyproxy`（`28888`）直接从内核路由表送入 `utun7` 虚拟网卡，容器内 `127.0.0.1:54632` 的 `aTrustSSLProxy` 完全无法触碰任何数据包。
3. **免装证书完成宿主机网页登录**：`54631` 端口使用的是权威 CA（DigiCert / GeoTrust）为公网域名 `localhost.sangfor.com.cn`（公网 DNS 解析指向 `127.0.0.1`）签发的合法商业证书，宿主机浏览器可直接通过原生 TLS 校验并将登录凭据回调给容器。

---



## 二、 目录结构与端口说明

### 1. 文件清单
```text
.
├── Dockerfile              # 定制构建脚本（含防崩溃、语言修复、端口配置）
├── docker-compose.yml      # 容器编排配置（严格绑定 127.0.0.1 与命名卷）
├── atrust.deb              # aTrust安装deb （需自行从 Releases 下载）
├── .uninstall_EasyConnect/ # 卸载残留 EasyConnect
│   └── .uninstall_RC.bat   # 清理脚本
├── .dockerignore           # 忽略无关文件以加速构建
├── .gitignore              # 忽略无关文件以加速构建
└── README.md               # 本文档
```

### 2. 暴露端口一览（均仅绑定 `127.0.0.1`）

| 宿主机端口 | 容器端口 | 协议 / 服务 | 用途说明 |
| :--- | :--- | :--- | :--- |
| `127.0.0.1:21080` | `21080` | **SOCKS5 (`danted`)** | **主力内网代理端口（支持容器内远程 DNS 解析）** |
| `127.0.0.1:28888` | `28888` | **HTTP (`tinyproxy`)** | 备用 HTTP 代理端口 |
| `127.0.0.1:28081` | `8080` | **Web VNC (`noVNC`)** | 浏览器访问容器内 `aTrust` 图形界面（默认密码：`123456`） |
| `127.0.0.1:54631` | `54631` | **HTTPS (`aTrustAgent`)** | 宿主机浏览器 CAS 登录成功后的本地回调端口 |
| `127.0.0.1:5901` | `5901` | **VNC (`TigerVNC`)** | 原生 VNC 客户端连接端口（默认密码：`123456`） |

---

## 三、 从零部署到登录完整操作步骤

>release内提供 `aTrust.deb` ，需要将其下载后放入项目根目录内

项目默认环境中有完整Docker desktop环境，默认使用WSL2，因此对部署docker不做赘述。

> 以下示例均使用占位域名 `example.edu.cn`，实际配置时请替换为您的目标单位域名。

### 第一步：构建并启动容器

在项目根目录下打开 PowerShell 运行：

```powershell
docker compose up -d --build
```

查看容器运行状态：

```powershell
docker compose ps
```

---

### 第二步：配置浏览器插件 SwitchyOmega（仅需配置一次）

> **注意**：如果您平时使用 Clash（`127.0.0.1:7890`）等系统代理，强烈建议使用浏览器的 **Proxy SwitchyOmega**（或 ZeroOmega）插件进行按域名分流，这样外网继续走 Clash，内网自动走 Docker 容器。

1. **修改/新建内网代理情景模式（`proxy`）**：
   - 打开 SwitchyOmega **选项 (Options)** -> 点击左侧 **`proxy`** 情景模式。
   - **代理协议**：选择 **`SOCKS5`**
   - **代理服务器**：填写 **`127.0.0.1`**
   - **代理端口**：填写 **`21080`**
   - 点击左下角 **应用选项 (Apply changes)** 保存。

2. **配置自动切换规则（`auto switch`）**：
   - 点击左侧 **`auto switch`** 情景模式，按以下**先后顺序**添加规则（**前 3 条必须设为直接连接，否则未登录 VPN 时无法打开登录页**）：

   | 优先级 | 条件类型 | 条件设置 | 情景模式 | 原因说明 |
   | :--- | :--- | :--- | :--- | :--- |
   | **1** | 域名通配符 | `vpn.example.edu.cn` | **`[直接连接]`** | aTrust 登录门户必须走公网直连 |
   | **2** | 域名通配符 | `uis.example.edu.cn` | **`[直接连接]`** | CAS 统一身份认证页必须走公网直连 |
   | **3** | 域名通配符 | `localhost.sangfor.com.cn` | **`[直接连接]`** | `54631` 端口唤醒回调必须直连本机 |
   | **4** | 域名通配符 | `*.example.edu.cn` | **`proxy`** | 其余所有内网域名走 Docker 容器 |
   | **5** | 域名通配符 | `10.*` | **`proxy`** | 内网 `10.x.x.x` 网段走 Docker 容器 |
   | **6** | 域名通配符 | `20.0.*` | **`proxy`** | 内网 `20.0.x.x` 网段走 Docker 容器 |
   | **默认** | 默认情景模式 | （列表最底部） | **`[系统代理]`** | 其他互联网流量照常走系统代理（如 Clash `7890`） |

   - 点击左下角 **应用选项 (Apply changes)** 保存。
   - 点击浏览器右上角扩展栏中的 SwitchyOmega 图标，将其切换为 **`auto switch`**。

---

### 第三步：首次设置 aTrust 服务器地址（仅首次部署需要）

1. 在宿主机浏览器打开 Web VNC：**[http://127.0.0.1:28081](http://127.0.0.1:28081)**
2. 点击 **Connect**，输入默认密码：**`123456`**。
3. 在容器内的 `aTrust` 客户端界面中，输入目标服务器地址（例如 `https://vpn.example.edu.cn`）并点击连接。
   *(注：得益于命名卷持久化，服务器地址会被永久保存，后续重启容器或重启电脑均无需再次输入。)*

---

### 第四步：登录认证与日常使用

首次配置好服务器地址后，日常使用有两种登录方式：

- **日常推荐（免开 VNC，宿主机浏览器直接登录）**：
  直接在宿主机浏览器访问您的 aTrust 门户地址（例如 `https://vpn.example.edu.cn`）。
  在网页中完成统一身份认证后，页面会通过 `https://localhost.sangfor.com.cn:54631` 自动将登录状态同步给容器内的 `aTrust`。看到网页提示认证成功，即可直接在浏览器访问任意内网系统。

- **备用方式（通过 Web VNC 复制链接）**：
  打开 `http://127.0.0.1:28081` 进入 VNC，在 `aTrust` 界面点击登录，弹窗中会显示完整的登录 URL（可点击 `Copy`），将其粘贴到宿主机浏览器完成登录即可。

---

## 四、 进阶场景配置：终端 SSH 连接内网服务器

在宿主机的 `C:\Users\<您的用户名>\.ssh\config` 中添加如下配置，即可直接 `ssh user@10.x.x.x` 无感穿透进内网：

```ssh-config
Host 10.* 20.0.* *.example.edu.cn
    ProxyCommand connect -S 127.0.0.1:21080 %h %p
```
*(注：Git for Windows 默认自带 `connect.exe`；若使用 OpenSSH 原生客户端且未将 Git `mingw64\bin` 加入 PATH，可将 `connect` 替换为 `"C:\Program Files\Git\mingw64\bin\connect.exe"`。)*

---

## 五、 常用运维命令与故障排查

### 1. 日常启停命令
```powershell
# 启动服务
docker compose start

# 停止服务（释放资源，保留登录配置）
docker compose stop

# 重启服务
docker compose restart

# 重新构建镜像并启动（修改 Dockerfile 后使用）
docker compose up -d --build
```

### 2. 常见问题速查

- **Q1：浏览器访问登录页提示“你尚未连接：代理服务器可能有问题，或地址不正确”？**
  - **原因**：浏览器插件 SwitchyOmega 误选中了未配置的示例模式（如 `proxy.example.com:8080`），或将登录门户域名路由到了尚未登录的容器代理端口。
  - **解决**：检查 SwitchyOmega 是否已按“第四节-第二步”将登录门户域名（如 `vpn.example.edu.cn`）、统一认证域名（如 `uis.example.edu.cn`）以及 `localhost.sangfor.com.cn` 设为 **`[直接连接]`**。

- **Q2：访问登录页弹窗提示 `{"code":10000001,"message":"invalid_param in query"}`？**
  - **原因**：URL 中的 `lang=` 参数为空。
  - **解决**：本项目的 `Dockerfile` 已内置 `/usr/share/sangfor/.aTrust/var/conf/localConfig.json` (`{"lang":"zh-CN"}`) 修复此问题。若手动拼接 URL，请确保参数中包含 `lang=zh-CN`。

- **Q3：需要彻底重置容器内的所有账号缓存与配置怎么办？**
  - 运行 `docker compose down -v`（`-v` 会清除命名卷中的所有历史缓存），然后重新执行 `docker compose up -d` 即可回到全新初始状态。
