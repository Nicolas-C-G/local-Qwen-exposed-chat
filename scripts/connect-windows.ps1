param(
    [string]$KeyPath = "$env:USERPROFILE\.ssh\ia-server",
    [string]$GuestUser = "ubuntu",
    [int]$SshPort = 2222,
    [int]$LocalPort = 8080
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $KeyPath -PathType Leaf)) { throw "Private key not found: $KeyPath" }
ssh.exe -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -L "127.0.0.1:${LocalPort}:127.0.0.1:8080" -i $KeyPath -p $SshPort "$GuestUser@127.0.0.1"
exit $LASTEXITCODE
