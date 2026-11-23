param(
    [string] $Dotnet = 'dotnet',
    [string] $Screenshot
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Drawing
Add-Type @'
using System.Runtime.InteropServices;
public static class AcasSmokeMouse {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint x, uint y, uint data, System.UIntPtr extra);
}
'@

$ae = [System.Windows.Automation.AutomationElement]
$scope = [System.Windows.Automation.TreeScope]::Descendants
$windows = Split-Path (Split-Path $PSScriptRoot)
$run = Join-Path $HOME "acas-menu-smoke-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $run | Out-Null
$process = $null

function Find-Element($parent, $property, $value) {
    $condition = [System.Windows.Automation.PropertyCondition]::new($property, $value)
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        $element = $parent.FindFirst($scope, $condition)
        if ($element) { return $element }
        if ($process.HasExited) { throw "Application exited: $($process.ExitCode)" }
        Start-Sleep -Milliseconds 100
    }
    throw "UI element not found: $value"
}

function Find-Id($id) {
    Find-Element $window $ae::AutomationIdProperty $id
}

function Select-Item($id) {
    (Find-Id $id).GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
}

function Click-Button($id) {
    (Find-Id $id).GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}

function Open-Form {
    Find-Id 'ScreenMenu' | Out-Null
    Select-Item 'SmokeOpenForm'
    Click-Button 'ScreenMenuOpen'
    Find-Id 'SmokeInput'
}

try {
    $app = Join-Path $windows 'Acas.App/Acas.App.csproj'
    $targets = Join-Path $PSScriptRoot 'MenuFixture.targets'
    $artifacts = Join-Path $run 'artifacts'
    $log = Join-Path $run 'build.log'
    & $Dotnet build $app -c Release --artifacts-path $artifacts "-p:CustomAfterMicrosoftCommonTargets=$targets" *> $log
    if ($LASTEXITCODE) {
        Get-Content $log -Tail 35
        throw 'Smoke application build failed.'
    }
    $exe = Join-Path $artifacts 'bin/Acas.App/release/Acas.App.exe'
    $database = Join-Path $run 'smoke.db'
    $process = Start-Process $exe -ArgumentList '--database', ('"{0}"' -f $database) -PassThru
    $process.WaitForInputIdle(10000) | Out-Null
    $window = Find-Element $ae::RootElement $ae::ProcessIdProperty $process.Id

    Select-Item 'SmokeNavigation'
    $input = Open-Form
    Find-Id 'ScreenMenuBack' | Out-Null
    if ($Screenshot) {
        $rect = $window.Current.BoundingRectangle
        $bitmap = New-Object Drawing.Bitmap ([int]$rect.Width), ([int]$rect.Height)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CopyFromScreen([int]$rect.X, [int]$rect.Y, 0, 0, $bitmap.Size)
            $bitmap.Save($Screenshot, [Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    }
    Click-Button 'ScreenMenuBack'
    $input = Open-Form
    $input.SetFocus()
    if ($ae::FocusedElement.Current.AutomationId -ne 'SmokeInput') { throw 'Expected focus in business form.' }

    $item = Find-Id 'SmokeNavigation'
    $selection = $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    if (!$selection.Current.IsSelected) { throw 'Expected navigation item to remain selected.' }
    $point = $item.GetClickablePoint()
    [AcasSmokeMouse]::SetCursorPos([int]$point.X, [int]$point.Y) | Out-Null
    [AcasSmokeMouse]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
    [AcasSmokeMouse]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
    Find-Id 'ScreenMenu' | Out-Null
    if ($ae::FocusedElement.Current.AutomationId -ne 'SmokeNavigation') { throw 'Focus did not return to navigation.' }
    'UIA PASS: business menu -> form -> header back -> form -> same tree item -> menu and tree focus restored'
} finally {
    if ($process -and !$process.HasExited) {
        $process.CloseMainWindow() | Out-Null
        if (!$process.WaitForExit(3000)) { $process.Kill(); $process.WaitForExit() }
    }
    Remove-Item -LiteralPath $run -Recurse -Force
}
