# TunnelBuddy
Easy Windows GUI for ScaleFT tunnel - all in one Powershell script  

- Easy to use
- No config or setup
- Accessable menu from the icon by the clock
- Customizable for your organizations need
- Spend more time working and less time typing commands 

All contained in one single Powershell script.  
There is **no need** to run as Administrator nor tamper with any ExecutionPolicy.  

![Picture of context menu when servers are connected](https://poweredbyrene.eu/wp-content/uploads/2020/02/connected.jpg)
![Picture of context menu when servers are disconnected](https://poweredbyrene.eu/wp-content/uploads/2020/02/disconnected.jpg)

## How to
1. Download TunnelBuddy.ps1
2. Right click the file and 'Run with powershell' 
3. Locate the ![ScaleFT](https://www.scaleft.com/favicon.ico) icon at the [Taskbar notification area](https://support.microsoft.com/en-us/help/30031/windows-10-customize-taskbar-notification-area)


Hoover the mouse over the icon to see current status.
Right click to find the menu: Here you may easily Connect or Disconnect from the serveres, open the ScaleFT online dashboard, or Exit the program. 

**TunnelBuddy tries to interfere as little as possible.**  
At startup the application will try to automatically connect.  
Should you already be conected to all or some servers TunnelBuddy does nothing fancy and updates its status to "connected". 
Also, exiting does not disconnect any connections. 


### Requirements
ScaleFT must be installed and set up according to your organization. This includes any special ssh-settings or host-file adjustments. 
Make sure to `sft enroll --team "your-team"` 

#### SSH Client
Due to limitations in the Windows ssh-client TunnelBuddy is configured to use the one bundled in "Git for Windows". 
You may change this by editing the line `$SSHClientExe=$ENV:UserProfile+"\AppData\Local\Programs\Git\usr\bin\ssh.exe"` at the top of the script. 
Any modern ssh-client should work. 

### Automatic startup with Windows 10: 
- Open the startup folder: press Win+R, type `shell:startup`, hit Enter 
- Create a shortcut with `powershell.exe "& 'C:\Users\Full path to\Documents\tunnelbuddy.ps1'"`

### Automaticly enroll
Open the `tunnelbuddy.ps1` i an text editor and fill your ScaleFT team name in the config.   
See custom branding an for example.

## Custom Branding 
The name "TunnelBuddy" makes me happy, but might not fit your organization.  
If your organization's name is "ABC" - you can easily rebrand the application to "ABC-Tunnel".
Change the icon to something your users are familiar to and pre-set the Team Name to enable auto-enrollment.  
Edit the script in your favourite editor.
Example:
```
# ScaleFT Config:
$TeamName="abc-team" # Fill in to enable auto-enrollment, or manually sft enroll --team "your-team"
$SSHClientExe=$ENV:UserProfile+"\AppData\Local\Programs\Git\usr\bin\ssh.exe" # Any modern ssh client like the one bundled with 'Git for Windows'
# Custom branding:
$TunnelBuddy="ABC-Tunnel" # Application name
$IconPath=$PSScriptRoot+"\abc-tunnel-icon.ico" # Defaults to ScaleFT's icon
```

### Server list
By default the application will connect to all the servers listed in the file "%UserProfile%\serverlist.tunnelbuddy". 
If, upon starup, this file does not exist it will try retrive a new list from ScaleFT by running `sft list-servers`.

## Troubleshooting

### Program does not start when I follow instructons
Try running the program from a Powershell terminal. 
If there's any missing files or misconfigurations the application will print out describing errors. 

### Program takes long time to start / is "loading" for a long time
Upon the first initial run TunnelBuddy automatically retrives a list of servers from ScaleFT. 
It does this by running `sft list-servers` and waiting for it's result. 
This might take some 10-30 secs depending on your network and setup. 
The list is cached on disk for faster startups later. 

### Program doesn't automatically connect to any servers
Make sure you have enrolled onto your team with `sft enroll --team "your-team"`.

### My web browser opens when I start the program or connect 
If ScaleFT requires a token renewal it will open the browser for a new approval. 
Afterwards you will need to manually connect again. 

### Servers are not updated
On initial run TunnelBuddy retrieves a server list from ScaleFT.
This list is cached in a file called "server-list.buddy" stored in the %UserProfile% directory. 
Usually "c:\Users\YourUsername\serverlist.tunnelbuddy".
The cache is never updated until the file is deleted. 

## Todo / wishlist / ideas
- Automatically reconnect if disconnected without users interaction (Windows sleeping / lost Wifi etc)
- Automatically connect after token renewal
- Update server cache every x-interval
- Internally validate the token's experation date
- Storing servers as json
- When asking sft for server list only ask for columns of interest (`--columns ip,hostname`)
- Let users chose within the app which servers to use (instead of connecting to all available)


# Licence
TunnelBuddy is licensed under the The Unlicense. See details in 
[Licence](https://github.com/72656e65/TunnelBuddy/blob/master/LICENSE)

https://github.com/72656e65/TunnelBuddy/
