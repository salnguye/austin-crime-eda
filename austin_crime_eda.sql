/*--------------------------------------- Data validation --------------------------------------------*/
-- 1. Confirm columns and data types
select column_name,
	data_type,
	udt_name
from information_schema.columns
where table_schema = 'public'
	and table_name = 'austin_crime';

-- 2. Total rows inserted
select count(*)
from austin_crime;

-- 3. Comparing the total row count and non-null counts of each column
select count(*) as row_count,
	count(incident_number) as incident_number,
	count(highest_offense_description) as highest_offense_description,
	count(highest_offense_code) as highest_offense_code,
	count(family_violence) as family_violence,
	count(occurred_date_time) as occurred_date_time,
	count(occurred_date) as occurred_date,
	count(occurred_time) as occurred_time,
	count(report_date_time) as report_date_time,
	count(report_date) as report_date,
	count(report_time) as report_time,
	count(location_type) as location_type,
	count(address) as address,
	count(zip_code) as zip_code,
	count(council_district) as council_district,
	count(apd_sector) as apd_sector,
	count(apd_district) as apd_district,
	count(pra) as pra,
	count(census_tract) as census_tract,
	count(clearance_status) as clearance_status,
	count(clearance_date) as clearance_date,
	count(ucr_category) as ucr_category,
	count(category_description) as category_description,
	count(x_coordinate) as x_coordinate,
	count(y_coordinate) as y_coordinate,
	count(latitude) as latitude,
	count(longitude) as longtidue,
	count(location) as location
from austin_crime;

-- 4. Validating distinct counts
select count(distinct highest_offense_code) as highest_offense_code,
	count(distinct highest_offense_description) as highest_offense_description,
	count(distinct family_violence) as family_violence,
	count(distinct clearance_status) as clearance_status,
	count(distinct ucr_category) as ucr_category,
	count(distinct category_description) as category_description,
	count(distinct zip_code) as zip_code,
	count(distinct council_district) as council_district,
	count(distinct apd_sector) as apd_sector,
	count(distinct apd_district) as apd_district
from austin_crime;

-- 5. Validating range in values
select min(length(zip_code::text)::int) as min_length_zip,
	max(length(zip_code::text)::int) as max_length_zip,
	min(report_date) as max_report_date_time,
	max(report_date) as max_report_date_time,
	min(occurred_date_time) as min_occurred_date_time,
	max(occurred_date_time) as max_occurred_date_time,
	min(clearance_date) as min_clearance_date,
	max(clearance_date) as max_clearance_date
from austin_crime;

--6. Validate if the incident number is unique
select incident_number,
	count(*)
from austin_crime
group by incident_number
having count(*) > 1;

--7. Validating discrepencies between clearance date and clearance status 
select count(*) as clearance_date_na,
	(select count(*) from austin_crime where clearance_date is not null and clearance_status is null) as status_na
from austin_crime
where clearance_date is null and clearance_status is not null;

-- 8. Number of incidents with a "Not cleared" status and has a clearance date
select count(*)
from austin_crime
where clearance_date is not null
	and clearance_status = 'N';

-- 9. Number of incidents where there's no clearance date/has clearance status, grouped by year reported and occurred
select extract(year from report_date) as report_year,
	extract(year from occurred_date) as occurred_year,
	count(*) as clearance_status_na
from austin_crime
where clearance_date is null 
	and clearance_status is not null
group by 1, 2;

-- 10. Distinct values for family_violence
select distinct family_violence
from austin_crime;

-- 11. Distinct values for location_type
select distinct location_type
from austin_crime;

-- 13. Incidents where occurred_date_time is null
select *
from austin_crime
where occurred_date_time is null;

-- 14. Percentage of missing zip codes
select 100 * (count(*)::decimal/(select count(*) from austin_crime)) as percent_zipcode_missing
from austin_crime
where zip_code is null;

-- 15. Zip codes recoverable by address
select distinct a.address, 
	a.zip_code
from austin_crime a inner join (
	select distinct address,
		zip_code
	from austin_crime
	where zip_code is null) b on a.address = b.address
where a.zip_code is not null;

-- 16. Confirming row count to update: 1426
with t1 as (
select distinct a.address, 
	a.zip_code
from austin_crime a inner join (
	select distinct address,
		zip_code
	from austin_crime
	where zip_code is null) b on a.address = b.address
where a.zip_code is not null
)select count(*)
from austin_crime
where address in (select distinct address from t1) 
	and zip_code is null;

/*--------------------------------------- Data cleansing --------------------------------------------*/

-- 17. Update missing zip codes
update austin_crime a
set zip_code = b.zip_code
from austin_crime b
where a.address = b.address
and a.zip_code is null
	and b.zip_code is not null;

-- 18. Create a working dataset as a view with cleansed data
create or replace view v_atx_crime as
with median_clearance as (
-- Calculate the median clearance date by reporting year, month, and type of crime
select extract(year from report_date) as report_year,
	extract(month from report_date) as report_month,
	highest_offense_code,
	to_char(to_timestamp(percentile_cont(0.5) within group(order by extract (epoch from clearance_date))), 'YYYY-MM-DD')::date as median_clearance_date
from austin_crime
group by 1, 2, 3
)select a.incident_number,
	highest_offense_description,
	upper(family_violence) as family_violence,
	occurred_date,
	occurred_date_time,
	report_date,
	report_date_time,
	case when clearance_status is not null and clearance_date is null then median_clearance_date else clearance_date end as clearance_date, -- Replace the missing clearance date with the median clearance date if clearance status is not null
	clearance_status,
	case clearance_status when 'C' then 'Cleared by Arrest' when 'O' then 'Cleared by Exception' when 'N' then 'Not Cleared' else 'Unknown Status' end as clearance_reason, -- Mapping clearance status codes to clearance status lookup values
	ucr_category,
	coalesce(category_description, 'No description') as category_description, -- Fill missing category description with 'No description'
	coalesce(location_type, 'OTHER / UNKNOWN') as location_type, -- Fill missing location type with 'UNKNOWN'
	zip_code,
	latitude,
	longitude
from austin_crime a left join median_clearance b on extract(year from report_date) = b.report_year
	and extract(month from report_date) = b.report_month
	and a.highest_offense_code = b.highest_offense_code
where occurred_date_time is not null
order by report_date;

/*--------------------------------------- Exploratory Analysis --------------------------------------------*/

-- Top 25 offenses reported
select highest_offense_description,
	count(*) as total_incidents
from v_atx_crime
group by highest_offense_description
order by 2 desc
limit 25;

-- Total 25 location types where crimes where committed
select location_type,
	count(*) as total_incidents
from v_atx_crime
group by location_type
order by 2 desc
limit 25;

-- Total 25 zip codes where most incidents were reported
select zip_code,
	count(*) total_incidents
from v_atx_crime
group by zip_code
order by 2 desc
limit 25;

-- Percentage of crimes cleared by status
select clearance_reason,
	round(100 * (count(*)::decimal/(select count(*) from austin_crime)),0) as percentage
from v_atx_crime
group by clearance_reason
order by 2 desc;
	
-- Distribution of incidents reported each year
select t.*,
	-- Calculate the percent change from the preceding year
	round(100 * ((total - lag(total) over(order by year_reported))::decimal / lag(total) over(order by year_reported)),2) as year_percent_change
from (
	-- Count the number of incidents by year
	select extract(year from report_date) as year_reported,
		count(*) as total
	from v_atx_crime
	group by year_reported
) t;

-- 12 month moving average total crimes reported
select t.*,
	round(avg(incident_count) over(order by report_month rows between 11 preceding and current row),2) as moving_avg_12m
from (
	select date_trunc('month', report_date)::date as report_month,
		count(*) as incident_count
	from v_atx_crime
	group by 1
)t ;

-- Distribution of crimes reported by day of the week
select to_char(report_date, 'DAY') as day,
	count(*) as reports
from v_atx_crime
group by 1, extract(dow from report_date)
order by extract(dow from report_date);

-- Hour when the most crimes occurred
select extract(hour from occurred_date_time) as occ_hour,
	count(*)
from v_atx_crime
group by 1
order by 2 desc;

-- Top 3 crimes committed by reported year
with offenses as (
select extract(year from report_date) as year,
	highest_offense_description,
	count(*) as total
from v_atx_crime
group by year,
	highest_offense_description
) select *
from (
	select dense_rank() over(partition by year order by total desc) as rank, -- Use a window function to rank the count of incidents by reporting year
		t.*
	from offenses t
) where rank <= 3;

-- Ratio of cleared incidents to reported incidents by year reported
select t.*,
	round(100 *(total_cleared::decimal/total_reported),2) as cleared_report_ratio
from (
	select extract(year from report_date) as year,
		count(*) as total_reported,
		sum(case when coalesce(clearance_status, 'N') <> 'N' then 1 else 0 end) as total_cleared
	from v_atx_crime
	group by 1
) t
order by year;

-- Number of incidents by clearance status
select clearance_reason,
	count(*) as total
from v_atx_crime
group by clearance_reason
order by 2 desc;

-- Percentage of crimes cleared by year
select t.*,
	round(100 * total_cleared::decimal / (total_cleared + not_cleared),2) as percent_cleared
from (
	select extract(year from report_date) as year,
		sum(case when coalesce(clearance_status, 'N') = 'N' then 1 else 0 end) as not_cleared,
		sum(case when coalesce(clearance_status, 'N') <> 'N' then 1 else 0 end) as total_cleared
	from v_atx_crime
	group by 1) t
order by 1;

-- Total incidents by FBI's UCR category and clearance reason
select t.*,
	round(100 * (total_incidents / sum(total_incidents) over(partition by fbi_ucr_category)), 2) as percentage
from (
	select category_description as fbi_ucr_category, 
		clearance_reason,
		count(*) as total_incidents
	from v_atx_crime
	where ucr_category is not null
	group by 1,2
	order by 1, 3 desc
) t;

-- FBI's UCR category over time
select extract(year from report_date) as report_year,
	count(*) filter(where category_description = 'Aggravated Assault') as aggrevated_assault,
	count(*) filter(where category_description = 'Auto Theft') as auto_theft,
	count(*) filter(where category_description = 'Burglary') as burglary,
	count(*) filter(where category_description = 'Murder') as murder,
	count(*) filter(where category_description = 'Rape') as rape,
	count(*) filter(where category_description = 'Robbery') as robbery,
	count(*) filter(where category_description = 'Theft') as theft
from v_atx_crime
where ucr_category is not null
group by 1
order by 1;

-- FBI's UCR category by zip code
select zip_code,
	count(*) filter(where category_description = 'Aggravated Assault') as aggrevated_assault,
	count(*) filter(where category_description = 'Auto Theft') as auto_theft,
	count(*) filter(where category_description = 'Burglary') as burglary,
	count(*) filter(where category_description = 'Murder') as murder,
	count(*) filter(where category_description = 'Rape') as rape,
	count(*) filter(where category_description = 'Robbery') as robbery,
	count(*) filter(where category_description = 'Theft') as theft
from v_atx_crime
group by 1;

-- Days to clear a crime for top 25 crimes reported
select a.highest_offense_description,
	(round(extract(epoch from min(clearance_date - report_date) / 86400),0)||' days') as min_days, -- Formatting 00:00:00 to '0 days'
	max(clearance_date - report_date) as max_days,
	avg(clearance_date - report_date) as avg_days,
	percentile_disc(0.5) within group (order by (clearance_date - report_date)) as median_days
from v_atx_crime a left join (
	select highest_offense_description, 
		count(*)
	from v_atx_crime
	group by highest_offense_description
	order by 2 desc
	limit 25) b on a.highest_offense_description = b.highest_offense_description
where coalesce(clearance_status, 'N') <> 'N'
	and b.highest_offense_description is not null
group by a.highest_offense_description;

-- Days to clear a crime by FBI UCR category
select category_description as fbi_ucr_category,
	min(clearance_date - report_date) as min_days,
	max(clearance_date - report_date) as max_days,
	avg(clearance_date - report_date) as avg_days,
	percentile_disc(0.5) within group (order by (clearance_date - report_date)) as median_days
from v_atx_crime
where coalesce(clearance_status, 'N') <> 'N'
	and ucr_category is not null
group by 1;

-- Summary days elapsed to clear crime by FBI UCR categories
with stat_summary as (
select category_description,
	count(*) as offense_count,
	max(days_length) as max_days,
	min(days_length) as min_days,
	round(avg(days_length),2) as avg_days,
	round(stddev_pop(days_length), 2) as std_days,
	percentile_cont(0.25) within group (order by days_length)::numeric as q25_days,
	percentile_cont(0.5) within group (order by days_length)::numeric as q50_days,
	percentile_cont(0.75) within group (order by days_length)::numeric as q75_days
from (
	select category_description,
		extract(day from clearance_date - report_date) as days_length
	from v_atx_crime
	where coalesce(clearance_status, 'N') <> 'N'
		and ucr_category is not null
	) group by category_description
)select t.*,
-- Calculating IQR can be used to roughly describe how the length of days are distributed
	(q75_days - q25_days) as iqr,
	q25_days - 1.5 * (q75_days-q25_days) as q1,
	q75_days + 1.5 * (q75_days-q25_days) as q3
from stat_summary t;

-- Summary days elapsed to clear crime by year
with stat_summary as (
select year,
	count(*) as offense_count,
	max(days_length) as max_days,
	min(days_length) as min_days,
	avg(days_length) as avg_days,
	round(stddev_pop(days_length), 2) as std_days,
	percentile_cont(0.25) within group (order by days_length)::numeric as q25_days,
	percentile_cont(0.5) within group (order by days_length)::numeric as q50_days,
	percentile_cont(0.75) within group (order by days_length)::numeric as q75_days
from (
	select incident_number,
		extract(year from report_date) as year,
		extract(day from clearance_date - report_date) as days_length
	from v_atx_crime
	where coalesce(clearance_status, 'N') <> 'N'
	) group by year
)select t.*,
-- Calculating IQR can be used to roughly describe how the length of days are distributed
	(q75_days - q25_days) as iqr,
	q25_days - 1.5 * (q75_days-q25_days) as q1,
	q75_days + 1.5 * (q75_days-q25_days) as q3
from stat_summary t;