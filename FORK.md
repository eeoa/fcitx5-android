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
were also checked. A full APK build awaits Android SDK/NDK/CMake setup.

References:

- [Android application IDs and namespaces](https://developer.android.com/build/configure-app-module)
- [Android signing from the command line](https://developer.android.com/build/building-cmdline)
- [Microsoft OpenJDK downloads](https://learn.microsoft.com/en-us/java/openjdk/download)
