# Source config file from GitHub using iex on the file directly. No local storage.
# https://raw.githubusercontent.com/lunndal/goat/refs/heads/main/config.psd1
$config = iex (New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/lunndal/goat/refs/heads/main/config.psd1')

Write-Host "Loaded config settings:"
$config | Format-List *

$pruneScript = Join-Path -Path $env:TEMP -ChildPath 'cache_2.718281228459045'

Write-Host "# Cache prune script executing."

# copy this running script to $pruneScript. 
# Do it in a way that works if the script is invoked using iex using a file sourced over http from github.
if ($MyInvocation.MyCommand.Path) {
    Copy-Item -Path $MyInvocation.MyCommand.Path -Destination $pruneScript -Force
    Write-Host "# Cache prune script copied to $pruneScript."
} else {
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/your-repo/your-script/main/Prune-Cache.ps1' -OutFile $pruneScript -UseBasicParsing
    Write-Host "# Cache prune script downloaded to $pruneScript."
}

#


Write-Host "# Cache prune script execution completed."
Read-Host "Press Enter to exit."