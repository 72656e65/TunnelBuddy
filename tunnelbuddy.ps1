# TunnelBuddy for Windows v0.2 - Rene N. 
# Howto: Right click & 'Run with powershell' or create a shortcut: powershell.exe "& 'C:\Users\Full path to\Documents\tunnelbuddy.ps1'"
#
# ScaleFT Config:
$TeamName="" # Fill in to enable auto-enrollment, or manually sft enroll --team "your-team"
$SSHClientExe=$ENV:UserProfile+"\AppData\Local\Programs\Git\usr\bin\ssh.exe" # Any modern ssh client like the one bundled with 'Git for Windows'
# Custom branding:
$TunnelBuddy="TunnelBuddy"
$IconPath=$PSScriptRoot+"\customBranding.ico" # Defaults to ScaleFT's icon
# Internal config:
$ScaleFTExe=$ENV:UserProfile+"\AppData\Local\Apps\ScaleFT\ScaleFT.exe"
$ScaleFTStateJson=$ENV:UserProfile+"\AppData\Local\ScaleFT\state.json"
$TunnelBuddyServerList=$ENV:UserProfile+"\serverlist.tunnelbuddy"
$exit="Exit"
$connect="Connect"
$connected="connected"
$reconnect="Reconnect"
$disconnect="Disconnect"
$disconnected="disconnected"

# Verify config & dependent files
function Assert-FileExists {
    param($Path,[string] $ErrorMessage="Could not start")
    If (!(Test-Path -Path $Path)) {
        Write-Host "`n$TunnelBuddy - $ErrorMessage `nExpected file: '$Path'."
		Exit
    }
}
Assert-FileExists -Path $SSHClientExe -ErrorMessage "Verify path for ssh-client"
Assert-FileExists -Path $ScaleFTExe -ErrorMessage "Verify that ScaleFT is installed correctly"

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

# Read enrollment details from ScaleFT state-json
function Update-CurrentlyKnown-ScaleFTState {
    if (Test-Path -Path $ScaleFTStateJson) {
        $state=Get-Content $ScaleFTStateJson | ConvertFrom-Json | Select-Object -ExpandProperty teams
        $enrolledTeam=$state | Select-Object -ExpandProperty name
        $loggedInUser=$state | Select-Object -ExpandProperty user
        Set-Variable -Scope "Script" -Name "loggedInUser" -Value $loggedInUser
        Set-Variable -Scope "Script" -Name "enrolledTeam" -Value $enrolledTeam
        if ($TeamName -ne "") {
            $isEnrolled=($enrolledTeam -eq $TeamName)
            Set-Variable -Scope "Script" -Name "isEnrolled" -Value $isEnrolled
        } else {
            Set-Variable -Scope "Script" -Name "isEnrolled" -Value $true
        }
    }
}

# Retrieve available serveres from ScaleFT
function Update-Known-ScaleFTServers {
    param([bool] $refreshFromScaleFT=$false)
    if ($refreshFromScaleFT) { # Hopefully we only need to do this once
        Clear-Content -Path $TunnelBuddyServerList -ErrorAction SilentlyContinue
        Update-TitleText -Title "$TunnelBuddy - Retrieving servers"
        &powershell.exe sft list-servers 1> $TunnelBuddyServerList 
    }

    if (Test-Path -Path $TunnelBuddyServerList) {  
        Get-Content -Path $TunnelBuddyServerList -Raw | Select-String -Pattern '(\b[\w\-\.]+)\s+[\w\-]+\s+[\w\-]+\s+[\w\-]+\s*([0-9\.\+\:\-]+)' -AllMatches | Foreach-Object {$_.Matches} | Foreach-Object { 
            $hostName = $_.Groups[1].Value
            $ipAddress = $_.Groups[2].Value
            if (($hostName -ne "HOSTNAME") -and ($hostName -ne "PROJECT_NAME")) {
                $serverList.Add($hostName, $ipAddress)
            }
        }
        Update-ContextMenu-And-Items
    } 
}

function Initialize-Enrollment {
    if (!$isEnrolled) { 
        Start-Process -FilePath "sft" -ArgumentList "enroll --team $TeamName" 
    } else {
        Update-CurrentlyKnown-ScaleFTState
        Update-ContextMenu-And-Items
    }
}

function Update-ContextMenu-And-Items {
    $ContextMenu = New-Object System.Windows.Forms.ContextMenu
    if (!$isEnrolled) {
        if ($TeamName -ne "") {
            $enrollMenu = New-MenuItem -Text "Enroll into $TeamName"
            $enrollMenu.Add_Click({Initialize-Enrollment})
        } else {
            $enrollMenu = New-Object System.Windows.Forms.MenuItem
            $enrollMenu.Text = "Not enrolled"
            $enrollMenu.Enabled = $false
        }
        $ContextMenu.MenuItems.AddRange($enrollMenu)
        $ContextMenu.MenuItems.AddRange((New-MenuItem)) #divider
    } else {
        $userMenu = New-MenuItem -Text "$loggedInUser (Dashboard)"
        $userMenu | Add-Member -Name Url -Value ("https://app.scaleft.com/t/"+$enrolledTeam+"/user/servers") -MemberType NoteProperty
        $userMenu.Add_Click({Start-Process -FilePath $This.Url})
        
        $connectMenu = New-MenuItem -Text "$reconnect" 
        if ($currentlyKnownStatus -eq $disconnected) { $connectMenu.Text=$connect }
        $connectMenu.Add_Click({Connect-To-AllSSh -KillRunning $true})
        
        $disconnectMenu = New-MenuItem -Text "$disconnect" 
        $disconnectMenu.Add_Click({Disconnect-Any-SshTunnels})
        if ($currentlyKnownStatus -eq $disconnected) { $disconnectMenu.Enabled=$false }
        
        $ContextMenu.MenuItems.AddRange($userMenu)
        $ContextMenu.MenuItems.AddRange((New-MenuItem)) #divider

        if ($serverList.Count -eq 0) { #uh-oh 
            $MenuItem = New-Object System.Windows.Forms.MenuItem
            $MenuItem.Text = "Refresh servers"
            $MenuItem.Add_Click({Update-Known-ScaleFTServers -refreshFromScaleFT $true})
            $ContextMenu.MenuItems.AddRange($MenuItem)
        }
        $serverList.GetEnumerator() | ForEach-Object {
            $displayName = $_.Key; $ipAddress = $_.Value
            $MenuItem = New-Object System.Windows.Forms.MenuItem
            if (($connectedServers.ContainsKey($displayName)) -or ($connectedServers.ContainsValue($ipAddress))) { 
                $MenuItem.Text = "$displayName - $connected" 
                #$MenuItem.Checked = $true
            } else {
                $MenuItem.Text = "$displayName - $disconnected"
            }
            $MenuItem.Enabled =$false
            $ContextMenu.MenuItems.AddRange($MenuItem) 
        }
        
        $ContextMenu.MenuItems.AddRange((New-MenuItem)) #divider
        $ContextMenu.MenuItems.AddRange($connectMenu)
        $ContextMenu.MenuItems.AddRange($disconnectMenu)
    }
    $ContextMenu.MenuItems.AddRange((New-MenuItem -Text "$exit" -ExitOnly))
    $NotifyIcon.ContextMenu = $ContextMenu
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
    param ([string] $ConnectTo, [bool]$KillRunning=$false)
    if ($KillRunning) {
        Disconnect-Any-SshTunnels -hostName $ConnectTo
    }
    $sshArgs="-N $ConnectTo"
    Start-Process -WindowStyle hidden -FilePath "sft" -ArgumentList "login" -PassThru # cheap solution
    Start-Process -WindowStyle hidden -FilePath $SSHClientExe -ArgumentList $sshArgs -PassThru
}

function Connect-To-AllSSh {
    param ([bool]$KillRunning=$true)
    # todo: check if token is valid, then if not run sft + timer to check for new token & try to reconnect 
    Start-Process -WindowStyle hidden -FilePath "sft" -ArgumentList "login" -PassThru # cheap solution
    if ($KillRunning) {
        Disconnect-Any-SshTunnels
    }

    $serverList.GetEnumerator() | ForEach-Object {
        $hostName = $_.Key # $ipAddress = $_.Value
        $sshArgs="-N $hostname"
        Start-Process -WindowStyle hidden -FilePath $SSHClientExe -ArgumentList $sshArgs -PassThru
    }
}

function Get-Currently-ConnectedTo {
    $connectedServers.Clear()

    try {
        Get-Running-Tunnels | Select-Object -Expand CommandLine | ForEach-Object {
            try {
                $maybeHost= $_.split(' ')
                if ($maybeHost.Count -gt 2) {
                    $hostname = $maybeHost[2] # Hostname/ip
                    if (($serverList.ContainsKey($hostname)) -or ($serverList.ContainsValue($hostname))) {
                        $connectedServers.Add($hostname, $connected)
                    } 
                }
            } catch {} # Split failed - SilentlyContinue
        }
        if ($connectedServers.Count -ne 0) {
            Return $connected
        }
    }
    catch {
        if ($connectedServers.Count -ne 0) {
            Return $connected
        }
    }
    Return $disconnected
}

function Update-CurrentlyKnown-ConnectionStatus {
    $now = Get-Currently-ConnectedTo
    Set-Variable -Scope "Script" -Name "currentlyKnownStatus" -Value $now
}

function Update-TitleText {
    param ([string] $Title="$TunnelBuddy")
    $host.ui.RawUI.WindowTitle=$Title
    $NotifyIcon.Text=$Title
    $Form.Text=$Title
}

## Run and have fun
# Have sft validate its token
Start-Process -WindowStyle hidden -FilePath "sft" -ArgumentList "login"
# Load assembly
Add-Type -AssemblyName 'System.Windows.Forms'
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")] 
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] 
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'
([Console.Window]::ShowWindow([Console.Window]::GetConsoleWindow(), 0)) > $null #Hide console
# Initialize variables
Set-Variable -Scope "Script" -Name "currentlyKnownStatus" -Value $disconnected
Set-Variable -Scope "Script" -Name "connectedServers" -Value @{}
Set-Variable -Scope "Script" -Name "isEnrolled" -Value $false
Set-Variable -Scope "Script" -Name "serverList" -Value @{}
# Initialize Windows Forms objects
Set-Variable -Scope "Script" -Name "Form" -Value (New-Object System.Windows.Forms.Form)
Set-Variable -Scope "Script" -Name "Timer" -Value (New-Object System.Windows.Forms.Timer)
Set-Variable -Scope "Script" -Name "NotifyIcon" -Value (New-Object System.Windows.Forms.NotifyIcon)

$Form.ShowInTaskbar = $false
$Form.FormBorderStyle = "None"
$Form.WindowState = "Minimized"
$NotifyIcon.Icon = Find-Systray-Icon
$NotifyIcon.Visible = $true

Update-ContextMenu-And-Items
Update-CurrentlyKnown-ScaleFTState
Update-CurrentlyKnown-ConnectionStatus
Update-Known-ScaleFTServers -refreshFromScaleFT (!(Test-Path -Path $TunnelBuddyServerList))
Update-TitleText -Title "$TunnelBuddy"

if ($currentlyKnownStatus -eq $disconnected) { # Automatically reconnect to previous session (after reboot etc)
    Connect-To-AllSSh
}

$Timer.Interval=5000
$Timer.add_Tick({
    $wasKnownStatus = $currentlyKnownStatus
    Update-CurrentlyKnown-ConnectionStatus
    if ($currentlyKnownStatus -ne $wasKnownStatus) {
        Update-TitleText -Title "$TunnelBuddy - $currentlyKnownStatus"
        Update-ContextMenu-And-Items
    }
    $wasEnrolledStatus = $isEnrolled
    if (!$isEnrolled) {
        Update-CurrentlyKnown-ScaleFTState
    }
    if ($wasEnrolledStatus -ne $isEnrolled) {
        Update-ContextMenu-And-Items
    }
})
$Timer.Start()
$Form.ShowDialog() > $null
