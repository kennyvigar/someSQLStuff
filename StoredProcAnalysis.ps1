#stored proc checker
# you ever just need to check all the procs on all your servers?   Powershell ftw

#dependancies - DBATOOLS.IO 
#  notice the invoke-dbaquery command

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
