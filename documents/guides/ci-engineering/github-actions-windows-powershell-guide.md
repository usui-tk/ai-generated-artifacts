# GitHub Actions + Windows Hosted Runner + PowerShell 5.1 実践調査メモ

## 概要

GitHub Actions の GitHub-hosted runner (`windows-latest`) 上で、
PowerShell スクリプトがローカルでは正常動作するが、
CI 上では失敗するケースについて、公開情報ベースで整理した内容。

前提:

- GitHub-hosted runner
- `runs-on: windows-latest`
- `shell: powershell`
- Windows PowerShell 5.1 前提

---

# GitHub-hosted Windows Runner の重要ポイント

## 1. `windows-latest` は固定環境ではない

`windows-latest` は GitHub が提供する最新安定イメージを指す。

そのため:

- 実行時期によって OS バージョンが変わる
- プリインストールツールが更新される
- 以前成功していた workflow が失敗することがある

参考:
https://docs.github.com/en/actions/reference/runners/github-hosted-runners

---

## 2. Runner イメージは定期更新される

GitHub-hosted runner は weekly cadence で更新される。

実行ログの:

- Set up job
- Runner Image
- Included Software

から、その実行時点のソフトウェア一覧を確認可能。

参考:
https://docs.github.com/actions/using-github-hosted-runners/about-github-hosted-runners

---

## 3. PowerShell 5.1 と PowerShell 7 は別物

GitHub Actions では:

| shell | 実体 |
|---|---|
| `powershell` | Windows PowerShell 5.1 |
| `pwsh` | PowerShell 7+ |

両者には:

- 文字コード
- モジュール互換
- .NET 実装
- パス処理
- Encoding
- JSON処理

などの差分がある。

---

# よくある失敗要因

## 1. 文字コード問題

PowerShell 5.1 は UTF-8 が既定ではない。

特に:

- GITHUB_ENV
- GITHUB_PATH
- GITHUB_OUTPUT

への書き込み時に問題化しやすい。

推奨:

```powershell
"KEY=VALUE" |
  Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
```

参考:
https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands

---

## 2. 相対パス問題

ローカルと GitHub Actions でカレントディレクトリが異なる場合がある。

推奨:

```yaml
defaults:
  run:
    working-directory: ${{ github.workspace }}
```

または:

```powershell
Set-Location $env:GITHUB_WORKSPACE
```

---

## 3. ExecutionPolicy 差異

Runner 側の ExecutionPolicy に依存するケースがある。

確認方法:

```powershell
Get-ExecutionPolicy -List
```

---

## 4. Administrator だがローカルPCとは違う

GitHub-hosted runner は Administrator 権限で動作する。

ただし:

- 毎回クリーン VM
- 永続設定なし
- 社内証明書なし
- GPOなし
- ローカルユーザ設定なし

そのため:

- 証明書依存
- レジストリ依存
- ローカルキャッシュ依存

などは失敗しやすい。

---

## 5. ネットワーク制約

GitHub-hosted runner は Azure VM 上で稼働。

注意点:

- ICMP inbound block
- 社内NWアクセス不可
- 固定IPではない

そのため:

- ping
- traceroute
- IP allowlist

依存スクリプトは失敗する可能性がある。

---

# 実践的な Workflow 例

```yaml
name: Windows PowerShell 5.1 Test

on:
  workflow_dispatch:
  push:
    branches: [ main ]
  pull_request:

jobs:
  test:
    runs-on: windows-latest

    defaults:
      run:
        shell: powershell
        working-directory: ${{ github.workspace }}

    env:
      CI: true
      LOG_DIR: ${{ runner.temp }}\logs
      RESULT_DIR: ${{ runner.temp }}\results

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Initialize environment
        run: |
          $ErrorActionPreference = 'Stop'

          New-Item -ItemType Directory -Force -Path $env:LOG_DIR | Out-Null
          New-Item -ItemType Directory -Force -Path $env:RESULT_DIR | Out-Null

          [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

          "TEST_ROOT=$env:GITHUB_WORKSPACE" |
            Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append

      - name: Diagnostics
        run: |
          $PSVersionTable
          Get-ExecutionPolicy -List
          Get-Location
          whoami

      - name: Install Pester
        run: |
          Install-Module Pester -Scope CurrentUser -Force

      - name: Run script
        run: |
          .\scripts\YourScript.ps1

      - name: Run tests
        run: |
          Invoke-Pester .\tests

      - name: Upload logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: logs
          path: ${{ runner.temp }}\logs
```

---

# 実務で推奨する調査ポイント

## 最優先

### 1. PowerShell バージョン確認

```powershell
$PSVersionTable
```

---

### 2. 現在ディレクトリ確認

```powershell
Get-Location
```

---

### 3. 環境変数確認

```powershell
Get-ChildItem Env:
```

---

### 4. Encoding 確認

```powershell
[Console]::OutputEncoding
```

---

### 5. 実行ポリシー確認

```powershell
Get-ExecutionPolicy -List
```

---

# 失敗時のベストプラクティス

## 必ずログを Artifact 保存する

```yaml
if: always()
```

を使う。

理由:

- 失敗時でもログ回収可能
- Runner 差分調査可能
- Encoding 問題分析可能

---

# 参考情報

## GitHub-hosted runners

https://docs.github.com/en/actions/reference/runners/github-hosted-runners

---

## About GitHub-hosted runners

https://docs.github.com/actions/using-github-hosted-runners/about-github-hosted-runners

---

## Workflow commands

https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands

---

## PowerShell build/test example

https://docs.github.com/actions/automating-builds-and-tests/building-and-testing-powershell
