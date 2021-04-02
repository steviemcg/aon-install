Add-Type -assembly "system.io.compression.filesystem"
$source="https://github.com/MicrosoftArchive/redis/releases/download/win-3.2.100/Redis-x64-3.2.100.zip"
$destination="c:\redisarchive"
Invoke-WebRequest $source -OutFile $destination
[IO.Compression.ZipFile]::ExtractToDirectory('c:\redisarchive', 'c:\redis-3.2.100')

Push-Location c:\redis-3.2.100

.\redis-server.exe --service-install
.\redis-server.exe --service-start

Pop-Location