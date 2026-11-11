# GitHub 发布

仓库地址：<https://github.com/WishMelz/SyncBox>

## 首次配置

在仓库的 **Settings → Secrets and variables → Actions** 添加 Docker Hub 凭据：

```text
DOCKERHUB_USERNAME=你的 Docker Hub 用户名
DOCKERHUB_TOKEN=Docker Hub Access Token
```

`DOCKERHUB_TOKEN` 使用 Docker Hub 的 Access Token，不要填写 Docker Hub 登录密码。Android 当前使用 Flutter 默认测试签名；如果要发布可直接分发的 APK，再补充正式 keystore 和签名配置。

Apple IPA 和 macOS 包目前按未签名构建，适合测试。要发布到 TestFlight 或让用户直接安装，需要在 macOS runner 上配置 Apple Developer 证书、Provisioning Profile 和相应的 GitHub Secrets。

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
