function Cleanup-VMs
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$false)]
        [Switch]
        $AzureStackHciHostVMs,

        [Parameter(Mandatory=$false)]
        [Switch]
        $WindowsAdminCenterVM,

        [Parameter(Mandatory=$false)]
        [Switch]
        $RedeployDeletedVMs
    )

    Begin
    {
        #initializing variables
        $AzureStackHCIHosts = Get-VM hpv*
        $domainName = (Get-ADDomain).DnsRoot
        $dhcpScopeString = '192.168.0.0'

    }
    Process
    {
        if ($AzureStackHciHostVMs)
        {
            $AzureStackHCIClusterName = 'Hci01'
            $AzureStackHCIHosts = Get-VM "hpv*"

            Write-Verbose "[Cleanup-VMs]: Removing Azure Stack HCI hosts and related DHCP, DNS records"
            #remove Azure Stack HCI hosts
            $AzureStackHCIHosts | Stop-VM -TurnOff -Passthru | Remove-VM -Force
            Remove-Item -Path $AzureStackHCIHosts.ConfigurationLocation -Recurse -Force

            #remove Azure Stack HCI hosts DNS records, DHCP leases and Disable Computer Accounts
            $AzureStackHCIHosts.Name | ForEach-Object {Get-DnsServerResourceRecord -ZoneName $domainName -Name $_ -ErrorAction SilentlyContinue | Remove-DnsServerResourceRecord -ZoneName $domainName -Force}
            $AzureStackHCIHosts.Name | ForEach-Object {Get-DhcpServerv4Lease -ScopeId $dhcpScopeString -ErrorAction SilentlyContinue | Where-Object hostname -like $_* | Remove-DhcpServerv4Lease}
            $AzureStackHCIHosts.Name | ForEach-Object {Set-ADComputer -Identity $_ -Enabled $false -ErrorAction SilentlyContinue}
            Set-ADComputer -Identity $AzureStackHCIClusterName -Enabled $false -ErrorAction SilentlyContinue
            
        }

        if ($WindowsAdminCenterVM)
        {
            $wac = Get-VM wac
            Write-Verbose "[Cleanup-VMs]: Removing Windows Center VM and related DHCP, DNS records"
            #remove Windows Admin Center host
            $wac | Stop-VM -TurnOff -Passthru | Remove-VM -Force
            Remove-Item -Path $wac.ConfigurationLocation -Recurse -Force
            
            #remove Windows Admin Center host DNS record, DHCP lease
            Get-DnsServerResourceRecord -ZoneName $domainName -Name $wac.Name -ErrorAction SilentlyContinue | Remove-DnsServerResourceRecord -ZoneName $domainName -Force
            Get-DhcpServerv4Lease -ScopeId $dhcpScopeString -ErrorAction SilentlyContinue | Where-Object hostname -like $wac.Name | Remove-DhcpServerv4Lease
        }

        if ($RedeployDeletedVMs)
        {
            Write-Verbose "[Cleanup-VMs]: Recalling DSC config to restore default state"
            Start-DscConfiguration -UseExisting -Wait -Force
        }

    }
    End
    {
    }
}

Function Configure-AzsHciClusterRoles
{
    [CmdletBinding()]

    Param
    (
    )

    begin 
    {
        #initializing variables
        $AzureStackHCIHosts = Get-VM hpv*
        
        #Enable Roles 
        $rolesToEnable = @("File-Services", "FS-FileServer", "FS-Data-Deduplication", "BitLocker", "Data-Center-Bridging", "EnhancedStorage", "Failover-Clustering", "RSAT", "RSAT-Feature-Tools", "RSAT-DataCenterBridging-LLDP-Tools", "RSAT-Clustering", "RSAT-Clustering-PowerShell", "RSAT-Role-Tools", "RSAT-AD-Tools", "RSAT-AD-PowerShell", "RSAT-Hyper-V-Tools", "Hyper-V-PowerShell")
        $rolesToDisable = @("telnet-client")

        #new PsSession to 
        $psSession = New-PSSession -ComputerName $AzureStackHCIHosts.Name
    }

    process
    {
        Write-Verbose "Enabling/Disabling Roles and Features required on Azure Stack HCI Hosts"
        Invoke-Command -Session $psSession -ScriptBlock {
            $VerbosePreference=$using:VerbosePreference
            if ($using:rolesToEnable.Count -gt 0)
            {
                Write-Verbose "Installing following required roles/features to Azure Stack HCI hosts"
                $using:rolesToEnable | Write-Verbose
                Install-WindowsFeature -Name $using:rolesToEnable
            }
    
            if ($using:rolesToDisable.Count -gt 0)
            {
                Write-Verbose "Removing following unnecessary roles/features from Azure Stack HCI hosts"
                $using:rolesToDisable | Write-Verbose
                Remove-WindowsFeature -Name $using:rolesToDisable
            }
        }
            
    }
    
    end
    {
        Remove-PSSession -Session $psSession
        Remove-Variable -Name psSession
    }   
}

Function Configure-AzsHciClusterNetwork
{

    [CmdletBinding(DefaultParameterSetName='Configure', SupportsShouldProcess=$true)]
    param (
    
        [Parameter(ParameterSetName='Configure')]
        [Parameter(Mandatory=$false)]
        [ValidateSet("HighAvailable","SingleAdapter","Dummy")]
        [string]
        $ManagementInterfaceConfig = "HighAvailable",

        [Parameter(ParameterSetName='Configure')]
        [Parameter(Mandatory=$false)]
        [ValidateSet("OneVirtualSwitchforAllTraffic","OneVirtualSwitchforComputeOnly","TwoVirtualSwitches","Dummy")]
        [string]
        $ComputeAndStorageInterfaceConfig = "OneVirtualSwitchforAllTraffic",

        [Parameter(ParameterSetName='Cleanup')]
        [Parameter(Mandatory=$false)]
        [switch]
        $CleanupConfiguration,

        [Parameter(ParameterSetName='Configure')]
        [Parameter(Mandatory=$false)]
        [switch]
        $ForceCleanup
    )

    begin 
    {
        #initializing variables
        $AzureStackHCIHosts = Get-VM hpv*
        $vSwitchNameMgmt = 'Management'
        $vSwitchNameConverged = "ConvergedSwitch"
        $vSwitchNameCompute = "ComputeSwitch"
        $vSwitchNameStorage = "StorageSwitch"

        #Enable Roles 
        $rolesToEnable = @("File-Services", "FS-FileServer", "FS-Data-Deduplication", "BitLocker", "Data-Center-Bridging", "EnhancedStorage", "Failover-Clustering", "RSAT", "RSAT-Feature-Tools", "RSAT-DataCenterBridging-LLDP-Tools", "RSAT-Clustering", "RSAT-Clustering-PowerShell", "RSAT-Role-Tools", "RSAT-AD-Tools", "RSAT-AD-PowerShell", "RSAT-Hyper-V-Tools", "Hyper-V-PowerShell")
        $rolesToDisable = @()

        Clear-DnsClientCache

        #Disable DHCP Scope to prevent IP address from DHCP
        Set-DhcpServerv4Scope -ScopeId 192.168.100.0 -State InActive

        #new PsSession to 
        $psSession = New-PSSession -ComputerName $AzureStackHCIHosts.Name
    }

    process
    {
        if ($cleanupConfiguration)
        {
            Write-Verbose "[Cleanup]: Current network configuration"
            Invoke-Command -Session $psSession -ScriptBlock {
            $vSwitch = Get-VMSwitch
            $VerbosePreference=$using:VerbosePreference
            Write-Verbose "[Cleanup]: Following vSwitch/es will be removed from Azure Stack HCI hosts"
            
            if ($vSwitch)
            {
                $vSwitch.Name | Write-Verbose                
            }

            if ($vSwitch.Name -contains $using:vSwitchNameMgmt)
            {
                Write-Warning -Message "[Cleanup]: $env:COMPUTERNAME Network connection will be interupted for couple of minutes, be patient"
                    
            }
            $vSwitch | Remove-VMSwitch -Force
        }

            Clear-DnsClientCache

            Write-Verbose "[Cleanup]: Scramble Nic names to prevent name conflict"
            Invoke-Command -Session $psSession -ScriptBlock {
                $i = get-random -Minimum 100000 -max 999999
                Get-NetAdapter | foreach {Rename-NetAdapter -Name $_.Name -NewName $i; $i++}
            }

            Invoke-Command -Session $psSession -ScriptBlock {
                $adapter = Get-NetAdapter | Where-Object status -eq "disabled"
                $VerbosePreference=$using:VerbosePreference
                if ($adapter)
                {
                    Write-Verbose "[Cleanup]: Following adapters will be enabled on Azure Stack HCI hosts"
                    $adapter.Name | Write-Verbose
                    $adapter | Enable-NetAdapter -Confirm:$false -Passthru
                }
            }
        
            Write-Verbose "[Cleanup]: Recalling DSC config to restore default state"
        
            Start-DscConfiguration -UseExisting -Wait -Verbose:$false
        
        }
        else
        {
            $state = Invoke-Command -Session $psSession -ScriptBlock {
                Get-NetAdapter -Name Management*
            }
            if ($ForceCleanup)
            {
                Write-Warning "Current configuration detected! ForceCleanup switch Enabled. Cleaning up"
                Configure-AzsHciClusterNetwork -CleanupConfiguration
            }
            elseif ($state)
            {
                Write-Warning "Current configuration detected! Cleanup required"
                
                Write-Host "Continue cleanup ? Continue without cleanup, recommended though 'n'o!!! Default action is cleanup. : " -Foregroundcolor Yellow -Nonewline
                $continue = Read-Host 
                if ($continue -ne 'n' )
                {
                    Configure-AzsHciClusterNetwork -CleanupConfiguration
                }
                else
                {
                    Write-Warning "Current configuration detected however no Cleanup option is selected. You may face some errors"
                    Write-Warning "Sleep for 10 seconds to make sure it is not accidentialy entered. You can break execution using 'Crtl + C' to cancel configuration"
                    Start-Sleep 10
                }
            }
            
            #Configure Management Network adapters

            switch ($ManagementInterfaceConfig) {
                "HighAvailable" {
                    Write-Verbose "[Configure ManagementInterfaceConfig]: HighAvailable - Configuring Management Interface"
                    Write-Warning -Message "[Configure ManagementInterfaceConfig]: Network connection will be interupted for couple of minutes, be patient"
                    Invoke-Command -Session $psSession -ScriptBlock {
                        $ipConfig = (
                            Get-NetAdapter -Physical | Get-NetAdapterBinding | Where-Object {$_.enabled -eq $true -and $_.DisplayName -eq 'Internet Protocol Version 4 (TCP/IPv4)'} | 
                                Get-NetIPConfiguration | Where-Object IPv4DefaultGateway | Sort-Object IPv4Address
                        )
                        $netAdapters = Get-NetAdapter -Name ($ipConfig.InterfaceAlias)
                        $VerbosePreference=$using:VerbosePreference
                        
                        $newAdapterNames = @()
                        for ($i = 1; $i -lt $netAdapters.count + 1; $i++)
                        {
                            $netAdapterName = $netAdapters[$i - 1].Name
                            
                            if ($netAdapterName -ne $($using:vSwitchNameMgmt + " $i"))
                            {
                                $newAdapterNames += $($using:vSwitchNameMgmt + " $i")
                                Rename-NetAdapter -Name $netAdapterName -NewName $($using:vSwitchNameMgmt + " $i")
                            }
                        }


                        #try to suppress error message
                        New-VMSwitch -Name $using:vSwitchNameMgmt -AllowManagementOS $true -NetAdapterName $newAdapterNames -EnableEmbeddedTeaming $true
                        Rename-NetAdapter -Name "vEthernet `($using:vSwitchNameMgmt`)" -NewName $using:vSwitchNameMgmt

                        
                    }
                }
                "SingleAdapter" {
                    Write-Verbose "[Configure ManagementInterfaceConfig]: SingleAdapter - Configuring Management Interface"
                    Invoke-Command -Session $psSession -ScriptBlock {
                        $ipConfig = (
                            Get-NetAdapter -Physical | Get-NetAdapterBinding | Where-Object {$_.enabled -eq $true -and $_.DisplayName -eq 'Internet Protocol Version 4 (TCP/IPv4)'} | 
                                Get-NetIPConfiguration | Where-Object IPv4DefaultGateway | Sort-Object IPv4Address
                        )
                        $netAdapters = Get-NetAdapter -Name ($ipConfig.InterfaceAlias)
                        $VerbosePreference=$using:VerbosePreference
                        Rename-NetAdapter -Name "$($netAdapters[0].Name)" -NewName $($using:vSwitchNameMgmt + " 1") 
                        Rename-NetAdapter -Name "$($netAdapters[1].Name)" -NewName $($using:vSwitchNameMgmt + " 2") 
                        Disable-NetAdapter -Name $($using:vSwitchNameMgmt + " 2") -Confirm:$false
                    }
                }
            }

            #Configure Compute And Storage Network adapters

            switch ($ComputeAndStorageInterfaceConfig) {
                "OneVirtualSwitchforAllTraffic" {
                    Write-Verbose "[Configure ComputeAndStorageInterfaces]: OneVirtualSwitchforAllTraffic - Configuring ComputeAndStorageInterfaces"
                    Invoke-Command -Session $psSession -ScriptBlock {
                        $ipConfig = (
                            Get-NetAdapter -Physical | Where-Object status -ne disabled | Get-NetAdapterBinding | Where-Object {$_.enabled -eq $true -and $_.DisplayName -eq 'Internet Protocol Version 4 (TCP/IPv4)'} | 
                                Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway -eq $null -and $_.IPv4Address.Ipaddress -like "192.168.25*"} | Sort-Object IPv4Address
                        )
                        $netAdapters = Get-NetAdapter -Name ($ipConfig.InterfaceAlias)
                        $VerbosePreference=$using:VerbosePreference
                        
                        New-VMSwitch -Name $using:vSwitchNameConverged -NetAdapterName $netAdapters.Name -EnableEmbeddedTeaming $true -AllowManagementOS $false
                        
                        for ($i = 1; $i -lt $netAdapters.Count + 1; $i++)
                        {
                            $adapterName = "smb " + $i
                            Add-VMNetworkAdapter -ManagementOS -SwitchName $using:vSwitchNameConverged -Name $adapterName
                            $vNic = Rename-NetAdapter -Name "vEthernet `($adapterName`)" -NewName $adapterName -PassThru
                            $pNic = Rename-NetAdapter -Name $netAdapters[$i - 1].Name -NewName $($using:vSwitchNameConverged + " $i") -PassThru
                            New-NetIPAddress -IPAddress $ipconfig[$i - 1].ipv4Address.Ipaddress -InterfaceAlias $vNic.Name -AddressFamily IPv4 -PrefixLength $ipconfig[$i - 1].ipv4Address.prefixlength | Out-Null
                            $sleep = 5
                            do
                            {
                                Write-Verbose "Waiting for NICs $($vNic.Name) and $($pNic.Name) to come 'up' for $sleep seconds"
                                Start-Sleep -Seconds $sleep
                            }
                            
                            until ((Get-NetAdapter -Name $vNic.Name | Where-Object status -eq "up") -and (Get-NetAdapter -Name $pNic.Name | Where-Object status -eq "up"))
                            Write-Verbose "Setting up $($vNic.Name) and $($pNic.Name) for VMNetworkAdapterTeamMapping"
                            Set-VMNetworkAdapterTeamMapping -ManagementOS -VMNetworkAdapterName $vnic.Name -PhysicalNetAdapterName $pNic.Name
                            
                        } 
                    }
                }
                "OneVirtualSwitchforComputeOnly" {
                    Write-Verbose "[Configure ComputeAndStorageInterfaces]: OneVirtualSwitchforComputeOnly - Configuring ComputeAndStorageInterfaces"
                    Invoke-Command -Session $psSession -ScriptBlock {
                        
                        $ipConfigCompute = (
                            Get-NetAdapter -Physical | Where-Object status -ne disabled | Get-NetAdapterBinding | ? {$_.enabled -eq $true -and $_.DisplayName -eq 'Internet Protocol Version 4 (TCP/IPv4)'} | 
                                Get-NetIPConfiguration | Where-Object {($_.IPv4DefaultGateway -eq $null) -and ($_.IPv4Address.Ipaddress -like "192.168.251.*" -or $_.IPv4Address.Ipaddress -like "192.168.252.*")} | 
                                Sort-Object IPv4Address
                        )
                        $netAdaptersCompute = Get-NetAdapter -Name ($ipConfigCompute.InterfaceAlias)
                        
                        $ipConfigStorage = (
                            Get-NetAdapter -Physical | Where-Object status -ne disabled | Get-NetAdapterBinding | ? {$_.enabled -eq $true -and $_.DisplayName -eq 'Internet Protocol Version 4 (TCP/IPv4)'} | 
                            Get-NetIPConfiguration | Where-Object {($_.IPv4DefaultGateway -eq $null) -and ($_.IPv4Address.Ipaddress -like "192.168.253.*" -or $_.IPv4Address.Ipaddress -like "192.168.254.*")} | 
                            Sort-Object IPv4Address
                        )                        
                        #$ipConfigStorage = (Get-NetAdapter -Physical | Where-Object status -ne disabled | Get-NetIPConfiguration | Where-Object {($_.IPv4DefaultGateway -eq $null) -and ($_.IPv4Address.Ipaddress -like "192.168.253.*" -or $_.IPv4Address.Ipaddress -like "192.168.254.*")})
                        $netAdaptersStorage = Get-NetAdapter -Name ($ipConfigStorage.InterfaceAlias)
                        
                        $VerbosePreference=$using:VerbosePreference
                        
                        Write-Verbose "[New SET switch]: $($using:vSwitchNameCompute) with following members"
                        Write-Verbose "$($netAdaptersCompute.Name)"

                        New-VMSwitch -Name $using:vSwitchNameCompute -NetAdapterName $netAdaptersCompute.Name -EnableEmbeddedTeaming $true -AllowManagementOS $false
                        
                        for ($i = 1; $i -lt $netAdaptersCompute.Count + 1; $i++){
                            Write-Verbose "[Rename NIC]: $($netAdaptersCompute[$i - 1].Name) to $($using:vSwitchNameCompute + " $i")"
                            $pNic = Rename-NetAdapter -Name $netAdaptersCompute[$i - 1].Name -NewName $($using:vSwitchNameCompute + " $i") -PassThru
                            
                        }

                        for ($i = 1; $i -lt $netAdaptersStorage.Count + 1; $i++)
                        { 
                            $adapterName = "smb " + $i
                            Write-Verbose "[Rename NIC]: $($netAdaptersStorage[$i - 1].Name) to $adapterName"
                            $pNic = Rename-NetAdapter -Name $netAdaptersStorage[$i - 1].Name -NewName $adapterName -PassThru
                            
                        }
                    }
                }
                "TwoVirtualSwitches" {
                    Write-Verbose "[Configure ComputeAndStorageInterfaces]: TwoVirtualSwitches - Configuring ComputeAndStorageInterfaces"
                    Invoke-Command -Session $psSession -ScriptBlock {
                        
                        $ipConfigCompute = (
                            Get-NetAdapter -Physical | Where-Object status -ne disabled | Get-NetAdapterBinding | Where-Object {$_.enabled -eq $true -and $_.DisplayName -eq 'Internet Protocol Version 4 (TCP/IPv4)'} | 
                                Get-NetIPConfiguration | Where-Object {($_.IPv4DefaultGateway -eq $null) -and ($_.IPv4Address.Ipaddress -like "192.168.251.*" -or $_.IPv4Address.Ipaddress -like "192.168.252.*")} | 
                                Sort-Object IPv4Address
                        )
                        $netAdaptersCompute = Get-NetAdapter -Name ($ipConfigCompute.InterfaceAlias)
                        
                        $ipConfigStorage = (
                            Get-NetAdapter -Physical | Where-Object status -ne disabled | Get-NetAdapterBinding | ? {$_.enabled -eq $true -and $_.DisplayName -eq 'Internet Protocol Version 4 (TCP/IPv4)'} | 
                            Get-NetIPConfiguration | Where-Object {($_.IPv4DefaultGateway -eq $null) -and ($_.IPv4Address.Ipaddress -like "192.168.253.*" -or $_.IPv4Address.Ipaddress -like "192.168.254.*")} | 
                            Sort-Object IPv4Address
                        )
                        $netAdaptersStorage = Get-NetAdapter -Name ($ipConfigStorage.InterfaceAlias)
                        
                        $VerbosePreference=$using:VerbosePreference
                        
                        Write-Verbose "[New SET switch]: $($using:vSwitchNameCompute) with following members"
                        
                        New-VMSwitch -Name $using:vSwitchNameCompute -NetAdapterName $netAdaptersCompute.Name -EnableEmbeddedTeaming $true -AllowManagementOS $false
                        
                        for ($i = 1; $i -lt $netAdaptersCompute.Count + 1; $i++)
                        {
                            Write-Verbose "[Rename NIC]: $($netAdaptersCompute[$i - 1].Name) to $adapterName"
                            $pNic = Rename-NetAdapter -Name $netAdaptersCompute[$i - 1].Name -NewName $($using:vSwitchNameCompute + " $i") -PassThru
                        }
                        
                        Write-Verbose "[New SET switch]: $($using:vSwitchNameStorage) with following members"
                        
                        New-VMSwitch -Name $using:vSwitchNameStorage -NetAdapterName $netAdaptersStorage.Name -EnableEmbeddedTeaming $true -AllowManagementOS $false
                        
                        for ($i = 1; $i -lt $netAdaptersStorage.Count + 1; $i++)
                        { 
                            $adapterName = "smb " + $i
                            Add-VMNetworkAdapter -ManagementOS -SwitchName $using:vSwitchNameStorage -Name $adapterName
                            #Start-Sleep 4
                            
                            Write-Verbose "[Rename NIC]: $($netAdaptersStorage[$i - 1].Name) to $adapterName"

                            $vNic = Rename-NetAdapter -Name "vEthernet `($adapterName`)" -NewName $adapterName -PassThru
                            $pNic = Rename-NetAdapter -Name $netAdaptersStorage[$i - 1].Name -NewName $($using:vSwitchNameStorage + " $i") -PassThru
                            New-NetIPAddress -IPAddress $ipConfigStorage[$i - 1].ipv4Address.Ipaddress -InterfaceAlias $vNic.Name -AddressFamily IPv4 -PrefixLength $ipConfigStorage[$i - 1].ipv4Address.prefixlength | Out-Null
                            $sleep = 5
                            do
                            {
                                Write-Verbose "Waiting for NICs $($vNic.Name) and $($pNic.Name) to come 'up' for $sleep seconds"
                                Start-Sleep -Seconds $sleep
                            }
                            until ((Get-NetAdapter -Name $vNic.Name | Where-Object status -eq "up") -and (Get-NetAdapter -Name $pNic.Name | Where-Object status -eq "up"))
                            Write-Verbose "Setting up vNIC: $($vNic.Name) and pNIC: $($pNic.Name) for VMNetworkAdapterTeamMapping"
                            Set-VMNetworkAdapterTeamMapping -ManagementOS -VMNetworkAdapterName $vnic.Name -PhysicalNetAdapterName $pNic.Name
                            
                        }
                    }
                }
            }
            
        }
    }
    end
    {
        #Re-Enable DHCP Scope

        Set-DhcpServerv4Scope -ScopeId 192.168.100.0 -State Active
        Remove-PSSession -Session $psSession
        Remove-Variable -Name psSession
    }
}

function Erase-AzsHciClusterDisks
{
    [CmdletBinding()]

    Param
    (
    )

    Begin
    {
        #initializing variables
        $AzureStackHCIHosts = Get-VM hpv*

        $psSession = New-PSSession -ComputerName $AzureStackHCIHosts.Name
    }

    Process
    {
        Write-Verbose "Cleaning up previously configured S2D Disks"
        Invoke-Command -Session $psSession -ScriptBlock {
            Update-StorageProviderCache
            Get-StoragePool | Where-Object IsPrimordial -eq $false | Set-StoragePool -IsReadOnly:$false -ErrorAction SilentlyContinue
            Get-StoragePool | Where-Object IsPrimordial -eq $false | Get-VirtualDisk | Remove-VirtualDisk -Confirm:$false -ErrorAction SilentlyContinue
            Get-StoragePool | Where-Object IsPrimordial -eq $false | Remove-StoragePool -Confirm:$false -ErrorAction SilentlyContinue
            Get-PhysicalDisk | Reset-PhysicalDisk -ErrorAction SilentlyContinue
            Get-Disk | Where-Object Number -ne $null | Where-Object IsBoot -ne $true | Where-Object IsSystem -ne $true | Where-Object PartitionStyle -ne RAW | Forech-Object {
                $_ | Set-Disk -isoffline:$false
                $_ | Set-Disk -isreadonly:$false
                $_ | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false
                $_ | Set-Disk -isreadonly:$true
                $_ | Set-Disk -isoffline:$true
            }
            Get-Disk | Where-Object Number -Ne $Null | Where-Object IsBoot -Ne $True | Where-Object IsSystem -Ne $True | Where-Object PartitionStyle -Eq RAW | Group -NoElement -Property FriendlyName
        } | Sort-Object -Property PsComputerName, Count
    }

    End
    {
        Remove-PSSession -Session $psSession
        Remove-Variable -Name psSession
    }
}

function Setup-AzsHciCluster
{
    [CmdletBinding()]
    Param
    (
        # Param1 help description
        [Parameter(Mandatory=$true)]
        $ClusterName
    )

    Begin
    {
        #initializing variables
        $AzureStackHCIHosts = Get-VM hpv*

        $cimSession = New-CimSession -ComputerName $AzureStackHCIHosts.Name
       
    }

    Process
    {
        
        <#
        Write-Verbose "Start testing cluster"
        Invoke-Command -ComputerName $AzureStackHCIHosts[0].Name -Authentication Credssp -Credential $cred -ScriptBlock {
           $VerbosePreference=$using:VerbosePreference
            Test-Cluster â€“Node $using:AzureStackHCIHosts.Name â€“Include "Storage Spaces Direct", "Inventory", "Network", "System Configuration" -Cluster $ClusterName
            Test-Cluster â€“Node $AzureStackHCIHosts.Name â€“Include "Storage Spaces Direct", "Inventory", "Network", "System Configuration" -Cluster $ClusterName
        }
        #>

        Write-Verbose "Enabling Cluster using name: $ClusterName"
        New-Cluster -Name $ClusterName -Node $AzureStackHCIHosts.Name -NoStorage -Force
        Write-Verbose "Enabling Storage Spaces Direct on Cluster: $ClusterName"
        Enable-ClusterStorageSpacesDirect -PoolFriendlyName "Cluster Storage Pool" -CimSession $cimSession -Confirm:$false -SkipEligibilityChecks -ErrorAction SilentlyContinue
    }

    End
    {
        #clean up variables
        Remove-CimSession -CimSession $cimSession
        Remove-Variable -Name cimSession
    }
}
