########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################

<#
.Synopsis
    Verify that VM sees all the FC disks attached in MPIO scenario.

.Description
    This script counts the number of connected fibre channel.
    Pushes a script to count the number of disks visible inside the VM
    and compares the results.
    A typical test case definition for this test script would look
    similar to the following:
    <test>
        <testName>FC_disks_multipath_detection</testName>
        <setupscript>setupscripts\FC_AddFibreChannelHba.ps1</setupscript>
        <testScript>setupscripts\FC_MultipathDetection.ps1</testScript>
        <timeout>10600</timeout>
        <testParams>
                <param>snapshotname=ICABase</param>
                <param>TC_COVERED=FC-xx</param>
                <param>vSANName=FC_NAME</param>
        </testParams>
            <onError>Continue</onError>
            <noReboot>False</noReboot>
        </test>

.Parameter vmName
    Name of the VM to perform the test with.

.Parameter hvServer
    Name of the Hyper-V server hosting the VM.

.Parameter testParams

.Example
    setupScripts\FC_MultipathDetection.ps1 -vmName "myVm" -hvServer "localhost" -TestParams "TC_COVERED=FC-08"
#>

param([string] $vmName, [string] $hvServer, [string] $testParams)

$remoteScript = "FC_multipath_detect.sh"
$summaryLog  = "${vmName}_summary.log"
$retVal = $False


######################################################################
#
#   Helper function to execute command on remote machine.
#
#######################################################################
function Execute ([string] $command)
{
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} $command
    return $?
}
#######################################################################
# Runs a remote script on the VM an returns the log.
#######################################################################
function RunRemoteScript($remoteScript)
{
    $retValue = $False
    $stateFile     = "state.txt"
    $TestCompleted = "TestCompleted"
    $TestAborted   = "TestAborted"
    $TestRunning   = "TestRunning"
    $TestFailed    ="TestFailed"
    $timeout       = 6000

    "./${remoteScript} > ${remoteScript}.log" | out-file -encoding ASCII -filepath runtest.sh

    .\bin\pscp -i ssh\${sshKey} .\runtest.sh root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy runtest.sh to the VM"
       return $False
    }

     .\bin\pscp -i ssh\${sshKey} .\remote-scripts\ica\${remoteScript} root@${ipv4}:
    if (-not $?)
    {
       Write-Output "ERROR: Unable to copy ${remoteScript} to the VM"
       return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix ${remoteScript} 2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on ${remoteScript}"
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "dos2unix runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to run dos2unix on runtest.sh"
        return $False
    }

    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x ${remoteScript}   2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x ${remoteScript}"
        return $False
    }
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "chmod +x runtest.sh  2> /dev/null"
    if (-not $?)
    {
        Write-Output "ERROR: Unable to chmod +x runtest.sh " -
        return $False
    }

    # Run the script on the vm
    .\bin\plink.exe -i ssh\${sshKey} root@${ipv4} "./runtest.sh"

    # Return the state file
    while ($timeout -ne 0 )
    {
    .\bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${stateFile} . #| out-null
    $sts = $?
    if ($sts)
    {
        if (test-path $stateFile)
        {
            $contents = Get-Content -Path $stateFile
            if ($null -ne $contents)
            {
                    if ($contents -eq $TestCompleted)
                    {
                        Write-Output "Info : state file contains Testcompleted"
                        $retValue = $True
                        break

                    }

                    if ($contents -eq $TestAborted)
                    {
                         Write-Output "Info : State file contains TestAborted failed. "
                         break

                    }
                    if ($contents -eq $TestFailed)
                    {
                        Write-Output "Test failed."
                        break
                    }
                    #Start-Sleep -s 1
                    $timeout--

                    if ($timeout -eq 0)
                    {
                        Write-Output "Error : Timed out on Test Running , Exiting test execution."
                        break
                    }

            }
            else
            {
                Write-Output "Warn : state file is empty"
                break
            }

        }
        else
        {
             Write-Host "Warn : ssh reported success, but state file was not copied"
             break
        }
    }
    else #
    {
         Write-Output "Error : pscp exit status = $sts"
         Write-Output "Error : unable to pull state.txt from VM."
         break
    }
    }

    # Get the logs
    $remoteScriptLog = $remoteScript+".log"

    bin\pscp -q -i ssh\${sshKey} root@${ipv4}:${remoteScriptLog} .
    $sts = $?
    if ($sts)
    {
        if (test-path $remoteScriptLog)
        {
            $contents = Get-Content -Path $remoteScriptLog
            Write-Output $contents | Tee-Object -Append -file $summaryLog
            if ($null -ne $contents)
            {
                    if ($null -ne ${TestLogDir})
                    {
                        move "${remoteScriptLog}" "${TestLogDir}\${remoteScriptLog}"

                    }

                    else
                    {
                        Write-Output "INFO: $remoteScriptLog is copied in ${rootDir}"
                    }

            }
            else
            {
                Write-Output "Warn: $remoteScriptLog is empty"
            }
        }
        else
        {
             Write-Output "Warn: ssh reported success, but $remoteScriptLog file was not copied"
        }
    }

    # Cleanup
    del state.txt -ErrorAction "SilentlyContinue"
    del runtest.sh -ErrorAction "SilentlyContinue"

    return $retValue
}

#######################################################################
#
# Main script body
#
#######################################################################
$retVal = $false

#
# Check input arguments
#
if ($vmName -eq $null) {
    "Error: VM name is null"
    return $retVal
}

if ($hvServer -eq $null) {
    "Error: hvServer is null"
    return $retVal
}

$params = $testParams.Split(";")

foreach ($p in $params) {
    $fields = $p.Split("=")

    switch ($fields[0].Trim()) {
        "sshKey" { $sshKey  = $fields[1].Trim() }
        "ipv4"   { $ipv4    = $fields[1].Trim() }
        "rootdir" { $rootDir = $fields[1].Trim() }
        "TC_COVERED" { $TC_COVERED = $fields[1].Trim() }
        "TestLogDir" { $TestLogDir = $fields[1].Trim() }
        default  {}
    }
}

if ($null -eq $sshKey) {
    "Error: Test parameter sshKey was not specified"
    return $False
}

if ($null -eq $ipv4) {
    "Error: Test parameter ipv4 was not specified"
    return $False
}

#
# Change the working directory to where we need to be
#
if (-not (Test-Path $rootDir)) {
    "Error: The directory `"${rootDir}`" does not exist!"
    return $False
}

Write-output "This script covers test case: ${TC_COVERED}" | Tee-Object -Append -file $summaryLog

cd $rootDir

#
# Source the TCUtils.ps1 file
#
. .\setupscripts\TCUtils.ps1

$fcDisks = Get-Disk | Where-Object -FilterScript {$_.BusType -Eq "Fibre Channel"}
$fcCount = $fcDisks.Length

#set fcCount in constants.sh
$cmd="echo `"expectedCount=$($fcCount)`" >> ~/constants.sh";
$result = Execute($cmd);
if (-not $result) {
    Write-Error -Message "Error: Unable to submit ${cmd} to vm" -ErrorAction SilentlyContinue
    return $False
}
$sts = RunRemoteScript  $remoteScript

return $sts
