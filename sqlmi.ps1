[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$subscriptionId,
    [Parameter(Mandatory)]
    [string]$resourceGroupName,
    [Parameter(Mandatory)]
    [string]$location,
    [Parameter(Mandatory=$false)]
    [string]$primaryNetworkName = "default"
)

$subscriptionId = ""

$azureAplicationId = ""
$azureTenantId = ""
$azurePassword = ConvertTo-SecureString ".password" -AsPlainText -Force

$randomIdentifier = $(Get-Random)
$environment = "dev"

$resourceGroupName = "test-sqlmi-rg"
$location = "westus2"
$primaryInstance = "primarysqlmi-instance28934"

#SQL MI tier data
$edition = "Business Critical"
$vCores = 8
$maxStorage = 512
$computeGeneration = "Gen5"
$license = "LicenseIncluded"

$pscredential = New-Object -TypeName System.Management.Automation.PSCredential($azureAplicationId, $azurePassword)
Connect-AzAccount -ServicePrincipal -Credential $pscredential -Tenant $azureTenantId

#Admin Login and Password
$secpasswd = "PWD27!"+(New-Guid).Guid | ConvertTo-SecureString -AsPlainText -Force
$mycreds = New-Object System.Management.Automation.PSCredential ("azureuser", $secpasswd)

Set-AzContext -SubscriptionId $subscriptionId

# Get Subscription Name
$subscription = Get-AzSubscription -SubscriptionId $subscriptionId | Select-Object -ExpandProperty Name

# Check if resource group exist
$resourceGroup = Get-AzResourceGroup -Name $resourceGroupName -Location $location

# If not create a new one
if(!$resourceGroup){
    $resourceGroup = New-AzResourceGroup -Name $resourceGroupName -Location $location
}

#Check if VNET exist
$primaryVnet = Get-AzVirtualNetwork -Name $primaryNetworkName -ResourceGroupName $resourceGroupName

# If not existing,create a new one
if(!$primaryVnet -or ($primaryNetworkName -eq "default")){
    $primaryVnet = @{
        Name = "vnet-$environment-$location"
        ResourceGroupName = $resourceGroupName
        Location = $location
        AddressPrefix = "10.0.0.0/16"
    }
    
    $primaryVirtualNetwork = New-AzVirtualNetwork @primaryVnet
    
    $primarySubnet = @{
        Name = "snet-$subscription-$environment-01"
        VirtualNetwork = $primaryVirtualNetwork
        AddressPrefix = "10.0.0.0/24"
    }
    
    $primarySubnetConfig = Add-AzVirtualNetworkSubnetConfig @primarySubnet
    
    $primaryVirtualNetwork | Set-AzVirtualNetwork

    $nsg = @{
        Name = "nsg-$subscription-01"
        ResourceGroupName = $resourceGroupName
        Location = $location
    }
    
    $primaryNSG = New-AzNetworkSecurityGroup @nsg
    
    $primaryRouteTableMiManagementService = New-AzRouteTable `
                          -Name 'primaryRouteTableMiManagementService' `
                          -ResourceGroupName $resourceGroupName `
                          -location $location
    $primaryRouteTableMiManagementService
    
    Set-AzVirtualNetworkSubnetConfig -Name $primarySubnet.Name `
                                     -VirtualNetwork $primaryVirtualNetwork `
                                     -NetworkSecurityGroup $primaryNSG `
                                     -AddressPrefix $primarySubnet.AddressPrefix `
                                     -RouteTable $primaryRouteTableMiManagementService | Set-AzVirtualNetwork
    
    
    $primaryVirtualNetwork = Get-AzVirtualNetwork -Name $primaryVNet.Name -ResourceGroupName $resourceGroupName
    $primaryMiSubnetConfig = Get-AzVirtualNetworkSubnetConfig -Name $primarySubnet.Name -VirtualNetwork $primaryVirtualNetwork
    $primaryMiSubnetConfig = Add-AzDelegation -Name "myDelegation" -ServiceName "Microsoft.Sql/managedInstances" -Subnet $primaryMiSubnetConfig
    Set-AzVirtualNetwork -VirtualNetwork $primaryVirtualNetwork
    
    $primarySubnetConfigId = $primaryMiSubnetConfig.Id
    
    Get-AzNetworkSecurityGroup `
                          -ResourceGroupName $resourceGroupName `
                          -Name $nsg.Name `
                        | Add-AzNetworkSecurityRuleConfig `
                          -Priority 100 `
                          -Name "allow_management_inbound" `
                          -Access Allow `
                          -Protocol Tcp `
                          -Direction Inbound `
                          -SourcePortRange * `
                          -SourceAddressPrefix * `
                          -DestinationPortRange 9000,9003,1438,1440,1452 `
                          -DestinationAddressPrefix * `
                        | Add-AzNetworkSecurityRuleConfig `
                          -Priority 200 `
                          -Name "allow_misubnet_inbound" `
                          -Access Allow `
                          -Protocol * `
                          -Direction Inbound `
                          -SourcePortRange * `
                          -SourceAddressPrefix $primarySubnet.AddressPrefix `
                          -DestinationPortRange * `
                          -DestinationAddressPrefix * `
                        | Add-AzNetworkSecurityRuleConfig `
                          -Priority 300 `
                          -Name "allow_health_probe_inbound" `
                          -Access Allow `
                          -Protocol * `
                          -Direction Inbound `
                          -SourcePortRange * `
                          -SourceAddressPrefix AzureLoadBalancer `
                          -DestinationPortRange * `
                          -DestinationAddressPrefix * `
                        | Add-AzNetworkSecurityRuleConfig `
                          -Priority 1000 `
                          -Name "allow_tds_inbound" `
                          -Access Allow `
                          -Protocol Tcp `
                          -Direction Inbound `
                          -SourcePortRange * `
                          -SourceAddressPrefix VirtualNetwork `
                          -DestinationPortRange 1433 `
                          -DestinationAddressPrefix * `
                        | Add-AzNetworkSecurityRuleConfig `
                          -Priority 1100 `
                          -Name "allow_redirect_inbound" `
                          -Access Allow `
                          -Protocol Tcp `
                          -Direction Inbound `
                          -SourcePortRange * `
                          -SourceAddressPrefix VirtualNetwork `
                          -DestinationPortRange 11000-11999 `
                          -DestinationAddressPrefix * `
                        | Add-AzNetworkSecurityRuleConfig `
                          -Priority 1200 `
                          -Name "allow_geodr_inbound" `
                          -Access Allow `
                          -Protocol Tcp `
                          -Direction Inbound `
                          -SourcePortRange * `
                          -SourceAddressPrefix VirtualNetwork `
                          -DestinationPortRange 5022 `
                          -DestinationAddressPrefix * `
                        | Add-AzNetworkSecurityRuleConfig `
                          -Priority 4096 `
                          -Name "deny_all_inbound" `
                          -Access Deny `
                          -Protocol * `
                          -Direction Inbound `
                          -SourcePortRange * `
                          -SourceAddressPrefix * `
                          -DestinationPortRange * `
                          -DestinationAddressPrefix * `
                        | Add-AzNetworkSecurityRuleConfig `
                          -Priority 100 `
                          -Name "allow_management_outbound" `
                          -Access Allow `
                          -Protocol Tcp `
                          -Direction Outbound `
                          -SourcePortRange * `
                          -SourceAddressPrefix * `
                          -DestinationPortRange 80,443,12000 `
                          -DestinationAddressPrefix * `
                        | Add-AzNetworkSecurityRuleConfig `
                          -Priority 200 `
                          -Name "allow_misubnet_outbound" `
                          -Access Allow `
                          -Protocol * `
                          -Direction Outbound `
                          -SourcePortRange * `
                          -SourceAddressPrefix * `
                          -DestinationPortRange * `
                          -DestinationAddressPrefix $primarySubnet.AddressPrefix `
                        | Add-AzNetworkSecurityRuleConfig `
                          -Priority 1100 `
                          -Name "allow_redirect_outbound" `
                          -Access Allow `
                          -Protocol Tcp `
                          -Direction Outbound `
                          -SourcePortRange * `
                          -SourceAddressPrefix VirtualNetwork `
                          -DestinationPortRange 11000-11999 `
                          -DestinationAddressPrefix $primarySubnet.AddressPrefix `
                        | Add-AzNetworkSecurityRuleConfig `
                          -Priority 1200 `
                          -Name "allow_geodr_outbound" `
                          -Access Allow `
                          -Protocol Tcp `
                          -Direction Outbound `
                          -SourcePortRange * `
                          -SourceAddressPrefix VirtualNetwork `
                          -DestinationPortRange 5022 `
                          -DestinationAddressPrefix $primarySubnet.AddressPrefix `
                        | Add-AzNetworkSecurityRuleConfig `
                          -Priority 4096 `
                          -Name "deny_all_outbound" `
                          -Access Deny `
                          -Protocol * `
                          -Direction Outbound `
                          -SourcePortRange * `
                          -SourceAddressPrefix * `
                          -DestinationPortRange * `
                          -DestinationAddressPrefix * `
                        | Set-AzNetworkSecurityGroup
    
    Get-AzRouteTable `
                          -ResourceGroupName $resourceGroupName `
                          -Name "primaryRouteTableMiManagementService" `
                        | Add-AzRouteConfig `
                          -Name "primaryToMIManagementService" `
                          -AddressPrefix 0.0.0.0/0 `
                          -NextHopType Internet `
                        | Add-AzRouteConfig `
                          -Name "ToLocalClusterNode" `
                          -AddressPrefix $primarySubnet.AddressPrefix `
                          -NextHopType VnetLocal `
                        | Set-AzRouteTable
}

# $nsg = @{
#     Name = "primary-sqlmi-nsg"
#     ResourceGroupName = $resourceGroupName
#     Location = $location
# }

# $primaryNSG = New-AzNetworkSecurityGroup @nsg

# $primaryRouteTableMiManagementService = New-AzRouteTable `
#                       -Name 'primaryRouteTableMiManagementService' `
#                       -ResourceGroupName $resourceGroupName `
#                       -location $location
# $primaryRouteTableMiManagementService

# Set-AzVirtualNetworkSubnetConfig -Name $primarySubnet.Name `
#                                  -VirtualNetwork $primaryVirtualNetwork `
#                                  -NetworkSecurityGroup $primaryNSG `
#                                  -AddressPrefix $primarySubnet.AddressPrefix `
#                                  -RouteTable $primaryRouteTableMiManagementService | Set-AzVirtualNetwork


# $primaryVirtualNetwork = Get-AzVirtualNetwork -Name $primaryVNet.Name -ResourceGroupName $resourceGroupName
# $primaryMiSubnetConfig = Get-AzVirtualNetworkSubnetConfig -Name $primarySubnet.Name -VirtualNetwork $primaryVirtualNetwork
# $primaryMiSubnetConfig = Add-AzDelegation -Name "myDelegation" -ServiceName "Microsoft.Sql/managedInstances" -Subnet $primaryMiSubnetConfig
# Set-AzVirtualNetwork -VirtualNetwork $primaryVirtualNetwork

# $primarySubnetConfigId = $primaryMiSubnetConfig.Id

# Get-AzNetworkSecurityGroup `
#                       -ResourceGroupName $resourceGroupName `
#                       -Name $nsg.Name `
#                     | Add-AzNetworkSecurityRuleConfig `
#                       -Priority 100 `
#                       -Name "allow_management_inbound" `
#                       -Access Allow `
#                       -Protocol Tcp `
#                       -Direction Inbound `
#                       -SourcePortRange * `
#                       -SourceAddressPrefix * `
#                       -DestinationPortRange 9000,9003,1438,1440,1452 `
#                       -DestinationAddressPrefix * `
#                     | Add-AzNetworkSecurityRuleConfig `
#                       -Priority 200 `
#                       -Name "allow_misubnet_inbound" `
#                       -Access Allow `
#                       -Protocol * `
#                       -Direction Inbound `
#                       -SourcePortRange * `
#                       -SourceAddressPrefix $primarySubnet.AddressPrefix `
#                       -DestinationPortRange * `
#                       -DestinationAddressPrefix * `
#                     | Add-AzNetworkSecurityRuleConfig `
#                       -Priority 300 `
#                       -Name "allow_health_probe_inbound" `
#                       -Access Allow `
#                       -Protocol * `
#                       -Direction Inbound `
#                       -SourcePortRange * `
#                       -SourceAddressPrefix AzureLoadBalancer `
#                       -DestinationPortRange * `
#                       -DestinationAddressPrefix * `
#                     | Add-AzNetworkSecurityRuleConfig `
#                       -Priority 1000 `
#                       -Name "allow_tds_inbound" `
#                       -Access Allow `
#                       -Protocol Tcp `
#                       -Direction Inbound `
#                       -SourcePortRange * `
#                       -SourceAddressPrefix VirtualNetwork `
#                       -DestinationPortRange 1433 `
#                       -DestinationAddressPrefix * `
#                     | Add-AzNetworkSecurityRuleConfig `
#                       -Priority 1100 `
#                       -Name "allow_redirect_inbound" `
#                       -Access Allow `
#                       -Protocol Tcp `
#                       -Direction Inbound `
#                       -SourcePortRange * `
#                       -SourceAddressPrefix VirtualNetwork `
#                       -DestinationPortRange 11000-11999 `
#                       -DestinationAddressPrefix * `
#                     | Add-AzNetworkSecurityRuleConfig `
#                       -Priority 1200 `
#                       -Name "allow_geodr_inbound" `
#                       -Access Allow `
#                       -Protocol Tcp `
#                       -Direction Inbound `
#                       -SourcePortRange * `
#                       -SourceAddressPrefix VirtualNetwork `
#                       -DestinationPortRange 5022 `
#                       -DestinationAddressPrefix * `
#                     | Add-AzNetworkSecurityRuleConfig `
#                       -Priority 4096 `
#                       -Name "deny_all_inbound" `
#                       -Access Deny `
#                       -Protocol * `
#                       -Direction Inbound `
#                       -SourcePortRange * `
#                       -SourceAddressPrefix * `
#                       -DestinationPortRange * `
#                       -DestinationAddressPrefix * `
#                     | Add-AzNetworkSecurityRuleConfig `
#                       -Priority 100 `
#                       -Name "allow_management_outbound" `
#                       -Access Allow `
#                       -Protocol Tcp `
#                       -Direction Outbound `
#                       -SourcePortRange * `
#                       -SourceAddressPrefix * `
#                       -DestinationPortRange 80,443,12000 `
#                       -DestinationAddressPrefix * `
#                     | Add-AzNetworkSecurityRuleConfig `
#                       -Priority 200 `
#                       -Name "allow_misubnet_outbound" `
#                       -Access Allow `
#                       -Protocol * `
#                       -Direction Outbound `
#                       -SourcePortRange * `
#                       -SourceAddressPrefix * `
#                       -DestinationPortRange * `
#                       -DestinationAddressPrefix $primarySubnet.AddressPrefix `
#                     | Add-AzNetworkSecurityRuleConfig `
#                       -Priority 1100 `
#                       -Name "allow_redirect_outbound" `
#                       -Access Allow `
#                       -Protocol Tcp `
#                       -Direction Outbound `
#                       -SourcePortRange * `
#                       -SourceAddressPrefix VirtualNetwork `
#                       -DestinationPortRange 11000-11999 `
#                       -DestinationAddressPrefix $primarySubnet.AddressPrefix `
#                     | Add-AzNetworkSecurityRuleConfig `
#                       -Priority 1200 `
#                       -Name "allow_geodr_outbound" `
#                       -Access Allow `
#                       -Protocol Tcp `
#                       -Direction Outbound `
#                       -SourcePortRange * `
#                       -SourceAddressPrefix VirtualNetwork `
#                       -DestinationPortRange 5022 `
#                       -DestinationAddressPrefix $primarySubnet.AddressPrefix `
#                     | Add-AzNetworkSecurityRuleConfig `
#                       -Priority 4096 `
#                       -Name "deny_all_outbound" `
#                       -Access Deny `
#                       -Protocol * `
#                       -Direction Outbound `
#                       -SourcePortRange * `
#                       -SourceAddressPrefix * `
#                       -DestinationPortRange * `
#                       -DestinationAddressPrefix * `
#                     | Set-AzNetworkSecurityGroup

# Get-AzRouteTable `
#                       -ResourceGroupName $resourceGroupName `
#                       -Name "primaryRouteTableMiManagementService" `
#                     | Add-AzRouteConfig `
#                       -Name "primaryToMIManagementService" `
#                       -AddressPrefix 0.0.0.0/0 `
#                       -NextHopType Internet `
#                     | Add-AzRouteConfig `
#                       -Name "ToLocalClusterNode" `
#                       -AddressPrefix $primarySubnet.AddressPrefix `
#                       -NextHopType VnetLocal `
#                     | Set-AzRouteTable


$primaryInstanceState = Get-AzSqlInstance -Name $primaryInstance -ResourceGroupName $resourceGroupName

if(!$primaryInstanceState){
  Write-host "Creating primary SQL Managed Instance..."
  Write-host "This will take some time, see https://docs.microsoft.com/azure/sql-database/sql-database-managed-instance#managed-instance-management-operations or more information."
    New-AzSqlInstance -Name $primaryInstance `
                      -ResourceGroupName $resourceGroupName `
                      -Location $location `
                      -SubnetId $primarySubnetConfigId `
                      -AdministratorCredential $mycreds `
                      -StorageSizeInGB $maxStorage `
                      -VCore $vCores `
                      -Edition $edition `
                      -ComputeGeneration $computeGeneration `
                      -LicenseType $license
} else {
    Write-Host "Instance $primaryInstance already exists"
}

