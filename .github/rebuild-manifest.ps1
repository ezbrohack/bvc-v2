param(
	[string]$Repo
)

$ErrorActionPreference = 'Stop'
if (-not $Repo) { $Repo = $PSScriptRoot | Split-Path -Parent }
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$utf8 = [System.Text.UTF8Encoding]::new($false)
$sha256 = [System.Security.Cryptography.SHA256]::Create()

$initPath = Join-Path $Repo 'init.lua'
if (-not (Test-Path -LiteralPath $initPath)) {
	throw "init.lua not found in $Repo"
}

$init = [System.IO.File]::ReadAllText($initPath)

$paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$tables = @('publicGamePaths', 'publicLibraryPaths', 'seedProfilePaths', 'commonInstallPaths')
foreach ($table in $tables) {
	$match = [regex]::Match($init, "local $table = \{(.*?)\n\}", [System.Text.RegularExpressions.RegexOptions]::Singleline)
	if (-not $match.Success) {
		throw "could not parse table: $table"
	}
	foreach ($pm in [regex]::Matches($match.Groups[1].Value, "\['([^']+)'\] = true")) {
		[void]$paths.Add($pm.Groups[1].Value)
	}
}

$fixed = @('init.lua', 'bootstrap.lua', 'loader.lua', 'main.lua', 'os.luau', 'reinstall.luau', 'guis/new.lua', 'guis/old.lua', 'profiles/features.json', 'profiles/packages.json')
foreach ($p in $fixed) {
	[void]$paths.Add($p)
}

$sorted = @($paths) | Sort-Object

$entries = @()
$revisionInput = [System.Text.StringBuilder]::new()
foreach ($p in $sorted) {
	$full = Join-Path $Repo ($p -replace '/', '\')
	if (-not (Test-Path -LiteralPath $full)) {
		throw "public path declared but file missing: $p"
	}
	$bytes = [System.IO.File]::ReadAllBytes($full)
	$ext = [System.IO.Path]::GetExtension($p).TrimStart('.').ToLower()
	if ($ext -in @('json', 'lua', 'luau', 'txt')) {
		$text = $latin1.GetString($bytes).Replace("`r`n", "`n")
		$canonical = $latin1.GetBytes($text)
		$len = $canonical.Length
	} else {
		$canonical = $bytes
		$len = $bytes.Length
	}
	$sha = -join ($sha256.ComputeHash($canonical) | ForEach-Object { $_.ToString('x2') })
	[void]$revisionInput.Append($p).Append(':').Append($sha).Append('|')
	$entries += [PSCustomObject]@{ Path = $p; Bytes = $len; Sha = $sha }
}

$revision = 'sha256-' + (-join ($sha256.ComputeHash($latin1.GetBytes($revisionInput.ToString())) | ForEach-Object { $_.ToString('x2') }))

$sb = [System.Text.StringBuilder]::new()
[void]$sb.Append("{" + [char]10)
[void]$sb.Append('  "schemaVersion": 1,' + [char]10)
[void]$sb.Append('  "revision": "' + $revision + '",' + [char]10)
[void]$sb.Append('  "files": [' + [char]10)
for ($i = 0; $i -lt $entries.Count; $i++) {
	$e = $entries[$i]
	$comma = if ($i -lt $entries.Count - 1) { ',' } else { '' }
	[void]$sb.Append('    {' + [char]10)
	[void]$sb.Append('      "path": "' + $e.Path + '",' + [char]10)
	[void]$sb.Append('      "bytes": ' + $e.Bytes + ',' + [char]10)
	[void]$sb.Append('      "sha256": "' + $e.Sha + '"' + [char]10)
	[void]$sb.Append('    }' + $comma + [char]10)
}
[void]$sb.Append('  ]' + [char]10)
[void]$sb.Append('}')

$out = Join-Path $Repo 'public-manifest.json'
$before = if (Test-Path -LiteralPath $out) { [System.IO.File]::ReadAllBytes($out) } else { $null }
[System.IO.File]::WriteAllText($out, $sb.ToString(), $utf8)
$after = [System.IO.File]::ReadAllBytes($out)

$changed = $true
if ($before -and $before.Length -eq $after.Length) {
	$changed = $false
	for ($i = 0; $i -lt $after.Length; $i++) {
		if ($before[$i] -ne $after[$i]) { $changed = $true; break }
	}
}

Write-Output "revision: $revision"
Write-Output "entries : $($entries.Count)"
Write-Output "changed : $changed"
exit 0
