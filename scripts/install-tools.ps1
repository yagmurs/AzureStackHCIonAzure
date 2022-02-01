Enter-PSSession -ComputerName ashci-0

Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
choco feature enable -n=allowGlobalConfirmation
choco install powershell-core
choco install windows-admin-center --params='/Port:443'

Install-WindowsFeature -Name Hyper-V, Failover-Clustering, FS-Data-Deduplication, Bitlocker, Data-Center-Bridging, RSAT-AD-PowerShell, NetworkATC -IncludeAllSubFeature -IncludeManagementTools -Verbose
Get-NetIPAddress | Where-Object IPv4Address -like 10.255.254.* | Get-NetAdapter | Rename-NetAdapter -NewName management
Get-NetIPAddress | Where-Object IPv4Address -like 10.255.255.* | Get-NetAdapter | Rename-NetAdapter -NewName smb
New-VMSwitch -name vmswitch -NetAdapterName management -AllowManagementOS $true
New-Cluster -Name ClusterName -Node NodeName.domain.com -NOSTORAGE
Enable-ClusterS2D -verbose

Install-Module -Name Az.StackHCI
Register-AzStackHCI -SubscriptionId "<subscription_ID>" -ComputerName Server1 -ResourceGroupName cluster1-rg