param vNetName string = 'AzureStackvNet'
param vNetAddressPrefix string = '10.255.254.0/23'
param location string = resourceGroup().location
param managementSubnetName string = 'Management-Subnet'
param smbSubnetName string = 'SMB-Subnet'
param managementSubnetAddressPrefix string = '10.255.254.0/24'
param smbSubnetAddressPrefix string = '10.255.255.0/24'
param dnsServer string = 'usevnetdefaults'
param managementNsg string = 'management-nsg'
param smbNsg string = 'smb-nsg'


resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: vNetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vNetAddressPrefix
      ]
    }
    dhcpOptions: {
      dnsServers: dnsServer == 'usevnetdefaults' ? null : [
        dnsServer
      ]
    }
    subnets: [
      {
        name: managementSubnetName
        properties: {
          addressPrefix: managementSubnetAddressPrefix
          networkSecurityGroup:{
            id: resourceId(resourceGroup().name, 'Microsoft.Network/networkSecurityGroups', managementNsg)
          }
        }
      }
      {
        name: smbSubnetName
        properties: {
          addressPrefix: smbSubnetAddressPrefix
          networkSecurityGroup:{
            id: resourceId(resourceGroup().name, 'Microsoft.Network/networkSecurityGroups', smbNsg)
          }
        }
      }
    ]
  }
  dependsOn: [
    
  ]
}
