<#
.SYNOPSIS
  Name: TimeWarHorn.ps1
  The purpose of this script is to monitor time drift on domain controllers and send an alert ("sound the horn") if it drifts to unacceptable levels
  
.DESCRIPTION
  The purpose of this script is to monitor time drift on domain controllers and send an alert ("sound the horn") if it drifts to unacceptable levels

.NOTES
    Release Date: 2022-12-29T15:18
    Last Updated: 2022-12-29T15:25
   
    Author: Luke Nichols
    https://github.com/jlukenichols/
#>

#TODO: "Functionalize" the script, rework input variables into 
#TODO: Figure out a way to take the domain name as a parameter so the script doesn't just use the current domain

Clear-Host

### User-Defined variables ###

$UnacceptableTimeDriftInSeconds = 0.1
$EmailTo = ""
$EmailFrom = ""
$EmailSMTPServer = ""
$EmailSubject = ""

#Get the current date and write it to a variable
#[DateTime]$currentDate=Get-Date #Local timezone
[DateTime]$currentDate = (Get-Date).ToUniversalTime() #UTC

#Grab the individual portions of the date and put them in vars
$currentYear = $($currentDate.Year)
$currentMonth = $($currentDate.Month).ToString("00")
$currentDay = $($currentDate.Day).ToString("00")

$currentHour = $($currentDate.Hour).ToString("00")
$currentMinute = $($currentDate.Minute).ToString("00")
$currentSecond = $($currentDate.Second).ToString("00")

### Script main body ###

#Cancel red alert
$TimeWarHasBegun = $false
$TimeDriftList = "Hostname TimeDrift"

#Query for a list of domain controllers in the current domain
:loopThroughDCs foreach ($DC in (Get-ADDomainController -Filter * | Select HostName)) {
    #Write the raw output of the command to a variable
    $TimeDriftRaw = & w32tm /stripchart /computer:$($DC.Hostname) /samples:1 /dataonly
    #Check if the DC returned a specific error that is not interesting to us
    if ($TimeDriftRaw -eq "The following error occurred: No such host is known. (0x80072AF9)") {
        #Skip to the next DC, this one is defunct
        continue loopThroughDCs
    } else {
        #Skip the first few lines which are not interesting and write to a temporary variable
        $TimeDriftTemp = (& w32tm /stripchart /computer:$($DC.Hostname) /samples:1 /dataonly | Select -Skip 3)
        #Convert to a powershell object, trim off the "s" at the end, and then write to a new variable of type [decimal] so we can easily do math on it
        [decimal]$TimeDrift = (($TimeDriftTemp | ConvertFrom-Csv -Header Time, Drift).Drift).Trim("s")
        #Get the absolute value of the time drift value (remove any negative numbers) because we don't care which way it's drifted, only by how much
        $TimeDrift = [Math]::abs($TimeDrift)
        
        if ($TimeDrift -ge 0.1) {
            $TimeWarHasBegun = $true
            Write-Output "BEGUN, THE TIME WAR HAS"
        }
        
        #Show your work
        $TimeDriftOutput = "$($DC.Hostname) $TimeDrift"
        $TimeDriftList += "`n$TimeDriftOutput"
        Write-Output $TimeDriftOutput
    }
}

#TODO: Build robust logging with rotation of old files.

if ($TimeWarHasBegun -eq $true) {
    Write-Output $TimeDriftList    
    $Body = "WARNING: TIME DRIFT EXCEEDING ACCEPTABLE LIMIT OF $UnacceptableTimeDriftInSeconds HAS BEEN DETECTED ON A DOMAIN CONTROLLER. SEE BELOW FOR MORE DETAILS.`n`n"
    $Body += "$TimeDriftList`n"
    #Always include contextual information about where the script is running so when your replacement needs to update it later they know where to find it
    $Body += "`nThis email was generated automatically by script `"$PSScriptRoot\$($MyInvocation.MyCommand.Name)`" on computer `"$env:COMPUTERNAME`" at $(Get-Date)"

    Write-Output $Body
    
    #TODO: Finish code to send an alert email
    #Send-MailMessage -Subject $EmailSubject -SmtpServer $EmailSMTPServer -To $EmailTo -From $EmailFrom -Body "$TimeDriftList"
} else {
    Write-Output "`n"
    Write-Output "All domain controllers have time drift within acceptable limit of +/- $UnacceptableTimeDriftInSeconds"
}
### End of script main body ###
break
exit