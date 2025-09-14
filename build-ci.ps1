Param(
    [string[]]$TargetFrameworks = @('net6.0','net8.0'),
    [string[]]$Rids = @('win-x86','win-x64')
)

Set-StrictMode -Version Latest
$project = Join-Path $PSScriptRoot 'Il2CppDumper\\Il2CppDumper.csproj'
$configuration = 'Release'
$outBase = Join-Path $PSScriptRoot 'Il2CppDumper\\bin\\Release'

function Publish-Target {
    param($tfm, $rid, $selfContained=$false, $trim=$false, $singleFile=$false)

    $ridArg = if ($rid) { "-r $rid" } else { '' }
    $selfArg = if ($selfContained) { ' --self-contained ' } else { ' --no-self-contained ' }
    $trimArg = if ($trim) { ' -p:PublishTrimmed=true ' } else { '' }
    $singleArg = if ($singleFile) { ' -p:PublishSingleFile=true ' } else { '' }

    $out = Join-Path $outBase "$tfm\publish\$rid"
    Write-Host "Publishing $tfm / $rid -> $out"
    $cmd = "dotnet publish `"$project`" -c $configuration -f $tfm $ridArg -o `"$out`" $selfArg $trimArg $singleArg --no-restore"
    Write-Host "Running: $cmd"
    $output = iex $cmd 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Publish command failed. Output:";
        $output | ForEach-Object { Write-Host $_ }
        throw "publish failed for $tfm / $rid"
    }
    return $out
}

function Safe-Copy {
    param($src, $dst)
    if (Test-Path $src) {
        New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
        Copy-Item $src -Destination $dst -Force
        Write-Host "Copied $src -> $dst"
    } else {
        Write-Host "Skipping missing file $src"
    }
}

# Single restore for the project (populates assets for all target frameworks)
Write-Host "Running dotnet restore for project"
dotnet restore $project
if ($LASTEXITCODE -ne 0) { throw 'dotnet restore failed' }

$artifacts = @()
$publishFailures = @()
foreach ($tfm in $TargetFrameworks) {
    foreach ($rid in $Rids) {
        try {
            $out = Publish-Target -tfm $tfm -rid $rid -selfContained:$false -singleFile:$true
            $artifacts += $out
        } catch {
            $err = "Publish failed for $($tfm)/$($rid): $($_)"
            Write-Host $err
            $publishFailures += $err
        }
    }
}

# Additional self-contained trimmed publishes for Windows x64 (optional)
try {
    $out = Publish-Target -tfm 'net6.0' -rid 'win-x64' -selfContained:$true -trim:$true -singleFile:$true
    $artifacts += $out
} catch {
    Write-Host "Optional self-contained publish failed: $($_)"
}

# If any mandatory publish failed, exit with non-zero to fail CI
if ($publishFailures.Count -gt 0) {
    Write-Host "One or more publishes failed. Failing the CI."
    $publishFailures | ForEach-Object { Write-Host $_ }
    exit 1
}

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

exit 0
