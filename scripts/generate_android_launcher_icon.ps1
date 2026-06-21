param(
    [string]$Source = "assets/icons/AppIcon-Default-1024.png",
    [string]$Destination = "assets/icons/AppIcon-Android-1024.png"
)

Add-Type -AssemblyName System.Drawing

$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$destinationPath = Join-Path (Get-Location) $Destination
$sourceBitmap = [System.Drawing.Bitmap]::new($sourcePath)
$outputBitmap = [System.Drawing.Bitmap]::new(
    $sourceBitmap.Width,
    $sourceBitmap.Height,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
)
$graphics = [System.Drawing.Graphics]::FromImage($outputBitmap)
$graphics.DrawImageUnscaled($sourceBitmap, 0, 0)
$graphics.Dispose()

function Test-OuterBackgroundPixel([System.Drawing.Color]$color) {
    $minimum = [Math]::Min($color.R, [Math]::Min($color.G, $color.B))
    $maximum = [Math]::Max($color.R, [Math]::Max($color.G, $color.B))
    return $minimum -ge 180 -and ($maximum - $minimum) -le 45
}

$width = $outputBitmap.Width
$height = $outputBitmap.Height
$visited = [System.Collections.BitArray]::new($width * $height)
$queue = [System.Collections.Generic.Queue[int]]::new()

function Add-BackgroundCandidate([int]$x, [int]$y) {
    $index = ($y * $width) + $x
    if ($visited[$index]) {
        return
    }
    $visited[$index] = $true
    if (Test-OuterBackgroundPixel $outputBitmap.GetPixel($x, $y)) {
        $queue.Enqueue($index)
    }
}

for ($x = 0; $x -lt $width; $x++) {
    Add-BackgroundCandidate $x 0
    Add-BackgroundCandidate $x ($height - 1)
}
for ($y = 1; $y -lt ($height - 1); $y++) {
    Add-BackgroundCandidate 0 $y
    Add-BackgroundCandidate ($width - 1) $y
}

while ($queue.Count -gt 0) {
    $index = $queue.Dequeue()
    $x = $index % $width
    $y = [Math]::Floor($index / $width)
    $outputBitmap.SetPixel($x, $y, [System.Drawing.Color]::Transparent)

    if ($x -gt 0) {
        Add-BackgroundCandidate ($x - 1) $y
    }
    if ($x + 1 -lt $width) {
        Add-BackgroundCandidate ($x + 1) $y
    }
    if ($y -gt 0) {
        Add-BackgroundCandidate $x ($y - 1)
    }
    if ($y + 1 -lt $height) {
        Add-BackgroundCandidate $x ($y + 1)
    }
}

$destinationDirectory = Split-Path -Parent $destinationPath
if (-not (Test-Path -LiteralPath $destinationDirectory)) {
    New-Item -ItemType Directory -Path $destinationDirectory | Out-Null
}
$outputBitmap.Save(
    $destinationPath,
    [System.Drawing.Imaging.ImageFormat]::Png
)
$outputBitmap.Dispose()
$sourceBitmap.Dispose()

Write-Output "Generated Android launcher source: $destinationPath"
