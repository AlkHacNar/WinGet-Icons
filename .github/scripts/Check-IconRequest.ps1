# Checks an icon request (issue form .github/ISSUE_TEMPLATE/icon-request.yml) when it is opened or edited:
# is the AppID in WinGet, is there already an icon for it, and is an attached image usable. Answers in one comment
# (updated on every edit, not added again) and with one result label.
# Run by .github/workflows/icon-request.yml; locally: -EventPath <issue event json> -DryRun prints instead of writing.
param([string]$EventPath = $env:GITHUB_EVENT_PATH, [string]$Repository = $env:GITHUB_REPOSITORY, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'IconChecks.psm1') -Force
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$issue = (Get-Content -LiteralPath $EventPath -Raw | ConvertFrom-Json).issue
$body = "$($issue.body)"

# An issue form's body is "### <label>" followed by the answer; an empty optional answer is "_No response_".
function Get-FormField([string]$Label)
{
    $m = [regex]::Match($body, "(?ms)^###\s*$([regex]::Escape($Label))\s*\r?\n(.*?)(?=^###\s|\z)")
    if(-not $m.Success){return ''}
    $value = $m.Groups[1].Value.Trim()
    if($value -eq '_No response_'){return ''}
    return $value
}

$appId = (Get-FormField 'AppID') -replace '[`''"]', ''
$appId = $appId.Trim()
$iconField = Get-FormField 'Icon'
# The form's checkbox, ticked: "- [X] This app is not in WinGet ...".
$nonWinGet = (Get-FormField 'Not in WinGet') -match '(?i)-\s*\[x\]'
$lines = @()
$result = $null
$folder = if($nonWinGet){'Non-WinGet'}else{'WinGet'}

function Test-ExistingIcon
{
    $existing = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot $folder) -File | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) -ceq $appId })
    if($existing.Count -eq 0){return $false}
    $script:lines += "- **Icon:** there already is one - [$folder/$($existing[0].Name)](https://github.com/$Repository/blob/main/$folder/$([uri]::EscapeDataString($existing[0].Name))). Attach a better one if it should be replaced."
    return $true
}

if([string]::IsNullOrWhiteSpace($appId))
{
    $lines += '- **AppID:** missing - please edit the issue and fill it in.'
    $result = 'not in WinGet'
}
elseif($nonWinGet)
{
    # Per request, an app outside WinGet goes to Non-WinGet/, named Vendor.Name like the WinGet IDs (MTG.SmartBridge).
    $status = Get-WinGetIdStatus -Id $appId
    if($null -ne $status.Kind)
    {
        $lines += "- **AppID:** ``$appId`` *is* in WinGet (a $($status.Kind)) - its icon belongs in ``WinGet/``. Please untick **Not in WinGet**."
        $result = 'name pattern'
    }
    elseif($appId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9+_-]*(\.[A-Za-z0-9][A-Za-z0-9+_-]*)+$')
    {
        $lines += "- **AppID:** ``$appId`` does not follow the name pattern **Vendor.Name** - letters, digits, ``+ _ -``, the parts separated by dots, no spaces, e.g. ``MTG.SmartBridge``. Please edit the issue and write the AppID that way."
        $result = 'name pattern'
    }
    else
    {
        $lines += "- **AppID:** ``$appId`` is not in WinGet and follows the name pattern **Vendor.Name** - its icon goes to ``Non-WinGet/``."
        $result = if(Test-ExistingIcon){'already exists'}else{'valid'}
    }
}
else
{
    $status = Get-WinGetIdStatus -Id $appId
    if($null -eq $status.Kind)
    {
        $lines += if($status.Suggestion){"- **AppID:** ``$appId`` is not in WinGet - did you mean ``$($status.Suggestion)``? The case has to match WinGet's."}
                  else{"- **AppID:** ``$appId`` is not a WinGet package ID or family. ``winget search <name>`` shows the ID."}
        # Per request: asked whether the icon should go to Non-WinGet/ instead - and, if so, to write the name as Vendor.Name.
        $lines += "- **Not in WinGet?** Should the icon go to [Non-WinGet/](https://github.com/$Repository/tree/main/Non-WinGet) instead? Then edit this issue, tick **This app is not in WinGet**, and write the AppID as **Vendor.Name** (e.g. ``MTG.SmartBridge``) - the check runs again on the edit."
        $result = 'not in WinGet'
    }
    else
    {
        $lines += "- **AppID:** ``$appId`` is a WinGet $($status.Kind) - fine."
        $result = if(Test-ExistingIcon){'already exists'}else{'valid'}
    }
}

# An attached image: the first image link in the Icon answer (drag & drop gives ![name](https://github.com/user-attachments/assets/...)).
$imageUrl = [regex]::Match($iconField, '(?i)(https://(github\.com/user-attachments/assets/[0-9a-f-]+|[^\s)"]+\.(png|jpe?g)))').Value
if($imageUrl)
{
    try
    {
        $headers = @{ 'User-Agent' = 'WinGet-Icons-check' }
        if($env:GITHUB_TOKEN){$headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)"}
        $bytes = (Invoke-WebRequest -Uri $imageUrl -Headers $headers -UseBasicParsing -MaximumRedirection 5).Content
        if($bytes -is [string]){$bytes = [Text.Encoding]::Latin1.GetBytes($bytes)}
        $info = Get-ImageInfo -Bytes $bytes
        $problems = @(Get-ImageProblems -Bytes $bytes)
        if($problems.Count -eq 0){$lines += "- **Attached image:** $($info.Format), $($info.Width) x $($info.Height) - usable."}
        else
        {
            $lines += "- **Attached image:** $($problems -join '; ')."
            if($result -eq 'valid'){$result = 'image problem'}
        }
    }
    catch
    {
        $lines += "- **Attached image:** could not be downloaded ($($_.Exception.Message))."
    }
}
elseif($result -eq 'valid')
{
    $lines += '- **Icon:** none attached yet - this is a request for one.'
}

$verdict = switch($result)
{
    'valid'          { 'Looks good.' }
    'already exists' { 'There already is an icon for this AppID.' }
    'image problem'  { 'The AppID is fine, but the attached image cannot be used as it is.' }
    'name pattern'   { 'Please check the AppID and its name pattern.' }
    default          { 'Please check the AppID - or whether the app belongs in Non-WinGet/.' }
}
$marker = '<!-- icon-request-check -->'
$comment = "$marker`n**Icon request check** - $verdict`n`n$($lines -join "`n")`n`n<sub>Checked automatically on every edit of this issue.</sub>"
$resultLabels = @('valid', 'not in WinGet', 'already exists', 'image problem', 'name pattern')

if($DryRun)
{
    "label: $result$(if($nonWinGet){' + non-winget'})"
    $comment
    return
}

# The labels exist before they are set (gh label create --force only updates an existing one).
$colors = @{ 'icon-request' = '1d76db'; 'valid' = '0e8a16'; 'not in WinGet' = 'b60205'; 'already exists' = 'fbca04'; 'image problem' = 'd93f0b'; 'name pattern' = 'd93f0b'; 'non-winget' = '5319e7' }
foreach($label in $colors.Keys){ & gh label create $label --color $colors[$label] --force -R $Repository | Out-Null }

$number = $issue.number
$previous = & gh api "repos/$Repository/issues/$number/comments" --paginate --jq ".[] | select(.body | contains(`"$marker`")) | .id" | Select-Object -First 1
if($previous){ & gh api -X PATCH "repos/$Repository/issues/comments/$previous" -f "body=$comment" | Out-Null }
else{ & gh issue comment $number -R $Repository --body $comment | Out-Null }

$stale = @($resultLabels | Where-Object { $_ -ne $result -and ($issue.labels.name -contains $_) })
foreach($label in $stale){ & gh issue edit $number -R $Repository --remove-label $label | Out-Null }
& gh issue edit $number -R $Repository --add-label $result --add-label 'icon-request' | Out-Null
# "non-winget" follows the checkbox, so a request moved to Non-WinGet/ can be told apart in the issue list.
if($nonWinGet){ & gh issue edit $number -R $Repository --add-label 'non-winget' | Out-Null }
elseif($issue.labels.name -contains 'non-winget'){ & gh issue edit $number -R $Repository --remove-label 'non-winget' | Out-Null }
"Issue #$number checked: $result"
