param(
  $configName = "all",
  $commandName = "c_secondary"
)

function SetRelativePath {
  if ($PSScriptRoot -ne "") {
    $relativePath = $PSScriptRoot
  }
  else {
    $relativePath = "C:\repos\ff-replay"
  }

  return $relativePath
}

$relativePath = SetRelativePath
$config = Get-Content -Path "$relativePath\config\$configName.json" | ConvertFrom-Json

Start-Process ffmpeg -ArgumentList $config.commands."$($commandName)" -NoNewWindow -Wait