# Test Environment Data Load
#   Author:                  Kenny V
#   Desc:                    This script is used to generate random data rows in a SQL test env table
#                                   - Uses `invoke-generate` to create random data (nameit module)
#                                   - Connects to source Instance, creates a table, and loads it.  Choose the Counter for the row count to load
#                                Setup
#                                   - The first couple blocks of code ensure a Database exists and the User Table exists
#                                Data Generation
#                                   - Rows are inserted to user table on intervals and by multiple processes
#   Date/Last Modified Date: Oct 2024
#   Dependancies -
#                - Install-Module NameIT -Scope CurrentUser    - Name and Data Generator https://github.com/dfinke/NameIT
#                - Install-Module dbatools -Scope CurrentUser  - DBA/SQL module        https://github.com/dataplat/dbatools/

import-module -name dbatools
import-module -name nameit
Set-DbatoolsInsecureConnection -SessionOnly

Write-Host "Start Time:   $(Get-Date -Format 'HH:mm:ss')"

#which instance and database would you like to chuck this data into?
$sourceinstance = 'sqlinstance'
$database = "MockData"
$tableName = "user_mockdata"


$server = Connect-DbaInstance -SqlInstance $sourceinstance

 $query = @"
 USE MASTER;
 IF NOT EXISTS (SELECT name FROM master.dbo.sysdatabases WHERE name =
'$database')
     CREATE DATABASE $database;
"@

Invoke-dbaquery -SqlInstance $server -query $query


$query = @"
USE $database;
IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE
TABLE_NAME = '$tableName')
BEGIN
    CREATE TABLE $tableName (
        user_id NVARCHAR(50) PRIMARY KEY,
        username NVARCHAR(50) NOT NULL,
        email NVARCHAR(100) NOT NULL,
        password_hash NVARCHAR(255) NOT NULL,
        first_name NVARCHAR(50),
        last_name NVARCHAR(50),
        date_of_birth DATE,
        gender NVARCHAR(10),
        registration_date DATETIME DEFAULT GETDATE(),
        profile_image_url NVARCHAR(255),
        bio NVARCHAR(MAX),
        is_active BIT DEFAULT 1
    )
END
"@

# # This ensures the table above is created befor inserting rows
Invoke-dbaquery -SqlInstance $server -database $database -query $query


# This is the amount of rows you want to create,
# Change the iteration to 1..numberyouchoose - in this case we're entering 10,000 users... more?.. 20?
1..20000 | ForEach-Object -Parallel {

    $result = @{
        Iteration = $counter
        Output    = $null
                        #You can store output data here
    }

    $id = New-Guid
    $hashedpwd = -join (((48..57) + (65..90) + (97..122)) * 90 | Get-Random -Count 255 | foreach-Object { [char]$_ })
    $username = NAMEIT\Invoke-Generate "[noun][noun]"
    $date = NAMEIT\Invoke-Generate "[randomdate]"
    $notes = NAMEIT\Invoke-Generate "[noun] [noun] [noun]  [noun] [noun]  [verb]  [verb] [verb] [noun]"

    $genderflag = Get-Random -Maximum 3 -Minimum 1

    if ($genderflag -eq 1) {
        $name = NAMEIT\Invoke-Generate "[person male]"
        $splitName = $name -split " "
        $firstName = $splitName[0]
        $lastName = $splitName[1]
        $gender = "male"
    }
    elseif ($genderflag -eq 2) {
        $name = NAMEIT\Invoke-Generate "[person female]"
        $splitName = $name -split " "
        $firstName = $splitName[0]
        $lastName = $splitName[1]
        $gender = "female"
    }
    else {
        $gender = "Other"
        $name = NAMEIT\Invoke-Generate "[person]"
        $splitName = $name -split " "
        $firstName = $splitName[0]
        $lastName = $splitName[1]
        $gender = "other"
    }


    $query = @"
        INSERT INTO users (user_id, username, email, password_hash, first_name, last_name, date_of_birth, gender, profile_image_url, bio, is_active)
        VALUES ('$id','$username', '$firstName$lastname-at-example.com', '$hashedpwd', '$firstName', '$lastname', '$date', '$gender', 'https:exampledotcom/$name$lastname.jpg', '$notes', 1)
"@

    # This line sends your SINGLE insert statement to the database
    # This is supposed to be inefficeint and supposed to send load to the server - hence the single INSERT instead of batch dbatools\
    
    Invoke-dbaquery -SqlInstance $using:server -database $using:database -query $query

    $result.Output = "Iteration $_ completed."

    $result
} -ThrottleLimit 10 | ForEach-Object {

    Write-Host $_.Output
}

Write-Host "End Time:   $(Get-Date -Format 'HH:mm:ss')"

Write-Host "Data Load to $table complete.."

$server | Disconnect-DbaInstance

# #20,000 lines duration
# #Start Time:  15:46:13
# #             16:11:06
