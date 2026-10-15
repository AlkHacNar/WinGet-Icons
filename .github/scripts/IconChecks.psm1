# Shared checks for the icon workflows: does a name exist in WinGet, and is a file a usable icon.
# An icon is named after a WinGet package ID (7zip.7zip.png) - or after a family of packages that share one icon
# (Microsoft.VCRedist.png for every Microsoft.VCRedist.*), as the App Update Script's icon rules use them.

$Script:GitHubHeaders = @{ 'User-Agent' = 'WinGet-Icons-check'; 'Accept' = 'application/vnd.github+json' }
$token = if($env:GITHUB_TOKEN){$env:GITHUB_TOKEN}elseif($env:GH_TOKEN){$env:GH_TOKEN}else{$null}
if($token){$Script:GitHubHeaders['Authorization'] = "Bearer $token"}
### Case-sensitive, like the paths themselves: 7zip/7Zip is not 7zip/7zip.
$Script:DirCache = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)

# The directories under a winget-pkgs manifest path, or $null when the path does not exist. Cached, so a run asks once per path.
function Get-WinGetManifestDirectories
{
    param([string]$Path)
    if($Script:DirCache.ContainsKey($Path)){return $Script:DirCache[$Path]}
    try
    {
        $items = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-pkgs/contents/$Path" -Headers $Script:GitHubHeaders -ErrorAction Stop
        $result = [pscustomobject]@{ Dirs = @($items | Where-Object type -eq 'dir' | ForEach-Object name); Files = @($items | Where-Object type -eq 'file' | ForEach-Object name) }
    }
    catch
    {
        if($_.Exception.Response.StatusCode.value__ -ne 404){throw}
        $result = $null
    }
    $Script:DirCache[$Path] = $result
    return $result
}

# Whether a name is a WinGet package ID or family, as winget-pkgs stores it: manifests/<first letter>/<ID with "." as "/">.
#   Kind 'package' - the folder holds versions (a version folder with <ID>.yaml or <ID>.installer.yaml)
#   Kind 'family'  - the folder only holds further packages (Microsoft.VCRedist -> .2015+.x64, ...)
#   Kind $null     - not in WinGet; Suggestion is the same name with WinGet's capitalisation when only the case was wrong.
# The comparison is case-sensitive like the icon downloads (raw.githubusercontent.com is): 7zip.7Zip is not 7zip.7zip.
function Get-WinGetIdStatus
{
    param([Parameter(Mandatory)][string]$Id)
    $Id = $Id.Trim()
    if($Id -notmatch '^[^.\s/\\]+(\.[^.\s/\\]+)+$'){return [pscustomobject]@{ Id = $Id; Kind = $null; Suggestion = $null }}
    $root = "manifests/$($Id.Substring(0, 1).ToLowerInvariant())"
    $path = "$root/$($Id.Replace('.', '/'))"
    $listing = Get-WinGetManifestDirectories -Path $path
    if($null -ne $listing)
    {
        $kind = 'family'
        foreach($dir in $listing.Dirs)
        {
            $inner = Get-WinGetManifestDirectories -Path "$path/$dir"
            if($null -ne $inner -and ($inner.Files -contains "$Id.yaml" -or $inner.Files -contains "$Id.installer.yaml")){$kind = 'package'; break}
            # Only the first folder: a package's version folders all look alike, a family's are packages.
            break
        }
        return [pscustomobject]@{ Id = $Id; Kind = $kind; Suggestion = $null }
    }
    # A family that continues after a hyphen: Avanquestpdfforge.PDFCreator covers Avanquestpdfforge.PDFCreator-Free and -Professional.
    $lastDot = $path.LastIndexOf('/')
    $parent = Get-WinGetManifestDirectories -Path $path.Substring(0, $lastDot)
    $leaf = $path.Substring($lastDot + 1)
    if($null -ne $parent -and @($parent.Dirs | Where-Object { $_.StartsWith("$leaf-", [StringComparison]::Ordinal) }).Count -gt 0)
    {
        return [pscustomobject]@{ Id = $Id; Kind = 'family'; Suggestion = $null }
    }
    # Not found - walk the path ignoring case, for a "did you mean".
    $current = $root
    $fixed = @()
    foreach($segment in $Id.Split('.'))
    {
        $listing = Get-WinGetManifestDirectories -Path $current
        $match = if($null -ne $listing){@($listing.Dirs | Where-Object { $_ -ieq $segment })[0]}
        if($null -eq $match){$fixed = $null; break}
        $fixed += $match
        $current = "$current/$match"
    }
    $suggestion = if($null -ne $fixed){$fixed -join '.'}else{$null}
    return [pscustomobject]@{ Id = $Id; Kind = $null; Suggestion = $suggestion }
}

# Format and size of an image from its first bytes - no System.Drawing, which the Linux runners do not have.
function Get-ImageInfo
{
    param([Parameter(Mandatory)][byte[]]$Bytes)
    if($Bytes.Length -ge 24 -and $Bytes[0] -eq 0x89 -and $Bytes[1] -eq 0x50 -and $Bytes[2] -eq 0x4E -and $Bytes[3] -eq 0x47)
    {
        $width = ([int]$Bytes[16] -shl 24) -bor ([int]$Bytes[17] -shl 16) -bor ([int]$Bytes[18] -shl 8) -bor $Bytes[19]
        $height = ([int]$Bytes[20] -shl 24) -bor ([int]$Bytes[21] -shl 16) -bor ([int]$Bytes[22] -shl 8) -bor $Bytes[23]
        return [pscustomobject]@{ Format = 'PNG'; Width = $width; Height = $height }
    }
    if($Bytes.Length -ge 4 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xD8)
    {
        $i = 2
        while($i + 9 -lt $Bytes.Length)
        {
            if($Bytes[$i] -ne 0xFF){$i++; continue}
            $marker = $Bytes[$i + 1]
            $length = ([int]$Bytes[$i + 2] -shl 8) -bor $Bytes[$i + 3]
            # SOF0..SOF15 except DHT (C4), JPG (C8) and DAC (CC) carry the size.
            if($marker -ge 0xC0 -and $marker -le 0xCF -and $marker -notin 0xC4, 0xC8, 0xCC)
            {
                return [pscustomobject]@{ Format = 'JPEG'; Width = (([int]$Bytes[$i + 7] -shl 8) -bor $Bytes[$i + 8]); Height = (([int]$Bytes[$i + 5] -shl 8) -bor $Bytes[$i + 6]) }
            }
            $i += 2 + $length
        }
        return [pscustomobject]@{ Format = 'JPEG'; Width = $null; Height = $null }
    }
    return [pscustomobject]@{ Format = $null; Width = $null; Height = $null }
}

# The problems of one icon image, as text lines - empty when it is fine. 512 x 512 is the most Intune and SCCM take
# (the App Update Script falls back to its default icon from 513 pixels on).
function Get-ImageProblems
{
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $info = Get-ImageInfo -Bytes $Bytes
    if($null -eq $info.Format){return @('is not a PNG or JPEG image')}
    $problems = @()
    if($null -eq $info.Width){$problems += "is a $($info.Format) whose size could not be read"}
    elseif($info.Width -ge 513 -or $info.Height -ge 513){$problems += "is $($info.Width) x $($info.Height) pixels - at most 512 x 512, larger ones are not used"}
    return $problems
}

# The problems of an icon's name: not in WinGet (with the right capitalisation, if that was all), or not .png/.jpg/.jpeg.
function Get-IconNameProblems
{
    param([Parameter(Mandatory)][string]$FileName)
    $extension = [IO.Path]::GetExtension($FileName).ToLowerInvariant()
    $problems = @()
    if($extension -notin '.png', '.jpg', '.jpeg'){$problems += "has the extension '$extension' - only .png, .jpg or .jpeg"}
    $id = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $status = Get-WinGetIdStatus -Id $id
    if($null -eq $status.Kind)
    {
        $problems += if($status.Suggestion){"is not a WinGet ID - did you mean '$($status.Suggestion)$extension'? (the case must match WinGet's)"}
                     else{"'$id' is not a WinGet package ID or family"}
    }
    return $problems
}

Export-ModuleMember -Function Get-WinGetIdStatus, Get-ImageInfo, Get-ImageProblems, Get-IconNameProblems
