# Load environment variables from .env (simple KEY=VALUE parser) and run the backend.
if (Test-Path .env) {
  Get-Content .env | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#")) {
      $idx = $line.IndexOf("=")
      if ($idx -gt 0) {
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()
        [Environment]::SetEnvironmentVariable($key, $val, "Process")
      }
    }
  }
}

moon run cmd/main
