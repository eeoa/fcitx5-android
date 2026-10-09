# Personal fork development

This fork is based on upstream release **0.1.3** (`048f581c`).

## Repository and branches

- `origin`: <https://github.com/eeoa/fcitx5-android>
- `upstream`: <https://github.com/fcitx5-android/fcitx5-android>
- `release/0.1.3`: unchanged upstream release baseline.
- `develop`: personal integration branch, initially based on that release.
- `setup/identity-and-signing`: independent package and signing preparation.

Create future layout work from the integration branch:

```powershell
git switch develop
git switch -c feature/keys14-layout
# Implement and commit the layout, then integrate it:
git switch develop
git merge --ff-only feature/keys14-layout
```

If `develop` has advanced, either rebase your unpublished feature branch onto
`develop` before the merge, or cherry-pick its selected commits onto `develop`.
Do not rewrite the published upstream tag or the release baseline. Future
upstream upgrades can be reviewed with `git fetch upstream --tags` before
merging a newer release tag into `develop`.

## Application identity

`gradle.properties` selects `forkApplicationId=org.fcitx.fcitx5.android.keys14`.

- Release app: `org.fcitx.fcitx5.android.keys14`
- Debug app: `org.fcitx.fcitx5.android.keys14.debug`
- Release plugins: `org.fcitx.fcitx5.android.keys14.plugin.<plugin>`
- Debug plugins: `org.fcitx.fcitx5.android.keys14.plugin.<plugin>.debug`

Kotlin/Java namespaces and JNI names remain upstream-compatible. The install
IDs, plugin discovery actions, package visibility, and IPC permissions follow
`forkApplicationId`. Build this fork's plugins with the same package setting
and signing key as its main app. Official plugin APKs target the official app.

The requested suffix `14keys` was changed to `keys14`, since each Android
application ID segment must start with a letter. Choose the final ID before
distribution and retain the same ID and signing key for future updates.

## Local files

The enclosing workspace keeps tools and private signing material outside Git:

```text
fcitx/
  fcitx5-android/             # this repository
  toolchains/
    jdk-21.0.12.1+1/          # portable Microsoft OpenJDK 21
    gradle-user-home/         # local Gradle downloads/cache
    android-sdk/             # local SDK, Build-Tools and NDK
    rime-1.12.0/              # official Windows engine for schema tests
  signing/
    fcitx5-release.p12        # private PKCS12 signing key
    release-signing.json     # private passwords and alias
    fcitx5-release.pem        # public certificate
    certificate-info.json    # public fingerprint and validity
```

The private directory has restricted Windows permissions. Keep a secure backup
of the keystore and its password together. The generator refuses to overwrite
existing signing material. The certificate is a normal self-signed Android
release certificate, with RSA 4096, SHA256withRSA, and 10,950 days of validity.

Certificate SHA-256:

```text
4E24E61D99DFE1B629577FEE5EAFB2EC8AA34E7EB7A72D7252FD01C268CF82D3
```

## Signed builds

PowerShell 7 and a JDK are required by the helper scripts. They discover a JDK
under the workspace's `toolchains/` directory, or accept `-JavaHome`.

```powershell
# Main app; the configured application ID is used automatically.
./tools/Build-Release.ps1

# Main app and all matching plugins, using the same private signing key.
./tools/Build-Release.ps1 -IncludePlugins

# Optional ABI selection for a smaller local build.
./tools/Build-Release.ps1 -GradleArguments '-PbuildABI=arm64-v8a'
```

The build helper passes `SIGN_KEY_FILE`, `SIGN_KEY_ALIAS`, `SIGN_KEY_PWD`, and
`SIGN_KEY_STORE_TYPE`
through the process environment to upstream's existing signing integration.
It restores the environment when finished and keeps passwords out of command
arguments. Standard debug builds retain Android's separate debug signing key.

For a new workspace without signing material, restore the existing key from
backup. Only generate a new signing identity for a new app:

```powershell
./tools/New-ReleaseSigningKey.ps1
```

Android SDK/NDK/CMake and the native build dependencies are listed in upstream
`README.md` and `build-logic/convention/src/main/kotlin/Versions.kt`. The pinned
release uses SDK 36, Build-Tools 36.1.0, NDK 28.0.13004108, and CMake 3.31.6.
Set `sdk.dir` in the ignored `local.properties`, or configure `ANDROID_HOME`.

Validation completed during setup: all pinned submodules were initialized,
the convention build's `compileKotlin` task passed, both PowerShell scripts
parsed successfully, and the generated private key signed a JAR whose signature
was verified. Key overwrite protection and invalid application ID rejection
were also checked. No full APK build was performed during the initial setup.

## 14 键拼音

开发分支：`feature/keys14-layout`。全键盘继续保留，新增布局使用以下字母分组：

```text
QW  ER  TY  UI  OP
AS  DF  GH  JK  L
    ZX  CV  BN  M
```

首版使用本 fork 的 **Rime 插件**解码。每个键发送该组第一个字母的小写编码；
`keys14_pinyin.schema.yaml` 将全部 26 个字母映射到这些编码，并复用朙月拼音词库。
这能同时处理一个音节中多个歧义字母和连续词组，不依赖单次拼写纠错。
内置拼音、双拼和其他输入法继续使用原布局。

使用方法：

1. 编译并安装本 fork 的主程序与 Rime 插件，使用相同的包名配置和签名。
2. 在输入法列表中添加 Rime，在其方案菜单中选择 **14键拼音**。
3. 键盘自动切换为 14 键。选择其他方案或 Rime 西文模式后恢复全键盘。
4. 点击“分词”插入 `'` 音节分隔符；点击“符”和“123”进入对应面板，
   返回字母键盘时自动恢复 14 键。字母键上的小数字、标点沿用滑动输入手势。

若已有 `default.custom.yaml` 覆盖 `schema_list`，需在自己的列表中加入
`- schema: keys14_pinyin`，然后重新部署 Rime。方案名 `14键拼音` 是 Android
端自动选择布局的标记，请保留此名称。

只编译主程序和 Rime 插件的 arm64 版本：

```powershell
./tools/Build-Release.ps1 -GradleArguments @('-PbuildABI=arm64-v8a', ':plugin:rime:assembleRelease')
```

例如“你好”按 `BN UI GH AS OP`，发送编码 `bugao`；“中国”按
`ZX GH OP BN GH GH UI OP`，发送编码 `zgobgguo`。同一编码可以产生多个正确的
拼音、汉字候选，由词频及上下文排序，并通过候选栏选词。

解码验证脚本使用官方 librime 1.12.0 Windows 发行包（与 Android 插件同版本），
在临时用户目录中部署 CMake 安装清单里的方案与词库，不会访问个人 Rime 配置：

```powershell
python tools/validate-keys14-rime.py --rime-dir ../toolchains/rime-1.12.0/dist --work-dir ../toolchains
```

已验证 `BN UI` 同时产生“你”和“不”，以及“你好”“中国”“学习”“输入”
“我们”“绿色”等词组、手动分词、退格、选词、空格上屏和原全拼方案。
`Keys14KeyboardTest` 另检查 26 个字母覆盖、界面编码与方案一致、每行宽度以及
只在匹配的 Rime 中文方案中启用布局。

Android `:app:compileDebugKotlin` 与上述两个单元测试已通过。
尚未在模拟器或真机上验证触摸与显示，也未构建完整 APK；原生打包还需要
SDK CMake、extra-cmake-modules 和 Gettext 等主机工具。

设计参考：[Rime 拼写运算](https://github.com/rime/home/wiki/SpellingAlgebra)。

References:

- [Android application IDs and namespaces](https://developer.android.com/build/configure-app-module)
- [Android signing from the command line](https://developer.android.com/build/building-cmdline)
- [Microsoft OpenJDK downloads](https://learn.microsoft.com/en-us/java/openjdk/download)
