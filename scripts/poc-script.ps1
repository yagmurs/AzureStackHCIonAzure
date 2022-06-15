$VerbosePreference = "Continue"

$tenantId = "<tenant_id>"
$subscriptionID = "<subscription_id>"
$targetResourceGroup = "<resource_group_name>"

$managementNetadapterName = "management"
$lanNetadapterName = "lan"
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
    $lanNetadapterName = $using:lanNetadapterName
    $vmSwitchName = $using:vmSwitchName
    $nestedNetAdapterName = "nestedgw"

    $natPrefix = $($using:natNetworkCIDR).Split("/")[1]
    $natIP = $($using:natNetworkCIDR).Replace($("0/" + "$natPrefix"), "1")
    $natNetworkCIDR = $using:natNetworkCIDR
    
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    choco feature enable -n=allowGlobalConfirmation
    #choco install powershell-core
    #choco install azure-cli
    choco install kubernetes-cli
    choco install kubernetes-helm

    Install-WindowsFeature -Name Hyper-V, Failover-Clustering, FS-Data-Deduplication, Bitlocker, Data-Center-Bridging, RSAT-AD-PowerShell, NetworkATC -IncludeAllSubFeature -IncludeManagementTools -Verbose
    Get-NetIPAddress | Where-Object IPv4Address -like 10.255.254.* | Get-NetAdapter | Rename-NetAdapter -NewName $managementNetadapterName
    Get-NetIPAddress | Where-Object IPv4Address -like 10.255.255.* | Get-NetAdapter | Rename-NetAdapter -NewName $lanNetadapterName
    Get-NetAdapter $lanNetadapterName | Set-DNSClient -RegisterThisConnectionsAddress $False

    New-VMSwitch -Name $lanNetadapterName -NetAdapterName $lanNetadapterName -AllowManagementOS $true -EnableEmbeddedTeaming $true

    ################ facilitate new vNic to enable NAT for internet access vNet connectivity ################
    Add-VMNetworkAdapter -ManagementOS -SwitchName $lanNetadapterName -Name $nestedNetAdapterName
    New-NetIPAddress -IPAddress $natIP -PrefixLength $natPrefix -InterfaceAlias "vEthernet `($nestedNetAdapterName`)"
    New-NetNat -Name $lanNetadapterName -InternalIPInterfaceAddressPrefix $natNetworkCIDR
    New-NetRoute -DestinationPrefix 10.255.254.0/24 -InterfaceAlias $managementNetadapterName -AddressFamily IPv4 -NextHop 10.255.254.1
    New-NetRoute -DestinationPrefix 10.255.254.0/23 -InterfaceAlias "vEthernet `($lanNetadapterName`)" -AddressFamily IPv4 -NextHop 10.255.255.1
    Set-NetIPInterface -InterfaceAlias "vEthernet `($lanNetadapterName`)", $managementNetadapterName, "vEthernet `($nestedNetAdapterName`)" -Forwarding Enabled
    #Get-NetIPInterface | select ifIndex,InterfaceAlias,AddressFamily,ConnectionState,Forwarding | Sort-Object -Property IfIndex | Format-Table
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
$hciNodes = (Get-ADComputer -Filter { OperatingSystem -Like '*Azure Stack HCI*'} | Sort-Object)
$hciNodes | Set-ADComputer -PrincipalsAllowedToDelegateToAccount $wacObject -Verbose
Get-ADComputer -Identity $clusterName | Set-ADComputer -PrincipalsAllowedToDelegateToAccount $wacObject -Verbose
Get-ClusterGroup -Name "Cluster Group" -Cluster $clusterName | Move-ClusterGroup -ErrorAction SilentlyContinue

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
Connect-AzAccount -Tenant $tenantId -Subscription $subscriptionID -UseDeviceAuthentication
Register-AzResourceProvider -ProviderNamespace Microsoft.Kubernetes
Register-AzResourceProvider -ProviderNamespace Microsoft.KubernetesConfiguration
Get-AzResourceProvider -ProviderNamespace Microsoft.Kubernetes
Get-AzResourceProvider -ProviderNamespace Microsoft.KubernetesConfiguration
Initialize-AksHciNode -Verbose
#static IP
$switch = Get-VmSwitch 
$vnet = New-AksHciNetworkSetting -name myvnet -vSwitchName $switch.Name -k8sNodeIpPoolStart "192.168.1.0" -k8sNodeIpPoolEnd "192.168.1.255" -vipPoolStart "192.168.2.0" -vipPoolEnd "192.168.2.255" -ipAddressPrefix "192.168.0.0/16" -gateway "192.168.0.1" -dnsServers "10.255.255.4" -vlanId 0
Set-AksHciConfig -imageDir c:\clusterstorage\volume1\ImageStore -workingDir c:\ClusterStorage\Volume1\ -cloudConfigLocation c:\clusterstorage\volume1\Config -vnet $vnet -cloudservicecidr "10.255.254.101/24"
Set-AksHciRegistration -subscriptionId $subscriptionID -resourceGroupName $targetResourceGroup -SkipLogin
Install-AksHci

# Create new Workload cluster without load balancer and onboard to Azure Arc
$lbCfg=New-AksHciLoadBalancerSetting -name "noLb" -loadBalancerSku "none"
New-AksHciCluster -Name w-1 -nodePoolName lp1 -nodeCount 1 -osType Linux -loadBalancerSettings $lbCfg
Set-AksHciRegistration -SubscriptionId $subscriptionID -TenantId $tenantId -ResourceGroupName $targetResourceGroup -SkipLogin
Enable-AksHciArcConnection -Name w-1

Get-AksHciCredential -Name w-1

#Deploy Metallb Load balancer to workload cluster
kubectl create namespace metallb-system
helm repo add metallb https://metallb.github.io/metallb
@"
configInline:
  address-pools:
  - name: default
    protocol: layer2
    addresses:
    - 192.168.3.0-192.168.255
"@ | Out-File -Encoding utf8 -FilePath .\values.yaml
helm install metallb metallb/metallb -f .\values.yaml --namespace metallb-system

# Test LB..
kubectl.exe apply -f https://raw.githubusercontent.com/yagmurs/kubernetes/main/deploy/nginx-deployment.yaml

kubectl get pods -A
kubectl get svc -A
iwr http://192.168.2.100 -UseBasicParsing

#endregion

dc subnet degistir
address space degistir /23 --> /22
lan subnet ekle
route tablosu ekle
route tablosunu lana bagla

$lanNetadapterName = "smb"
Add-NetIntent -Name $vmSwitchName -Compute -ClusterName $clusterName -AdapterName $lanNetadapterName
Add-VMNetworkAdapter -ManagementOS -SwitchName 'ComputeSwitch(vmswitch)' -Name nestedgw
Add-VMNetworkAdapter -ManagementOS -SwitchName 'ComputeSwitch(vmswitch)' -Name smb
New-NetIPAddress -IPAddress 192.168.0.1 -PrefixLength 16 -InterfaceAlias 'vEthernet (nestedgw)'
New-NetIPAddress -IPAddress 10.255.255.5 -PrefixLength 24 -InterfaceAlias 'vEthernet (smb)'
New-NetNat -Name nat -InternalIPInterfaceAddressPrefix 192.168.0.0/16
New-NetRoute -DestinationPrefix 10.255.254.0/23 -InterfaceAlias $lanNetadapterName -AddressFamily IPv4 -NextHop 10.255.255.1
New-NetRoute -DestinationPrefix 10.255.254.0/24 -InterfaceAlias $managementNetadapterName -AddressFamily IPv4 -NextHop 10.255.254.1
Set-NetIPInterface -InterfaceAlias 'vEthernet (smb)', $managementNetadapterName, 'vEthernet (nestedgw)' -Forwarding Enabled
Get-NetIPInterface | select ifIndex,InterfaceAlias,AddressFamily,ConnectionState,Forwarding | Sort-Object -Property IfIndex | Format-Table


$lanNetadapterName = "lan"
$nestedNetAdapterName = "nestedgw"
New-VMSwitch -Name $lanNetadapterName -NetAdapterName $lanNetadapterName -AllowManagementOS $true -EnableEmbeddedTeaming $true
Add-VMNetworkAdapter -ManagementOS -SwitchName $lanNetadapterName -Name $nestedNetAdapterName
New-NetIPAddress -IPAddress $natIP -PrefixLength $natPrefix -InterfaceAlias "vEthernet `($nestedNetAdapterName`)"
New-NetNat -Name nat -InternalIPInterfaceAddressPrefix $natNetworkCIDR
New-NetRoute -DestinationPrefix 10.255.254.0/24 -InterfaceAlias $managementNetadapterName -AddressFamily IPv4 -NextHop 10.255.254.1
New-NetRoute -DestinationPrefix 10.255.254.0/23 -InterfaceAlias "vEthernet `($lanNetadapterName`)" -AddressFamily IPv4 -NextHop 10.255.255.1
Set-NetIPInterface -InterfaceAlias "vEthernet `($lanNetadapterName`)", $managementNetadapterName, "vEthernet `($nestedNetAdapterName`)" -Forwarding Enabled
Get-NetIPInterface | select ifIndex,InterfaceAlias,AddressFamily,ConnectionState,Forwarding | Sort-Object -Property IfIndex | Format-Table

