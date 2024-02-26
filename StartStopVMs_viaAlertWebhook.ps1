<#
.SYNOPSIS
  Starts or stops tagged or all VMs via Azure Alert Webhooks

.DESCRIPTION
  This runbook starts or stops tagged or all VMs via Azure Alert Webhooks. Uses Managed Identity for Authentication. Useful for cases where Azure Autoscale cannot be used.  

.PARAMETER Action 
   Required
   "Start" or "Stop" action to be executed on defined VMs

.PARAMETER TagName 
   Optional
   Tag Name of the VMs to be considered. E.g. "ServerGroup"
   Requires TagValue

.PARAMETER ServiceName
   Optional
   Value of the VM Tag defined by TagName. E.g. "Group1"

.NOTES
   ORIGINAL AUTHOR: Haidar Suhaimi - mohdhaidar@gmail.com
   COMMENTS: Based on the "Stop / Start all or only tagged Azure VMs" runbook by Farouk Friha, and information from the article https://learn.microsoft.com/en-us/azure/automation/automation-create-alert-triggered-runbook
#>

param
(
    [Parameter (Mandatory=$false)]
    [object] $WebhookData,
	
    [Parameter(Mandatory=$true)]  
    [String] $Action,

    [Parameter(Mandatory=$false)]  
    [String] $TagName,

    [Parameter(Mandatory=$false)]
    [String] $TagValue
)

if ($WebhookData)
{
	# Get the data object from WebhookData
	$WebhookBody = (ConvertFrom-Json -InputObject $WebhookData.RequestBody)

	# Get the info needed to identify the VM (depends on the payload schema)
	$schemaId = $WebhookBody.schemaId
	Write-Output "schemaId: $schemaId" -Verbose
	if ($schemaId -eq "azureMonitorCommonAlertSchema") {
		# This is the common Metric Alert schema (released March 2019)
		$Essentials = [object] ($WebhookBody.data).essentials
		# Get the first target only as this script doesn't handle multiple
		$alertTargetIdArray = (($Essentials.alertTargetIds)[0]).Split("/")
		$SubId = ($alertTargetIdArray)[2]
		$ResourceGroupName = ($alertTargetIdArray)[4]
		$ResourceType = ($alertTargetIdArray)[6] + "/" + ($alertTargetIdArray)[7]
		$ResourceName = ($alertTargetIdArray)[-1]
		$status = $Essentials.monitorCondition
	}
	elseif ($schemaId -eq "AzureMonitorMetricAlert") {
		# This is the near-real-time Metric Alert schema
		$AlertContext = [object] ($WebhookBody.data).context
		$SubId = $AlertContext.subscriptionId
		$ResourceGroupName = $AlertContext.resourceGroupName
		$ResourceType = $AlertContext.resourceType
		$ResourceName = $AlertContext.resourceName
		$status = ($WebhookBody.data).status
	}
	elseif ($schemaId -eq "Microsoft.Insights/activityLogs") {
		# This is the Activity Log Alert schema
		$AlertContext = [object] (($WebhookBody.data).context).activityLog
		$SubId = $AlertContext.subscriptionId
		$ResourceGroupName = $AlertContext.resourceGroupName
		$ResourceType = $AlertContext.resourceType
		$ResourceName = (($AlertContext.resourceId).Split("/"))[-1]
		$status = ($WebhookBody.data).status
	}
	elseif ($schemaId -eq $null) {
		# This is the original Metric Alert schema
		$AlertContext = [object] $WebhookBody.context
		$SubId = $AlertContext.subscriptionId
		$ResourceGroupName = $AlertContext.resourceGroupName
		$ResourceType = $AlertContext.resourceType
		$ResourceName = $AlertContext.resourceName
		$status = $WebhookBody.status
	}
	else {
		# Schema not supported
		Write-Error "The alert data schema - $schemaId - is not supported."
	}

	Write-Output "status: $status" -Verbose
	if (($status -eq "Activated") -or ($status -eq "Fired"))
	{
		## Authentication
		Write-Output ""
		Write-Output "------------------------ Authentication ------------------------"
		Write-Output "Logging into Azure ..."

		try
		{
			Write-Output "Disable-AzContextAutosave.."
			# Ensures you do not inherit an AzContext in your runbook
			Disable-AzContextAutosave -Scope Process

			Write-Output "Connect-AzAccount.."
			# Connect to Azure with system-assigned managed identity
			$AzureContext = (Connect-AzAccount -Identity).context

			Write-Output "Set-AzContext.."
			# set and store context
			$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext

			Write-Output "Successfully logged into Azure." 
		} 
		catch
		{
			if (!$Conn)
			{
				throw $ErrorMessage
			} 
			else
			{
				Write-Error -Message $_.Exception
				throw $_.Exception
			}
		}
		## End of authentication

		Write-Output "resourceType: $ResourceType" -Verbose
		Write-Output "resourceName: $ResourceName" -Verbose
		Write-Output "resourceGroupName: $ResourceGroupName" -Verbose
		Write-Output "subscriptionId: $SubId" -Verbose

		## Getting all virtual machines
		Write-Output ""
		Write-Output ""
		Write-Output "---------------------------- Status ----------------------------"
		Write-Output "Getting all virtual machines from all resource groups ..."

		try
		{
			Write-Output "Tag: $TagName"
			if ($TagName)
			{                    
				$instances = Get-AzResource -TagName $TagName -TagValue $TagValue -ResourceType "Microsoft.Compute/virtualMachines"
				
				if ($instances)
				{
					Write-Output "Instances found"
					$resourceGroupsContent = @()
								   
					foreach ($instance in $instances)
					{
						$instancePowerState = (((Get-AzVM -ResourceGroupName $($instance.ResourceGroupName) -Name $($instance.Name) -Status).Statuses.Code[1]) -replace "PowerState/", "")

						$resourceGroupContent = New-Object -Type PSObject -Property @{
							"Resource group name" = $($instance.ResourceGroupName)
							"Instance name" = $($instance.Name)
							"Instance type" = (($instance.ResourceType -split "/")[0].Substring(10))
							"Instance state" = ([System.Threading.Thread]::CurrentThread.CurrentCulture.TextInfo.ToTitleCase($instancePowerState))
							$TagName = $TagValue
						}
						Write-Output "Instance : " + $instance.Name
						$resourceGroupsContent += $resourceGroupContent
					}
				}
				else
				{
						Write-Output "No Instances found"
				}            
			}
			else
			{
				$instances = Get-AzResource -ResourceType "Microsoft.Compute/virtualMachines"

				if ($instances)
				{
					$resourceGroupsContent = @()
			  
					 foreach ($instance in $instances)
					{
						$instancePowerState = (((Get-AzVM -ResourceGroupName $($instance.ResourceGroupName) -Name $($instance.Name) -Status).Statuses.Code[1]) -replace "PowerState/", "")

						$resourceGroupContent = New-Object -Type PSObject -Property @{
							"Resource group name" = $($instance.ResourceGroupName)
							"Instance name" = $($instance.Name)
							"Instance type" = (($instance.ResourceType -split "/")[0].Substring(10))
							"Instance state" = ([System.Threading.Thread]::CurrentThread.CurrentCulture.TextInfo.ToTitleCase($instancePowerState))
						}

						$resourceGroupsContent += $resourceGroupContent
					}
				}
				else
				{
					#Do nothing
				}
			}

			$resourceGroupsContent | Format-Table -AutoSize
		}
		catch
		{
			Write-Output "Failed in getting instances try catch"
			Write-Error -Message $_.Exception
			throw $_.Exception    
		}
		## End of getting all virtual machines

		$runningInstances = ($resourceGroupsContent | Where-Object {$_.("Instance state") -eq "Running" -or $_.("Instance state") -eq "Starting"})
		$deallocatedInstances = ($resourceGroupsContent | Where-Object {$_.("Instance state") -eq "Deallocated" -or $_.("Instance state") -eq "Deallocating"})

		## Updating virtual machines power state
		if (($runningInstances) -and ($Action -eq "Stop"))
		{
			Write-Output "--------------------------- Updating ---------------------------"
			Write-Output "Trying to stop virtual machines ..."

			try
			{
				$updateStatuses = @()

				foreach ($runningInstance in $runningInstances)
				{
						Write-Output "$($runningInstance.("Instance name")) is shutting down ..."
					
						$startTime = Get-Date -Format G

						$null =  Stop-AzVM -ResourceGroupName $($runningInstance.("Resource group name")) -Name $($runningInstance.("Instance name")) -Force -DefaultProfile $AzureContext
						
						$endTime = Get-Date -Format G

						$updateStatus = New-Object -Type PSObject -Property @{
							"Resource group name" = $($runningInstance.("Resource group name"))
							"Instance name" = $($runningInstance.("Instance name"))
							"Start time" = $startTime
							"End time" = $endTime
						}
					
						$updateStatuses += $updateStatus
						  
				}

				$updateStatuses | Format-Table -AutoSize
			}
			catch
			{
				Write-Error -Message $_.Exception
				throw $_.Exception    
			}
		}
		elseif (($deallocatedInstances) -and ($Action -eq "Start"))
		{
			Write-Output "--------------------------- Updating ---------------------------"
			Write-Output "Trying to start virtual machines ..."

			try
			{
				$updateStatuses = @()

				foreach ($deallocatedInstance in $deallocatedInstances)
				{                                    
					
						Write-Output "$($deallocatedInstance.("Instance name")) is starting ..."

						$startTime = Get-Date -Format G

						$null = Start-AzVM -ResourceGroupName $($deallocatedInstance.("Resource group name")) -Name $($deallocatedInstance.("Instance name"))  -DefaultProfile $AzureContext

						$endTime = Get-Date -Format G

						$updateStatus = New-Object -Type PSObject -Property @{
							"Resource group name" = $($deallocatedInstance.("Resource group name"))
							"Instance name" = $($deallocatedInstance.("Instance name"))
							"Start time" = $startTime
							"End time" = $endTime
						}
					
						$updateStatuses += $updateStatus
							   
				}

				$updateStatuses | Format-Table -AutoSize
			}
			catch
			{
				Write-Error -Message $_.Exception
				throw $_.Exception    
			}
		}else
		{
			Write-Output "Nothing to do.. Servers already running / stopped"   
		}
		#### End of updating virtual machines power state

	}
	else {
		# The alert status was not 'Activated' or 'Fired' so no action taken
		Write-Output "No action taken. Alert status: " + $status
	}
	
	#Write-Output "Disconnecting.."
	#Disconnect-AzAccount
}
else {
	# Error
	Write-Error "This runbook is meant to be started from an Azure alert webhook only."
}
