-- Quick little, and scalable SQL accuracy checks between client provided data and `seat count` and `event` tables



DECLARE @clientTicketVol AS FLOAT = 123456 -- amount of sales provided by client spreadsheet
DECLARE @clientRevenue AS FLOAT = 7654321.29 -- amount of revenuew provided by client spreadsheet
DECLARE @eventDate AS varchar(10) = '1989-01-01' -- date 

SELECT e.eventname, count(t.eventseatid) AS ourSeatCount, @clientTicketVol AS clientsSeatCount, LEFT((100.0 * clientTicketVol)/COUNT(t.eventseatid),6) AS seatCountAccuracy, ROUNT(SUM(reportedRev),2) AS ourReportedRev, @clientRevenue AS clientReportedRev, ROUND(100.0 * SUM(reportedRev)/clientReportedRev,2) as RevenueAccuracy
FROM dbname.schemaname.seatCounts t
JOIN dbname.schemaname.events e ON t.id = e.id
WHERE e.eventdate = @eventDate 
GROUP BY eventid, eventname