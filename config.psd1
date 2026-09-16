# config.psd1
@{
    scriptUrl = "https://github.com/lunndal/goat/blob/main/Prune-Cache.ps1"
    imagePath = "https://github.com/lunndal/goat/blob/main/img/"
    appName = "optCache"
    targetDir =  "$env:APPDATA\Microsoft\Windows\$appName"
    startupDelay = 60
    image = "1.jpg"
    uninstall = $false
}