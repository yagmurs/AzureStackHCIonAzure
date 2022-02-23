$VerbosePreference = "Continue"

$tenantId = "<tenant_id>"
$subscriptionID = "<subscription_id>"
$targetResourceGroup = "<resource_group_name>"

$managementNetadapterName = "management"
$smbNetadapterName = "smb"
$vmSwitchName = "vmswitch"
$clusterName = "cls1"
$natNetworkCIDR =  "192.168.0.0/16"
$hciNodes = (Get-ADComputer -Filter { OperatingSystem -Like '*Azure Stack HCI*'} | Sort-Object)

$firstNode = $hciNodes | Select-Object -First 1
$newVolumeName = "volume1"
$ws2019IsoUri = "https://software-download.microsoft.com/download/pr/17763.737.190906-2324.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us_1.iso"

################ Install managament tools for future use ################
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
choco feature enable -n=allowGlobalConfirmation
#choco install powershell-core
choco install azure-cli
choco install kubernetes-cli
choco install kubernetes-helm

# Update Powershell package provider and trust gallery
Install-PackageProvider Nuget -Force -Verbose
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
#Install-Module -Name az -Verbose

################ Prepare Azure Stack HCI nodes for cluster setup ################
Invoke-Command -ComputerName $hciNodes.name -ScriptBlock {

    # Update Powershell package provider and trust gallery
    Install-PackageProvider Nuget -Force -Verbose
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name PowerShellGet -Force

    # Preparing Azure Stack HCI node for Azure Arc integration (Disabling WindowsAzureGuestAgent) https://docs.microsoft.com/en-us/azure/azure-arc/servers/plan-evaluate-on-azure-virtual-machine
    Set-Service WindowsAzureGuestAgent -StartupType Disabled -Verbose
    Stop-Service WindowsAzureGuestAgent -Force -Verbose
    New-NetFirewallRule -Name BlockAzureIMDS -DisplayName "Block access to Azure IMDS" -Enabled True -Profile Any -Direction Outbound -Action Block -RemoteAddress 169.254.169.254

    $managementNetadapterName = $using:managementNetadapterName
    $smbNetadapterName = $using:smbNetadapterName
    $vmSwitchName = $using:vmSwitchName
    
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    choco feature enable -n=allowGlobalConfirmation
    #choco install powershell-core
    #choco install azure-cli

    Install-WindowsFeature -Name Hyper-V, Failover-Clustering, FS-Data-Deduplication, Bitlocker, Data-Center-Bridging, RSAT-AD-PowerShell, NetworkATC -IncludeAllSubFeature -IncludeManagementTools -Verbose
    Get-NetIPAddress | Where-Object IPv4Address -like 10.255.254.* | Get-NetAdapter | Rename-NetAdapter -NewName $managementNetadapterName
    Get-NetIPAddress | Where-Object IPv4Address -like 10.255.255.* | Get-NetAdapter | Rename-NetAdapter -NewName $smbNetadapterName
    Get-NetAdapter $smbNetadapterName | Set-DNSClient -RegisterThisConnectionsAddress $False
}

################ Create New Azure Stack HCI cluster ################
New-Cluster -Name $clusterName -Node $hciNodes.name -NoStorage -ManagementPointNetworkType Distributed -Verbose
Clear-DnsClientCache

################ Enable Storage Spaces Direct on Azure Stack HCI Cluster ################
Enable-ClusterS2D -CimSession $clusterName -Confirm:$false -Verbose
Start-Sleep -Seconds 60

################ Create new thin volume on Storage Spaces Direct on Azure Stack HCI Cluster ################

New-Volume -FriendlyName $newVolumeName -FileSystem CSVFS_ReFS -StoragePoolFriendlyName S2D* -Size 1TB -ProvisioningType Thin -CimSession $clusterName

################ Install Windows Admin Center onto first Azure Stack HCI Node ################
Invoke-Command -ComputerName $firstNode.name -ScriptBlock {
    choco install windows-admin-center --params='/Port:443'
}

################ Enable AD kerberos delegation for Windows Admin Center Computer Account for SSO ################
$wacObject = Get-ADComputer -Identity $firstNode
$hciNodes | Set-ADComputer -PrincipalsAllowedToDelegateToAccount $wacObject -Verbose
Get-ADComputer -Identity $clusterName | Set-ADComputer -PrincipalsAllowedToDelegateToAccount $wacObject -Verbose
Get-ClusterGroup -Name "Cluster Group" -Cluster $clusterName | Move-ClusterGroup -ErrorAction SilentlyContinue

################ Setup Intent based network config on Azure Stack HCI Cluster ################
## Workaround to run NetworkATC cmdlets remotely
Copy-Item "\\$($firstNode.name)\c$\Windows\System32\WindowsPowerShell\v1.0\Modules\NetworkATC\" -Destination C:\Windows\System32\WindowsPowerShell\v1.0\Modules\NetworkATC -Recurse -Force -Verbose
Copy-Item "\\$($firstNode.name)\c$\Windows\System32\NetworkAtc.Driver.dll" -Destination "C:\Windows\System32\" -Force -Verbose
Copy-Item "\\$($firstNode.name)\c$\Windows\System32\Newtonsoft.Json.dll" -Destination "C:\Windows\System32\" -Force -Verbose
Import-Module NetworkATC
Add-NetIntent -Name $vmSwitchName -Management -Compute -ClusterName $clusterName -AdapterName $managementNetadapterName

################ Add additional vNic to enable NAT to allow VMs to access to internet ################
Invoke-Command -ComputerName $hciNodes.name -ScriptBlock {

    do
    {
        $switch = Get-VMSwitch
        Write-Verbose "Waiting for VM Switch"
        Start-Sleep -Seconds 5
    }
    until ($switch.count -gt 0)
    
    $natPrefix = $($using:natNetworkCIDR).Split("/")[1]
    $natIP = $($using:natNetworkCIDR).Replace($("0/" + "$natPrefix"), "1")
    $natNetworkCIDR = $using:natNetworkCIDR

    Write-Verbose "Adding vNic for NAT"
    Add-VMNetworkAdapter -SwitchName  $switch.Name -Name nat -ManagementOS

    # Set IP Address to new vNic
    Write-Verbose "Set IP Address to new vNic: nat"
    $intIndex = (Get-NetAdapter | Where-Object { $_.Name -match "nat"}).ifIndex
    New-NetIPAddress -IPAddress $natIP -PrefixLength $natPrefix -InterfaceIndex $intIndex | Out-Null

    # Create NetNAT
    Write-Verbose "Creating new NetNat"
    New-NetNat -Name nat  -InternalIPInterfaceAddressPrefix $natNetworkCIDR | Out-Null
}


################ Register Windows Admin Center with Azure ################
# https://docs.microsoft.com/en-us/azure-stack/hci/deploy/register-with-azure#prerequisites-for-cluster-registration

################ Register Azure Stack HCI using Windows Admin Center ################
# https://docs.microsoft.com/en-us/azure-stack/hci/deploy/register-with-azure#register-a-cluster-using-windows-admin-center

################ Register Azure Stack HCI using Powershell ################
# https://docs.microsoft.com/en-us/azure-stack/hci/deploy/register-with-azure#register-a-cluster-using-powershell
Install-Module -Name Az.StackHCI -Verbose
Register-AzStackHCI -SubscriptionId $subscriptionID -ComputerName $firstNode.name -ResourceGroupName $targetResourceGroup -TenantId $tenantId -Verbose # -Region "<region>"

#region for VM testing

################ Download Windows Server 2019 ISO file to Cluster Storage ################
$isoFileDestination = "\\$($firstNode.name)\c$\ClusterStorage\$newVolumeName\iso"
New-Item -Path $isoFileDestination -ItemType Directory -Force
Start-BitsTransfer -Source $ws2019IsoUri -Destination "$isoFileDestination\ws2019.iso"

################ Create VMs for testing ################
Invoke-Command -ComputerName $firstNode.name -ScriptBlock {
    $newVolumeName = $using:newVolumeName
    $isoFile = "$using:isoFileDestination\ws2019.iso"
    $vhdPath = "c:\Clusterstorage\$newVolumeName\VMs"
    $vmPrefix = "test"
    foreach ($item in 1..2)
    {
        $vmName = $vmPrefix + $item
        $vm = New-VM -Name $vmName -MemoryStartupBytes 4gb -SwitchName nat -NewVHDPath "$vhdPath\$vmName\Virtual Hard Disks\$vmName.vhdx" -NewVHDSizeBytes 50gb -Path $vhdPath -Generation 2
        Set-VMProcessor -VMName $vmName -Count 2
        Add-VMDvdDrive -VM $vm -Path $isoFile
        $dvdDrive = Get-VMDvdDrive -vm $vm
        $osDrive = Get-VMHardDiskDrive -VM $vm
        Set-VMFirmware -VM $vm -BootOrder $osDrive, $dvdDrive
        Add-ClusterVirtualMachineRole -VMId $vm.VMId
        Start-VM -Name $vmName  
    }
}

#endregion

#region run from Azure Stack HCI node
################ Run following from one of Azure Stack HCI nodes using RDP ################
$VerbosePreference = "Continue"
Install-Module -Name AksHci -Repository PSGallery -AcceptLicense
Connect-AzAccount -UseDeviceAuthentication
Set-AzContext -Subscription $subscriptionID
Register-AzResourceProvider -ProviderNamespace Microsoft.Kubernetes
Register-AzResourceProvider -ProviderNamespace Microsoft.KubernetesConfiguration
Get-AzResourceProvider -ProviderNamespace Microsoft.Kubernetes
Get-AzResourceProvider -ProviderNamespace Microsoft.KubernetesConfiguration
Initialize-AksHciNode -Verbose
#static IP
$switch = Get-VmSwitch 
$vnet = New-AksHciNetworkSetting -name myvnet -vSwitchName $switch.Name -k8sNodeIpPoolStart "192.168.1.0" -k8sNodeIpPoolEnd "192.168.1.255" -vipPoolStart "192.168.2.0" -vipPoolEnd "192.168.2.255" -ipAddressPrefix "192.168.0.0/16" -gateway "192.168.0.1" -dnsServers "10.255.254.4" -vlanId 0
Set-AksHciConfig -imageDir c:\clusterstorage\volume1\ImageStore -workingDir c:\ClusterStorage\Volume1\ -cloudConfigLocation c:\clusterstorage\volume1\Config -vnet $vnet -cloudservicecidr "10.255.254.101/24"
Set-AksHciRegistration -subscriptionId $subscriptionID -resourceGroupName $targetResourceGroup -SkipLogin
Install-AksHci

New-AksHciCluster -Name w-1 -nodePoolName lp1 -nodeCount 1 -osType Linux
Enable-AksHciArcConnection -Name w-1
#endregion
