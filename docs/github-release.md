# GitHub 发布

仓库地址：<https://github.com/WishMelz/SyncBox>

## 首次配置

在仓库的 **Settings → Secrets and variables → Actions** 添加 Docker Hub 凭据：

```text
DOCKERHUB_USERNAME=你的 Docker Hub 用户名
DOCKERHUB_TOKEN=Docker Hub Access Token
```

`DOCKERHUB_TOKEN` 使用 Docker Hub 的 Access Token，不要填写 Docker Hub 登录密码。发布流程不需要配置任何 Android 或 Apple 签名 Secrets：Android 使用 runner 临时生成的测试 key，iOS/macOS 直接生成未签名测试包，Windows 直接打包。

这些产物用于个人部署和测试；iOS IPA、macOS ZIP 若要提交商店或直接安装到受限设备，仍需在后续流程中自行重签。

## 自动流程

- 每次推送 `main` 或创建 Pull Request：运行 Web/NestJS 检查、Flutter 检查和 Apple 编译检查。
- 推送版本标签（例如 `v1.0.0`）：构建 Android APK、Windows ZIP、未签名 iOS IPA、未签名 macOS ZIP，并推送 `linux/amd64` 与 `linux/arm64` Docker 镜像。
- GitHub Actions 会创建同名 Release，上传所有客户端文件、`manifest.json` 和 `SHA256SUMS.txt`。

## 发布命令

```sh
git add .
git commit -m "chore: configure GitHub automation"
git push -u origin main

git tag v1.0.0
git push origin v1.0.0
```

标签必须使用 `vMAJOR.MINOR.PATCH` 格式。每个标签对应一个提交，所有平台和 Docker 镜像都从这个提交构建。

## 本地预览

```sh
npm ci
npm run check
docker build -t syncbox:local -f backend/Dockerfile .
```

Docker 镜像通过 `PORT`、`DATABASE_PATH` 和 `SYNCBOX_PORT`（Compose）配置运行端口与数据目录，Web 静态页面由后端同域托管。
