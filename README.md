# Start / Stop Azure VMs via Alert Webhook

This runbook starts or stops tagged or all VMs via Azure Alert Webhooks. Uses Managed Identity for Authentication.
Useful for cases where VMs need to be preserved and turned on/off as needed, as an alternative to Autoscale. 

Use Case examples:
* Start all/group of VMs when an alert is triggered. E.g. when metric value exceeds a threshold, start a group of VMs to add them to server pool.
* Stop all/group of VMs when an alert is resolved
* Start/Stop groups of VMs based on separate metric thresholds.

Input Parameters (defined at the Action under Action Group):
* $Action  : [Required] "Start" or "Stop" 
* $TagName  : [Optional] VM Tag Name. Requires $TagValue if defined. if left empty, all vms in the resource group will be started/stopped
* $TagValue  : [Optional] VM Tag Value
  
Notes:
* VMs are started in series
* Checks and only starts stopped VMs and vice versa
* Executes if Alert status is either Activated / Fired

Based on the "Stop / Start all or only tagged Azure VMs" runbook by Farouk Friha, and information from the article https://learn.microsoft.com/en-us/azure/automation/automation-create-alert-triggered-runbook
