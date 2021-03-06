<#
  This script will Create, Import and Export WMI Filters

  Syntax examples:
    Create:
      ManageWMIFilters.ps1 -Action Create -ReferenceFile DefaultWMIFilters.csv
    Export:
      ManageWMIFilters.ps1 -Action Export -ReferenceFile WMIFiltersExport.csv
    Import:
      ManageWMIFilters.ps1 -Action Import -ReferenceFile WMIFiltersExport.csv

  It is based on the following three scripts:
    1) Using Powershell to Automatically Create WMI Filters:
       http://gallery.technet.microsoft.com/scriptcenter/f1491111-9f5d-4c83-b436-537eca9e8d94
    2) Exporting and Importing WMI Filters with PowerShell: Part 1, Export:
       http://blogs.technet.com/b/manny/archive/2012/02/04/perform-a-full-export-and-import-of-wmi-filters-with-powershell.aspx
    3) Exporting and Importing WMI Filters with PowerShell: Part 2, Import:
       http://blogs.technet.com/b/manny/archive/2012/02/05/exporting-and-importing-wmi-filters-with-powershell-part-2-import.aspx

  I left the code as 3 separate modules so that it can be easily split and
  reused if preferred. Hence the reason why there is some duplicate code.

  If your Active Directory is based on Windows 2003 or has been upgraded
  from Windows 2003, you may may have an issue with System Owned Objects.
  If this is the case you will need to set the following registry value:
    Key: HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\NTDS\Parameters
    Type: REG_DWORD
    Value: Allow System Only Change
    Data: 1

  Release 1.1
  Written by Jeremy@jhouseconsulting.com 11th September 2013
  Modified by Jeremy@jhouseconsulting.com 29th January 2014
#>

#-------------------------------------------------------------
param([String]$Action,[String]$ReferenceFile)

Write-Host -ForegroundColor Green "Verifying script parameters...`n"

if ([String]::IsNullOrEmpty($Action)) {
  write-host -ForeGroundColor Red "Action is a required parameter. Exiting Script.`n"
  exit
} else {
  switch ($Action)
  {
    "Create" {$Create = $true;$Import = $false;$Export = $false}
    "Import" {$Create = $false;$Import = $true;$Export = $false}
    "Export" {$Create = $false;$Import = $false;$Export = $true}
    default {$Create = $false;$Import = $false;$Export = $false}
  }
  if ($Create -eq $false -AND $Import -eq $false -AND $Export -eq $false) {
    write-host -ForeGroundColor Red "The Action parameter is invalid. Exiting Script.`n"
    exit
  }
}

if ([String]::IsNullOrEmpty($ReferenceFile)) {
  write-host -ForeGroundColor Red "ReferenceFile is a required parameter. Exiting Script.`n"
  exit
}

#-------------------------------------------------------------

# Import the Active Directory Module
Import-Module ActiveDirectory -WarningAction SilentlyContinue
if ($Error.Count -eq 0) {
  #Write-Host "Successfully loaded Active Directory Powershell's module`n" -ForeGroundColor Green
} else {
  Write-Host "Error while loading Active Directory Powershell's module : $Error`n" -ForeGroundColor Red
  exit
}

#-------------------------------------------------------------
If ($Import -eq $true) {

  if ((Test-Path $ReferenceFile) -eq $False) {
    Write-Host -ForegroundColor Red "The $ReferenceFile file is missing. Cannot import WMI Filters.`n"
    exit
  }

  $Header = "Name","Description","Filter"
  $WMIFilters = import-csv $ReferenceFile -Delimiter "`t" -Header $Header

  $RowCount = $WMIFilters | Measure-Object | Select-Object -expand count

  if ($RowCount -gt 0) {

    write-host -ForeGroundColor Green "Importing $RowCount WMI Filters`n"

    $defaultNamingContext = (get-adrootdse).defaultnamingcontext
    $configurationNamingContext = (get-adrootdse).configurationNamingContext

    $UseAdministrator = $False
    If ($UseAdministrator -eq $False) {
      $msWMIAuthor = (Get-ADUser $env:USERNAME).Name
    } Else {
      $msWMIAuthor = "Administrator@" + [System.DirectoryServices.ActiveDirectory.Domain]::getcurrentdomain().name
    }

    foreach ($WMIFilter in $WMIFilters) {
      $WMIGUID = [string]"{"+([System.Guid]::NewGuid())+"}"
      $WMIDN = "CN="+$WMIGUID+",CN=SOM,CN=WMIPolicy,CN=System,"+$defaultNamingContext
      $WMICN = $WMIGUID
      $WMIdistinguishedname = $WMIDN
      $WMIID = $WMIGUID
 
      $now = (Get-Date).ToUniversalTime()
      $msWMICreationDate = ($now.Year).ToString("0000") + ($now.Month).ToString("00") + ($now.Day).ToString("00") + ($now.Hour).ToString("00") + ($now.Minute).ToString("00") + ($now.Second).ToString("00") + "." + ($now.Millisecond * 1000).ToString("000000") + "-000" 
      $msWMIName = $WMIFilter.Name
      $msWMIParm1 = $WMIFilter.Description + " "
      $msWMIParm2 = $WMIFilter.Filter

      $Attr = @{"msWMI-Name" = $msWMIName;"msWMI-Parm1" = $msWMIParm1;"msWMI-Parm2" = $msWMIParm2;"msWMI-Author" = $msWMIAuthor;"msWMI-ID"=$WMIID;"instanceType" = 4;"showInAdvancedViewOnly" = "TRUE";"distinguishedname" = $WMIdistinguishedname;"msWMI-ChangeDate" = $msWMICreationDate; "msWMI-CreationDate" = $msWMICreationDate} 
      $WMIPath = ("CN=SOM,CN=WMIPolicy,CN=System,"+$defaultNamingContext) 

      $ExistingWMIFilters = Get-ADObject -Filter 'objectClass -eq "msWMI-Som"' -Properties "msWMI-Name","msWMI-Parm1","msWMI-Parm2"
      $array = @()
      foreach ($ExistingWMIFilter in $ExistingWMIFilters) {
        $array += $ExistingWMIFilter."msWMI-Name"
      }

      if ($array -notcontains $msWMIName) {
        write-host -ForeGroundColor Green "Importing the $msWMIName WMI Filter from $ReferenceFile`n"
        New-ADObject -name $WMICN -type "msWMI-Som" -Path $WMIPath -OtherAttributes $Attr
      } Else {
        write-host -ForeGroundColor Yellow "The $msWMIName WMI Filter already exists`n"
      }
    }
  } else {
    Write-Host -ForegroundColor Red "The data in the $ReferenceFile file is missing.`n"
  }
}

#-------------------------------------------------------------
If ($Export -eq $true) {

  set-content $ReferenceFile $NULL

  $WMIFilters = Get-ADObject -Filter 'objectClass -eq "msWMI-Som"' -Properties "msWMI-Name","msWMI-Parm1","msWMI-Parm2"

  $RowCount = $WMIFilters | Measure-Object | Select-Object -expand count

  if ($RowCount -ne 0) {
    write-host -ForeGroundColor Green "Exporting $RowCount WMI Filters`n"

    foreach ($WMIFilter in $WMIFilters) {
      write-host -ForeGroundColor Green "Exporting the" $WMIFilter."msWMI-Name" "WMI Filter to $ReferenceFile`n"
      $NewContent = $WMIFilter."msWMI-Name" + "`t" + $WMIFilter."msWMI-Parm1" + "`t" + $WMIFilter."msWMI-Parm2"
      add-content $NewContent -path $ReferenceFile
    }
    write-host -ForeGroundColor Green "An export of the WMI Filters has been stored at $ReferenceFile`n"

  } else {
    write-host -ForeGroundColor Green "There are no WMI Filters to export`n"
  } 
}

#-------------------------------------------------------------
If ($Create -eq $true) {

  if ((Test-Path $ReferenceFile) -eq $False) {
    Write-Host -ForegroundColor Red "The $ReferenceFile file is missing. Cannot create WMI Filters.`n"
    exit
  }

  $defaultNamingContext = (get-adrootdse).defaultnamingcontext  

  $UseAdministrator = $False
  If ($UseAdministrator -eq $False) {
    $msWMIAuthor = (Get-ADUser $env:USERNAME).Name
  } Else {
    $msWMIAuthor = "Administrator@" + [System.DirectoryServices.ActiveDirectory.Domain]::getcurrentdomain().name
  }

  # Import WMI Filters From CSV
  # Name,Description,Filter
  $WMIFilters = import-csv $ReferenceFile

  $RowCount = $WMIFilters | Measure-Object | Select-Object -expand count

  if ($RowCount -gt 0) {

    write-host -ForeGroundColor Green "Creating $RowCount WMI Filters`n"

    foreach ($WMIFilter in $WMIFilters) {
      $WMIGUID = [string]"{"+([System.Guid]::NewGuid())+"}"    
      $WMIDN = "CN="+$WMIGUID+",CN=SOM,CN=WMIPolicy,CN=System,"+$defaultNamingContext 
      $WMICN = $WMIGUID 
      $WMIdistinguishedname = $WMIDN 
      $WMIID = $WMIGUID 
 
      $now = (Get-Date).ToUniversalTime() 
      $msWMICreationDate = ($now.Year).ToString("0000") + ($now.Month).ToString("00") + ($now.Day).ToString("00") + ($now.Hour).ToString("00") + ($now.Minute).ToString("00") + ($now.Second).ToString("00") + "." + ($now.Millisecond * 1000).ToString("000000") + "-000" 
 
      $msWMIName = $WMIFilter.Name 
      $msWMIParm1 = $WMIFilter.Description + " " 
      $msWMIParm2 = "1;3;" + $WMIFilter.Namespace.Length.ToString() + ";" + $WMIFilter.Query.Length.ToString() + ";WQL;" + $WMIFilter.Namespace + ";" + $WMIFilter.Query + ";"

      $Attr = @{"msWMI-Name" = $msWMIName;"msWMI-Parm1" = $msWMIParm1;"msWMI-Parm2" = $msWMIParm2;"msWMI-Author" = $msWMIAuthor;"msWMI-ID"=$WMIID;"instanceType" = 4;"showInAdvancedViewOnly" = "TRUE";"distinguishedname" = $WMIdistinguishedname;"msWMI-ChangeDate" = $msWMICreationDate; "msWMI-CreationDate" = $msWMICreationDate} 
      $WMIPath = ("CN=SOM,CN=WMIPolicy,CN=System,"+$defaultNamingContext) 

      $ExistingWMIFilters = Get-ADObject -Filter 'objectClass -eq "msWMI-Som"' -Properties "msWMI-Name","msWMI-Parm1","msWMI-Parm2"
      $array = @()
      foreach ($ExistingWMIFilter in $ExistingWMIFilters) {
        $array += $ExistingWMIFilter."msWMI-Name"
      }

      if ($array -notcontains $msWMIName) {
        write-host -ForeGroundColor Green "Creating the $msWMIName WMI Filter from $ReferenceFile`n"
        New-ADObject -name $WMICN -type "msWMI-Som" -Path $WMIPath -OtherAttributes $Attr 
      } Else {
        write-host -ForeGroundColor Yellow "The $msWMIName WMI Filter already exists`n"
      }
    }
  } else {
    Write-Host -ForegroundColor Red "The data in the $ReferenceFile file is missing.`n"
  }
}
