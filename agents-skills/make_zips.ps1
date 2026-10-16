# Creates a .zip for each folder in the current directory
Get-ChildItem -Directory | ForEach-Object {
    $zip = "$($_.Name).zip"
    Compress-Archive -Path $_.FullName -DestinationPath $zip -Force
    Write-Host "Created $zip"
}
