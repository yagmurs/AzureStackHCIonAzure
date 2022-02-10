$managementNetadapterName = "management"
$smbNetadapterName = "smb"
$vmSwitchName = "vmswitch"
$clusterName = "cls1"
$natNetworkCIDR =  "192.168.0.0/16"
$hciNodes = (Get-ADComputer -Filter { OperatingSystem -Like '*Azure Stack HCI*'} | Sort-Object)
$subscriptionID = "4df06176-1e12-4112-b568-0fe6d209bbe2"
$wac = $hciNodes[0]
$newVolumeName = "volume1"
$ws2019IsoUri = "https://software-download.microsoft.com/download/pr/17763.737.190906-2324.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us_1.iso"

################ Install managament tools for future use ################
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
choco feature enable -n=allowGlobalConfirmation
choco install powershell-core
choco install azure-cli
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name az -Verbose

################ Prepare Azure Stack HCI nodes for cluster setup ################
Invoke-Command -ComputerName $hciNodes.name -ScriptBlock {

    # Preparing Azure Stack HCI node for Azure Arc integration (Disabling WindowsAzureGuestAgent) https://docs.microsoft.com/en-us/azure/azure-arc/servers/plan-evaluate-on-azure-virtual-machine
    Set-Service WindowsAzureGuestAgent -StartupType Disabled -Verbose
    Stop-Service WindowsAzureGuestAgent -Force -Verbose
    New-NetFirewallRule -Name BlockAzureIMDS -DisplayName "Block access to Azure IMDS" -Enabled True -Profile Any -Direction Outbound -Action Block -RemoteAddress 169.254.169.254

    $managementNetadapterName = $using:managementNetadapterName
    $smbNetadapterName = $using:smbNetadapterName
    $vmSwitchName = $using:vmSwitchName
    $natNetworkCIDR = $using:natNetworkCIDR

    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    choco feature enable -n=allowGlobalConfirmation
    choco install powershell-core
    choco install azure-cli

    Install-WindowsFeature -Name Hyper-V, Failover-Clustering, FS-Data-Deduplication, Bitlocker, Data-Center-Bridging, RSAT-AD-PowerShell, NetworkATC -IncludeAllSubFeature -IncludeManagementTools -Verbose
    Get-NetIPAddress | Where-Object IPv4Address -like 10.255.254.* | Get-NetAdapter | Rename-NetAdapter -NewName $managementNetadapterName
    Get-NetIPAddress | Where-Object IPv4Address -like 10.255.255.* | Get-NetAdapter | Rename-NetAdapter -NewName $smbNetadapterName
    Get-NetAdapter $smbNetadapterName | Set-DNSClient -RegisterThisConnectionsAddress $False

<#
    $switchExist = Get-VMSwitch -Name $vmSwitchName -ErrorAction SilentlyContinue
    if (!$switchExist) {

        $natPrefix = $natNetworkCIDR.Split("/")[1]
        $natIP = $natNetworkCIDR.Replace($("0/" + "$natPrefix"), "1") 

        Write-Verbose "Creating Internal NAT Switch: $vmSwitchName"
        # Create Internal VM Switch for NAT
        New-VMSwitch -Name $vmSwitchName -SwitchType Internal | Out-Null

        Write-Verbose "Applying IP Address to NAT Switch: $vmSwitchName"
        # Apply IP Address to new Internal VM Switch
        $intIndex = (Get-NetAdapter | Where-Object { $_.Name -match $vmSwitchName}).ifIndex
   
        New-NetIPAddress -IPAddress $natIP -PrefixLength 16 -InterfaceIndex $intIndex | Out-Null

        # Create NetNAT

        Write-Verbose "Creating new NETNAT"
        New-NetNat -Name $vmSwitchName  -InternalIPInterfaceAddressPrefix "192.168.0.0/16" | Out-Null
#>

}

################ Create New Azure Stack HCI cluster ################
New-Cluster -Name $clusterName -Node $hciNodes.name -NoStorage -ManagementPointNetworkType Distributed -Verbose

################ Enable Storage Spaces Direct on Azure Stack HCI Cluster ################
Enable-ClusterS2D -CimSession $clusterName -Confirm:$false -Verbose

################ Create new thin volume on Storage Spaces Direct on Azure Stack HCI Cluster ################
New-Volume -FriendlyName $newVolumeName -FileSystem CSVFS_ReFS -StoragePoolFriendlyName S2D* -Size 1TB -ProvisioningType Thin -CimSession $clusterName

################ Install Windows Admin Center onto first Azure Stack HCI Node ################
Invoke-Command -ComputerName $hciNodes[0].name -ScriptBlock {
    choco install windows-admin-center --params='/Port:443'
}

################ Enable AD kerberos delegation for Windows Admin Center Computer Account for SSO ################
$gatewayObject = Get-ADComputer -Identity $wac
$hciNodes | Set-ADComputer -PrincipalsAllowedToDelegateToAccount $gatewayObject -Verbose
Get-ADComputer -Identity $clusterName | Set-ADComputer -PrincipalsAllowedToDelegateToAccount $gatewayObject -Verbose
Get-ClusterGroup -Name "Cluster Group" -Cluster $clusterName | Move-ClusterGroup

################ Download Windows Server 2019 ISO file to Cluster Storage ################
$isoFileDestination = "\\$($hciNodes[0].name)\c$\ClusterStorage\$newVolumeName\iso"
New-Item -Path $isoFileDestination -ItemType Directory -Force
Start-BitsTransfer -Source $ws2019IsoUri -Destination "$isoFileDestination\ws2019.iso"

################ Setup Intent based network config from first Azure Stack HCI Node ################
## Workaround to run NetworkATC cmdlets remotely
Copy-Item "\\$($hciNodes[0].name)\c$\Windows\System32\WindowsPowerShell\v1.0\Modules\NetworkATC\" -Destination C:\Windows\System32\WindowsPowerShell\v1.0\Modules\NetworkATC -Recurse -Force -Verbose
Copy-Item "\\$($hciNodes[0].name)\c$\Windows\System32\NetworkAtc.Driver.dll" -Destination "C:\Windows\System32\" -Force -Verbose
Copy-Item "\\$($hciNodes[0].name)\c$\Windows\System32\Newtonsoft.Json.dll" -Destination "C:\Windows\System32\" -Force -Verbose
Import-Module NetworkATC
Add-NetIntent -Name $vmSwitchName -Management -Compute -ClusterName $clusterName -AdapterName $managementNetadapterName

################ Register Windows Admin Center with Azure ################
# https://docs.microsoft.com/en-us/azure-stack/hci/deploy/register-with-azure#prerequisites-for-cluster-registration

################ Register Azure Stack HCI using Windows Admin Center ################
# https://docs.microsoft.com/en-us/azure-stack/hci/deploy/register-with-azure#register-a-cluster-using-windows-admin-center

################ Register Azure Stack HCI using Powershell ################
# https://docs.microsoft.com/en-us/azure-stack/hci/deploy/register-with-azure#register-a-cluster-using-powershell