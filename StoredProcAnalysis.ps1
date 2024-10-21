# Stored proc checker
#   Author:                  Kenny V
#   Desc:                    This script checks all servers for all procs - can narrow down to a single proc if needed
#                             
#   Date/Last Modified Date: Oct 2024
#   Dependancies - Install-Module dbatools -Scope CurrentUser  - DBA/SQL module        https://github.com/dataplat/dbatools/


# you ever just need to check all the procs on all your servers?   Powershell ftw

import dbatools

$servers = @( "server1", "server2", "server3", "server4", "server5")

$check = @()

foreach ($server in $servers)
{
    try {
        $query = "
    SELECT o.name AS ProcedureName,
           @@SERVERNAME AS ServerName,
           ps.last_execution_time
    FROM sys.dm_exec_procedure_stats ps
    INNER JOIN
           sys.objects o ON ps.object_id = o.object_id;"

        $queryrun = Invoke-DbaQuery -SqlInstance $server -Query $query

        if ($queryrun)
        {

            $check += $queryrun
        }
    }
    catch {
        Write-Output "cannot make connection to $server.."
    }
}

$check | Format-Table -AutoSize
