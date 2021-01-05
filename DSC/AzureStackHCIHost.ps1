configuration AzureStackHCIHost
{ 
   param 
   ( 
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Int]$RetryCount=20,

        [Int]$RetryIntervalSec=30,

        [String]$targetDrive = "V:",

        [String]$sourcePath =  "$targetDrive\source",

        [String]$targetVMPath = "$targetDrive\VMs",

        [String]$baseVHDFolderPath = "$targetVMPath\base",

        [String]$azsHCIISOLocalPath = "$sourcePath\AzSHCI.iso",

        [String]$wacLocalPath = "$sourcePath\WACLatest.msi",

        [String]$azsHCIIsoUri = "https://aka.ms/2CNBagfhSZ8BM7jyEV8I",

        [String]$azsHciVhdPath = "$baseVHDFolderPath\AzSHCI.vhdx",

        [String]$ws2019IsoUri = "https://software-download.microsoft.com/download/pr/17763.737.190906-2324.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us_1.iso",

        [String]$ws2019IsoLocalPath = "$sourcePath\ws2019.iso",

        [String]$ws2019VhdPath = "$baseVHDFolderPath\ws2019.vhdx",

        [String]$wacUri = "https://aka.ms/wacdownload",

        [String]$wacMofUri = "https://raw.githubusercontent.com/yagmurs/AzureStackHCIonAzure/master/helpers/Install-WacUsingChoco.ps1",

        [Int]$azsHostCount = 2,

        [Int]$azsHostDataDiskCount = 3,

        [Int64]$dataDiskSize = 500GB,

        [string]$natPrefix = "AzSHCI",

        [string]$vSwitchNameMgmt = "default",

        [string]$vSwitchNameConverged = "ConvergedSW",

        [string]$HCIvmPrefix = "hpv",

        [string]$wacVMName = "wac"
    ) 
    
    Import-DscResource -ModuleName 'xActiveDirectory'
    Import-DscResource -ModuleName 'xStorage'
    Import-DscResource -ModuleName 'xNetworking'
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'xPendingReboot'
    Import-DscResource -ModuleName 'xHyper-v'
    Import-DscResource -ModuleName 'xPSDesiredStateConfiguration'
    Import-DscResource -module 'xDHCpServer'
    Import-DscResource -Module 'cChoco'
    
    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)
    $Interface=Get-NetAdapter | Where-Object Name -Like "Ethernet*" | Select-Object -First 1
    $InterfaceAlias=$($Interface.Name)

    Node localhost
    {
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            ActionAfterReboot  = 'ContinueConfiguration'
            ConfigurationMode = 'ApplyOnly'
        }

        xWaitforDisk Disk1
        {
            DiskID = 1
            RetryIntervalSec =$RetryIntervalSec
            RetryCount = $RetryCount
        }

        xDisk ADDataDisk 
        {
            DiskID = 1
            DriveLetter = "F"
            DependsOn = "[xWaitForDisk]Disk1"
        }

        xWaitforDisk Disk2
        {
            DiskID = 2
            RetryIntervalSec =$RetryIntervalSec
            RetryCount = $RetryCount
        }

        xDisk hpvDataDisk 
        {
            DiskID = 2
            DriveLetter = $targetDrive
            DependsOn = "[xWaitForDisk]Disk2"
        }

        File "source"
        {
            DestinationPath = $sourcePath
            Type = 'Directory'
            Force = $true
            DependsOn = "[xDisk]hpvDataDisk"
        }

        File "folder-vms"
        {
            Type = 'Directory'
            DestinationPath = $targetVMPath
            DependsOn = "[xDisk]hpvDataDisk"
        }

        File "VM-base"
        {
            Type = 'Directory'
            DestinationPath = $baseVHDFolderPath
            DependsOn = "[File]folder-vms"
        } 
<#
        script "Download Windows Admin Center"
        {
            GetScript = {
                $result = Test-Path -Path $using:wacLocalPath
                return @{ 'Result' = $result }
            }

            SetScript = {
                Start-BitsTransfer -Source $using:wacUri -Destination $using:wacLocalPath           
            }

            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            DependsOn = "[File]source"
        }
 #>
        script "Download Mof for $wacVMName"
        {
            GetScript = {
                $result = Test-Path -Path "$using:sourcePath\Install-WacUsingChoco.ps1"
                return @{ 'Result' = $result }
            }

            SetScript = {
                Start-BitsTransfer -Source "$using:wacMofUri" -Destination "$using:sourcePath\Install-WacUsingChoco.ps1"          
            }

            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            DependsOn = "[File]source"
        }

        script "Download AzureStack HCI bits"
        {
            GetScript = {
                $result = Test-Path -Path $using:azsHCIISOLocalPath
                return @{ 'Result' = $result }
            }

            SetScript = {
                Start-BitsTransfer -Source $using:azsHCIIsoUri -Destination $using:azsHCIISOLocalPath            
            }

            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            DependsOn = "[File]source"
        }

        script "Download Windows Server 2019"
        {
            GetScript = {
                $result = Test-Path -Path $using:ws2019IsoLocalPath
                return @{ 'Result' = $result }
            }

            SetScript = {
                Start-BitsTransfer -Source $using:ws2019IsoUri -Destination $using:ws2019IsoLocalPath            
            }

            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            DependsOn = "[File]source"
        }

        WindowsFeature DNS 
        { 
            Ensure = "Present" 
            Name = "DNS"		
        }

        Script EnableDNSDiags
	    {
      	    SetScript = { 
		        Set-DnsServerDiagnostics -All $true
                Write-Verbose -Verbose "Enabling DNS client diagnostics" 
            }
            GetScript =  { @{} }
            TestScript = { $false }
	        DependsOn = "[WindowsFeature]DNS"
        }

	    WindowsFeature DnsTools
	    {
	        Ensure = "Present"
            Name = "RSAT-DNS-Server"
            DependsOn = "[WindowsFeature]DNS"
	    }

        xDnsServerAddress "DnsServerAddress for $InterfaceAlias"
        { 
            Address        = '127.0.0.1' 
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
	        DependsOn = "[WindowsFeature]DNS"
        }

        WindowsFeature ADDSInstall 
        { 
            Ensure = "Present" 
            Name = "AD-Domain-Services"
	        DependsOn="[WindowsFeature]DNS" 
        } 

        WindowsFeature ADDSTools
        {
            Ensure = "Present"
            Name = "RSAT-ADDS-Tools"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        WindowsFeature ADAdminCenter
        {
            Ensure = "Present"
            Name = "RSAT-AD-AdminCenter"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }
         
        xADDomain FirstDS 
        {
            DomainName = $DomainName
            DomainAdministratorCredential = $DomainCreds
            SafemodeAdministratorPassword = $DomainCreds
            DatabasePath = "F:\NTDS"
            LogPath = "F:\NTDS"
            SysvolPath = "F:\SYSVOL"
	        DependsOn = @("[xDisk]ADDataDisk", "[WindowsFeature]ADDSInstall")
        }

        WindowsFeature "Install DHCPServer"
        {
           Name = 'DHCP'
           Ensure = 'Present'
        }

        WindowsFeature DHCPTools
	    {
	        Ensure = "Present"
            Name = "RSAT-DHCP"
            DependsOn = "[WindowsFeature]Install DHCPServer"
	    }

        WindowsFeature "Hyper-V" 
        {
            Name   = "Hyper-V"
            Ensure = "Present"
        }

        WindowsFeature "RSAT-Hyper-V-Tools" 
        {
            Name = "RSAT-Hyper-V-Tools"
            Ensure = "Present"
            DependsOn = "[WindowsFeature]Hyper-V" 
        }

        WindowsFeature "RSAT-Clustering" 
        {
            Name = "RSAT-Clustering"
            Ensure = "Present"
        }

        xVMHost "hpvHost"
        {
            IsSingleInstance = 'yes'
            EnableEnhancedSessionMode = $true
            VirtualHardDiskPath = $targetVMPath
            VirtualMachinePath = $targetVMPath
            DependsOn = "[WindowsFeature]Hyper-V"
        }

        xVMSwitch "$vSwitchNameMgmt"
        {
            Name = $vSwitchNameMgmt
            Type = "Internal"
            DependsOn = "[WindowsFeature]Hyper-V"
        }

        xVMSwitch "$vSwitchNameConverged"
        {
            Name = $vSwitchNameConverged
            Type = "Internal"
            DependsOn = "[WindowsFeature]Hyper-V"
        }

        xIPAddress "New IP for vEthernet $vSwitchNameMgmt"
        {
            InterfaceAlias = "vEthernet `($vSwitchNameMgmt`)"
            AddressFamily = 'IPv4'
            IPAddress = '192.168.0.1/24'
            DependsOn = "[xVMSwitch]$vSwitchNameMgmt"
        }

        xDnsServerAddress "DnsServerAddress for vEthernet $vSwitchNameMgmt" 
        { 
            Address        = '127.0.0.1' 
            InterfaceAlias = "vEthernet `($vSwitchNameMgmt`)"
            AddressFamily  = 'IPv4'
	        DependsOn = "[xIPAddress]New IP for vEthernet $vSwitchNameMgmt"
        }

        xIPAddress "New IP for vEthernet $vSwitchNameConverged"
        {
            InterfaceAlias = "vEthernet `($vSwitchNameConverged`)"
            AddressFamily = 'IPv4'
            IPAddress = '192.168.100.1/24'
            DependsOn = "[xVMSwitch]$vSwitchNameConverged"
        }

        xDnsServerAddress "DnsServerAddress for vEthernet $vSwitchNameConverged" 
        { 
            Address        = '127.0.0.1' 
            InterfaceAlias = "vEthernet `($vSwitchNameConverged`)"
            AddressFamily  = 'IPv4'
	        DependsOn = "[xIPAddress]New IP for vEthernet $vSwitchNameConverged"
        }

        xDhcpServerAuthorization "Authorize DHCP"
        {
            Ensure = 'Present'
            DependsOn = @('[WindowsFeature]Install DHCPServer')
            DnsName = [System.Net.Dns]::GetHostByName($env:computerName).hostname
            IPAddress = '192.168.100.1'
        }

        xDhcpServerScope "Scope 192.168.0.0" 
        { 
            Ensure = 'Present'
            IPStartRange = '192.168.0.220' 
            IPEndRange = '192.168.0.240' 
            ScopeId = '192.168.0.0'
            Name = 'Management Address Range for VMs on AzSHCI Cluster' 
            SubnetMask = '255.255.255.0' 
            LeaseDuration = '00:08:00' 
            State = 'Active' 
            AddressFamily = 'IPv4'
            DependsOn = @("[WindowsFeature]Install DHCPServer", "[xIPAddress]New IP for vEthernet $vSwitchNameMgmt")
        }

        xDhcpServerScope "Scope 192.168.100.0" 
        { 
            Ensure = 'Present'
            IPStartRange = '192.168.100.21' 
            IPEndRange = '192.168.100.254' 
            ScopeId = '192.168.100.0'
            Name = 'Client Address Range for Nested VMs on AzSHCI Cluster' 
            SubnetMask = '255.255.255.0' 
            LeaseDuration = '00:08:00' 
            State = 'Active' 
            AddressFamily = 'IPv4'
            DependsOn = @("[WindowsFeature]Install DHCPServer", "[xIPAddress]New IP for vEthernet $vSwitchNameConverged")
        }

        xDhcpServerOption "Option" 
        { 
            Ensure = 'Present' 
            ScopeID = '192.168.0.0' 
            DnsDomain = $DomainName 
            DnsServerIPAddress = '192.168.0.1' 
            AddressFamily = 'IPv4' 
            Router = '192.168.0.1'
            DependsOn = @("[WindowsFeature]Install DHCPServer", "[xIPAddress]New IP for vEthernet $vSwitchNameMgmt")
        }

        xDhcpServerOption "Option" 
        { 
            Ensure = 'Present' 
            ScopeID = '192.168.100.0' 
            DnsDomain = $DomainName 
            DnsServerIPAddress = '192.168.100.1' 
            AddressFamily = 'IPv4' 
            Router = '192.168.100.1'
            DependsOn = @("[WindowsFeature]Install DHCPServer", "[xIPAddress]New IP for vEthernet $vSwitchNameConverged")
        }

        script "New Nat rule for Management Network"
        {
            GetScript = {
                $nat = $($using:natPrefix + "-Management")
                $result = if (Get-NetNat -Name $nat -ErrorAction SilentlyContinue) {$true} else {$false}
                return @{ 'Result' = $result }
            }

            SetScript = {
                $nat = $($using:natPrefix + "-Management")
                New-NetNat -Name $nat -InternalIPInterfaceAddressPrefix "192.168.0.0/24"          
            }

            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            DependsOn = "[xIPAddress]New IP for vEthernet $vSwitchNameMgmt"
        }

        script "New Nat rule for Nested Network"
        {
            GetScript = {
                $nat = $($using:natPrefix + "-Nested")
                $result = if (Get-NetNat -Name $nat -ErrorAction SilentlyContinue) {$true} else {$false}
                return @{ 'Result' = $result }
            }

            SetScript = {
                $nat = $($using:natPrefix + "-Nested")
                New-NetNat -Name $nat -InternalIPInterfaceAddressPrefix "192.168.100.0/24"          
            }

            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            DependsOn = "[xIPAddress]New IP for vEthernet $vSwitchNameConverged"
        }

        script "prepareVHDX"
        {
            GetScript = {
                $result = Test-Path -Path $using:azsHciVhdPath
                return @{ 'Result' = $result }
            }

            SetScript = {
                #Create Azure Stack HCI Host Image
                Convert-Wim2Vhd -DiskLayout UEFI -SourcePath $using:azsHCIISOLocalPath -Path $using:azsHciVhdPath -Size 100B -Dynamic -Index 1 -ErrorAction SilentlyContinue
                #Enable Hyper-v role on the Azure Stack HCI Host Image
                Install-WindowsFeature -Vhd $using:azsHciVhdPath -Name Hyper-V
            }

            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            DependsOn = "[file]VM-Base", "[script]Download AzureStack HCI bits"
        }

        script "prepareVHDX ws2019"
        {
            GetScript = {
                $result = Test-Path -Path $using:ws2019VhdPath
                return @{ 'Result' = $result }
            }

            SetScript = {
                Convert-Wim2Vhd -DiskLayout UEFI -SourcePath $using:ws2019IsoLocalPath -Path $using:ws2019VhdPath -Size 100GB -Dynamic -Index 1 -ErrorAction SilentlyContinue
            }

            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            DependsOn = "[file]VM-Base", "[script]Download Windows Server 2019"
        }

        for ($i = 1; $i -lt $azsHostCount + 1; $i++)
        {
            $suffix = '{0:D2}' -f $i
            $vmname = $($HCIvmPrefix + $suffix)
            $ipAddressManagement = $("192.168.0.1" + $suffix)
            $ipAddressNic1 = $("192.168.254.1" + $suffix)
            $ipAddressNic2 = $("192.168.255.1" + $suffix)

            file "VM-Folder-$vmname"
            {
                Ensure = 'Present'
                DestinationPath = "$targetVMPath\$vmname"
                Type = 'Directory'
                DependsOn = "[File]folder-vms"
            }
            
            xVhd "NewOSDisk-$vmname"
            {
                Ensure           = 'Present'
                Name             = "$vmname-OSDisk.vhdx"
                Path             = "$targetVMPath\$vmname"
                Generation       = 'vhdx'
                ParentPath       = $azsHciVhdPath
                Type             = 'Differencing'
                DependsOn = "[xVMSwitch]$vSwitchNameMgmt", "[script]prepareVHDX", "[file]VM-Folder-$vmname"
            }

            xVMHyperV "VM-$vmname"
            {
                Ensure          = 'Present'
                Name            = $vmname
                VhdPath         = "$targetVMPath\$vmname\$vmname-OSDisk.vhdx"
                Path            = $targetVMPath
                Generation      = 2
                StartupMemory   = 10GB
                ProcessorCount  = 4
                DependsOn       = "[xVhd]NewOSDisk-$vmname"
            }

            xVMProcessor "Enable NestedVirtualization-$vmname"
            {
                VMName = $vmname
                ExposeVirtualizationExtensions = $true
                DependsOn = "[xVMHyperV]VM-$vmname"
            }
<#
            xVMNetworkAdapter "remove default Network Adapter on VM-$vmname"
            {
                Ensure = 'Absent'
                Id = "Network Adapter"
                Name = "Network Adapter"
                SwitchName = $vSwitchNameMgmt
                VMName = $vmName
                DependsOn = "[xVMHyperV]VM-$vmname"
            }
#>
            script "remove default Network Adapter on VM-$vmname"
            {
                GetScript = {
                    $VMNetworkAdapter = Get-VMNetworkAdapter -VMName $using:vmname -Name 'Network Adapter' -ErrorAction SilentlyContinue
                    $result = if ($VMNetworkAdapter) {$false} else {$true}
                    return @{
                        VMName = $VMNetworkAdapter.VMName
                        Name = $VMNetworkAdapter.Name
                        Result = $result
                    }
                }
    
                SetScript = {
                    $state = [scriptblock]::Create($GetScript).Invoke()
                    Remove-VMNetworkAdapter -VMName $state.VMName -Name $state.Name                 
                }
    
                TestScript = {
                    # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                    $state = [scriptblock]::Create($GetScript).Invoke()
                    return $state.Result
                }
                DependsOn = "[xVMHyperV]VM-$vmname"
            }

            xVMNetworkAdapter "New Network Adapter Management VM-$vmname"
            {
                Id = "$vmname-Management"
                Name = "$vmname-Management"
                SwitchName = $vSwitchNameMgmt
                VMName = $vmname
                NetworkSetting = xNetworkSettings {
                    IpAddress = $ipAddressManagement
                    Subnet = "255.255.255.0"
                    DefaultGateway = "192.168.0.1"
                    DnsServer = "192.168.0.1"
                }
                Ensure = 'Present'
                DependsOn = "[xVMHyperV]VM-$vmname"
            }

            xVMNetworkAdapter "New Network Adapter Converged $('VM-' + $vmname + '-Nic1')"
            {
                Id = "$vmname-Converged-Nic1"
                Name = "$vmname-Converged-Nic1"
                SwitchName = $vSwitchNameConverged
                VMName = $vmname
                NetworkSetting = xNetworkSettings {
                    IpAddress = $ipAddressNic1
                    Subnet = "255.255.255.0"
                }
                Ensure = 'Present'
                DependsOn = "[xVMHyperV]VM-$vmname"
            }

            xVMNetworkAdapter "New Network Adapter Converged $('VM-' + $vmname + '-Nic2')"
            {
                Id = "$vmname-Converged-Nic2"
                Name = "$vmname-Converged-Nic2"
                SwitchName = $vSwitchNameConverged
                VMName = $vmname
                NetworkSetting = xNetworkSettings {
                    IpAddress = $ipAddressNic2
                    Subnet = "255.255.255.0"
                }
                Ensure = 'Present'
                DependsOn = "[xVMHyperV]VM-$vmname"
            }

            script "Enable $('VM-' + $vmname + '-Nic1') Mac address spoofing"
            {
                GetScript = {
                    $VMNetworkAdapter = Get-VMNetworkAdapter -VMName $using:vmname -Name $using:vmname-Converged-Nic1
                    $result = if ($VMNetworkAdapter.MacAddressSpoofing -eq 'on') {$true} else {$false}
                    return @{
                        MacAddressSpoofing = $VMNetworkAdapter.MacAddressSpoofing
                        VMName = $VMNetworkAdapter.VMName
                        Name = $VMNetworkAdapter.Name
                        Result = $result
                    }
                }
    
                SetScript = {
                    $state = [scriptblock]::Create($GetScript).Invoke()
                    Set-VMNetworkAdapter -VMName $state.VMName -Name $state.Name -MacAddressSpoofing on                  
                }
    
                TestScript = {
                    # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                    $state = [scriptblock]::Create($GetScript).Invoke()
                    return $state.Result
                }
                DependsOn = "[xVMNetworkAdapter]New Network Adapter Converged $('VM-' + $vmname + '-Nic1')"
            }

            script "Enable $('VM-' + $vmname + '-Nic2') Mac address spoofing"
            {
                GetScript = {
                    $VMNetworkAdapter = Get-VMNetworkAdapter -VMName $using:vmname -Name $using:vmname-Converged-Nic2
                    $result = if ($VMNetworkAdapter.MacAddressSpoofing -eq 'on') {$true} else {$false}
                    return @{
                        MacAddressSpoofing = $VMNetworkAdapter.MacAddressSpoofing
                        VMName = $VMNetworkAdapter.VMName
                        Name = $VMNetworkAdapter.Name
                        Result = $result
                    }
                }
    
                SetScript = {
                    $state = [scriptblock]::Create($GetScript).Invoke()
                    Set-VMNetworkAdapter -VMName $state.VMName -Name $state.Name -MacAddressSpoofing on                  
                }
    
                TestScript = {
                    # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                    $state = [scriptblock]::Create($GetScript).Invoke()
                    return $state.Result
                }
                DependsOn = "[xVMNetworkAdapter]New Network Adapter Converged $('VM-' + $vmname + '-Nic2')"
            }

            for ($j = 1; $j -lt $azsHostDataDiskCount + 1 ; $j++)
            { 
                xvhd "$vmname-DataDisk$j"
                {
                    Ensure           = 'Present'
                    Name             = "$vmname-DataDisk$j.vhdx"
                    Path             = "$targetVMPath\$vmname"
                    Generation       = 'vhdx'
                    Type             = 'Dynamic'
                    MaximumSizeBytes = $dataDiskSize
                    DependsOn        = "[xVMHyperV]VM-$vmname"
                }
            
                xVMHardDiskDrive "$vmname-DataDisk$j"
                {
                    VMName = $vmname
                    ControllerType = 'SCSI'
                    ControllerLocation = $j
                    Path = "$targetVMPath\$vmname\$vmname-DataDisk$j.vhdx"
                    Ensure = 'Present'
                    DependsOn = "[xVMHyperV]VM-$vmname"
                }
            }

            script "UnattendXML for $vmname"
            {
                GetScript = {
                    $name = $using:VmName
                    $result = Test-Path -Path "$using:targetVMPath\$name\Unattend.xml"
                    return @{ 'Result' = $result }
                }

                SetScript = {
                    try 
                    {
                        $name = $using:VmName
                        $mount = Mount-VHD -Path "$using:targetVMPath\$name\$name-OSDisk.vhdx" -Passthru -ErrorAction Stop
                        Start-Sleep -Seconds 2
                        $driveLetter = $mount | Get-Disk | Get-Partition | Get-Volume | Where-Object DriveLetter | Select-Object -ExpandProperty DriveLetter
                        
                        New-Item -Path $("$driveLetter" + ":" + "\Temp") -ItemType Directory -Force -ErrorAction Stop
                        
                        New-BasicUnattendXML -ComputerName $name -LocalAdministratorPassword $using:Admincreds.Password -OutputPath "$using:targetVMPath\$name" -Force -ErrorAction Stop

                        Copy-Item -Path "$using:targetVMPath\$name\Unattend.xml" -Destination $("$driveLetter" + ":" + "\Windows\system32\SysPrep") -Force -ErrorAction Stop

                        #New-UnattendXml -Path $("$driveLetter" + ":" + "\Windows\system32\SysPrep\Unattend.xml") -ComputerName $name -enableAdministrator -AdminCredential $using:Admincreds -UserAccount $using:Admincreds
                        #New-UnattendXml -Path "$using:targetVMPath\$name\Unattend.xml" -ComputerName $name -enableAdministrator -AdminCredential $using:Admincreds -UserAccount $using:Admincreds
                        Start-Sleep -Seconds 2
                    }
                    finally 
                    {
                        DisMount-VHD -Path "$using:targetVMPath\$name\$name-OSDisk.vhdx"
                    }
                    
                    Start-VM -Name $name
                }

                TestScript = {
                    # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                    $state = [scriptblock]::Create($GetScript).Invoke()
                    return $state.Result
                }
                DependsOn = "[xVhd]NewOSDisk-$vmname"
            }
        }

        file "VM-Folder-$wacVMName"
        {
            Ensure = 'Present'
            DestinationPath = "$targetVMPath\$wacVMName"
            Type = 'Directory'
            DependsOn = "[File]folder-vms"
        }
        
        xVhd "NewOSDisk-$wacVMName"
        {
            Ensure           = 'Present'
            Name             = "$wacVMName-OSDisk.vhdx"
            Path             = "$targetVMPath\$wacVMName"
            Generation       = 'vhdx'
            ParentPath       = $ws2019VhdPath
            Type             = 'Differencing'
            DependsOn = "[xVMSwitch]$vSwitchNameMgmt", "[script]prepareVHDX ws2019", "[file]VM-Folder-$wacVMName"
        }

        xVMHyperV "VM-$wacVMName"
        {
            Ensure          = 'Present'
            Name            = $wacVMName
            VhdPath         = "$targetVMPath\$wacVMName\$wacVMName-OSDisk.vhdx"
            Path            = $targetVMPath
            Generation      = 2
            StartupMemory   = 4GB
            ProcessorCount  = 2
            DependsOn       = "[xVhd]NewOSDisk-$wacVMName"
        }
        
        xVMNetworkAdapter "remove default Network Adapter on VM-$wacVMName"
        {
            Ensure = 'Absent'
            Id = "Network Adapter"
            Name = "Network Adapter"
            SwitchName = $vSwitchNameMgmt
            VMName = $wacVMName
            DependsOn = "[xVMHyperV]VM-$wacVMName"
        }

        xVMNetworkAdapter "New Network Adapter Management for VM-$wacVMName"
        {
            Id = "$wacVMName-Management"
            Name = "$wacVMName-Management"
            SwitchName = $vSwitchNameMgmt
            VMName = $wacVMName
            NetworkSetting = xNetworkSettings {
                IpAddress = "192.168.0.100"
                Subnet = "255.255.255.0"
                DefaultGateway = "192.168.0.1"
                DnsServer = "192.168.0.1"
            }
            Ensure = 'Present'
            DependsOn = "[xVMHyperV]VM-$wacVMName"
        }

        Script "UnattendXML for $wacVMName"
        {
            GetScript = {
                $name = $using:wacVMName
                $result = Test-Path -Path "$using:targetVMPath\$name\Unattend.xml"
                return @{ 'Result' = $result }
            }

            SetScript = {
                try 
                {
                    $name = $using:wacVMName
                    $mount = Mount-VHD "$using:targetVMPath\$name\$name-OSDisk.vhdx" -Passthru -ErrorAction Stop
                    Start-Sleep -Seconds 2
                    $driveLetter = $mount | Get-Disk | Get-Partition | Get-Volume | Where-Object DriveLetter | Select-Object -ExpandProperty DriveLetter
                    
                    New-Item -Path $("$driveLetter" + ":" + "\Temp") -ItemType Directory -Force -ErrorAction Stop
                    Copy-Item -Path "$using:sourcePath\Install-WacUsingChoco.ps1" -Destination $("$driveLetter" + ":" + "\Temp") -Force -ErrorAction Stop

                    New-BasicUnattendXML -ComputerName $name -LocalAdministratorPassword $($using:Admincreds).Password -Domain $using:DomainName -Username $using:Admincreds.Username `
                    -Password $($using:Admincreds).Password -JoinDomain $using:DomainName -AutoLogonCount 1 -OutputPath "$using:targetVMPath\$name" -Force `
                    -IpCidr "192.168.0.100/24" -DnsServer '192.168.0.1' -NicNameForIPandDNSAssignments 'Ethernet' -PowerShellScriptFullPath 'c:\temp\Install-WacUsingChoco.ps1' -ErrorAction Stop
                    
                    Copy-Item -Path "$using:targetVMPath\$name\Unattend.xml" -Destination $("$driveLetter" + ":" + "\Windows\system32\SysPrep") -Force -ErrorAction Stop
                    
                    #New-UnattendXml -Path $("$driveLetter" + ":" + "\Windows\system32\SysPrep\Unattend.xml") -ComputerName $name -enableAdministrator -AdminCredential $using:Admincreds -UserAccount $using:Admincreds
                    #New-UnattendXml -Path "$using:targetVMPath\$name\Unattend.xml" -ComputerName $name -enableAdministrator -AdminCredential $using:Admincreds -UserAccount $using:Admincreds
                    #Copy-Item -Path "$using:sourcePath\pending.mof" -Destination $("$driveLetter" + ":" + "\Windows\system32\Configuration\pending.mof") -Force
                    
                    Copy-Item -Path "C:\Program Files\WindowsPowerShell\Modules\cChoco" -Destination $("$driveLetter" + ":" + "\Program Files\WindowsPowerShell\Modules") -Recurse -Force -ErrorAction Stop

                    Start-Sleep -Seconds 2
                    
                }
                finally
                {
                    DisMount-VHD "$using:targetVMPath\$name\$name-OSDisk.vhdx"
                }
                
                Start-VM -Name $name
            }

            TestScript = {
                # Create and invoke a scriptblock using the $GetScript automatic variable, which contains a string representation of the GetScript.
                $state = [scriptblock]::Create($GetScript).Invoke()
                return $state.Result
            }
            DependsOn = "[xVhd]NewOSDisk-$wacVMName", "[script]Download Mof for $wacVMName"
        }

        cChocoInstaller InstallChoco
        {
            InstallDir = "c:\choco"
        }

        cChocoFeature allowGlobalConfirmation 
        {

            FeatureName = "allowGlobalConfirmation"
            Ensure      = 'Present'
            DependsOn   = '[cChocoInstaller]installChoco'
        }

        cChocoFeature useRememberedArgumentsForUpgrades 
        {

            FeatureName = "useRememberedArgumentsForUpgrades"
            Ensure      = 'Present'
            DependsOn   = '[cChocoInstaller]installChoco'
        }

        cChocoPackageInstaller "Install Chromium Edge"
        {
            Name        = 'microsoft-edge'
            Ensure      = 'Present'
            AutoUpgrade = $true
            DependsOn   = '[cChocoInstaller]installChoco'
        }
    }
}