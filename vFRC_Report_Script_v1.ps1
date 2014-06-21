<#----------------------------------------------------------------------
A simple script to real all VMDKs on all VMs in your vSphere environment
and report the VMware vSphere Flash Read Cache (vFRC) configuration
(cache block size in KB and cache size in GB) in a CSV file.

v1.0    20 June 2014:   Initial draft

Written By Josh Townsend
http://vmtoday.com

!!!All Code provided as is and used at your own risk!!!

Requires PowerCLI 5.5 R1 or later (https://www.vmware.com/support/developer/PowerCLI)
Requires PowerCLI Extensions Fling (https://labs.vmware.com/flings/powercli-extensions)
----------------------------------------------------------------------#>
$Data = @()
#Before we get going, let's figure out where you want this report saved!
#If you want to define a path instead of dialog, comment out the following until I say stop
Function Select-FolderDialog
{
    param([string]$Description="Choose the location for your report to be saved",[string]$RootFolder="Desktop")

 [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
     Out-Null     

   $objForm = New-Object System.Windows.Forms.FolderBrowserDialog
        $objForm.Rootfolder = $RootFolder
        $objForm.Description = $Description
        $Show = $objForm.ShowDialog()
        If ($Show -eq "OK")
        {
            Return $objForm.SelectedPath
        }
        Else
        {
            Write-Error "Operation cancelled by user."
        }
    }
$vFRCReportPath = Select-FolderDialog
$ReportDate = (Get-Date).tostring("yyyyMMdd")
$vFRCReportFileName = $ReportDate + '_vFRCReport.csv'
$vFRCReport = $vFRCReportPath + "\" + $vFRCReportFileName
#Stop

#Now uncomment the line below and configure your variable.
#$vFRCReport = "C:\Temp\vFRCReport.csv"

#Let's see if the report already exists and if so prompt to overwrite
$ReportExists = Test-Path $vFRCReport
If ($ReportExists -eq $True){
$delete = New-Object System.Management.Automation.Host.ChoiceDescription "&Delete",""
$quit = New-Object System.Management.Automation.Host.ChoiceDescription "&Quit",""
$dq = [System.Management.Automation.Host.ChoiceDescription[]]($Delete,$quit)
$caption0 = "Overwrite or quit"
$message0 = "Oops - the report already exists! What do you want to do?"
$dqprompt = $Host.UI.PromptForChoice($caption0,$message0,$dq,0)

switch ($dqprompt){
 0 { Remove-Item $vFRCReport; Write-Host "Deleted! Moving on..." -ForegroundColor Green }
 1 { Write-host "Manually delete, move or rename the existing then re-run this script when you're ready" -foregroundcolor Red ; $global:xExitSession=$true; exit }
 }  
}
#A little help adding in the PowerCLI snapin and Extensions modules in case you forgot to
#Add PowerCLI snapin if not already loaded
if ((Get-PSSnapin -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) -eq $null ) {Add-PsSnapin VMware.VimAutomation.Core; $bSnapinAdded = $true}
#Add vFRC and vSAN Extensions

Import-Module VMware.VimAutomation.Extensions
Get-Command -Module VMware.VimAutomation.Extensions

# Prompt for vCenter or ESXi server
Write-host "Enter the name or IP of your vCenter Server or ESXi host: " -Foregroundcolor yellow -NoNewLine 
$vCenter = Read-host
Write-host "Domain name (leave blank if using local ESXi account or vCenter Local SSO account): " -Foregroundcolor yellow -NoNewLine
$domain = Read-host 
Write-host "vCenter or ESXi user account: "  -Foregroundcolor yellow -NoNewLine
$user = Read-host
Write-host "Enter password: " -Foregroundcolor yellow -NoNewLine 
$password = Read-host -AsSecureString
$decodedpassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
Connect-VIServer $vCenter -user $domain\$user -Password $decodedpassword

#Some other connection options:
#Option 1 - Show menu of recently used ESXi or vCenter Servers
#Write-host "Choose from the list below or enter the name of your vCenter Server or ESXi Host, then enter credentials as prompted" -ForegroundColor Yellow
#Connect-VIServer -Menu $true
#option 2 - Hard code it.  This leaves your password in plain text.  Consider using the new-VICredentialStore option to securely store your credentials!
#Connect-VIServer -Server 10.10.10.10 -User root -Password vmware

#Now lets get our vFRC config per VM/VMDK
$vms = Get-VM *
$data = @()
foreach ($vm in $vms){
    $vmdks = get-harddisk -VM $vm
    foreach ($vmdk in $vmdks) {
        if ($vmdk -ne $null){
        $vFRCConfig = Get-HardDiskVFlashConfiguration -Disk $vmdk
        $cacheBlockSizeKB = $vFRCConfig.CacheBlockSizeKB
        $cacheSizeGB = $vFRCConfig.CacheSizeGB 

        Get-HardDiskVFlashConfiguration -Disk $vmdk
        $data += New-Object -TypeName psobject -Property @{
        VMname = $VM.Name
        Datastore = $VMDK.FileName.Split(']')[0].TrimStart('[')
        VMDK = $VMDK.FileName.Split(']')[1].TrimStart('[')
        vFRCBlockSizeKB = $cacheBlockSizeKB
        vFRCCacheSizeGB = $cacheSizeGB
        } | select-object VMname,Datastore,VMDK,vFRCBlockSizeKB,vFRCCacheSizeGB
        
       }  
    }
  } 
#And finally, let's save our output CSV.
$data | ConvertTo-Csv | Out-file $vFRCReport -NoClobber

Write-host "That's it. You can find your report at $vFRCReport" -ForegroundColor Yellow
Write-host "Do you want to open the report now?" -ForegroundColor Yellow
$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes",""
$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No",""
$choices = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)
$caption = ""
$message = ""
$result = $Host.UI.PromptForChoice($caption,$message,$choices,0)

switch ($result){
 0 { Invoke-Item $vFRCReport; exit } 
 1 { exit }
}