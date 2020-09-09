
<#PSScriptInfo

.VERSION 1.0

.GUID

.AUTHOR AzureAutomationTeam

.COMPANYNAME Microsoft

.COPYRIGHT

.TAGS AzureAutomation Utility

.LICENSEURI

.PROJECTURI https://github.com/azureautomation/runbooks/blob/master/Utility/Remove-ResourceGroups.ps1

.ICONURI

.EXTERNALMODULEDEPENDENCIES

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES

#>

#Requires -Module Azure
#Requires -Module AzureRM.Profile
#Requires -Module AzureRM.Resources

<#
.SYNOPSIS
  Connects to Azure and removes all resource groups which match the name filter

.DESCRIPTION
  This runbook connects to Azure and removes all resource groups which match the name filter.
  You can run across multiple subscriptions, delete all resource groups, or run in preview mode.
  Warning: This will delete all resources, including child resources in a group when preview mode is set to $false.

  REQUIRED AUTOMATION ASSETS
    Authorization to targeted Azure subscriptions using one of the following options:
        Option 1: An Automation credential asset that contains the Azure AD user credential.
        Option 2: An Automation connection asset that contains the Azure AD service principal.

.PARAMETER ActionType
  Mandatory.
  The specific action to take for either keeping assets that match the name filter and deleting everything else or deleting just those assets that match the name filter.
  Valid values are KEEP, DELETE, and DELETEALL.
    - KEEP = Delete everything except resource groups that match the name filter
    - DELETE = Delete only resource groups that match the name filter
    - DELETEALL = Delete all resource groups

.PARAMETER SubscriptionIds
  Mandatory
  Allows you to specify the targeted subscription id(s) for removal of resource groups.
  Pass multiple subscripription ids through a comma separated list.

.PARAMETER NameFilter
  Optional
  Allows you to specify a name filter to limit the resource groups that you will KEEP or DELETE.
  Pass multiple name filters through a comma separated list.
  The filter is not case sensitive and will match any resource group that contains the string.

.PARAMETER PreviewMode
  Optional with default of $true.
  Execute the runbook to see which resource groups would be deleted but take no action.

.EXAMPLE
    Remove-ResourceGroups `
        -AuthenticationType ServicePrincipal `
        -AuthenticationAssetName AzureRunAsConnection `
        -ActionType DELETE `
        -SubscriptionIds abcd1234-567e-8f9a-1a2b-3c4de5fa6b78,bbcd1234-567e-8f9a-1a2b-3c4de5fa6b78 `
        -NameFilter removeme,removemetoo

.NOTES
    AUTHOR: System Center Automation Team
    LASTEDIT: August 8, 2016
#>

workflow RRG
{
	param(
		[parameter(Mandatory = $false)]
		[string]$NameFilter,

		[parameter(Mandatory = $false)]
		[bool]$PreviewMode = $true
	)


	# Returns strings with status messages
	[OutputType([String])]

	$VerbosePreference = 'Continue'

	if ($NameFilter) {
		$nameFilterList = $NameFilter.Split(',')
		[regex]$nameFilterRegex = ‘(‘ + (($nameFilterList | foreach {[regex]::escape($_.ToLower())}) –join “|”) + ‘)’
	}

  # Connect to ServicePrincipal
  $ServicePrincipalConnection = Get-AutomationConnection -Name "AzureRunAsConnection"

  Add-AzureRmAccount -ServicePrincipal `
       -TenantId $servicePrincipalConnection.TenantId `
       -ApplicationId $servicePrincipalConnection.ApplicationId `
       -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint

  # Use same subscription as ServicePrincipal
  $subscriptionId = $ServicePrincipalConnection.SubscriptionID

	# Begin loop through each subscription

	try {
		# Select the subscription, if not found, skip resource group removal
		Write-Verbose "Attempting connection to subscription: $subscriptionId"
		Set-AzureRMContext -SubscriptionId $subscriptionId -ErrorAction Stop -ErrorVariable err
		if($err) {
			Write-Error "Subscription not found: $subscriptionId."
			throw $err
		}
		else {
			Write-Verbose "Successful connection to subscription: $subscriptionId"
			# Find resource groups to remove based on passed in name filter and KEEP, DELETE, or DELEETALL action
			$groupsToRemove = Get-AzureRmResourceGroup | `
								? { $nameFilterList.Count -eq 0 -or $_.ResourceGroupName.ToLower() -match $nameFilterRegex }

			# No matching groups were found to remove
			if ($groupsToRemove.Count -eq 0) {
				Write-Output "No matching resource groups found for subscription: $($subscriptionId)"
			}
			# Matching groups were found to remove
			else
			{
				# In preview mode, output what would take place but take no action
				if ($PreviewMode -eq $true) {
					Write-Output "Preview Mode: The following resource groups would be removed for subscription: $($subscriptionId)"
					foreach ($group in $groupsToRemove){
					Write-Output $($group.ResourceGroupName)
					}
					Write-Output "Preview Mode: The following resources would be removed:"
					$resources = (Get-AzureRmResource | foreach {$_} | Where-Object {$groupsToRemove.ResourceGroupName.Contains($_.ResourceGroupName)})
					foreach ($resource in $resources) {
						Write-Output $resource
					}
				}
				# Remove the resource groups in parallel
				else {
					Write-Output "Preparing to remove resource groups in parallel for subscription: $($subscriptionId)"
					Write-Output "The following resources will be removed:"
					$resources = (Get-AzureRmResource | foreach {$_} | Where-Object {$groupsToRemove.ResourceGroupName.Contains($_.ResourceGroupName)})
					foreach ($resource in $resources) {
						Write-Output $resource
					}
					foreach -parallel ($resourceGroup in $groupsToRemove) {
						Write-Output "Starting to remove resource group: $($resourceGroup.ResourceGroupName)"
						Remove-AzureRmResourceGroup -Name $($resourceGroup.ResourceGroupName) -Force
						if ((Get-AzureRmResourceGroup -Name $($resourceGroup.ResourceGroupName) -ErrorAction SilentlyContinue) -eq $null) {
							Write-Output "...successfully removed resource group: $($resourceGroup.ResourceGroupName)"
						}
					}
				}
				Write-Output "Completed."
			}
		}
    }
		catch {
			$errorMessage = $_
		}
		if ($errorMessage) {
			Write-Error $errorMessage
		}
}
