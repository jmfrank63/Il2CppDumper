Param(
    [string[]]$TargetFrameworks = @('net6.0','net8.0'),
    [string[]]$Rids = @('win-x86','win-x64')
)

Set-StrictMode -Version Latest
$project = Join-Path $PSScriptRoot 'Il2CppDumper\Il2CppDumper.csproj'
$configuration = 'Release'
$outBase = Join-Path $PSScriptRoot 'Il2CppDumper\bin\Release'

function Publish-Target {
    param($tfm, $rid, $selfContained=$false, $trim=false, $singleFile=$false)

    $ridArg = if ($rid) { "-r $rid" } else { '' }
    $selfArg = if ($selfContained) { ' --self-contained ' } else { ' --no-self-contained ' }
    $trimArg = if ($trim) { ' -p:PublishTrimmed=true ' } else { '' }
    $singleArg = if ($singleFile) { ' -p:PublishSingleFile=true ' } else { '' }

    $out = Join-Path $outBase "$tfm\publish\$rid"
    Write-Host "Publishing $tfm / $rid -> $out"
    dotnet publish $project -c $configuration -f $tfm $ridArg -o $out $selfArg $trimArg $singleArg
    if ($LASTEXITCODE -ne 0) { throw "publish failed for $tfm / $rid" }
    return $out
}

function Safe-Copy {
    param($src, $dst)
    if (Test-Path $src) {
        New-Item -ItemType Directory -Force -Path (Split-Path $dst)
        Copy-Item $src -Destination $dst -Force
        Write-Host "Copied $src -> $dst"
    } else {
        Write-Host "Skipping missing file $src"
    }
}

# Ensure restore
& dotnet restore $project
if ($LASTEXITCODE -ne 0) { throw 'dotnet restore failed' }

$artifacts = @()
foreach ($tfm in $TargetFrameworks) {
    foreach ($rid in $Rids) {
        try {
            $out = Publish-Target -tfm $tfm -rid $rid -selfContained:$false -singleFile:$true
            $artifacts += $out
        } catch {
            Write-Host "Publish failed for $tfm/$rid: $_"
        }
    }
}

# Additional self-contained trimmed publishes for Windows x64/x86 (optional)
try {
    $out = Publish-Target -tfm 'net6.0' -rid 'win-x64' -selfContained:$true -trim:$true -singleFile:$true
    $artifacts += $out
} catch { Write-Host "Optional self-contained publish failed: $_" }

# Copy or prepare artifact outputs
$finalDir = Join-Path $outBase 'published'
New-Item -ItemType Directory -Force -Path $finalDir | Out-Null
foreach ($a in $artifacts | Sort-Object -Unique) {
    if (Test-Path $a) {
        Get-ChildItem -Path $a -Filter 'Il2CppDumper*.exe' -File -Recurse | ForEach-Object {
            Safe-Copy $_.FullName (Join-Path $finalDir $_.Name)
        }
    }
}

Write-Host "Published artifacts to $finalDir"
Write-Host "##[set-output name=artifact-path]$finalDir"

# Keep exit code 0 to allow CI to collect artifacts even if some publishes failed
exit 0
