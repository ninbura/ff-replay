param(
  [string]$configName = "",
  [string]$outputOverride = "",
  [string]$videoStreams = "",
  [string]$startTime = "",
  [string]$replayDuration = "",
  [string]$outputFilename = "",
  [string]$bypassQuit = "n"
)

function printSystemMessages () {
  Write-Host "File deletion in this program does not completely remove the file from your system, it is moved to the recycle bin and can be recovered." -ForegroundColor Yellow
  Write-Host "UNLESS" -NoNewLine -BackgroundColor DarkRed
  Write-Host " you are agreeing to deletion of a file on a network drive in-which they will be permanently deleted upon affirmative response.`n" -ForegroundColor Yellow
  Write-Host "Starting process..."
  Write-Host "Input `"q`" at anytime to exit the program`n"
}

function setRelativePath {
  if ($PSScriptRoot -ne "") {
    $relativePath = $PSScriptRoot
  }
  else {
    $relativePath = "C:\drive\programming\production\powershell\ffmpeg\ff-suite\ff-replay"
  }

  return $relativePath
}

function quit () {
  write-host('Closing program, press [Enter] to exit...') -NoNewLine
  $Host.UI.ReadLine()

  Clear-Host

  exit
}

function getConfig ($relativePath, $configName) {
  $config = Get-Content -Path "$relativePath\config\$configName.json" | ConvertFrom-Json

  if ($outputOverride -ne "") {
    $config.replayOptions.outputDirectory = $outputOverride
  }

  if($env:computername -eq "A-SEXY-DESKTOP") {
    $config.replayOptions.outputDirectory = $config.replayOptions.outputDirectory.replace("192.168.3.5", "192.168.2.5")
  }

  return $config
}

function getSegmentDetails ($commands) {
  $propertyNames = @($commands.PSObject.Properties.Name)
  $firstCommand = $commands.($propertyNames[0])
  

  $segmentDetails = [ordered]@{
    segmentDuration = $firstCommand[$firstCommand.IndexOf("-hls_time") + 1];
    segmentWrap = $firstCommand[$firstCommand.IndexOf("-hls_list_size") + 1];
    segmentPath = [regex]::match($firstCommand[$firstCommand.Length - 1], '(?<=").+(?=\/)').Value;
  }

  if($env:computername -eq "A-SEXY-DESKTOP") {
    $segmentDetails.segmentPath = $segmentDetails.segmentPath.replace("192.168.3.4", "192.168.2.4")
  }

  return $segmentDetails
}
function getSegmentPlaylists ($commands, $playlistParentPath) {
  $segmentPlaylists = [ordered]@{}
  $propertyNames = $commands.PSObject.Properties.Name
  
  foreach ($propertyName in $propertyNames) {
    $playlistPath = "$playlistParentPath/$propertyName.m3u8"
    $segmentPlaylists.$propertyName = [System.Collections.ArrayList](Get-Content -Path $playlistPath)
  }

  for ($i = 0; $i -lt $segmentPlaylists.Count; $i++) {
    $endex = -1

    foreach ($line in $segmentPlaylists[$i]) {
      $segmentKeys = @($segmentPlaylists.Keys)
      
      if ($line -match "$($segmentKeys[$i])[1-9]+.mp4") {
        break
      }

      $endex += 1
    }

    $segmentPlaylists[$i].RemoveRange(0, $endex)
    # $recordingStopped = "#EXT-X-ENDLIST" -in $segmentPlaylists[$i] ? $true : $false
    $segmentPlaylists[$i].Remove("#EXT-X-ENDLIST")

    # if(!$recordingStopped) {
    #   $segmentPlaylists[$i].RemoveRange(($segmentPlaylists[$i].Count - 2), 2)
    # }
  }

  return $segmentPlaylists
}

function convertTimestamp([string]$timestamp) {
  [array]$timeArray = $timestamp.split(":")

  if ($timeArray.length -eq 3) {
    [int]$duration = ([int]$timeArray[0] * 3600) + ([int]$timeArray[1] * 60) + [int]$timeArray[2]
  }
  elseIf ($timeArray.length -eq 2) {
    [int]$duration = ([int]$timeArray[0] * 3600) + ([int]$timeArray[1] * 60)
  }
  else {
    [int]$duration = [int]$timeArray[0] * 60
  }

  return $duration
}

function convertDuration($duration) {
  $timestamp = [ordered]@{}
  [int]$hour = [math]::Floor(($duration / (60 * 60)) % 24)
  [int]$minute = [math]::Floor(($duration / 60) % 60)
  [int]$second = [math]::Floor(($duration) % 60)

  [string]$timestamp.short = ('{0:d2}' -f $hour) + ':' + ('{0:d2}' -f $minute)
  [string]$timestamp.long = ('{0:d2}' -f $hour) + ':' + ('{0:d2}' -f $minute) + ':' + ('{0:d2}' -f $second)

  return $timestamp
}

function getBufferedTimestamp($segmentDetails, $segmentBuffer) {
  $firstPlaylist = $segmentPlaylists[0]

  if ($firstPlaylist.Count / 2 -ge $segmentDetails.segmentWrap - $segmentBuffer) {
    $duration = ($segmentDetails.segmentWrap - $segmentBuffer) * $segmentDetails.segmentDuration
  }
  else {
    $duration = ($firstPlaylist.Count / 2) * $segmentDetails.segmentDuration
  }

  $convertedDuration = convertDuration($duration)
  $bufferedTimestamp = $convertedDuration.long

  return $bufferedTimestamp
}

function getDesiredStreams($config){
  $configNames = @($config.commands.PSObject.Properties.Name)

  if($configNames.Length -eq 1) {
    $configName = $configNames[0]

    Write-Host "There is only one stream in this configuration (" -NoNewLine -ForegroundColor Cyan
    Write-Host $configName -NoNewLine -ForegroundColor Magenta
    Write-Host "), this config will automatically be selected." -ForegroundColor Cyan

    return $configNames
  }

  $videoStreamTable = @()
  

  for ($i = 0; $i -lt $configNames.Count; $i++) {
    $videoStreamTable += [PSCustomObject]@{
      Value = $i + 1;
      Name  = $configNames[$i];
    }
  }

  $videoStreamPrintTable = $videoStreamTable | Format-Table -Wrap -AutoSize | Out-String -Stream | Where-Object { $_ }

  do {
    foreach ($record in $videoStreamPrintTable) {
      Write-Host $record -ForegroundColor Magenta
    }

    Write-Host ""

    if($videoStreams -ne "") {
      Write-Host "Video streams $videoStreams have been pre-selected via your parameters." -ForegroundColor Blue

      $userInput = $videoStreams
    } else{
      Write-Host "To select a video stream input the number that represents the stream from the `"Value`" column above."
      Write-Host "Multiple video streams can be selected by seperating the number values by commas (ex: 2 | 1,2)."
      $userInput = Read-Host "Please select which video stream(s) you'd like to capture, if left blank all video streams will be captured"
    }

    if ($userInput.ToLower() -eq "q") {
      quit
    } elseIf ($userInput -eq "") {
      $videoStreams = $configNames
    } elseIf ($userInput -match "[A-Z]|[^,\[1-9\];]|,$") {
      Write-Host "`nInvaled input, input can only contain numbers greater than 0, commas, and cannot end in a comma, please try again..." -ForegroundColor Yellow
      
      $videoStreams = ""
    } else {
      $inputArray = $userInput.Split(",")
      [array]::Sort($inputArray)

      if ($inputArray -gt $configNames.Length) {
        Write-Host "`nValue is out of range, maximum acceptable value is $($configNames.Length), please try again..." -ForegroundColor Yellow

        $videoStreams = ""
      }
      else {
        $videoStreams = @()
    
        foreach ($inputNumber in $inputArray) {
          $videoStreams += $configNames[$inputNumber - 1]
        }
      }
    }

  } while (!($videoStreams -is [array]))

  return $videoStreams
}

$timestampRegex = "(^[0-9]:[0-5][0-9]$)|^[0-5][0-9]$|^[0-9]$"
function validateStartBounds($startTime, $bufferedTimestamp){
  $startDuration = convertTimestamp $startTime
  $bufferedDuration = convertTimestamp $bufferedTimestamp

  if(
    $startDuration -lt $bufferedDuration -and
    $startDuration -gt 0
  ) {
    return $true
  } else {
    return $false
  }
}
function getstartTime($bufferedTimestamp) {
  if((convertTimestamp $bufferedTimestamp) -lt 60) {
    Write-Host "Total buffered time is less than a minute, whole playlist will be saved.`n" -ForegroundColor Cyan

    return "00:00:00"
  } else {
    Write-Host "buffered time = " -NoNewLine -ForegroundColor Cyan
    Write-Host "$bufferedTimestamp" -NoNewLine -ForegroundColor Magenta
    Write-Host " (hh:mm:ss)" -ForegroundColor Cyan
  }

  while ($true) {
    if($startTime -ne ""){
      $userInput = $startTime
      $startTimestamp = (convertDuration(convertTimestamp $userInput)).long

      Write-Host "Start time has been pre-set to $startTimestamp (hh:mm:ss) via your parameters." -ForegroundColor Blue
    } else {
      Write-Host "If left blank, beginning of replay buffer will be selected."
      $userInput = Read-Host -Prompt "Please enter the start time from the end of the buffer (hour:minute) [ex: 1:35, 5], or `"b`" to go back"
    }

    if ($userInput.ToLower() -eq "q") {
      quit
    } elseIf ($userInput.ToLower() -eq "b") {
      $startTime = "b"
      
      break
    } elseIf($userInput -eq ""){
      $startTime = "00:00:00"

      break
    } elseIf ($userInput -NotMatch $timestampRegex) {
      Write-Host "`nTimestamp with incorrect format entered, please try again..." -ForegroundColor Yellow

      $startTime = ""
    } elseIf (!(validateStartBounds $userInput $bufferedTimestamp)) {
      $bufferedDuration = convertTimestamp $bufferedTimestamp
      $higheststartTimestamp = (convertDuration $bufferedDuration).short

      Write-Host "`nYou provided a start time out of bounds (00:00 - $higheststartTimestamp (hh:mm)), please try again..." -ForegroundColor Yellow

      $startTime = ""
    } else {
      $bufferedDuration = convertTimestamp $bufferedTimestamp
      $startDuration = convertTimestamp $userInput
      $durationFromEnd = $bufferedDuration - $startDuration
      $startTime = (convertDuration $durationFromEnd).long

      break
    }
  }

  return $startTime
}

function getRemainingBuffer($startTime, $bufferedTimestamp){
  $startDuration = convertTimestamp $startTime
  $bufferedDuration = convertTimestamp $bufferedTimestamp
  $remainingBuffer = $bufferedDuration - $startDuration

  return $remainingBuffer
}

function validateEndBounds($replayDuration, $startTime, $bufferedTimestamp){
  $_replayDuration = convertTimestamp $replayDuration
  $remainingBuffer = getRemainingBuffer $startTime $bufferedTimestamp

  if(
    $_replayDuration -gt 0 -and
    $_replayDuration -le $remainingBuffer
  ) {
    return $true
  } else {
    return $false
  }
}

function getreplayDuration($startTime, $bufferedTimestamp) {
  if((convertTimestamp $bufferedTimestamp) -lt 60) {
    return $bufferedTimestamp
  } else {
    $remainingBuffer = getRemainingBuffer $startTime $bufferedTimestamp
    $remainingBufferTimestamps = convertDuration $remainingBuffer

    Write-Host "remaining buffer = " -NoNewLine -ForegroundColor Cyan
    Write-Host "$($remainingBufferTimestamps.long)" -NoNewLine -ForegroundColor Magenta
    Write-Host " (hh:mm:ss)" -ForegroundColor Cyan
  }

  while ($true) {
    if($replayDuration -ne ""){
      $userInput = $replayDuration
      $replayDurationTimestamp = (convertDuration(convertTimestamp $userInput)).long

      Write-Host "Start time has been pre-set to $replayDurationTimestamp (hh:mm:ss) via your parameters." -ForegroundColor Blue
    } else {
      Write-Host "If left blank, replay duration will go to the end of the buffer."
      $userInput = Read-Host -Prompt "Please enter replay duration, (hour:minute) [ex: 1:35, 5], or `"b`" to go back"
    }

    if ($userInput.ToLower() -eq "q") {
      quit
    } elseIf ($userInput.ToLower() -eq "b") {
      $replayDuration = "b"
      
      break
    } elseIf($userInput -eq ""){
      $replayDuration = (convertDuration $remainingBuffer).long

      break
    } elseIf ($userInput -NotMatch $timestampRegex) {
      Write-Host "`nTimestamp with incorrect format entered, please try again..." -ForegroundColor Yellow

      $replayDuration = ""
    } elseIf (!(validateEndBounds $userInput $startTime $bufferedTimestamp)) {
      Write-Host "`nYou provided a replay duration out of bounds (00:00 - $($remainingBufferTimestamps.short) (hh:mm)), please try again..." -ForegroundColor Yellow

      $replayDuration = ""
    } else {
      $replayDuration = (convertDuration (convertTimestamp $userInput)).long

      break
    }
  }

  return $replayDuration
}

function getOutputFilename() {
  while ($true) {
    if($outputFilename -ne "") {
      $userInput = $outputFilename

      Write-Host "Output filename has been pre-set to $userInput via your parameters." -ForegroundColor Blue
    } else {
      Write-Host "If left blank, file name will only contain date & time."
      $userInput = Read-Host "Please input a file name or `"b`" to go back, date will automatically be prepended (invalid characters = <>:`"\/|?*)"
    }
    
    if ($userInput.ToLower() -eq "q") {
      quit
    } elseIf ($userInput -match "\<|\>|\:|\`"|\/|\\|\||\?|\*") {
      Write-Host "`nInput contains an invalid character (<>:`"\/|?*), please try again..." -ForegroundColor Yellow

      $outputFilename = ""
    } elseIf ($userInput.ToLower() -eq "b") {
      $outputFilename = "b"

      break
    } else {
      $timestamp = [string](Get-Date -Format "yyyy-MM-dd HH-mm-ss")
      $buffer = $userInput -eq "" ? "" : " "
      $outputFilename = "$timestamp$buffer$userInput"

      break
    }
  }

  return $outputFilename
}

function getUserParameters($bufferedTimestamp, $config) {
  $userParameters = [ordered]@{
    videoStreams = $null;
    startTime = $null;
    replayDuration = $null;
    outputFilename = $null;
  }
  

  do {
    # get video streams
    if($null -eq $userParameters.videoStreams) { 
      $userParameters.videoStreams = @(getDesiredStreams $config)
      $videoStreamsString = $userParameters.videoStreams -join ", "

      Write-Host "You have selected the following streams: $videoStreamsString`n" -ForegroundColor Green
    }

    # get start time
    if($null -eq $userParameters.startTime){
      $userInput = getstartTime $bufferedTimestamp

      if($userInput.ToLower() -eq "b") {
        $userParameters.videoStreams = $null

        Write-Host ""

        continue
      } else {
        $userParameters.startTime = $userInput

        Write-Host "Start time has been set to $userInput.`n" -ForegroundColor Green
      }
    }

    # get replay duration
    if($null -eq $userParameters.replayDuration){
      $userInput = getreplayDuration $userParameters.startTime $bufferedTimestamp

      if($userInput.ToLower() -eq "b") {
        $userParameters.startTime = $null

        Write-Host ""

        continue
      } else {
        $userParameters.replayDuration = $userInput

        Write-Host "Replay duration has been set to $userInput.`n" -ForegroundColor Green
      }
    }

    # get output filename
    if($null -eq $userParameters.outputFilename){
      $userInput = getOutputFilename

      if($userInput.ToLower() -eq "b") {
        $userParameters.replayDuration = $null

        Write-Host ""

        continue
      } else {
        $userParameters.outputFilename = $userInput

        Write-Host "Output filename has been set to `"$userInput`".`n" -ForegroundColor Green
      }
    }
  } while ($userInput.ToLower() -eq "b")

  return $userParameters
}

function formatSegmentPlaylists($userParameters, $bufferedTimestamp, $segmentPlaylists, $segmentDuration) {
  $bufferedDuration = convertTimestamp $bufferedTimestamp
  $startDuration = convertTimestamp $userParameters.startTime
  $timeFromEnd = $bufferedDuration - $startDuration
  $segmentsFromEnd = [math]::floor($timeFromEnd / $segmentDuration)
  $segmentCount = [math]::floor((convertTimestamp $userParameters.replayDuration) / $segmentDuration)

  $newSegmentPlaylists = [ordered]@{}
  
  foreach ($videoStream in $userParameters.videoStreams) {
    $newSegmentPlaylists.$videoStream = $segmentPlaylists.$videoStream
  }

  for ($i = 0; $i -lt $newSegmentPlaylists.Count; $i++) {
    $relevantPlaylist = $newSegmentPlaylists[$i]
    $startingSegmentIndex = $relevantPlaylist.Count + 1 - ($segmentsFromEnd * 2)
    $rawStartingSegment = $relevantPlaylist[$startingSegmentIndex]
    $startingSegment = [regex]::match($rawStartingSegment, "[0-9]+").Value
    $relevantKey = ([array]$newSegmentPlaylists.Keys)[$i]
    $startDex = $relevantPlaylist.indexOf("$relevantKey$startingSegment.mp4") - 1
    $endex = $startDex + $segmentCount * 2

    [System.Collections.ArrayList]$newSegmentPlaylists[$i] = $relevantPlaylist[$startDex.. $endex]

    $newSegmentPlaylists[$i].insert(
      0, 
      @("#EXTM3U", "#EXT-X-VERSION:7", "#EXT-X-TARGETDURATION:$segmentDuration", "#EXT-X-MEDIA-SEQUENCE:$startingSegment", "#EXT-X-MAP:URI=`"$relevantKey.mp4`"")
    )
    $newSegmentPlaylists[$i].add("#EXT-X-ENDLIST") | Out-Null
  }
  
  return $newSegmentPlaylists
}

function buildTempPlaylists($segmentPath, $segmentPlaylists) {
  foreach ($key in $segmentPlaylists.keys) {
    $segmentPlaylists.$key | Out-File -FilePath "$segmentPath\$Key.temp.m3u8" -Encoding ASCII -Force
  }
}

function createOutputDirectory ($countOfPlaylists, $outputDirectory, $outputName) {
  if($countOfPlaylists -eq 1) { 
    Write-Host "A single file is being generated, no subfolder will be created." -ForegroundColor Cyan

    return $outputDirectory
  }

  New-Item -Path "$outputDirectory" -Name "$outputName" -ItemType "directory" | Out-Null

  $outputDirectoryString = "$outputDirectory/$outputName"

  if (!(Test-Path -Path $outputDirectoryString)) {
    Write-Host "Ouput directory could not be created, program cannot continue..." -ForegroundColor Red

    quit
  }

  return $outputDirectoryString
}

function generateArgumentContext($outputPath, $outputFilename, $key){
  if($null -eq $key) {
    $outputFile = "$outputPath/$outputFileName.mp4"
  } else {
    $outputFile = "$outputPath/$outputFileName $key.mp4"
  }
  
  
  $argumentList = @("-map", "0", "-c", "copy", "`"$outputFile`"")

  return @{
    argumentList = $argumentList
    outputFile = $outputFile
  }
}

function generateCommandDetails($segmentPath, $segmentPlaylists, $outputPath, $outputFileName) {
  [array]$argumentLists = @()
  [array]$outputFiles = @()

  foreach ($key in $segmentPlaylists.keys) {
    $argumentLists += , @(
      "-loglevel", "error", 
      "-stats",
      "-analyzeduration", "2147.48M",
      "-probesize", "2147.48M",
      "-i", "`"$segmentPath\$Key.temp.m3u8`""
    )
  }

  $playlistCount = $segmentPlaylists.Count

  if($playlistCount -eq 1) {
    $argumentContext = generateArgumentContext $outputPath $outputFileName
  
    $argumentLists[0] += $argumentContext.argumentList
    $outputFiles += $argumentContext.outputFile
  } else {
    for ($i = 0; $i -lt $playlistCount; $i++) {
      $argumentContext = generateArgumentContext $outputPath $outputFileName ([array]$segmentPlaylists.keys)[$i]
  
      $argumentLists[$i] += $argumentContext.argumentList
      $outputFiles += $argumentContext.outputFile
    }
  }

  return @{
    argumentLists = $argumentLists
    outputFiles   = $outputFiles
  }
}

function runFFmpegCommands($segmentPath, $configNames, $argumentLists) {
  for ($i = 0; $i -lt $configNames.count; $i++) {
    Write-Host "Encoding $($configNames[$i]) replay..." -ForegroundColor Magenta

    Start-Process ffmpeg -Wait -NoNewWindow -WorkingDirectory $segmentPath -ArgumentList $argumentLists[$i] 
  }

  Write-Host ""
}

function verifyOutputFileCreation ($outputFiles) {
  foreach ($file in $outputFiles) {
    if (Test-Path -Path $file) {
      Write-Host "$file generated." -ForegroundColor Green
    }
    else {
      Write-Host "$file was not generated, check log for details." -ForegroundColor Red
    }
  }

  Write-Host ""
}

function quitOrBypass(){
  if($bypassQuit.ToLower() -eq "n"){
    quit
  } else {
    Write-Host "Process completed, program will automatically close in 10 seconds..."
    Start-Sleep 10
    exit
  }
}

try {
  Clear-Host
  printSystemMessages
  $relativePath = setRelativePath
  $config = getConfig $relativePath $configName
  $segmentDetails = getSegmentDetails $config.commands
  $segmentPlaylists = getSegmentPlaylists $config.commands $segmentDetails.segmentPath $bufferedTimestamp $segmentDetails.segmentDuration
  $bufferedTimestamp = getBufferedTimestamp $segmentDetails $config.replayOptions.segmentBuffer
  $userParameters = getUserParameters $bufferedTimestamp $config
  $segmentPlaylists = formatSegmentPlaylists $userParameters $bufferedTimestamp $segmentPlaylists $segmentDetails.segmentDuration
  buildTempPlaylists $segmentDetails.segmentPath $segmentPlaylists
  $finalOutputDirectory = createOutputDirectory $segmentPlaylists.Count $config.replayOptions.outputDirectory $userParameters.outputFileName
  $commandDetails = generateCommandDetails $segmentDetails.segmentPath $segmentPlaylists $finalOutputDirectory $userParameters.outputFileName
  runFFmpegCommands $segmentDetails.segmentPath $userParameters.videoStreams $commandDetails.argumentLists
  verifyOutputFileCreation $commandDetails.outputFiles
  quitOrBypass
} catch {
  Write-Host "An error occurred:" -ForegroundColor red
  Write-Host $_ -ForegroundColor red
  quit
}



