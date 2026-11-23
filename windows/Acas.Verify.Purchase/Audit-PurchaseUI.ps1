param(
    [Parameter(Mandatory)][string]$Application,
    [Parameter(Mandatory)][string]$Fixture,
    [Parameter(Mandatory)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Acas {
    public static class PurchaseAuditWindow {
        private delegate bool WindowCallback(IntPtr window, IntPtr state);
        [DllImport("user32.dll")] private static extern bool EnumWindows(WindowCallback callback, IntPtr state);
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr window, uint command);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
        [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
        [DllImport("user32.dll")] private static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extraInfo);
        public static IntPtr FindDialog(IntPtr owner) {
            IntPtr result = IntPtr.Zero;
            EnumWindows((window, state) => {
                if (GetWindow(window, 4) != owner || !IsWindowVisible(window)) return true;
                result = window;
                return false;
            }, IntPtr.Zero);
            return result;
        }
        public static void Click(int x, int y) {
            if (!SetCursorPos(x, y)) throw new InvalidOperationException("Could not move the mouse.");
            mouse_event(2, 0, 0, 0, UIntPtr.Zero);
            mouse_event(4, 0, 0, 0, UIntPtr.Zero);
        }
    }
}
'@
[System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$database = Join-Path $OutputDirectory ('purchase-' + [guid]::NewGuid() + '.db')
$businessValuesJson = @'
import json, sqlite3, sys
with open(sys.argv[1], encoding="utf-8-sig") as source:
    fixture = json.load(source)
with sqlite3.connect(sys.argv[2]) as db:
    db.executescript("CREATE TABLE files(name TEXT PRIMARY KEY); CREATE TABLE rec(file TEXT NOT NULL, key TEXT NOT NULL, data BLOB NOT NULL, PRIMARY KEY(file,key)) WITHOUT ROWID;")
    db.executemany("INSERT INTO files VALUES (?)", [(name,) for name in fixture["files"]])
    for name, rows in fixture["records"].items():
        db.executemany("INSERT INTO rec VALUES (?, ?, ?)", [(name, key, bytes.fromhex(data)) for key, data in rows.items()])

def text(record, start, length):
    return bytes.fromhex(record)[start:start + length].decode("latin-1").strip()

records = fixture["records"]
issuer = text(records["ledgers/acas/system.dat"]["00000001"], 31, 32)
suppliers = records.get("ledgers/acas/purchled.dat", {})
print(json.dumps([issuer, *suppliers, *(text(row, 9, 30) for row in suppliers.values())]))
'@ | python - $Fixture $database
if ($LASTEXITCODE -ne 0) { throw 'Could not create the isolated audit database.' }
$businessValues = foreach ($value in (ConvertFrom-Json -InputObject $businessValuesJson)) {
    if ($value) { [string]$value }
}
$businessValues = $businessValues | Sort-Object Length -Descending

$scope = [Windows.Automation.TreeScope]::Descendants
$root = [Windows.Automation.AutomationElement]::RootElement
$control = [Windows.Automation.Automation]::ControlViewCondition
$idProperty = [Windows.Automation.AutomationElement]::AutomationIdProperty
$violations = [Collections.Generic.List[object]]::new()
$visited = [Collections.Generic.List[object]]::new()
$process = Start-Process -FilePath (Resolve-Path $Application) -ArgumentList "--database `"$database`"" -PassThru

function Find-Id($parent, [string]$id) {
    $parent.FindFirst($scope, [Windows.Automation.PropertyCondition]::new($idProperty, $id))
}

function Wait-Id($parent, [string]$id) {
    $until = [DateTime]::UtcNow.AddSeconds(8)
    do {
        $element = Find-Id $parent $id
        if ($element) { return $element }
        Start-Sleep -Milliseconds 75
    } while ([DateTime]::UtcNow -lt $until)
    throw "UI Automation element not found: $id"
}

function Invoke-Button($parent, [string]$id) {
    $element = Wait-Id $parent $id
    $element.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
}

function Select-Route($window, [string]$id) {
    $item = Wait-Id $window $id
    $pattern = $item.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)
    if ($pattern.Current.IsSelected) {
        (Wait-Id $window 'PurchaseNavigation').GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
    }
    $pattern.Select()
}

function Click-Element($element) {
    $scroll = $null
    if ($element.Current.IsOffscreen -and $element.TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern, [ref]$scroll)) {
        $scroll.ScrollIntoView()
    }
    $point = $element.GetClickablePoint()
    [Acas.PurchaseAuditWindow]::Click([int]$point.X, [int]$point.Y)
}

function Find-Confirmation([IntPtr]$owner) {
    $handle = [Acas.PurchaseAuditWindow]::FindDialog($owner)
    if ($handle -ne [IntPtr]::Zero) {
        $dialog = [Windows.Automation.AutomationElement]::FromHandle($handle)
        if ($dialog.Current.AutomationId -eq 'Confirmation') { return $dialog }
    }
}

function Wait-Confirmation([IntPtr]$owner) {
    $until = [DateTime]::UtcNow.AddSeconds(8)
    do {
        $dialog = Find-Confirmation $owner
        if ($dialog) { return $dialog }
        Start-Sleep -Milliseconds 75
    } while ([DateTime]::UtcNow -lt $until)
    throw 'The purchasing confirmation window did not open.'
}

function Cancel-Confirmation($dialog, [IntPtr]$owner) {
    Click-Element (Wait-Id $dialog 'ConfirmationCancel')
    $until = [DateTime]::UtcNow.AddSeconds(8)
    while ([Acas.PurchaseAuditWindow]::FindDialog($owner) -ne [IntPtr]::Zero) {
        if ([DateTime]::UtcNow -ge $until) { throw 'The purchasing confirmation window did not close.' }
        Start-Sleep -Milliseconds 75
    }
}

function Inspect-View([string]$route, $container, [string]$title) {
    $visible = @($container.FindAll($scope, $control) | Where-Object { -not $_.Current.IsOffscreen })
    $visited.Add([pscustomobject]@{ Route = $route; Title = $title; Elements = $visible.Count })
    foreach ($element in $visible) {
        $current = $element.Current
        $type = $current.ControlType.ProgrammaticName -replace '^ControlType\.', ''
        if (-not $current.AutomationId) {
            $violations.Add([pscustomobject]@{ Route = $route; Issue = 'MissingId'; Type = $type; Name = $current.Name })
        }
        if ($current.AutomationId -eq 'ReportDocumentContent') {
            $document = $element.GetCurrentPattern([Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(-1)
            foreach ($value in $businessValues) { $document = $document.Replace($value, '') }
            if ($document -cmatch '[A-Za-z]') {
                $tokens = [regex]::Matches($document, '[A-Za-z]+').Value | Select-Object -Unique
                $violations.Add([pscustomobject]@{ Route = $route; Issue = 'LatinText'; Type = $type; Name = $tokens -join ', ' })
            }
        }
        # UIA DataItem/Custom/Table cell names and editable contents can carry business data.
        if ($type -in @('Button', 'Text', 'HeaderItem', 'TreeItem', 'MenuItem', 'Window') -and
            $current.Name -cmatch '[A-Za-z]' -and $current.AutomationId -notmatch '^(ReportDocument|PurchaseSupplierSelectedCode)$') {
            $walker = [Windows.Automation.TreeWalker]::ControlViewWalker
            $ancestor = $walker.GetParent($element)
            $dataValue = $false
            while ($ancestor -and -not [Windows.Automation.Automation]::Compare($ancestor, $container)) {
                if ($ancestor.Current.ControlType -eq [Windows.Automation.ControlType]::DataItem) {
                    $dataValue = $true
                    break
                }
                $ancestor = $walker.GetParent($ancestor)
            }
            if (-not $dataValue) {
                $violations.Add([pscustomobject]@{ Route = $route; Issue = 'LatinText'; Type = $type; Name = $current.Name })
            }
        }
    }
}

function Save-Window($window, [string]$name) {
    $bounds = $window.Current.BoundingRectangle
    $bitmap = [Drawing.Bitmap]::new([int]$bounds.Width, [int]$bounds.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen([int]$bounds.Left, [int]$bounds.Top, 0, 0, $bitmap.Size)
        $bitmap.Save((Join-Path $OutputDirectory "$name.png"), [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Test-InvoiceDraftNavigation($window, [string]$route) {
    $item = Wait-Id $window $route
    $item.GetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView()
    $caption = Wait-Id $window ($route + 'Caption')
    (Wait-Id $window 'PurchaseInvoiceSupplier').GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('SUPP018')
    (Wait-Id $window 'PurchaseInvoiceOrder').GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).SetValue('DRAFT')
    Invoke-Button $window 'FormSubmit'
    (Wait-Id $window 'PurchaseInvoiceAddLine').GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Invoke-Button $window 'ScreenMenuOpen'
    $net = (Wait-Id $window 'PurchaseLineNet').GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern)
    $net.SetValue('123.45')

    $label = $caption.Current.BoundingRectangle
    if ($label.IsEmpty -or $label.Height -lt 2) { throw 'The invoice navigation caption is not visible.' }
    $selection = $item.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)
    if (!$selection.Current.IsSelected) { throw 'The invoice navigation item is not selected.' }
    $right = (Wait-Id $window 'Navigation').Current.BoundingRectangle.Right
    $y = [int]($label.Top + $label.Height / 2)
    $walker = [Windows.Automation.TreeWalker]::RawViewWalker
    $point = $null
    for ($x = [int][Math]::Floor($label.Right) + 1; $x -lt $right; $x++) {
        $candidate = [Windows.Point]::new($x, $y)
        $hit = [Windows.Automation.AutomationElement]::FromPoint($candidate)
        for ($element = $hit; $element; $element = $walker.GetParent($element)) {
            if ([Windows.Automation.Automation]::Compare($element, $item)) {
                $point = $candidate
                break
            }
        }
        if ($point) { break }
    }
    if (!$point) { throw 'No whitespace to the right of the invoice caption hit the selected navigation item.' }
    [Acas.PurchaseAuditWindow]::Click([int]$point.X, [int]$point.Y)
    Start-Sleep -Milliseconds 200
    $remaining = Find-Id $window 'PurchaseLineNet'
    if (!$remaining -or $remaining.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value -ne '123.45') {
        throw 'Navigation whitespace discarded the unsaved invoice line.'
    }
    Save-Window $window 'purchase-invoice-draft'

    Click-Element $caption
    $order = (Wait-Id $window 'PurchaseInvoiceOrder').GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern)
    if ($order.Current.Value -ne '') { throw 'Clicking the selected navigation caption did not reopen invoice entry.' }
    Write-Output 'UIA PASS: navigation whitespace preserves the unsaved invoice line; clicking the caption reopens invoice entry'
}

try {
    $window = Wait-Id $root 'AcasWindow'
    if ($window.Current.ProcessId -ne $process.Id) { throw 'Close any other instance of ACAS before the audit.' }
    $owner = [IntPtr]$window.Current.NativeWindowHandle
    Select-Route $window 'PurchaseNavigation'
    Inspect-View 'PurchaseNavigation/ProcessingDate' $window (Wait-Id $window 'ScreenTitle').Current.Name
    Invoke-Button $window 'FormSubmit'
    $null = Wait-Id $window 'ScreenMenu'
    Inspect-View 'PurchaseNavigation/MainMenu' $window (Wait-Id $window 'ScreenTitle').Current.Name
    Save-Window $window 'purchase-menu'

    $navigation = Wait-Id $window 'PurchaseNavigation'
    $routes = @($navigation.FindAll($scope, $control) | ForEach-Object { $_.Current.AutomationId } |
        Where-Object { $_ -match '^PurchaseMenu.+Navigation$' -and $_ -ne 'PurchaseMenuXNavigation' })
    if ($routes.Count -ne 48) { throw "Unexpected purchasing navigation route count: $($routes.Count)" }
    foreach ($route in $routes) {
        if ($route -in @('PurchaseMenuM3Navigation', 'PurchaseMenuM4Navigation')) {
            $item = Wait-Id $window $route
            $item.GetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView()
            Click-Element (Wait-Id $window ($route + 'Caption'))
            $confirmation = Wait-Confirmation $owner
            Inspect-View "$route/Confirmation" $confirmation $confirmation.Current.Name
            Cancel-Confirmation $confirmation $owner
        } else {
            Select-Route $window $route
            Inspect-View $route $window (Wait-Id $window 'ScreenTitle').Current.Name
            if ($route -eq 'PurchaseMenuDNavigation') { Test-InvoiceDraftNavigation $window $route }
            if ($route -eq 'PurchaseMenuANavigation') { Invoke-Button $window 'FormSubmit' }
            if ($route -eq 'PurchaseMenuRNavigation') {
                Invoke-Button $window 'FormSubmit'
                $null = Wait-Id $window 'ReportDocument'
                Inspect-View "$route/Report" $window (Wait-Id $window 'ScreenTitle').Current.Name
                Save-Window $window 'purchase-report'
            }
            if ($route -in @('PurchaseMenuHNavigation', 'PurchaseMenuS5Navigation', 'PurchaseMenuTNavigation')) {
                Click-Element (Wait-Id $window 'FormSubmit')
                $confirmation = Wait-Confirmation $owner
                Inspect-View "$route/Confirmation" $confirmation $confirmation.Current.Name
                if ($route -eq 'PurchaseMenuTNavigation') { Save-Window $confirmation 'purchase-closing-confirmation' }
                Cancel-Confirmation $confirmation $owner
            }
        }
    }
    Select-Route $window 'PurchaseMenuXNavigation'
    Inspect-View 'PurchaseMenuXNavigation' $window (Wait-Id $window 'ScreenTitle').Current.Name
} finally {
    $result = [pscustomobject]@{ Visited = @($visited.ToArray()); Violations = @($violations.ToArray()) }
    $result | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputDirectory 'purchase-uia.json') -Encoding UTF8
    if (-not $process.HasExited) { Stop-Process -Id $process.Id }
}

$missing = @($violations | Where-Object Issue -eq 'MissingId').Count
$latin = @($violations | Where-Object Issue -eq 'LatinText').Count
Write-Output "Visited: $($visited.Count); missing IDs: $missing; Latin label occurrences: $latin"
if ($violations.Count -ne 0) { exit 1 }
