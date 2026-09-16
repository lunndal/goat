# Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072 ; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/lunndal/goat/refs/heads/main/Prune-Cache.ps1'))
& (Join-Path $PSScriptRoot 'Prune-Cache.ps1')
