param(
  $configName = "all",
  $commandName = "d_camera"
)

function SetRelativePath {
  if ($PSScriptRoot -ne "") {
    $relativePath = $PSScriptRoot
  }
  else {
    $relativePath = "~\repos\ff-replay\test"
  }

  return $relativePath
}

$relativePath = SetRelativePath
$config = Get-Content -Path "$relativePath\..\config\$configName.json" | ConvertFrom-Json

Start-Process ffmpeg -ArgumentList $config.commands."$($commandName)" -NoNewWindow -Wait