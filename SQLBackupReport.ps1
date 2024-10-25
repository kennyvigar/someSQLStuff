# Full SQL Backup Report
#   Author:                  Kenny V
#   Desc:                    This script rules.   It checks Active Directory dynamically for all servers "like SQL".   Then checks each server for any databases that have not had a backup in the last 24 hours.
#                            The script will then send a beautifully formatted HTML email with the list of servers separated by environment (dev, test, prod - for example)
#                             
#   Date/Last Modified Date: Oct 2024
#   Dependancies - Install-Module dbatools -Scope CurrentUser  - DBA/SQL module        https://github.com/dataplat/dbatools/



Start-Transcript E:\scripts\logs\healthcheck.txt

Import-Module -Name "C:\Program Files\PowerShell\7\Modules\dbatools\2.1.6\dbatools.psd1" -Force

Set-DbatoolsInsecureConnection -SessionOnly


$SMTPServer = ""
$emailFrom = ""
$to = @("","","")

$date = Get-Date
$hour = $date.Hour


function Get-Servers
{
    $servers = Get-ADComputer -Filter { name -like "*sql*" } 
    
    return $servers
}


$servers = Get-Servers

$bkupReport = @()

foreach ($server in $servers)
{        
    if ($server.name -like "prod") #filter out any servers for just SQL or env
    {
        try
        {

            $connection = Connect-DbaInstance -SqlInstance $server.name 
            $server.name


            $connection.status
            Write-Host ".... Connection Test ..works - $($server)"
    
            $connection.status
            if ($connection.status -eq 'online')
            {
                try
                {
                    $queryBaks = "
                        WITH BackupInfo AS (
                        SELECT
                            CONVERT(CHAR(100), SERVERPROPERTY('Servername')) AS Server, 
                            d.name AS database_name,
                            bs.backup_start_date, 
                            bs.backup_finish_date, 
                            bs.expiration_date, 
                            CASE bs.type 
                                WHEN 'D' THEN 'Database' 
                                WHEN 'L' THEN 'Log' 
                            END AS backup_type, 
                            bs.backup_size / (1024.0 * 1024.0 * 1024.0) AS backup_size_in_gb, 
                            bmf.physical_device_name,
                            ROW_NUMBER() OVER (PARTITION BY d.name ORDER BY bs.backup_finish_date DESC) AS rn
                        FROM 
                            sys.databases d
                        LEFT JOIN 
                            msdb.dbo.backupset bs ON d.name = bs.database_name
                                                AND bs.type = 'D'
                                                AND bs.is_copy_only = 0  -- Consider only 'non-copy-only' backups if needed
                        LEFT JOIN 
                            msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
                    )
                    SELECT
                        Server,
                        database_name,
                        MAX(backup_start_date) AS backup_start_date,
                        MAX(backup_finish_date) AS backup_finish_date,
                        MAX(expiration_date) AS expiration_date,
                        MAX(backup_type) AS backup_type,
                        MAX(backup_size_in_gb) AS backup_size_in_gb,
                        MAX(physical_device_name) AS physical_device_name
                    FROM 
                        BackupInfo
                    WHERE 
                        rn = 1  -- Get the most recent backup for each database
                        AND (DATEDIFF(DAY, backup_finish_date, GETDATE()) > 1 OR backup_finish_date IS NULL)  -- Filter for backups older than 1 day or where backup information is missing
                        AND database_name NOT IN ('master','model','msdb','tempdb')
                    GROUP BY
                        Server,
                        database_name
                    ORDER BY 
                        database_name;"
           
                    $queryrun = Invoke-DbaQuery -SqlInstance $server.name -Query $queryBaks
                
                    $queryrun

                    $queryJobs = "
                    SELECT jobs.name, jobs.description
                    FROM msdb.dbo.sysjobs jobs
                    LEFT JOIN msdb.dbo.sysjobschedules job_schedules ON jobs.job_id = job_schedules.job_id
                    LEFT JOIN msdb.dbo.sysschedules schedules ON job_schedules.schedule_id = schedules.schedule_id
                    WHERE jobs.description like '%FIRST4%' and jobs.enabled <> 0
                    ORDER BY jobs.name;"
               
                    $queryrunJobs = Invoke-DbaQuery -SqlInstance $server.name -Query $queryJobs
                
                    if ($queryrun)
                    {
                        foreach ($row in $queryrun)
                        {
                            $row
                            $details = [PSCustomObject]@{
                                server         = if (-not [string]::IsNullOrEmpty($server.name))
                                {
                                    # $server 
                                    $server.name 
                                }
                                else
                                {
                                    "server not found" 
                                }
                                notes          = $connection.status

                                isbackupJob    = if ($queryrunJobs.name -like "*Backup*")
                                {
                                    $true 
                                }
                                else
                                {
                                    "N/A" 
                                }
                            
                                db             = $row.database_name
                                lastBackupDate = $row.backup_start_date
                                location       = $row.physical_device_name
                            }
                            $bkupReport += $details
                        }
                    }
                    else 
                    {

                     
                        $details = [PSCustomObject]@{
                            server      = if (-not [string]::IsNullOrEmpty($server.name))
                            {
                                $server.name 
                            }
                            else
                            {
                                "server not found" 
                            }
                            notes       = $connection.status
                            isbackupJob = if ($queryrunJobs.name -like "*Backup*")
                            {
                                $true 
                            }
                            else
                            {
                                "N/A" 
                            }
                        
                            db          = ""
                            start       = ""
                            location    = ""
                        }
                        $bkupReport += $details
                    }

                }
                catch
                {
                    $_
                }
            }
            else
            {         
                Write-Host ".....verfify connection status for $($server.name)"
            }   
        }
        catch
        {
            Write-Host 'catch!'
            $server.name 
            $_.Exception.Message
        }
    }
}

$bkupReport | Format-Table -AutoSize




$style = @'
<style>body{font-family:`"Calibri`",`"sans-serif`"; font-size: 14px;text-align: center;}
    .container {
            display: flex;
            justify-content: center; 
            align-items: flex-start;
        }

    table {
        border: 1px solid black;
        border-collapse: collapse;
        mso-table-lspace: 0pt;
        mso-table-rspace: 0pt;
        margin: 6px;
    }

    th {
        border: 1px solid black;
        background: #20A4F3;
        padding: 5px;
    }

    td {
        border: 1px solid black;
        padding: 5px;
        background: #C1CFDA;
    }

    .notes{
        font-size: 11px;
        font-style: italic;
        text-align: center;
        }
    .errors {
        color:#941C2F;
        font-size: 11px;
        text-align: center;
        }

    .success {
        text-align: center;
        color:#008000;
        font-size: 11px;
    }
    
    hr {
        width: 50%;
        margin: 20px auto;
        border: 1px solid #000;
    }

    p {
        text-align: center;
    }

    h3 {
        text-align: center;
    }
    
    h1 {
        text-align: center;
    }

</style>
'@


$mailbody += '<html><head><meta http-equiv=Content-Type content="text/html; charset=utf-8">' + $style + '</head><body>'


$mailbody += '<h1>Database Backup Health Status</h1>'

#conditonal formatting on the time of day 'cause that's pretty rad -- coffee emoji in morning, sun in the afternoon, and some beers for the evening :D
if ($hour -ge 5 -and $hour -lt 12)
{
    $subject = "(Morning) Database Backup Health Report"
    $mailbody += '<p>Good morning... take this - its dangerous to go alone...  &#9749; ' + '<br />' + 'Please see your morning Sql Database Backup health report below.' + '<br />' + '</p><p></p>'
}
elseif ($hour -ge 12 -and $hour -lt 17)
{
    $subject = "(Afternoon) Database Backup Health Report"
    $mailbody += '<p>Good afternoon!  &#x1F60E;' + '<br />' + 'Please see your afternoon Sql Database Backup health report below.' + '<br />' + '</p><p></p>'
}
else
{
    $subject = "(Evening) Database Backup Health Report"
    $mailbody += '<p>Good evening!  &#x1F37B; ' + '<br />' + 'Please see your evening Sql Database Backup health report below.' + '<br />' + '</p><p></p>'
}


$mailbody += '<br />' + '<hr>' + '<br />' 

$mailbody += '<p>Backup Health Summary' + '<br />'
$mailbody += '<p class="notes">... Across all servers that match *SQL* in Active Directory... This is your DB backup status </p> '
$mailbody += '<p class="errors">... The following DBs have a backup OLDER THAN 24 HOURS </p> '
$mailbody += '<p class="errors">... This list does not include System DBs (master, model, msdb, tempdb) </p> '
$mailbody += '<p class="notes"></p>'

if ($bkupReport)
{
    
    $prodReport = $bkupReport | Where-Object { $_.server -like "Prod*" }
    $testReport = $bkupReport | Where-Object { $_.server -like "Test*" }
    $devReport = $bkupReport | Where-Object { $_.server -like "Dev*" }

    $groupedReportPrd = $prodReport | Group-Object -Property server
    $groupedReportTst = $testReport | Group-Object -Property server
    $groupedReportDev = $devReport | Group-Object -Property server

    $mailbody += '<h3>Prod</h3>'


    foreach ($serverGroup in $groupedReportPrd)
    {
        $mailbody += '<div class="container">'

        $server = $serverGroup.Name
        $rows = $serverGroup.Group

        $mailbody += '<br><table>'
        $mailbody += '<tr><th>Server</th><th>EnabledBaks?</th><th>Database</th><th>Last Backup</th><th>Location</th></tr>'

    
        foreach ($row in $rows)
        {
            # To Do - do this string concat in other loops - it's cleaner than + signs
            $mailbody += "<tr><td>$($row.server)</td><td>$($row.isbackupJob)</td><td>$($row.db)</td><td>$($row.lastBackupDate)</td><td>$($row.location)</td></tr>"
        }
        $mailbody += '</table></p>'     
        $mailbody += '</div>'   
    }
    
    $mailbody += '<h3>Dev</h3>'

    foreach ($serverGroup in $groupedReportDev)
    {
        $server = $serverGroup.Name
        $rows = $serverGroup.Group
        $mailbody += '<div class="container">'

        $mailbody += '<br><table>'
        $mailbody += '<tr><th>Server</th><th>EnabledBaks?</th><th>Database</th><th>Last Backup</th><th>Location</th></tr>'

        foreach ($row in $rows)
        {
            # To Do - do this string concat in other loops - it's cleaner than + signs
            $mailbody += "<tr><td>$($row.server)</td><td>$($row.isbackupJob)</td><td>$($row.db)</td><td>$($row.lastBackupDate)</td><td>$($row.location)</td></tr>"
        }
       
        $mailbody += '</table></p>'     
        $mailbody += '</div>'   
    }
    
    $mailbody += '<h3>Test</h3>'

    foreach ($serverGroup in $groupedReportTst)
    {
        $server = $serverGroup.Name
        $rows = $serverGroup.Group
    
        $mailbody += '<div class="container">'

        $mailbody += '<br><table>'
        $mailbody += '<tr><th>Server</th><th>EnabledBaks?</th><th>Database</th><th>Last Backup</th><th>Location</th></tr>'

    
        foreach ($row in $rows)
        {
            # To Do - do this string concat in other loops - it's cleaner than + signs
            $mailbody += "<tr><td>$($row.server)</td><td>$($row.isbackupJob)</td><td>$($row.db)</td><td>$($row.lastBackupDate)</td><td>$($row.location)</td></tr>"
        }
        $mailbody += '</table></p>'      
        $mailbody += '</div>'  
    }       
}

$mailbody += '</body>'
$mailbody += '</html>'

## Mail Settings and Send

$mailParams = @{
    SmtpServer = $SMTPServer
    From       = $emailfrom
    To         = $to
    Subject    = $subject
    Body       = $mailbody
    BodyAsHtml = $true  
}

Send-MailMessage @mailParams


Stop-Transcript
