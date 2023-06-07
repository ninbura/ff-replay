param(
  [string]$relativePath = "C:/repositories/ff-replay",
  [string]$configName = "all"
)

function quit() {
  write-host('Closing program, press [Enter] to exit...') -NoNewLine
  $Host.UI.ReadLine()

  Clear-Host
  exit
}

function setRelativePath {
  if ($PSScriptRoot -ne "") {
    $relativePath = $PSScriptRoot
  }

  return $relativePath
}

function createProcessInfo($config) {
  $processInfo = [ordered]@{}

  foreach ($propertyName in $config.PSObject.Properties.Name) {
    $arguments = @("-loglevel", "quiet", "-stats", "-stats_period", "2") + $config.$propertyName

    $processInfo.$propertyName = New-Object System.Diagnostics.ProcessStartInfo;
    $processInfo.$propertyName.FileName = "ffmpeg"
    $processInfo.$propertyName.Arguments = "$($arguments)"
    $processInfo.$propertyName.UseShellExecute = $false
    $processInfo.$propertyName.RedirectStandardError = $true
    $processInfo.$propertyName.RedirectStandardInput = $true
  }

  return $processInfo
}

function startProcesses($processInfo) {
  $process = [ordered]@{}

  foreach ($key in $processInfo.Keys) {
    $process.$key = [System.Diagnostics.Process]::Start($processInfo.$key);
  }

  return $process
}

function killProcesses($process, $relativePath) {
  $WaitForKey = Start-Process powershell "$relativePath\wait-for-key.ps1" -NoNewWindow -PassThru

  while (!$WaitForKey.HasExited) {
    $table = @()

    foreach ($key in $process.Keys) {
      $statArray = ("feed=$key $($process.$key.StandardError.ReadLine())" -Replace "=\s+", "=").Trim().Split(" ")
      $statObject = [ordered]@{}

      foreach ($stat in $statArray) {
        $statObject.([regex]::match($stat, ".+(?=\=)")) = [regex]::match($stat, "(?<=\=).+")
      }

      $table += [PSCustomObject]$statObject
    }

    Clear-Host

    $printTable = $table | Format-Table -Wrap -AutoSize | Out-String -Stream | Where-Object { $_ }

    foreach ($line in $printTable) {
      Write-Host $line -ForegroundColor Cyan
    }
  }

  foreach ($key in $process.Keys) {
    $process.$key.StandardInput.WriteLine("q");
  }
}

function deleteSegments ($commands) {
  if ($commands.PSObject.Properties.Name.Count -eq 1) {
    $segmentDirectory = [regex]::match($commands.($commands.PSObject.Properties.Name)[$commands.($commands.PSObject.Properties.Name).Count - 1], "(?!`").+(?=/)").Value
  }
  else {
    $segmentDirectory = [regex]::match($commands.($commands.PSObject.Properties.Name[0])[$commands.($commands.PSObject.Properties.Name[0]).Count - 1], "(?!`").+(?=/)").Value
  }

  if ($(Get-ChildItem -Path "$segmentDirectory" | Measure-Object).Count -gt 0) {
    $userInput = ""

    while ($userInput.ToUpper() -notmatch "^Y$|^N$") {
      if (!(Test-Path -Path $segmentDirectory)) {
        Write-Host $segmentDirectory
        Write-Host "Segment directory not found, aborting to protect your system32 folder 😂"

        quit
      }

      $userInput = Read-Host "Would you like to delete existing segment buffer before you start recording? [y/n]"

      if ($userInput.ToUpper() -notmatch "^Y$|^N$") {
        Write-Host "Invalid input please try again..." -ForegroundColor Yellow
      }

      Write-Host ""
    }

    if ($userInput.ToUpper() -eq "Y") {
      Write-Host "Deleting segment files..."
            
      Remove-Item -Path "$segmentDirectory\*" -Recurse -Force

      if (!(Test-Path -Path "$segmentDirectory\*")) {
        Write-Host "Segment files have been succesfully deleted."
      }
      else {
        Write-Host "Segment files were not deleted, please see above for any errors..." -ForegroundColor Yellow
      }
            
    }
    else {
      Write-Host "Segment files have not been deleted."
    }

    Write-Host ""
  }
}

try {
  Clear-Host
  $relativePath = setRelativePath
  $config = Get-Content -Path "$relativePath\config\$configName.json" | ConvertFrom-Json
  deleteSegments $config.commands
  $processInfo = createProcessInfo $config.commands
  $process = startProcesses $processInfo
  killProcesses $process $relativePath
  Write-Host "`nCaught F16, ending recording...`n" -ForegroundColor Green
  deleteSegments $config.commands
  quit
} catch {
  Write-Host "An error occurred:" -ForegroundColor red
  Write-Host $_ -ForegroundColor red
  quit
}