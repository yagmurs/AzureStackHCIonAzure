Import-Module AzureStackHCIInstallerHelper

$selectionRoles = Read-Host  @"

============================================================================================

Azure Stack HCI Roles and Features Installation options
    Roles are installed by default. (Optional)
    
    0. Install required roles to Azure Stack HCI Hosts
    1. Do NOT install any Roles ( !!Default selection!! )

============================================================================================

Select
"@

$selectionNetwork = Read-Host  @"

============================================================================================

Azure Stack HCI Network Adapter Configuration options (SET Switch)
    
    0. Cleanup Network configuration (recommended if redeploying)
    1. High-available networks for Management & One Virtual Switch for All Traffic
    2. High-available networks for Management & One Virtual Switch for Compute Only
    3. High-available networks for Managament & Two Virtual Switches
    4. Single Network Adapter for Management & One Virtual Switch for All Traffic
    5. Single Network Adapter for Management & One Virtual Switch for Compute Only
    6. Single Network Adapter for Management & Two Virtual Switches for Compute and Storage

Includes Cleanup (recommended if redeploying)
    
    7. High-available networks for Management & One Virtual Switch for All Traffic
    8. Single Network Adapter for Management & One Virtual Switch for Compute Only
    9. High-available networks for Managament & Two Virtual Switches
   10. Do NOT configure networks

============================================================================================
    
Select
"@

$selectionDisks = Read-Host  @"

============================================================================================

Azure Stack HCI Disks cleanup options
    Please do so, if this is NOT first installation on top of clean environment. (Optional)
    
    0. Erase all drives
    1. Do NOT erase and cleanup ( !!Default selection!! )

============================================================================================

Select
"@

$selectionCluster = Read-Host  @"

============================================================================================

Azure Stack HCI Cluster options
    Install cluster using default name to prevent any misconfigurations
    
    0. Enable Cluster using custom name (Will be prompted)
    1. Enable Cluster using default Name (Cluster Name: hci01) ( !!Default selection!! )
    2. Do NOT Create Cluster yet.   

============================================================================================

Select
"@

if ($selectionCluster -eq 0)
{
    $nameForCluster = Read-Host "Enter Name for Cluster: "
}


switch ($selectionRoles)
{
    0 {Configure-AzsHciClusterRoles -Verbose}
    Default {Write-Warning "[Configure-AzsHciClusterRoles]: Not installing Roles and  Feature, assuming All Roles and Features required are already installed. Subsequent process may rely on Roles and Features Installation."} 
}
  
switch ($selectionNetwork)
{
    0 {Configure-AzsHciClusterNetwork -CleanupConfiguration -Verbose}
    1 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig HighAvailable -Verbose -ComputeAndStorageInterfaceConfig OneVirtualSwitchforAllTraffic}
    2 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig HighAvailable -Verbose -ComputeAndStorageInterfaceConfig OneVirtualSwitchforComputeOnly}
    3 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig HighAvailable -Verbose -ComputeAndStorageInterfaceConfig TwoVirtualSwitches}
    4 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig SingleAdapter -Verbose -ComputeAndStorageInterfaceConfig OneVirtualSwitchforAllTraffic}
    5 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig SingleAdapter -Verbose -ComputeAndStorageInterfaceConfig OneVirtualSwitchforComputeOnly}
    6 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig SingleAdapter -Verbose -ComputeAndStorageInterfaceConfig TwoVirtualSwitches}
    7 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig HighAvailable -Verbose -ComputeAndStorageInterfaceConfig OneVirtualSwitchforAllTraffic -ForceCleanup}
    8 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig SingleAdapter -Verbose -ComputeAndStorageInterfaceConfig OneVirtualSwitchforComputeOnly -ForceCleanup}
    9 {Configure-AzsHciClusterNetwork -ManagementInterfaceConfig HighAvailable -Verbose -ComputeAndStorageInterfaceConfig TwoVirtualSwitches -ForceCleanup}
   10 {Write-Warning "[Configure-AzsHciClusterNetwork]: Assuming Networks are setup"}
    Default {"Select between 0 to 10 from the menu"} 
}

switch ($selectionDisks)
{
    0 {Erase-AzsHciClusterDisks -Verbose}
    Default {Write-Warning "[Erase-AzsHciClusterDisks]: Assuming this is first installation on top of clean environment. Otherwise subsequent process may fail."} 
}

switch ($selectionCluster)
{
    0 {Setup-AzsHciCluster -ClusterName $nameForCluster -Verbose}
    2 {Write-Warning "You may need to configure cluster manually!"}
    Default {Setup-AzsHciCluster -ClusterName hci01 -Verbose} 
}

break

Cleanup-VMs -AzureStackHciHosts -RedeployDeletedVMs -WindowsAdminCenterVM