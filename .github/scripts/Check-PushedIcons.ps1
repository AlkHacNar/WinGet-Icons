# Checks the icons in WinGet/ and Non-WinGet/ that a push or pull request adds or changes - or all of them (-All, the manual run).
# WinGet/: the name must be a WinGet package ID or family with WinGet's capitalisation. Non-WinGet/: per request the name pattern
# Vendor.Name, and not an app WinGet has. Both: a PNG or JPEG of at most 512 x 512.
# A push to main with problems opens an issue naming each file; a pull request with problems fails, so it shows red.
# Run by .github/workflows/icon-check.yml; locally: -All -DryRun prints instead of writing.
param([switch]$All, [string]$Before = $env:BEFORE, [string]$After = $env:AFTER, [string]$EventName = $env:EVENT_NAME, [string]$Repository = $env:GITHUB_REPOSITORY, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'IconChecks.psm1') -Force
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location -LiteralPath $repoRoot

# Default.png is the fallback icon itself, not an app's.
$files = if($All -or [string]::IsNullOrWhiteSpace($Before) -or $Before -match '^0+$')
{
    @(foreach($folder in 'WinGet', 'Non-WinGet'){ Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue | ForEach-Object { "$folder/$($_.Name)" } })
}
else
{
    @(& git diff --name-only --diff-filter=AMR $Before $After -- 'WinGet/' 'Non-WinGet/' | Where-Object { $_ })
}
$files = @($files | Where-Object { (Split-Path $_ -Leaf) -ne 'Default.png' } | Sort-Object)

$report = foreach($file in $files)
{
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){continue}
    $leaf = Split-Path $file -Leaf
    $nameProblems = if($file -like 'Non-WinGet/*')
    {
        $id = [IO.Path]::GetFileNameWithoutExtension($leaf)
        if([IO.Path]::GetExtension($leaf).ToLowerInvariant() -notin '.png', '.jpg', '.jpeg'){"has the extension '$([IO.Path]::GetExtension($leaf))' - only .png, .jpg or .jpeg"}
        if($id -cnotmatch '^[A-Za-z0-9][A-Za-z0-9+_-]*(\.[A-Za-z0-9][A-Za-z0-9+_-]*)+$'){"'$id' does not follow the name pattern Vendor.Name (e.g. MTG.SmartBridge)"}
        elseif($null -ne (Get-WinGetIdStatus -Id $id).Kind){"'$id' is in WinGet - its icon belongs in WinGet/"}
    }
    else{Get-IconNameProblems -FileName $leaf}
    $problems = @($nameProblems) + @(Get-ImageProblems -Bytes ([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $file).Path)))
    if($problems.Count -gt 0){"- ``$file`` $($problems -join '; ')"}
}
$report = @($report)
$scope = if($All){"all $($files.Count) icons in WinGet/ and Non-WinGet/"}else{"$($files.Count) added or changed icon(s)"}
$summary = if($report.Count -eq 0){"**Icon check** - $scope checked, no problems."}
           else{"**Icon check** - $scope checked, $($report.Count) with problems:`n`n$($report -join "`n")`n`nAn icon is named after the app's WinGet package ID (or a family like ``Microsoft.VCRedist``), with WinGet's capitalisation - ``winget search <name>`` shows it. Apps that are not in WinGet belong in ``Non-WinGet/``, named ``Vendor.Name``."}

if($env:GITHUB_STEP_SUMMARY){Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summary}
if($DryRun){$summary; return}
if($report.Count -eq 0){$summary; return}

if($EventName -eq 'pull_request')
{
    $summary
    Write-Error "$($report.Count) icon(s) with problems - see the summary."
    exit 1
}

& gh label create 'icon-check' --color 'b60205' --description 'Problems found in icons in WinGet/' --force -R $Repository | Out-Null
$title = if($All){"Icon check: $($report.Count) icon(s) with problems"}else{"Icon check: $($report.Count) problem(s) in $($After.Substring(0, 7))"}
$where = if($All){'A manual check of every icon found these.'}else{"Commit [$($After.Substring(0, 7))](https://github.com/$Repository/commit/$After) added or changed these."}
& gh issue create -R $Repository --title $title --label 'icon-check' --body "$where`n`n$summary" | Out-Null
"Issue opened: $title"
