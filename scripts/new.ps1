# Scaffolds framework files from the _Template modules and refreshes the sourcemap.
#
#   ./scripts/new.ps1 service ShopService
#   ./scripts/new.ps1 controller ShopController
#   ./scripts/new.ps1 event Shop
#   ./scripts/new.ps1 component Door
#   ./scripts/new.ps1 class Match
#
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("service", "controller", "event", "component", "class")]
    [string]$Kind,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[A-Z][A-Za-z0-9]*$")]
    [string]$Name
)

$root = Split-Path $PSScriptRoot -Parent

$targets = @{
    service    = @{
        Template    = "src\ServerStorage\ServerRuntime\Services\_ServiceTemplate.luau"
        Destination = "src\ServerStorage\ServerRuntime\Services\$Name.luau"
        Replace     = @{ "ServiceName" = $Name }
    }
    controller = @{
        Template    = "src\ReplicatedStorage\ClientRuntime\Controllers\_ControllerTemplate.luau"
        Destination = "src\ReplicatedStorage\ClientRuntime\Controllers\$Name.luau"
        Replace     = @{ "ControllerName" = $Name }
    }
    event      = @{
        Template    = "src\ReplicatedStorage\Core\Shared\Network\Events\_EventTemplate.luau"
        Destination = "src\ReplicatedStorage\Core\Shared\Network\Events\$Name.luau"
        Replace     = @{ '"Example"' = "`"$Name`"" }
    }
    component  = @{
        Template    = "src\ReplicatedStorage\Core\Classes\_ComponentTemplate.luau"
        Destination = "src\ReplicatedStorage\Core\Modules\$Name.luau"
        Replace     = @{ "MyComponent" = $Name; '"MyTag"' = "`"$Name`"" }
    }
    class      = @{
        Template    = "src\ReplicatedStorage\Core\Classes\_ClassTemplate.luau"
        Destination = "src\ReplicatedStorage\Core\Classes\$Name.luau"
        Replace     = @{ "ClassName" = $Name }
    }
}

$target = $targets[$Kind]
$templatePath = Join-Path $root $target.Template
$destinationPath = Join-Path $root $target.Destination

if (-not (Test-Path $templatePath)) {
    Write-Error "Template not found: $($target.Template)"
    exit 1
}
if (Test-Path $destinationPath) {
    Write-Error "Already exists: $($target.Destination)"
    exit 1
}

$content = Get-Content $templatePath -Raw
foreach ($pair in $target.Replace.GetEnumerator()) {
    $content = $content.Replace($pair.Key, $pair.Value)
}
# strip the selene allow markers and template-instruction comments from the copy
$content = ($content -split "`n" | Where-Object { $_ -notmatch "selene: allow" }) -join "`n"

# WriteAllText with explicit UTF8-no-BOM: Windows PowerShell's `-Encoding utf8` adds a BOM, which selene rejects
[System.IO.File]::WriteAllText($destinationPath, $content, (New-Object System.Text.UTF8Encoding $false))

Write-Host "Created $($target.Destination)"

# refresh the sourcemap so luau-lsp picks the new module up immediately
Push-Location $root
try {
    rojo sourcemap --output sourcemap.json | Out-Null
    Write-Host "Sourcemap refreshed"
}
finally {
    Pop-Location
}
