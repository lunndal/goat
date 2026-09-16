#$pruneScriptPath = Join-Path -Path $env:TEMP -ChildPath 'cache_2.718281228459045)'

#if (-not (Test-Path -LiteralPath $pruneScriptPath)) {
#    throw "Prune script not found: $pruneScriptPath"
#}

#Write-Host "Executing cache prune script: $pruneScriptPath"
#& $pruneScriptPath

write-console "Cache prune script executed."
Read-Host "Press Enter to exit."