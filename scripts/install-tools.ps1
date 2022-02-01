$managementNetadapterName = "management"
$smbNetadapterName = "smb"
$vmSwitchName = "vmswitch"
$clusterName = "cls1"
$natNetworkCIDR =  "192.168.0.0/16"
$hciNodes = (Get-ADComputer -Filter { OperatingSystem -Like '*Azure Stack HCI*'} | Sort-Object)
$subscriptionID = "4df06176-1e12-4112-b568-0fe6d209bbe2"
$wac = $hciNodes[0]

Invoke-Command -ComputerName $hciNodes -ScriptBlock {

    $managementNetadapterName = $using:managementNetadapterName
    $smbNetadapterName = $using:smbNetadapterName
    $vmSwitchName = $using:vmSwitchName
    $natNetworkCIDR = $using:natNetworkCIDR

    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    choco feature enable -n=allowGlobalConfirmation
    choco install powershell-core
    #choco install windows-admin-center --params='/Port:443'
    #choco uninstall windows-admin-center
    choco install azure-cli

    Install-WindowsFeature -Name Hyper-V, Failover-Clustering, FS-Data-Deduplication, Bitlocker, Data-Center-Bridging, RSAT-AD-PowerShell, NetworkATC -IncludeAllSubFeature -IncludeManagementTools -Verbose
    Get-NetIPAddress | Where-Object IPv4Address -like 10.255.254.* | Get-NetAdapter | Rename-NetAdapter -NewName $managementNetadapterName
    Get-NetIPAddress | Where-Object IPv4Address -like 10.255.255.* | Get-NetAdapter | Rename-NetAdapter -NewName $smbNetadapterName
    Get-NetAdapter $smbNetadapterName | Set-DNSClient –RegisterThisConnectionsAddress $False

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
    }

}

New-Cluster -Name $clusterName -Node $hciNodes.name -NoStorage -verbose
New-net
Enable-ClusterS2D -CimSession $clusterName -Confirm:$false -Verbose
New-Volume -FriendlyName "Volume1" -FileSystem CSVFS_ReFS -StoragePoolFriendlyName S2D* -Size 1TB -ProvisioningType Thin -CimSession $clusterName

Add-NetIntent -Name vmswitch -Management -Compute -ClusterName cls1 -AdapterName management

################ Enable AD kerberos delegation for Windows Admin Center Computer ################

$gatewayObject = Get-ADComputer -Identity $wac
$hciNodes | Set-ADComputer -PrincipalsAllowedToDelegateToAccount $gatewayObject -Verbose

Install-Module -Name Az.StackHCI
Register-AzStackHCI -SubscriptionId $subscriptionID -ComputerName $hciNodes[0] -ResourceGroupName sil


