# TunnelHelper for Windows v0.3 - Rene N
# Howto: Right click & 'Run with powershell' or create a shortcut: powershell.exe "& 'C:\Users\Full path to\Documents\tunnelhelper.ps1'"
# ScaleFT Config:
$TeamName=""
$SSHConfig=$ENV:UserProfile+"\.ssh\config2"
$defaultHost="devWeb02" # Default to this if config does not include any hosts
$SSHClientExe=$ENV:UserProfile+"\AppData\Local\Programs\Git\usr\bin\ssh.exe" # Any modern ssh client like the one bundled with 'Git for Windows'
$ScaleFTExe=$ENV:UserProfile+"\AppData\Local\Apps\ScaleFT\ScaleFT.exe"
$ScaleFTStateJson=$ENV:UserProfile+"\AppData\Local\ScaleFT\state.json"
# Custom branding:
$TunnelHelper="TunnelBuddy"
$IconPath=$PSScriptRoot+"\customBranding.ico" # Defaults to ScaleFT's icon
# Internal config:
$TunnelHelperState=$ENV:UserProfile+"\tunnelHelper.state"
$exit="Exit"
$connect="Connect"
$reconnect="Reconnect"
$disconnect="Disconnect"
$disconnected="Disconnected"
$disconnectAll="Disconnect All"

# Verify config & dependent files
function Assert-FileExists {
    param($Path,[string] $ErrorMessage="Could not start")
    If (!(Test-Path -Path $Path)) {
        Write-Host "`n$TunnelHelper - $ErrorMessage `nExpected file: '$Path'."
        Exit
    }
}
Assert-FileExists -Path $SSHClientExe -ErrorMessage "Verify that path for ssh-client"
Assert-FileExists -Path $SSHConfig -ErrorMessage "SSH config missing"
Assert-FileExists -Path $ScaleFTExe -ErrorMessage "Verify that ScaleFT is installed correctly"
if (Test-Path -Path $TunnelHelperState) {
    $lastRunStatus = Get-Content -Path $TunnelHelperState -TotalCount 1 -ErrorAction SilentlyContinue
    Set-Variable -Scope "Script" -Name "lastRunStatus" -Value $lastRunStatus
}

Add-Type -AssemblyName 'System.Windows.Forms'
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")] 
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] 
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'

function Find-Systray-Icon {
    if ((Test-Path -Path $IconPath)) {
        Return [System.Drawing.Icon]::ExtractAssociatedIcon($IconPath)
    } else {
        Return [System.Drawing.Icon]::ExtractAssociatedIcon($ScaleFTExe)
    }
}

function Exit-And-CleanUp {
    [System.GC]::Collect()
    $NotifyIcon.Dispose()
    $Timer.Dispose()
    $Form.Dispose()
}

function New-MenuItem{
    param([string] $Text = "-", [string] $ConnectTo, [switch] $ExitOnly = $false)
    $MenuItem = New-Object System.Windows.Forms.MenuItem
    $MenuItem.Text = $Text

    if ($ConnectTo -and !$ExitOnly){
        $MenuItem | Add-Member -Name ConnectTo -Value $ConnectTo -MemberType NoteProperty
        $MenuItem.Add_Click({ Connect-SshTunnel -ConnectTo $This.ConnectTo -KillRunning $false})
    }

    if ($ExitOnly){
        $MenuItem.Add_Click({ Exit-And-CleanUp })
    }
    $MenuItem
}

function Update-CurrentlyKnown-ScaleFTState {
    if (Test-Path -Path $ScaleFTStateJson) {
        $state=Get-Content $ScaleFTStateJson | ConvertFrom-Json | Select-Object -ExpandProperty teams
        $enrolledTeam=$state | Select-Object -ExpandProperty name
        $loggedInUser=$state | Select-Object -ExpandProperty user
        $isEnrolled=($enrolledTeam -eq $TeamName)
		Set-Variable -Scope "Script" -Name "enrolledTeam" -Value $enrolledTeam
        Set-Variable -Scope "Script" -Name "loggedInUser" -Value $loggedInUser
		Set-Variable -Scope "Script" -Name "isEnrolled" -Value $isEnrolled
    }
}

function Initialize-Enrollment {
    if (!$isEnrolled) { 
        Start-Process -FilePath "sft" -ArgumentList "enroll --team $TeamName" 
    } else {
        Update-ContextMenu-And-Items
    }
}

function Update-ContextMenu-And-Items {
    $ContextMenu = New-Object System.Windows.Forms.ContextMenu
    if (!$isEnrolled) {
        $enrollMenu = New-MenuItem -Text "Enroll into $TeamName"
        $enrollMenu.Add_Click({Initialize-Enrollment})
        $ContextMenu.MenuItems.AddRange($enrollMenu)
        $ContextMenu.MenuItems.AddRange((New-MenuItem)) #divider
    } else {
        $userMenu = New-MenuItem -Text "$loggedInUser (Dashboard)"
        $userMenu | Add-Member -Name Url -Value ("https://app.scaleft.com/t/"+$TeamName+"/user/servers") -MemberType NoteProperty
        $userMenu.Add_Click({Start-Process -FilePath $This.Url})
        
        $disconnectMenu = New-MenuItem -Text "$disconnectAll" 
        $disconnectMenu.Add_Click({Disconnect-Any-SshTunnels})
        if ($currentlyKnownStatus -eq $disconnected) { $disconnectMenu.Enabled=$false }
        
        $ContextMenu.MenuItems.AddRange($userMenu)
        $ContextMenu.MenuItems.AddRange((New-MenuItem)) #divider

#Get-Content -Path "C:\Users\N151699\.ssh\config2" -Raw | Select-String -Pattern 'Hostname\s*(\b[\w\.+\:\-]+)' -AllMatches  | Foreach-Object {$_.Matches}  | Foreach-Object {$_.Groups[1].Value}
# Get-Content -Path "C:\Users\N151699\.ssh\config2" -Raw | Select-String -Pattern 'Host\s+(\b[\w\-\.]+).*\n\s*Hostname\s*(\b[\w\.+\:\-]+)' -AllMatches  | Foreach-Object {$_.Matches} | Foreach-Object { $_.Groups[1].Value} #Groups[2].Value = Hostname
#Select-String -Pattern 'Host\s+(\b[\w\-\.]+).*' 
         Get-Content -Path $SSHConfig -Raw | Select-String -Pattern 'Host\s+(\b[\w\-\.]+).*\n\s*Hostname\s*(\b[\w\.+\:\-]+)' -AllMatches  | Foreach-Object {$_.Matches} | Foreach-Object { 
            $displayName = $_.Groups[1].Value
            $hostName = $_.Groups[2].Value
            if ($hostName -ne "127.0.0.1") {
                $text = "$connect $displayName"
                if ($_.Groups[1].Value -eq $currentlyKnownStatus) { $text = "$reconnect $hostName" }
                $ContextMenu.MenuItems.AddRange((New-MenuItem -Text "$text" -ConnectTo $hostName )) 
            }
        }
        #if contextMenu.MenuItems .count <= 2 ==> add $defaultHost
        if ($ContextMenu.MenuItems.Count -lt 3) {
            $ContextMenu.MenuItems.AddRange((New-MenuItem -Text "$connect $defaultHost" -ConnectTo $defaultHost )) 
        }
		
		# Connect All menu
        $ContextMenu.MenuItems.AddRange($disconnectMenu)
    }
    $ContextMenu.MenuItems.AddRange((New-MenuItem -Text "$exit" -ExitOnly))
    $ContextMenu
}

function Get-Running-Tunnels {
    param ([string] $hostName="")
    $match="-N"
    if ($hostName -ne "") {
        $match="-N $hostName"
    }
    Return Get-WmiObject Win32_Process -Filter "name = 'ssh.exe'" -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq "$SSHClientExe" } | Where-Object CommandLine -match "$match"
}

function Disconnect-Any-SshTunnels {
    param ([string] $hostName="")
    Get-Running-Tunnels -hostName $hostName | ForEach-Object { Invoke-WmiMethod -Path $_.__Path –Name Terminate -ErrorAction SilentlyContinue }
}

function Connect-SshTunnel {
    param ([string] $ConnectTo, [bool]$KillRunning=$true)
    if ($KillRunning) {
        Disconnect-Any-SshTunnels -hostName $ConnectTo
    }
    $sshArgs="-N $ConnectTo"
    Start-Process -WindowStyle hidden -FilePath "sft" -ArgumentList "login" -PassThru
    Start-Process -WindowStyle hidden -FilePath $SSHClientExe -ArgumentList $sshArgs -PassThru
}

function Connect-To-AllSSh {
    param ([string] $ConnectTo, [bool]$KillRunning=$true)
    Start-Process -WindowStyle hidden -FilePath "sft" -ArgumentList "login" -PassThru
    if ($KillRunning) {
        Disconnect-Any-SshTunnels
    }
    $sshArgs="-fNq $ConnectTo"
    Start-Process -WindowStyle hidden -FilePath $SSHClientExe -ArgumentList $sshArgs -PassThru
}

function Get-Currently-ConnectedTo {
    try {
        [array]$maybeTunnelDetails=(Get-Running-Tunnels | Select-Object -Expand CommandLine).split(' ') 
        if ($maybeTunnelDetails.Count -gt 2) {
            Return $maybeTunnelDetails[2] # returns Hostname
        }
    }
    catch {
        Return $disconnected
    }
    Return $disconnected
}

function Update-CurrentlyKnown-ConnectionStatus {
    $now = Get-Currently-ConnectedTo
    Set-Variable -Scope "Script" -Name "currentlyKnownStatus" -Value $now
}

# Run and have fun
([Console.Window]::ShowWindow([Console.Window]::GetConsoleWindow(), 0)) > $null #Hide console
Set-Variable -Scope "Script" -Name "currentlyKnownStatus" -Value $disconnected
Set-Variable -Scope "Script" -Name "isEnrolled" -Value $false
Update-CurrentlyKnown-ScaleFTState
Update-CurrentlyKnown-ConnectionStatus

$Form = New-Object System.Windows.Forms.Form
$Form.Text=$TunnelHelper
$Form.BackColor = "Black"
$Form.ShowInTaskbar = $false
$Form.FormBorderStyle = "None"
$Form.TransparencyKey = "Black"
$Form.WindowState = "Minimized"

if ($currentlyKnownStatus -eq $disconnected) { # Automatically reconnect to previous session (after reboot etc)
        Connect-SshTunnel -ConnectTo "-all" -KillRunning $false
}

$NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
$NotifyIcon.Icon = Find-Systray-Icon
$NotifyIcon.Text = "$TunnelHelper - $currentlyKnownStatus"
$NotifyIcon.ContextMenu = Update-ContextMenu-And-Items
$NotifyIcon.Visible = $true

$Timer=New-Object System.Windows.Forms.Timer
$Timer.Interval=5000
$Timer.add_Tick({
    $wasKnownStatus = $currentlyKnownStatus
    Update-CurrentlyKnown-ConnectionStatus
    if ($currentlyKnownStatus -ne $wasKnownStatus) {
        $NotifyIcon.Text = "$TunnelHelper - $currentlyKnownStatus"
        $NotifyIcon.ContextMenu = Update-ContextMenu-And-Items
        $currentlyKnownStatus | Out-File -FilePath $TunnelHelperState -NoNewline
    }
#did disconnect on purpose otherwise: reconnect
    $wasEnrolledStatus = $isEnrolled
    if (!$isEnrolled) {
        Update-CurrentlyKnown-ScaleFTState
    }
    if ($wasEnrolledStatus -ne $isEnrolled) {
        $NotifyIcon.ContextMenu = Update-ContextMenu-And-Items
    }
})
$Timer.Start()
$Form.ShowDialog() > $null
